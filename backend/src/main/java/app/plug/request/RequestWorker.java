package app.plug.request;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class RequestWorker {
    private final RequestService service;
    private final boolean enabled;
    public RequestWorker(RequestService service, @org.springframework.beans.factory.annotation.Value(
            "${plug.requests-v2.worker-enabled:true}") boolean enabled) {
        this.service = service;
        this.enabled = enabled;
    }
    @Scheduled(fixedDelayString = "${plug.requests-v2.worker-delay-ms:1000}")
    public void tick() {
        if (!enabled) return;
        try { service.workOnce(); }
        catch (RuntimeException failure) {
            // No SQL, payload or provider exception text in operational logs.
            org.slf4j.LoggerFactory.getLogger(RequestWorker.class).warn("request_worker_failed exception_type={}",
                    failure.getClass().getSimpleName());
        }
    }
}
