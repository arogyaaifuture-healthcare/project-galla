package app.galla.subscription;
import java.util.UUID;
/** The one place that knows what the restaurant's plan allows (plan 18.3). */
public interface PlanLimits {
  /** Throws 409 PLAN_LIMIT_USERS or PLAN_LIMIT_ROLE if one more active user with this role would not fit. */
  void checkCanAddUser(UUID tenantId, String role);
  /** Only the per-role cap (used when an active user changes role: the total does not change). */
  void checkRoleCap(UUID tenantId, String role);
}
