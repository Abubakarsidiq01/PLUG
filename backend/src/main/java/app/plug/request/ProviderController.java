package app.plug.request;

import app.plug.request.ProviderPayloads.ProviderProfile;
import app.plug.request.ProviderPayloads.ProviderSetup;
import app.plug.request.ProviderPayloads.SkillProposal;
import app.plug.request.ProviderPayloads.SkillProposalRequest;
import app.plug.security.PlugPrincipal;
import jakarta.validation.Valid;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/providers")
@ConditionalOnProperty(prefix = "plug.requests-v2", name = "enabled", havingValue = "true")
public class ProviderController {
    private final ProviderService providers;
    public ProviderController(ProviderService providers) { this.providers = providers; }

    @PostMapping("/skills/propose")
    SkillProposal propose(@AuthenticationPrincipal PlugPrincipal caller, @Valid @RequestBody SkillProposalRequest body) {
        return providers.propose(caller, body.description());
    }
    @PostMapping("/skills")
    ProviderProfile set(@AuthenticationPrincipal PlugPrincipal caller, @Valid @RequestBody ProviderSetup body) {
        return providers.set(caller, body);
    }
    @GetMapping("/me")
    ProviderProfile me(@AuthenticationPrincipal PlugPrincipal caller) {
        return providers.me(caller);
    }
}
