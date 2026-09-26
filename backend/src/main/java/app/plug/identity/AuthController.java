package app.plug.identity;

import app.plug.foundation.CorrelationFilter;
import app.plug.identity.IdentityPayloads.PhoneChallengeResponse;
import app.plug.identity.IdentityPayloads.SessionResponse;
import app.plug.security.PlugPrincipal;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

// The sign-in surface. Every route here is reachable without a session, which is why the
// validation on each request record is strict: shape, length, character set and range are
// settled before any of it reaches a service (manual.docx 25.3).
//
// Each record overrides toString. A token, a code and a phone number all arrive through
// this class, and Spring MVC will print a payload through toString at DEBUG level.
// Registered only when the module is enabled. The application's component scan covers
// this package, so without the condition the routes would be published in an
// environment that has no database behind them.
@org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(
        prefix = "plug.identity", name = "enabled", havingValue = "true")
@RestController
@RequestMapping("/v1/auth")
class AuthController {
    private final AccountService accounts;
    private final SessionService sessions;
    private final PhoneVerificationService phones;

    AuthController(AccountService accounts, SessionService sessions, PhoneVerificationService phones) {
        this.accounts = accounts;
        this.sessions = sessions;
        this.phones = phones;
    }

    // A guest access token in the Authorization header upgrades that guest in place. It is
    // optional, so an anonymous caller reaches the same route and simply creates an account.
    @PostMapping("/apple")
    ResponseEntity<SessionResponse> apple(@AuthenticationPrincipal PlugPrincipal caller,
            @Valid @RequestBody ProviderSignIn request, HttpServletRequest http) {
        var signIn = accounts.signInWithApple(request.identityToken(), request.nonce(),
                request.consentVersion(), caller, requestId(http), request.intent());
        return ResponseEntity.status(HttpStatus.CREATED).body(SessionResponse.from(signIn));
    }

    @PostMapping("/google")
    ResponseEntity<SessionResponse> google(@AuthenticationPrincipal PlugPrincipal caller,
            @Valid @RequestBody ProviderSignIn request, HttpServletRequest http) {
        var signIn = accounts.signInWithGoogle(request.identityToken(), request.nonce(),
                request.consentVersion(), caller, requestId(http), request.intent());
        return ResponseEntity.status(HttpStatus.CREATED).body(SessionResponse.from(signIn));
    }

    @PostMapping("/phone/start")
    ResponseEntity<PhoneChallengeResponse> startPhone(@Valid @RequestBody PhoneStart request,
            HttpServletRequest http) {
        var started = phones.start(request.phoneNumber(), CallerAddress.prefixOf(http));
        return ResponseEntity.accepted().body(new PhoneChallengeResponse(
                started.challengeId(), started.expiresAt(), started.attemptsRemaining()));
    }

    @PostMapping("/phone/verify")
    ResponseEntity<SessionResponse> verifyPhone(@AuthenticationPrincipal PlugPrincipal caller,
            @Valid @RequestBody PhoneVerify request, HttpServletRequest http) {
        var signIn = accounts.verifyPhone(request.challengeId(), request.code(), request.consentVersion(),
                caller, CallerAddress.prefixOf(http), requestId(http), request.intent());
        return ResponseEntity.status(HttpStatus.CREATED).body(SessionResponse.from(signIn));
    }

    @PostMapping("/guest")
    ResponseEntity<SessionResponse> guest(@Valid @RequestBody GuestSignIn request, HttpServletRequest http) {
        var signIn = accounts.signInAsGuest(request.consentVersion(), requestId(http));
        return ResponseEntity.status(HttpStatus.CREATED).body(SessionResponse.from(signIn));
    }

    // Refresh does not need an access token: the refresh token is the credential, and the
    // access token it replaces has usually expired by the time a client gets here.
    @PostMapping("/refresh")
    ResponseEntity<SessionResponse> refresh(@Valid @RequestBody RefreshRequest request) {
        return ResponseEntity.ok(SessionResponse.from(accounts.refresh(request.refreshToken())));
    }

    @PostMapping("/logout")
    ResponseEntity<Void> logout(@AuthenticationPrincipal PlugPrincipal caller) {
        sessions.revokeCurrent(caller, "logout");
        return ResponseEntity.noContent().build();
    }

    // The correlation id the filter put on the request, stored alongside the consent row
    // so support can tie an acceptance back to the call that recorded it.
    private String requestId(HttpServletRequest http) {
        Object value = http.getAttribute(CorrelationFilter.REQUEST_ATTRIBUTE);
        return value == null ? null : value.toString();
    }

    record ProviderSignIn(
            @NotBlank @Size(max = 4096) String identityToken,
            @NotBlank @Size(min = 16, max = 128) @Pattern(regexp = "^[A-Za-z0-9_-]+$") String nonce,
            @NotBlank @Pattern(regexp = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") String consentVersion,
            @Pattern(regexp = "^(sign_up|sign_in)$") String intent) {
        @Override
        public String toString() {
            return "ProviderSignIn[redacted]";
        }
    }

    record PhoneStart(@NotBlank @Pattern(regexp = "^\\+[1-9][0-9]{7,14}$") String phoneNumber) {
        @Override
        public String toString() {
            return "PhoneStart[redacted]";
        }
    }

    record PhoneVerify(
            @NotBlank @Size(max = 64) @Pattern(regexp = "^cha_[A-Za-z0-9-]+$") String challengeId,
            @NotBlank @Pattern(regexp = "^[0-9]{6}$") String code,
            @NotBlank @Pattern(regexp = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") String consentVersion,
            @Pattern(regexp = "^(sign_up|sign_in)$") String intent) {
        @Override
        public String toString() {
            return "PhoneVerify[redacted]";
        }
    }

    record GuestSignIn(@NotBlank @Pattern(regexp = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") String consentVersion) {}

    record RefreshRequest(@NotBlank @Size(max = 512) String refreshToken) {
        @Override
        public String toString() {
            return "RefreshRequest[redacted]";
        }
    }
}
