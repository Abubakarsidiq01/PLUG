package app.plug.request;

import app.plug.foundation.ApiException;
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
    public RequestPayloads.ProviderInbox inbox(PlugPrincipal caller) {
        return requests.inbox(caller);
    }
    /// Contract 0.7.0 registerDevice, after the body is validated. Push needs an Apple Developer
    /// Program team (P3-apns); until one is configured nothing is stored and the inbox works by pull.
    public void registerDevice(PlugPrincipal caller) {
        requests.requireCaller(caller);
        if (!requests.limiter.tryConsume("devices:" + caller.userId(), 10, requests.window.length())) {
            throw ApiException.rateLimited(requests.window.retryAfterSeconds());
        }
        throw ApiException.dependencyUnavailable("Notifications are not available yet. Your inbox still updates when you open it.", 3600);
    }
    public RequestPayloads.Offer sendOffer(PlugPrincipal caller, String requestId, String key, RequestPayloads.OfferCreate offer) {
        return requests.sendOffer(caller, requestId, key, offer);
    }
    public RequestPayloads.InboxItem answer(PlugPrincipal caller, String matchId, String decision) {
        return requests.answer(caller, matchId, decision);
    }
}
