package app.plug.identity;

import app.plug.foundation.ApiException;
import app.plug.identity.IdentityRecords.UserRow;
import app.plug.identity.SessionService.IssuedSession;
import app.plug.security.PlugPrincipal;
import java.time.Instant;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.transaction.annotation.Transactional;

// Where an account comes into existence, and where a guest becomes a real one.
//
// The rule the whole phase rests on: one person has one user id, for the life of the
// account. Signing in with Apple on top of a guest session keeps that id, which is why the
// request a guest started is still theirs afterwards, and why Phase 2 can key everything
// to the same identifier without inventing a second one (manual.docx 27.2).
public class AccountService {
    private static final Logger log = LoggerFactory.getLogger(AccountService.class);

    private final IdentityRepository identities;
    private final SessionService sessions;
    private final AppleIdentityVerifier apple;
    private final GoogleIdentityVerifier google;
    private final PhoneVerificationService phones;
    private final AuditLog audit;
    private final Secrets secrets;
    private final IdentitySettings settings;

    AccountService(IdentityRepository identities, SessionService sessions, AppleIdentityVerifier apple, GoogleIdentityVerifier google,
            PhoneVerificationService phones, AuditLog audit, Secrets secrets, IdentitySettings settings) {
        this.identities = identities;
        this.sessions = sessions;
        this.apple = apple;
        this.google = google;
        this.phones = phones;
        this.audit = audit;
        this.secrets = secrets;
        this.settings = settings;
    }

    record SignIn(IssuedSession session, UserRow user, ConsentState consent) {}

    record ConsentState(String currentVersion, String acceptedVersion, Instant acceptedAt) {}

    @Transactional
    public SignIn signInAsGuest(String consentVersion, String requestId) {
        requirePublishedConsent(consentVersion);
        UserRow user = identities.createUser(AccountType.GUEST);
        identities.recordConsent(user.id(), consentVersion, requestId);
        audit.record(user.id(), AccountType.GUEST.storage(), "account.created", "user", user.id(), "guest");
        return issueFor(user, false);
    }

    @Transactional
    public SignIn signInWithApple(String identityToken, String nonce, String consentVersion,
            PlugPrincipal caller, String requestId, String intent) {
        requirePublishedConsent(consentVersion);
        var verified = apple.verify(identityToken, nonce);
        return completeSignIn(AccountType.APPLE, secrets.hashSubject(verified.subject()),
                consentVersion, caller, requestId, intent);
    }

    @Transactional
    public SignIn signInWithGoogle(String identityToken, String nonce, String consentVersion,
            PlugPrincipal caller, String requestId, String intent) {
        requirePublishedConsent(consentVersion);
        return completeSignIn(AccountType.GOOGLE, secrets.hashSubject(google.verify(identityToken, nonce)),
                consentVersion, caller, requestId, intent);
    }

    @Transactional
    public SignIn verifyPhone(String challengeId, String code, String consentVersion,
            PlugPrincipal caller, String addressPrefix, String requestId, String intent) {
        requirePublishedConsent(consentVersion);
        String phoneHash = phones.verify(challengeId, code, addressPrefix);
        return completeSignIn(AccountType.PHONE, phoneHash, consentVersion, caller, requestId, intent);
    }

    // The three-way decision every verified sign-in makes. Written once so the Apple path
    // and the phone path cannot drift into behaving differently about the same question.
    private SignIn completeSignIn(AccountType type, String subjectHash, String consentVersion,
            PlugPrincipal caller, String requestId, String intent) {
        Optional<UserRow> existing = identities.findUserByIdentity(type.storage(), subjectHash);
        // Intent is checked after ownership verification and before issuing any session.
        // Missing intent preserves compatibility with earlier clients' combined flow.
        if ("sign_up".equals(intent) && existing.isPresent()) {
            throw alreadyRegistered();
        }
        if ("sign_in".equals(intent) && existing.isEmpty()) {
            throw ApiException.authIntentConflict("account_not_found",
                    "No PLUG account exists for this sign-in method. Create an account first.");
        }
        UserRow guest = callerGuest(caller);

        if (guest != null) {
            if (existing.isPresent() && !existing.get().id().equals(guest.id())) {
                // The person already has an account under this identity. Merging two
                // accounts is a decision with consequences nobody can undo from a sign-in
                // screen, so it is refused here and the client offers the real account.
                audit.record(guest.id(), guest.type().storage(), "account.link_conflict",
                        "identity", type.storage(), "already_linked");
                throw ApiException.conflict("That sign-in is already connected to another PLUG account."
                        + " Sign in to that account instead.");
            }
            if (existing.isEmpty() && !identities.attachIdentity(guest.id(), type.storage(), subjectHash)) {
                if ("sign_up".equals(intent)) { throw alreadyRegistered(); }
                // The unique constraint refused it, which means another request attached
                // the same subject while this one was deciding.
                throw ApiException.conflict("That sign-in is already connected to another PLUG account."
                        + " Sign in to that account instead.");
            }
            identities.promoteAccountType(guest.id(), type);
            identities.recordConsent(guest.id(), consentVersion, requestId);
            // Upgrading is a change to how the account is secured, so everything issued
            // under the weaker guest identity stops working (manual.docx 25.2). The user
            // id does not change, so nothing the guest started is lost.
            sessions.revokeAllForUser(guest.id(), AccountType.GUEST, "security_change");
            audit.record(guest.id(), type.storage(), "account.upgraded", "user", guest.id(), type.storage());
            log.info("account_upgraded user={} to={}", PlugPrincipal.hashForLogging(guest.id()), type.storage());
            return issueFor(identities.findUser(guest.id()).orElseThrow(), false);
        }

        UserRow user = existing.orElse(null);
        if (user == null) {
            user = identities.createUser(type);
            if (!identities.attachIdentity(user.id(), type.storage(), subjectHash)) {
                if ("sign_up".equals(intent)) { throw alreadyRegistered(); }
                throw ApiException.conflict("That sign-in is already connected to another PLUG account.");
            }
            audit.record(user.id(), type.storage(), "account.created", "user", user.id(), type.storage());
        } else {
            audit.record(user.id(), type.storage(), "account.signed_in", "user", user.id(), type.storage());
        }
        identities.recordConsent(user.id(), consentVersion, requestId);
        return issueFor(user, false);
    }

    private static ApiException alreadyRegistered() {
        return ApiException.authIntentConflict("account_exists",
                "You already have a PLUG account. Sign in instead.");
    }

    @Transactional
    public ConsentState acceptConsent(PlugPrincipal principal, String version, String requestId) {
        requirePublishedConsent(version);
        UserRow user = requireActive(principal.userId());
        identities.recordConsent(user.id(), version, requestId);
        audit.record(user.id(), user.type().storage(), "consent.accepted", "consent", version, null);
        return consentFor(user.id());
    }

    // Rotation returns the same shape as a sign-in, because that is what the client has
    // to store: a client that handles refresh differently from sign-in is a client with two
    // ways to end up holding a stale token.
    @Transactional
    public SignIn refresh(String refreshToken) {
        IssuedSession rotated = sessions.rotate(refreshToken);
        UserRow user = requireActive(rotated.userId());
        return new SignIn(rotated, user, consentFor(user.id()));
    }

    @Transactional(readOnly = true)
    public SignIn describe(PlugPrincipal principal) {
        UserRow user = requireActive(principal.userId());
        return new SignIn(null, user, consentFor(user.id()));
    }

    // Deleting an account revokes every session it has, in the same transaction. Doing only
    // one of the two leaves a live credential pointing at a deleted account.
    @Transactional
    public void deleteAccount(PlugPrincipal principal) {
        UserRow user = requireActive(principal.userId());
        sessions.revokeAllForUser(user.id(), user.type(), "account_deleted");
        identities.markDeleted(user.id());
        audit.record(user.id(), user.type().storage(), "account.deleted", "user", user.id(), null);
    }

    private SignIn issueFor(UserRow user, boolean multiFactorVerified) {
        return new SignIn(sessions.issue(user.id(), user.type(), multiFactorVerified), user, consentFor(user.id()));
    }

    private ConsentState consentFor(String userId) {
        return identities.latestConsent(userId)
                .map(row -> new ConsentState(settings.consentVersion(), row.version(), row.acceptedAt()))
                .orElseGet(() -> new ConsentState(settings.consentVersion(), null, null));
    }

    // A caller may only upgrade a guest. Presenting a session that is already a member
    // means the client is trying to link a second identity, which this phase does not do.
    private UserRow callerGuest(PlugPrincipal caller) {
        if (caller == null) {
            return null;
        }
        UserRow user = requireActive(caller.userId());
        if (user.type() != AccountType.GUEST) {
            throw ApiException.conflict("This account is already signed in. Sign out first to use a different one.");
        }
        return user;
    }

    private UserRow requireActive(String userId) {
        UserRow user = identities.findUser(userId).orElseThrow(
                () -> ApiException.unauthenticated("Your session has ended. Sign in again."));
        if (!user.isActive()) {
            throw ApiException.unauthenticated("Your session has ended. Sign in again.");
        }
        return user;
    }

    // Consent is only meaningful if the server knows what the person was shown. A version
    // it never published is rejected rather than recorded as agreement to unknown text.
    private void requirePublishedConsent(String version) {
        if (!settings.consentVersion().equals(version)) {
            throw ApiException.validation("consent_version", "unsupported",
                    "Please review the current Terms and Privacy Policy to continue.");
        }
    }
}
