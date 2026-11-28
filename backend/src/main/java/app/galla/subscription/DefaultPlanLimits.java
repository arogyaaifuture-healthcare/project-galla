package app.galla.subscription;
import app.galla.common.ApiException;
import app.galla.subscription.SubscriptionModels.Plan;
import app.galla.subscription.SubscriptionPorts.*;
import app.galla.user.UserRepository;
import java.util.UUID;
import org.springframework.stereotype.Service;
@Service
class DefaultPlanLimits implements PlanLimits {
  private final SubscriptionRepository subs; private final PlanRepository plans; private final UserRepository users;
  DefaultPlanLimits(SubscriptionRepository subs, PlanRepository plans, UserRepository users) { this.subs = subs; this.plans = plans; this.users = users; }
  private Plan plan(UUID tenantId) { return subs.findByTenant(tenantId, false).flatMap(x -> plans.findById(x.planId())).orElseThrow(() -> ApiException.notFound("Plan")); }
  @Override public void checkCanAddUser(UUID tenantId, String role) {
    var plan = plan(tenantId); int total = users.countActive(tenantId);
    if (total >= plan.maxUsers()) throw ApiException.conflict("PLAN_LIMIT_USERS", "Your plan allows " + plan.maxUsers() + " active users (you have " + total + "). Disable a user or ask for a bigger plan.");
    checkRoleCap(tenantId, role);
  }
  @Override public void checkRoleCap(UUID tenantId, String role) {
    Integer cap = plan(tenantId).roleLimits().get(role);
    if (cap == null) return;
    int n = users.countActiveWithRole(tenantId, role);
    if (n >= cap) throw ApiException.conflict("PLAN_LIMIT_ROLE", "Your plan allows " + cap + " active " + role.toLowerCase() + " users (you have " + n + ").");
  }
}
