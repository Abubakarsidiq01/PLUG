package app.plug.request;

import app.plug.request.AdminInspection.Classification;
import app.plug.request.AdminInspection.Gap;
import app.plug.request.AdminInspection.Page;
import app.plug.request.AdminInspection.Refusal;
import app.plug.request.AdminInspection.Vocabulary;
import app.plug.security.PlugPrincipal;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/// Staff-only reads. Authorization (admin scope plus a completed second factor) is enforced for
/// all of /v1/admin in SecurityConfiguration before any of this runs. Responses are never cached.
@RestController
@RequestMapping("/v1/admin")
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class AdminInspectionController {
    private final AdminInspection inspection;
    public AdminInspectionController(AdminInspection inspection) { this.inspection = inspection; }

    @GetMapping("/skills")
    ResponseEntity<Vocabulary> skills(@AuthenticationPrincipal PlugPrincipal staff) {
        return private_(inspection.vocabulary(staff));
    }

    @GetMapping("/skills/gaps")
    ResponseEntity<Page<Gap>> gaps(@AuthenticationPrincipal PlugPrincipal staff,
            @RequestParam(required = false) String cursor,
            @RequestParam(required = false) String limit) {
        return private_(inspection.gaps(staff, cursor, AdminInspection.limit(limit)));
    }

    @GetMapping("/classifications")
    ResponseEntity<Page<Classification>> classifications(@AuthenticationPrincipal PlugPrincipal staff,
            @RequestParam(required = false) String cursor,
            @RequestParam(required = false) String limit) {
        return private_(inspection.classifications(staff, cursor, AdminInspection.limit(limit)));
    }

    @GetMapping("/refusals")
    ResponseEntity<Page<Refusal>> refusals(@AuthenticationPrincipal PlugPrincipal staff,
            @RequestParam(required = false) String cursor,
            @RequestParam(required = false) String limit) {
        return private_(inspection.refusals(staff, cursor, AdminInspection.limit(limit)));
    }

    private static <T> ResponseEntity<T> private_(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }
}
