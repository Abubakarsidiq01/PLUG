package app.plug.identity;

import app.plug.foundation.CorrelationFilter;
import app.plug.identity.IdentityPayloads.ConsentResponse;
import app.plug.identity.IdentityPayloads.MeResponse;
import app.plug.identity.IdentityPayloads.SessionListResponse;
import app.plug.identity.IdentityPayloads.SessionSummaryResponse;
import app.plug.security.PlugPrincipal;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

// The caller's own account, and the sessions it holds. Every route reads or writes exactly
// one person's data, and the person is taken from the authenticated principal rather than
// from anything in the request. A route that accepted a user id from the caller would be
// asking to be pointed at somebody else's account (manual.docx 19.4).
//
// This is also the phase's resource-level authorization test surface: GET and DELETE on
// /v1/me/sessions/{session_id} take an identifier an attacker can change, which is what a
// BOLA test needs in order to prove anything.
// Registered only when the module is enabled. The application's component scan covers
// this package, so without the condition the routes would be published in an
// environment that has no database behind them.
@org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(
        prefix = "plug.identity", name = "enabled", havingValue = "true")
@RestController
@RequestMapping("/v1/me")
class MeController {
    private final AccountService accounts;
    private final SessionService sessions;

    MeController(AccountService accounts, SessionService sessions) {
        this.accounts = accounts;
        this.sessions = sessions;
    }

    @GetMapping
    ResponseEntity<MeResponse> me(@AuthenticationPrincipal PlugPrincipal caller) {
        return ResponseEntity.ok(MeResponse.from(accounts.describe(caller)));
    }

    @PostMapping("/consent")
    ResponseEntity<ConsentResponse> acceptConsent(@AuthenticationPrincipal PlugPrincipal caller,
            @Valid @RequestBody ConsentAcceptance request, HttpServletRequest http) {
        Object requestId = http.getAttribute(CorrelationFilter.REQUEST_ATTRIBUTE);
        var state = accounts.acceptConsent(caller, request.version(),
                requestId == null ? null : requestId.toString());
        return ResponseEntity.ok(ConsentResponse.from(state));
    }

    @GetMapping("/sessions")
    ResponseEntity<SessionListResponse> listSessions(@AuthenticationPrincipal PlugPrincipal caller) {
        var summaries = sessions.listOwned(caller).stream()
                .map(row -> SessionSummaryResponse.from(row, caller.sessionId())).toList();
        return ResponseEntity.ok(new SessionListResponse(summaries));
    }

    @GetMapping("/sessions/{sessionId}")
    ResponseEntity<SessionSummaryResponse> session(@AuthenticationPrincipal PlugPrincipal caller,
            @PathVariable @Size(max = 64) @Pattern(regexp = "^ses_[A-Za-z0-9-]+$") String sessionId) {
        return ResponseEntity.ok(SessionSummaryResponse.from(
                sessions.requireOwned(caller, sessionId), caller.sessionId()));
    }

    @DeleteMapping("/sessions/{sessionId}")
    ResponseEntity<Void> revokeSession(@AuthenticationPrincipal PlugPrincipal caller,
            @PathVariable @Size(max = 64) @Pattern(regexp = "^ses_[A-Za-z0-9-]+$") String sessionId) {
        sessions.revokeOwned(caller, sessionId);
        return ResponseEntity.noContent().build();
    }

    record ConsentAcceptance(@NotBlank @Pattern(regexp = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") String version) {}
}
