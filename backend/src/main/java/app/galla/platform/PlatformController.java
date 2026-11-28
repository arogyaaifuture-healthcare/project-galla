package app.galla.platform;
import app.galla.security.CurrentUser;
import app.galla.subscription.SubscriptionModels.Plan;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

/** Platform console API. Money-related actions are SUPER_ADMIN only. */
@RestController @RequestMapping("/api/v1/platform")
public class PlatformController {
  public record LoginRequest(@NotBlank @Email String email, @NotBlank String password) {}
  public record RejectRequest(@NotBlank @Size(min = 3, max = 300) String reason) {}
  public record PlanPatch(@Size(min = 1, max = 80) String name, @Pattern(regexp = "^\\d{1,8}(\\.\\d{1,2})?$") String priceMonthly, @Pattern(regexp = "^\\d{1,8}(\\.\\d{1,2})?$") String priceYearly,
      @Min(0) @Max(365) Integer trialDays, @Min(1) @Max(1000) Integer maxUsers, @Min(1) @Max(1000) Integer maxOutlets, Boolean active) {}
  public record Me(UUID id, String role) {}

  private static final String ADMIN = "hasRole('SUPER_ADMIN')";
  private final PlatformAuthService auth; private final PlatformBillingService billing;
  public PlatformController(PlatformAuthService auth, PlatformBillingService billing) { this.auth = auth; this.billing = billing; }

  @PostMapping("/auth/login") PlatformAuthService.Login login(@Valid @RequestBody LoginRequest r) { return auth.login(r.email(), r.password()); }
  @GetMapping("/me") Me me() { var p = CurrentUser.Platform.get(); return new Me(p.userId(), p.role()); }

  @GetMapping("/claims") @PreAuthorize(ADMIN) List<Map<String, Object>> claims(@RequestParam(required = false) String status) { return billing.claims(status); }
  @PostMapping("/claims/{id}/confirm") @PreAuthorize(ADMIN) void confirm(@PathVariable UUID id) { billing.confirm(id, CurrentUser.Platform.get().userId()); }
  @PostMapping("/claims/{id}/reject") @PreAuthorize(ADMIN) void reject(@PathVariable UUID id, @Valid @RequestBody RejectRequest r) { billing.reject(id, CurrentUser.Platform.get().userId(), r.reason()); }

  @GetMapping("/settings") @PreAuthorize(ADMIN) Map<String, String> settings() { return billing.settings(); }
  @PutMapping("/settings") @PreAuthorize(ADMIN) Map<String, String> putSettings(@RequestBody Map<String, String> body) { return billing.updateSettings(CurrentUser.Platform.get().userId(), body); }

  @GetMapping("/plans") @PreAuthorize(ADMIN) List<Plan> plans() { return billing.plans(); }
  @PatchMapping("/plans/{id}") @PreAuthorize(ADMIN)
  Plan patchPlan(@PathVariable UUID id, @Valid @RequestBody PlanPatch p) { return billing.updatePlan(CurrentUser.Platform.get().userId(), id, p.name(), p.priceMonthly(), p.priceYearly(), p.trialDays(), p.maxUsers(), p.maxOutlets(), p.active()); }
  @GetMapping("/tenants") @PreAuthorize(ADMIN) List<Map<String, Object>> tenants() { return billing.restaurants(); }
}
