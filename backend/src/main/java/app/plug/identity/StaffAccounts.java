package app.plug.identity;

import app.plug.foundation.ApiException;
import app.plug.foundation.FixedWindowLimiter;
import app.plug.identity.IdentityRecords.UserRow;
import app.plug.security.PlugPrincipal;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.annotation.Transactional;

// Staff accounts (ADR-013, owner decision 2026-10-05). The people who run PLUG sign in with
// their own account, separate from any customer account: an email, a password, and a
// six-digit code emailed on every sign-in. Only a session that finished both steps carries
// the second factor that /v1/admin requires.
//
// Nobody is added in code. The first owner is invited once from the server's configuration
// (plug.staff.owner-email, used only while no staff account exists); every other person is
// invited by an owner from the console. There is no QR code and no authenticator app.
//
// What the controls are for:
//   one response for every sign-in attempt   no answer reveals whether an email is staff
//   BCrypt, cost 12, and a dummy comparison   a wrong email costs as much time as a wrong password
//   per-email, per-address, per-challenge     the same three-way limits as phone codes
//   single-use, hashed, expiring tokens       a leaked database or old email opens nothing
class StaffAccounts {
    static final Duration INVITE_TTL = Duration.ofHours(72);
    static final Duration CODE_TTL = Duration.ofMinutes(10);
    static final int CODE_ATTEMPTS = 5;
    private static final Pattern EMAIL = Pattern.compile("^[^@\\s]{1,64}@[^@\\s]+\\.[^@\\s]{2,}$");
    private static final int RETRY_AFTER_SECONDS = 900;

    private final JdbcTemplate jdbc;
    private final IdentityRepository identities;
    private final SessionService sessions;
    private final AuditLog audit;
    private final Secrets secrets;
    private final StaffMailer mailer;
    private final IdentitySettings settings;
    private final Clock clock;
    private final String consoleUrl;
    private final BCryptPasswordEncoder passwords = new BCryptPasswordEncoder(12);
    private final FixedWindowLimiter limiter = new FixedWindowLimiter(4096);
    // Compared against when the email is unknown, so both paths spend one BCrypt check.
    private final String decoyHash = passwords.encode(Secrets.token("decoy_"));

    StaffAccounts(JdbcTemplate jdbc, IdentityRepository identities, SessionService sessions, AuditLog audit,
            Secrets secrets, StaffMailer mailer, IdentitySettings settings, Clock clock, String consoleUrl) {
        this.jdbc = jdbc;
        this.identities = identities;
        this.sessions = sessions;
        this.audit = audit;
        this.secrets = secrets;
        this.mailer = mailer;
        this.settings = settings;
        this.clock = clock;
        this.consoleUrl = consoleUrl.endsWith("/") ? consoleUrl.substring(0, consoleUrl.length() - 1) : consoleUrl;
    }

    record Invite(String inviteId, String email, String role, Instant expiresAt) {}

    record Challenge(String challengeId, Instant expiresAt) {}

    record Member(String userId, String email, String role, String status, Instant createdAt) {}

    private record Account(String userId, String email, String passwordHash, String role, String status) {}

    // Runs at start-up. Does nothing once any staff account exists, or while an earlier
    // invitation to the same address is still open, so restarts do not resend it.
    @Transactional
    Optional<Invite> bootstrap(String rawEmail) {
        String email = email(rawEmail);
        Integer staff = jdbc.queryForObject("SELECT count(*) FROM staff_accounts", Integer.class);
        if (staff != null && staff > 0) return Optional.empty();
        Integer open = jdbc.queryForObject("SELECT count(*) FROM staff_invites WHERE email = ? AND accepted_at IS NULL"
                + " AND revoked_at IS NULL AND expires_at > ?", Integer.class, email, Timestamp.from(clock.instant()));
        if (open != null && open > 0) return Optional.empty();
        Invite invite = createInvite(email, "owner", null);
        audit.record("system", "system", "staff.bootstrap_invited", "staff_invite", invite.inviteId(), null);
        return Optional.of(invite);
    }

    @Transactional
    Invite invite(PlugPrincipal caller, String rawEmail, String role) {
        Account inviter = requireOwner(caller);
        String email = email(rawEmail);
        if (!List.of("owner", "staff").contains(role)) {
            throw ApiException.validation("role", "invalid", "Choose owner or staff.");
        }
        if (find(email).filter(account -> "active".equals(account.status())).isPresent()) {
            throw ApiException.conflict("That person already has an active staff account.");
        }
        // A new invitation replaces any earlier one, so only the latest link works.
        jdbc.update("UPDATE staff_invites SET revoked_at = now() WHERE email = ? AND accepted_at IS NULL AND revoked_at IS NULL",
                email);
        Invite invite = createInvite(email, role, inviter.userId());
        audit.record(inviter.userId(), "staff", "staff.invited", "staff_invite", invite.inviteId(), role);
        return invite;
    }

    private Invite createInvite(String email, String role, String invitedBy) {
        requireMail();
        String id = Secrets.identifier("inv_");
        String token = Secrets.token("sti_");
        Instant expires = clock.instant().plus(INVITE_TTL);
        jdbc.update("INSERT INTO staff_invites (id, email, role, token_hash, invited_by, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
                id, email, role, Secrets.hashToken(token), invitedBy, Timestamp.from(expires));
        deliver(email, "Your PLUG staff invitation",
                "You have been invited to run PLUG as " + role + ".\n\n"
                + "Choose your password here within 72 hours:\n" + consoleUrl + "/staff/accept#token=" + token + "\n\n"
                + "Or give this invitation code to the staff console: " + token + "\n\n"
                + "If you did not expect this, ignore it. Nothing happens unless the link is used.");
        return new Invite(id, email, role, expires);
    }

    // Choosing a password spends the invitation. Unknown, used, replaced and expired
    // invitations all get the same answer.
    @Transactional
    void accept(String token, String password) {
        var rows = jdbc.queryForList("SELECT id, email, role, invited_by FROM staff_invites WHERE token_hash = ?"
                + " AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > ? FOR UPDATE",
                Secrets.hashToken(token), Timestamp.from(clock.instant()));
        if (rows.isEmpty()) {
            throw ApiException.validation("invite_token", "expired", "That invitation has expired or was already used. Ask for a new one.");
        }
        var invite = rows.get(0);
        String email = (String) invite.get("email");
        String role = (String) invite.get("role");
        checkPassword(password, email);
        String hash = passwords.encode(password);
        Optional<Account> existing = find(email);
        String userId;
        if (existing.isPresent()) {
            // Re-inviting a disabled person restores them with the new password.
            userId = existing.get().userId();
            jdbc.update("UPDATE staff_accounts SET password_hash = ?, role = ?, status = 'active', disabled_at = NULL,"
                    + " updated_at = now() WHERE user_id = ?", hash, role, userId);
            sessions.revokeAllForUser(userId, AccountType.STAFF, "security_change");
        } else {
            userId = identities.createUser(AccountType.STAFF).id();
            jdbc.update("INSERT INTO staff_accounts (user_id, email, password_hash, role, invited_by) VALUES (?, ?, ?, ?, ?)",
                    userId, email, hash, role, invite.get("invited_by"));
        }
        jdbc.update("UPDATE staff_invites SET accepted_at = now() WHERE id = ?", invite.get("id"));
        audit.record(userId, "staff", "staff.joined", "staff_invite", (String) invite.get("id"), role);
    }

    // Step one. The answer is the same shape and status whether the email is unknown, the
    // password is wrong, or both are right; only the last sends a code.
    @Transactional
    Challenge startLogin(String rawEmail, String password, String addressPrefix) {
        String email = email(rawEmail);
        limit("staff:login:email:" + secrets.hashSubject(email), 5, Duration.ofMinutes(15), addressPrefix);
        limit("staff:login:address:" + addressPrefix, 20, Duration.ofMinutes(15), addressPrefix);
        requireMail();
        Optional<Account> account = find(email).filter(found -> "active".equals(found.status()));
        boolean matches = passwords.matches(password, account.map(Account::passwordHash).orElse(decoyHash));
        String challengeId = Secrets.identifier("slc_");
        Instant expires = clock.instant().plus(CODE_TTL);
        if (account.isPresent() && matches) {
            String code = Secrets.numericCode(6);
            jdbc.update("INSERT INTO staff_login_challenges (id, user_id, code_hash, expires_at) VALUES (?, ?, ?, ?)",
                    challengeId, account.get().userId(), secrets.hashSubject(code), Timestamp.from(expires));
            deliver(email, "Your PLUG staff sign-in code: " + code,
                    "Your PLUG staff sign-in code is " + code + ". It works once, for 10 minutes.\n\n"
                    + "If you did not just sign in, change your password: someone knows it.");
            audit.record(account.get().userId(), "staff", "staff.code_sent", "staff_login", challengeId, null);
        } else {
            audit.recordAnonymous("staff.login_failed", addressPrefix, "bad_credentials");
        }
        return new Challenge(challengeId, expires);
    }

    // Step two: the emailed code buys one session that carries the second factor. A refusal
    // keeps its counted attempt; rolling it back would give every guess a free retry.
    @Transactional(noRollbackFor = ApiException.class)
    AccountService.SignIn verifyLogin(String challengeId, String code, String addressPrefix) {
        limit("staff:verify:challenge:" + challengeId, CODE_ATTEMPTS, Duration.ofMinutes(10), addressPrefix);
        limit("staff:verify:address:" + addressPrefix, 20, Duration.ofMinutes(15), addressPrefix);
        var rows = jdbc.queryForList("SELECT user_id, code_hash, attempts_used, expires_at, consumed_at"
                + " FROM staff_login_challenges WHERE id = ? FOR UPDATE", challengeId);
        if (rows.isEmpty()) throw expired();
        var challenge = rows.get(0);
        if (challenge.get("consumed_at") != null
                || !((Timestamp) challenge.get("expires_at")).toInstant().isAfter(clock.instant())) {
            throw expired();
        }
        int used = ((Number) challenge.get("attempts_used")).intValue() + 1;
        if (used > CODE_ATTEMPTS) throw ApiException.rateLimited(RETRY_AFTER_SECONDS);
        jdbc.update("UPDATE staff_login_challenges SET attempts_used = ? WHERE id = ?", used, challengeId);
        String userId = (String) challenge.get("user_id");
        if (!Secrets.matches((String) challenge.get("code_hash"), secrets.hashSubject(code))) {
            audit.record(userId, "staff", "staff.code_failed", "staff_login", challengeId, "attempts=" + used);
            throw used >= CODE_ATTEMPTS ? ApiException.rateLimited(RETRY_AFTER_SECONDS)
                    : ApiException.validation("code", "invalid", "That code is not correct.");
        }
        jdbc.update("UPDATE staff_login_challenges SET consumed_at = now() WHERE id = ?", challengeId);
        limiter.forget("staff:verify:challenge:" + challengeId);
        Account account = findById(userId).filter(found -> "active".equals(found.status())).orElseThrow(StaffAccounts::expired);
        UserRow user = identities.findUser(account.userId()).orElseThrow(StaffAccounts::expired);
        var issued = sessions.issue(user.id(), AccountType.STAFF, true);
        audit.record(user.id(), "staff", "staff.signed_in", "session", issued.sessionId(), null);
        return new AccountService.SignIn(issued, user,
                new AccountService.ConsentState(settings.consentVersion(), null, null));
    }

    @Transactional(readOnly = true)
    List<Member> list(PlugPrincipal caller) {
        Account reader = requireStaff(caller);
        audit.record(reader.userId(), "staff", "admin.read", "staff_accounts", "list", null);
        return jdbc.query("SELECT user_id, email, role, status, created_at FROM staff_accounts ORDER BY created_at, user_id",
                (row, index) -> new Member(row.getString("user_id"), row.getString("email"), row.getString("role"),
                        row.getString("status"), row.getTimestamp("created_at").toInstant()));
    }

    // Offboarding: the account stops working everywhere at once.
    @Transactional
    void disable(PlugPrincipal caller, String userId) {
        Account owner = requireOwner(caller);
        if (owner.userId().equals(userId)) {
            throw ApiException.conflict("You cannot disable your own account. Ask another owner.");
        }
        Account target = findById(userId).orElseThrow(() -> ApiException.notFound("No such staff account."));
        jdbc.update("UPDATE staff_accounts SET status = 'disabled', disabled_at = COALESCE(disabled_at, now()),"
                + " updated_at = now() WHERE user_id = ?", target.userId());
        sessions.revokeAllForUser(target.userId(), AccountType.STAFF, "security_change");
        audit.record(owner.userId(), "staff", "staff.disabled", "user", target.userId(), null);
    }

    private Account requireStaff(PlugPrincipal caller) {
        return findById(caller.userId()).filter(account -> "active".equals(account.status()))
                .orElseThrow(() -> ApiException.forbidden("This operation is not allowed."));
    }

    private Account requireOwner(PlugPrincipal caller) {
        Account account = requireStaff(caller);
        if (!"owner".equals(account.role())) throw ApiException.forbidden("Only an owner can manage staff.");
        return account;
    }

    private Optional<Account> find(String email) {
        return jdbc.query("SELECT user_id, email, password_hash, role, status FROM staff_accounts WHERE email = ?",
                (row, index) -> new Account(row.getString(1), row.getString(2), row.getString(3), row.getString(4),
                        row.getString(5)), email).stream().findFirst();
    }

    private Optional<Account> findById(String userId) {
        return jdbc.query("SELECT user_id, email, password_hash, role, status FROM staff_accounts WHERE user_id = ?",
                (row, index) -> new Account(row.getString(1), row.getString(2), row.getString(3), row.getString(4),
                        row.getString(5)), userId).stream().findFirst();
    }

    private void requireMail() {
        if (!mailer.isAvailable()) {
            throw ApiException.dependencyUnavailable("Staff email is not configured on this server.", 60);
        }
    }

    private void deliver(String to, String subject, String text) {
        try {
            mailer.send(to, subject, text);
        } catch (RuntimeException failure) {
            throw ApiException.dependencyUnavailable("We could not send the email. Try again shortly.", 60);
        }
    }

    private void limit(String key, int maximum, Duration window, String addressPrefix) {
        if (!limiter.tryConsume(key, maximum, window)) {
            audit.recordAnonymous("staff.rate_limited", addressPrefix, "limit_reached");
            throw ApiException.rateLimited(RETRY_AFTER_SECONDS);
        }
    }

    static String email(String raw) {
        String email = raw == null ? "" : raw.strip().toLowerCase(Locale.ROOT);
        if (email.length() < 6 || email.length() > 254 || !EMAIL.matcher(email).matches()) {
            throw ApiException.validation("email", "invalid", "Enter a valid email address.");
        }
        return email;
    }

    // NIST 800-63B style: long enough to matter, short enough for BCrypt's 72 bytes, and not
    // something an attacker would try first.
    static void checkPassword(String password, String email) {
        if (password == null || password.length() < 12 || password.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw ApiException.validation("password", "length", "Use 12 to 64 characters.");
        }
        String lower = password.toLowerCase(Locale.ROOT);
        String local = email.substring(0, email.indexOf('@'));
        if (password.chars().distinct().count() < 5 || (local.length() >= 4 && lower.contains(local))
                || lower.contains("password") || lower.contains("plug")) {
            throw ApiException.validation("password", "too_weak", "Choose a password that is harder to guess.");
        }
    }

    private static ApiException expired() {
        return ApiException.validation("code", "expired", "That code has expired. Sign in again.");
    }
}
