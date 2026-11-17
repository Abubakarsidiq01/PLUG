package app.plug.request;

import app.plug.security.PlugPrincipal;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.stereotype.Service;

/// P3.S6 selection and the provider's reservation decision. Exists only while both
/// requests-v2 and the provider inbox are enabled; the timers live in RequestService so a
/// reservation still times out and completes with the flag turned off again.
@Service
@ConditionalOnExpression("${plug.requests-v2.enabled:false} and ${plug.provider-inbox.enabled:false}")
public class ReservationService {
    public record ProviderDecisionResult(String reservationStatus, String requestStatus) {}
    private final RequestService requests;
    public ReservationService(RequestService requests) { this.requests = requests; }
    public RequestPayloads.Resource select(PlugPrincipal caller, String requestId, String key, RequestPayloads.Selection selection) {
        return requests.select(caller, requestId, key, selection);
    }
    /// decision is "confirm" or "release"; the caller is the provider's own user id.
    public ProviderDecisionResult decide(String providerUserId, String matchId, String decision) {
        return requests.decide(providerUserId, matchId, decision);
    }
    public RequestPayloads.InboxItem answer(PlugPrincipal caller, String matchId, String decision) {
        return requests.answer(caller, matchId, decision);
    }
}
