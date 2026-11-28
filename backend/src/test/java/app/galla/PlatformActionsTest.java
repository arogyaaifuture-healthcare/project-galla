package app.galla;
import static org.hamcrest.Matchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.Cookie;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest @AutoConfigureMockMvc
class PlatformActionsTest extends IntegrationBase {
  @Autowired MockMvc mvc; @Autowired ObjectMapper om; @Autowired JdbcTemplate jdbc;
  static final String PW = "correct-horse-1"; static final AtomicInteger N = new AtomicInteger();
  record Acct(String auth, UUID tenant, String email, String cookie) {}
  String json(Object o) throws Exception { return om.writeValueAsString(o); }
  JsonNode body(MvcResult r) throws Exception { return om.readTree(r.getResponse().getContentAsString()); }

  @BeforeEach void defaults() {
    jdbc.update("update plans set price_monthly=500, price_yearly=5000 where code='STANDARD'");
    jdbc.update("insert into platform_settings(key,value) values ('upi_vpa','galla@okbank'),('upi_payee_name','Galla Tech') on conflict (key) do update set value=excluded.value");
    jdbc.update("update platform_settings set value='LOCKED' where key='expired_access_mode'");
  }
  Acct register() throws Exception {
    String email = "pa" + N.incrementAndGet() + "@x.io";
    var r = mvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("restaurantName", "R", "ownerName", "O", "email", email, "password", PW)))).andExpect(status().isOk()).andReturn();
    var b = body(r); String h = r.getResponse().getHeader("Set-Cookie");
    return new Acct("Bearer " + b.get("accessToken").asText(), UUID.fromString(b.at("/user/tenantId").asText()), email, h.substring(9, h.indexOf(';')));
  }
  String admin() throws Exception {
    var r = mvc.perform(post("/api/v1/platform/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", "root@galla.test", "password", "super-admin-pass-1")))).andExpect(status().isOk()).andReturn();
    return "Bearer " + body(r).get("accessToken").asText();
  }
  void post(String url, String auth, Object b, int expected) throws Exception {
    mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post(url).header("Authorization", auth).contentType(MediaType.APPLICATION_JSON).content(json(b))).andExpect(status().is(expected));
  }
  /** Registers, ends the trial, requests an invoice, submits a UTR and has the super admin confirm it. */
  Acct paid() throws Exception {
    var a = register(); String adm = admin();
    jdbc.update("update subscriptions set trial_ends_at = now() - interval '10 days' where tenant_id=?", a.tenant());
    String inv = body(mvc.perform(post("/api/v1/subscription/invoices").header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("cycle", "MONTHLY")))).andExpect(status().isOk()).andReturn()).get("id").asText();
    String utr = "UTR" + System.nanoTime(); utr = utr.substring(0, Math.min(utr.length(), 20));
    post("/api/v1/subscription/invoices/" + inv + "/claim", a.auth(), Map.of("utr", utr), 201);
    String claim = jdbc.queryForObject("select id::text from payment_claims where utr=?", String.class, utr.toUpperCase());
    mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/api/v1/platform/claims/" + claim + "/confirm").header("Authorization", adm)).andExpect(status().isOk());
    return a;
  }

  @Test void extendingATrialRestoresALockedRestaurant() throws Exception {
    var a = register(); String adm = admin();
    jdbc.update("update subscriptions set trial_ends_at = now() - interval '10 days' where tenant_id=?", a.tenant());
    mvc.perform(get("/api/v1/outlets").header("Authorization", a.auth())).andExpect(status().isPaymentRequired());
    post("/api/v1/platform/tenants/" + a.tenant() + "/extend-trial", adm, Map.of("days", 100, "reason", "goodwill"), 422);
    post("/api/v1/platform/tenants/" + a.tenant() + "/extend-trial", adm, Map.of("days", 5), 422);
    post("/api/v1/platform/tenants/" + a.tenant() + "/extend-trial", adm, Map.of("days", 5, "reason", "onboarding delay"), 200);
    mvc.perform(get("/api/v1/outlets").header("Authorization", a.auth())).andExpect(status().isOk());
    mvc.perform(get("/api/v1/subscription").header("Authorization", a.auth())).andExpect(jsonPath("$.status").value("TRIALING")).andExpect(jsonPath("$.daysLeft").value(5));
    Assertions_eq(1, jdbc.queryForObject("select count(*) from audit_logs where tenant_id=? and action='TRIAL_EXTENDED'", Integer.class, a.tenant()));
    post("/api/v1/platform/tenants/" + UUID.randomUUID() + "/extend-trial", adm, Map.of("days", 5, "reason", "unknown"), 404);
  }
  @Test void paidRestaurantsCannotGetATrialExtension() throws Exception {
    var a = paid();
    post("/api/v1/platform/tenants/" + a.tenant() + "/extend-trial", admin(), Map.of("days", 5, "reason", "try"), 409);
  }
  @Test void suspendingARestaurantCutsEveryoneOffUntilReactivated() throws Exception {
    var a = register(); String adm = admin();
    post("/api/v1/platform/tenants/" + a.tenant() + "/suspend", adm, Map.of("reason", "abuse report"), 200);
    mvc.perform(get("/api/v1/outlets").header("Authorization", a.auth())).andExpect(status().isUnauthorized());
    mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", a.email(), "password", PW)))).andExpect(status().isForbidden());
    mvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("galla_rt", a.cookie()))).andExpect(status().isUnauthorized());
    post("/api/v1/platform/tenants/" + a.tenant() + "/reactivate", adm, Map.of("reason", "resolved"), 200);
    mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", a.email(), "password", PW)))).andExpect(status().isOk());
  }
  @Test void platformActionsAreForTheSuperAdminOnly() throws Exception {
    var a = register();
    post("/api/v1/platform/tenants/" + a.tenant() + "/suspend", a.auth(), Map.of("reason", "nope nope"), 403);
    mvc.perform(get("/api/v1/platform/dashboard").header("Authorization", a.auth())).andExpect(status().isForbidden());
    mvc.perform(get("/api/v1/platform/dashboard")).andExpect(status().isUnauthorized());
  }
  @Test void dashboardShowsCountsAndMoneyCollected() throws Exception {
    paid();
    mvc.perform(get("/api/v1/platform/dashboard").header("Authorization", admin())).andExpect(status().isOk())
        .andExpect(jsonPath("$.restaurantsByStatus.ACTIVE").value(greaterThanOrEqualTo(1))).andExpect(jsonPath("$.pendingPayments").isNumber())
        .andExpect(jsonPath("$.collectedThisMonth", matchesPattern("^\\d+\\.\\d{2}$")));
  }
  @Test void ownerSeesInvoicesAndCanCancelAndResume() throws Exception {
    var a = paid();
    mvc.perform(get("/api/v1/subscription/invoices").header("Authorization", a.auth())).andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(1)))
        .andExpect(jsonPath("$[0].status").value("PAID")).andExpect(jsonPath("$[0].total").value("500.00")).andExpect(jsonPath("$[0].number", startsWith("GL-INV-")));
    post("/api/v1/subscription/cancel", a.auth(), Map.of(), 200); post("/api/v1/subscription/cancel", a.auth(), Map.of(), 200);   // idempotent
    mvc.perform(get("/api/v1/subscription").header("Authorization", a.auth())).andExpect(jsonPath("$.cancelAtPeriodEnd").value(true)).andExpect(jsonPath("$.status").value("ACTIVE"));
    post("/api/v1/subscription/resume", a.auth(), Map.of(), 200);
    mvc.perform(get("/api/v1/subscription").header("Authorization", a.auth())).andExpect(jsonPath("$.cancelAtPeriodEnd").value(false));
    // once the paid period is over, a cancelled plan stays cancelled
    post("/api/v1/subscription/cancel", a.auth(), Map.of(), 200);
    jdbc.update("update subscriptions set current_period_end = now() - interval '1 day' where tenant_id=?", a.tenant());
    mvc.perform(get("/api/v1/subscription").header("Authorization", a.auth())).andExpect(jsonPath("$.status").value("CANCELLED"));
    post("/api/v1/subscription/resume", a.auth(), Map.of(), 409);
  }
  @Test void trialsCannotBeCancelledAndInvoicesAreTenantScoped() throws Exception {
    var a = register(); var b = paid();
    post("/api/v1/subscription/cancel", a.auth(), Map.of(), 409);
    mvc.perform(get("/api/v1/subscription/invoices").header("Authorization", a.auth())).andExpect(jsonPath("$", hasSize(0)));
    mvc.perform(get("/api/v1/subscription/invoices").header("Authorization", b.auth())).andExpect(jsonPath("$", hasSize(1)));
  }
  private static void Assertions_eq(int expected, Integer actual) { org.junit.jupiter.api.Assertions.assertEquals(expected, actual); }
}
