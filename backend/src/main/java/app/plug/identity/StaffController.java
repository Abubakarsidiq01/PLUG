package app.plug.identity;

import app.plug.identity.IdentityPayloads.SessionResponse;
import app.plug.security.PlugPrincipal;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

// Staff sign-in and staff management (ADR-013). The three /v1/staff routes are reachable
// without a session; everything under /v1/admin/staff needs an admin session that finished
// the emailed second factor, like every other admin route. Records carrying a password, a
// code or a token override toString so a DEBUG log cannot print them.
@org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(
        prefix = "plug.identity", name = "enabled", havingValue = "true")
@RestController
class StaffController {
    private final StaffAccounts staff;

    StaffController(StaffAccounts staff) {
        this.staff = staff;
    }

    @PostMapping("/v1/staff/invites/accept")
    ResponseEntity<Void> accept(@Valid @RequestBody AcceptInvite request) {
        staff.accept(request.inviteToken(), request.password());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/v1/staff/login")
    ResponseEntity<ChallengeResponse> login(@Valid @RequestBody Login request, HttpServletRequest http) {
        var challenge = staff.startLogin(request.email(), request.password(), CallerAddress.prefixOf(http));
        return ResponseEntity.accepted().body(new ChallengeResponse(challenge.challengeId(), challenge.expiresAt()));
    }

    @PostMapping("/v1/staff/login/verify")
    ResponseEntity<SessionResponse> verify(@Valid @RequestBody Verify request, HttpServletRequest http) {
        var signIn = staff.verifyLogin(request.challengeId(), request.code(), CallerAddress.prefixOf(http));
        return ResponseEntity.status(HttpStatus.CREATED).body(SessionResponse.from(signIn));
    }

    @GetMapping("/v1/admin/staff")
    ResponseEntity<StaffList> list(@AuthenticationPrincipal PlugPrincipal caller) {
        var members = staff.list(caller).stream().map(member -> new StaffMember(member.userId(), member.email(),
                member.role(), member.status(), member.createdAt())).toList();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new StaffList(members));
    }

    @PostMapping("/v1/admin/staff/invites")
    ResponseEntity<InviteResponse> invite(@AuthenticationPrincipal PlugPrincipal caller,
            @Valid @RequestBody InviteRequest request) {
        var invite = staff.invite(caller, request.email(), request.role());
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore())
                .body(new InviteResponse(invite.inviteId(), invite.email(), invite.role(), invite.expiresAt()));
    }

    @PostMapping("/v1/admin/staff/{userId}/disable")
    ResponseEntity<Void> disable(@AuthenticationPrincipal PlugPrincipal caller,
            @PathVariable @Pattern(regexp = "^usr_[A-Za-z0-9-]{1,60}$") String userId) {
        staff.disable(caller, userId);
        return ResponseEntity.noContent().build();
    }

    record AcceptInvite(
            @NotBlank @Size(max = 128) @Pattern(regexp = "^sti_[A-Za-z0-9_-]+$") String inviteToken,
            @NotBlank @Size(max = 256) String password) {
        @Override
        public String toString() {
            return "AcceptInvite[redacted]";
        }
    }

    record Login(@NotBlank @Size(max = 254) String email, @NotBlank @Size(max = 256) String password) {
        @Override
        public String toString() {
            return "Login[redacted]";
        }
    }

    record Verify(
            @NotBlank @Size(max = 64) @Pattern(regexp = "^slc_[A-Za-z0-9-]+$") String challengeId,
            @NotBlank @Pattern(regexp = "^[0-9]{6}$") String code) {
        @Override
        public String toString() {
            return "Verify[redacted]";
        }
    }

    record InviteRequest(@NotBlank @Size(max = 254) String email, @NotBlank @Pattern(regexp = "^(owner|staff)$") String role) {}

    record ChallengeResponse(String challengeId, Instant expiresAt) {}

    record InviteResponse(String inviteId, String email, String role, Instant expiresAt) {}

    record StaffMember(String userId, String email, String role, String status, Instant createdAt) {}

    record StaffList(List<StaffMember> staff) {}
}
