package app.plug.request;

import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;

/// Provider capability on an existing account (manual v4 §2.3, §12B, contract 0.5.0).
public final class ProviderPayloads {
    private ProviderPayloads() {}
    public record SkillProposalRequest(@NotBlank @Size(max = 300) String description) {
        @Override public String toString() { return "SkillProposalRequest[redacted]"; }
    }
    public record SkillTag(String tag, String display, boolean requiresLicence) {
        static SkillTag of(SkillVocabulary.Skill skill) { return new SkillTag(skill.tag(), skill.display(), skill.requiresLicence()); }
    }
    public record SkillProposal(List<SkillTag> skills, List<String> unmatched) {}
    public record AvailabilityWindow(@NotNull @Pattern(regexp = "weekdays|weekends|every_day") String days,
            @NotNull @Pattern(regexp = "([01][0-9]|2[0-3]):[0-5][0-9]") String from,
            @NotNull @Pattern(regexp = "([01][0-9]|2[0-3]):[0-5][0-9]|24:00") String to) {}
    public record ProviderSetup(@NotEmpty @Size(max = 10) List<@NotBlank @Pattern(regexp = "[a-z][a-z0-9_]{1,39}") String> skillTags,
            @NotNull @Min(500) @Max(80000) Integer travelRadiusM,
            @NotNull @Valid RequestPayloads.Location baseLocation,
            @NotEmpty @Size(max = 6) List<@NotNull @Valid AvailabilityWindow> availability,
            @NotBlank @Size(max = 64) @Pattern(regexp = "[A-Za-z0-9_+/-]+") String timeZone,
            @Size(min = 3, max = 64) @Pattern(regexp = "[A-Za-z0-9 ./-]+") String licenceRef,
            Boolean accepting) {
        @Override public String toString() { return "ProviderSetup[redacted]"; }
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public record ProviderProfile(String userId, List<SkillTag> skills, int travelRadiusM, List<AvailabilityWindow> availability,
            String timeZone, boolean accepting, boolean licenceOnFile, RequestPayloads.ProviderScore score, Instant createdAt) {}
}
