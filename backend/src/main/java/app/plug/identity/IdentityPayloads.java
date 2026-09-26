package app.plug.identity;

import app.plug.identity.IdentityRecords.SessionRow;
import app.plug.identity.SessionService.IssuedSession;
import java.time.Instant;
import java.util.List;

// The response shapes from contracts/openapi.yaml, in one file so the contract can be read
// against them side by side. Jackson is configured to write snake_case, so the field names
// here are the field names on the wire.
final class IdentityPayloads {
    private IdentityPayloads() {}

    // Carries two readable tokens, which is why every record in this file overrides
    // toString. Spring MVC and Jackson both call toString on a payload at DEBUG level, and
    // that is the accident that puts a credential in a log file.
    record SessionResponse(String accessToken, Instant accessTokenExpiresAt, String refreshToken,
            Instant refreshTokenExpiresAt, AccountResponse account, ConsentResponse consent) {
        static SessionResponse from(AccountService.SignIn signIn) {
            IssuedSession issued = signIn.session();
            return new SessionResponse(issued.accessToken(), issued.accessExpiresAt(),
                    issued.refreshToken(), issued.refreshExpiresAt(),
                    AccountResponse.from(signIn), ConsentResponse.from(signIn.consent()));
        }

        @Override
        public String toString() {
            return "SessionResponse[redacted]";
        }
    }

    record AccountResponse(String userId, String type, List<String> scopes) {
        static AccountResponse from(AccountService.SignIn signIn) {
            return new AccountResponse(signIn.user().id(), signIn.user().type().storage(),
                    signIn.user().type().scopes().stream().sorted().toList());
        }
    }

    record ConsentResponse(String currentVersion, String acceptedVersion, Instant acceptedAt) {
        static ConsentResponse from(AccountService.ConsentState state) {
            return new ConsentResponse(state.currentVersion(), state.acceptedVersion(), state.acceptedAt());
        }
    }

    record MeResponse(AccountResponse account, ConsentResponse consent) {
        static MeResponse from(AccountService.SignIn signIn) {
            return new MeResponse(AccountResponse.from(signIn), ConsentResponse.from(signIn.consent()));
        }
    }

    record PhoneChallengeResponse(String challengeId, Instant expiresAt, int attemptsRemaining) {}

    record SessionSummaryResponse(String sessionId, Instant createdAt, Instant lastUsedAt,
            Instant expiresAt, boolean current) {
        static SessionSummaryResponse from(SessionRow row, String currentSessionId) {
            return new SessionSummaryResponse(row.id(), row.createdAt(), row.lastUsedAt(),
                    row.refreshExpiresAt(), row.id().equals(currentSessionId));
        }
    }

    record SessionListResponse(List<SessionSummaryResponse> sessions) {}
}
