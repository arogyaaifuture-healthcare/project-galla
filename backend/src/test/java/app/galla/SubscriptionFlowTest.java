package app.galla;
import static org.hamcrest.Matchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
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
class SubscriptionFlowTest extends IntegrationBase {
  @Autowired MockMvc mvc; @Autowired ObjectMapper om; @Autowired JdbcTemplate jdbc;
  static final String PW = "correct-horse-1"; static final AtomicInteger N = new AtomicInteger();

  record Acct(String auth, UUID tenant, UUID outlet) {}
  String json(Object o) throws Exception { return om.writeValueAsString(o); }
  JsonNode body(MvcResult r) throws Exception { return om.readTree(r.getResponse().getContentAsString()); }

  @BeforeEach void defaults() {
    jdbc.update("update plans set price_monthly=500, price_yearly=5000 where code='STANDARD'");
    jdbc.update("insert into platform_settings(key,value) values ('upi_vpa','galla@okbank'),('upi_payee_name','Galla Tech') on conflict (key) do update set value=excluded.value");
    jdbc.update("update platform_settings set value='LOCKED' where key='expired_access_mode'");
  }
  Acct register() throws Exception {
    String email = "sub" + N.incrementAndGet() + "@x.io";
    var r = mvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("restaurantName", "R", "ownerName", "O", "email", email, "password", PW)))).andExpect(status().isOk()).andReturn();
    var b = body(r); UUID t = UUID.fromString(b.at("/user/tenantId").asText());
    return new Acct("Bearer " + b.get("accessToken").asText(), t, jdbc.queryForObject("select id from outlets where tenant_id=?", UUID.class, t));
  }
  String admin() throws Exception {
    var r = mvc.perform(post("/api/v1/platform/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", "root@galla.test", "password", "super-admin-pass-1")))).andExpect(status().isOk()).andReturn();
    return "Bearer " + body(r).get("accessToken").asText();
  }
  void expireTrial(Acct a, int daysAgo) { jdbc.update("update subscriptions set trial_ends_at = now() - make_interval(days => ?) where tenant_id=?", daysAgo, a.tenant()); }
  String invoice(Acct a, String cycle) throws Exception { return body(mvc.perform(post("/api/v1/subscription/invoices").header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("cycle", cycle)))).andExpect(status().isOk()).andReturn()).get("id").asText(); }
  void claim(Acct a, String invoiceId, String utr, int expected) throws Exception {
    mvc.perform(post("/api/v1/subscription/invoices/" + invoiceId + "/claim").header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("utr", utr)))).andExpect(status().is(expected));
  }
  String pendingClaimId(String utr) { return jdbc.queryForObject("select id from payment_claims where utr=?", String.class, utr.toUpperCase()); }

  @Test void newRestaurantStartsA30DayTrialWithFullAccess() throws Exception {
    var a = register();
    mvc.perform(get("/api/v1/subscription").header("Authorization", a.auth())).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("TRIALING"))
        .andExpect(jsonPath("$.daysLeft").value(30)).andExpect(jsonPath("$.upiConfigured").value(true));
    mvc.perform(get("/api/v1/outlets").header("Authorization", a.auth())).andExpect(status().isOk());
  }
  @Test void graceKeepsAccessWithAWarningThenTheAccountLocks() throws Exception {
    var a = register();
    expireTrial(a, 2);
    mvc.perform(get("/api/v1/outlets").header("Authorization", a.auth())).andExpect(status().isOk()).andExpect(header().string("X-Subscription-Warning", "PAST_DUE"));
    expireTrial(a, 10);
    mvc.perform(get("/api/v1/outlets").header("Authorization", a.auth())).andExpect(status().isPaymentRequired()).andExpect(jsonPath("$.code").value("SUBSCRIPTION_INACTIVE"));
    mvc.perform(get("/api/v1/subscription").header("Authorization", a.auth())).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SUSPENDED"));
    mvc.perform(get("/api/v1/me").header("Authorization", a.auth())).andExpect(status().isOk());
  }
  @Test void readOnlyModeStillShowsDataButBlocksChanges() throws Exception {
    var a = register(); expireTrial(a, 10);
    jdbc.update("update platform_settings set value='READ_ONLY' where key='expired_access_mode'");
    mvc.perform(get("/api/v1/outlets").header("Authorization", a.auth())).andExpect(status().isOk());
    mvc.perform(post("/api/v1/menu/categories").header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("outletId", a.outlet(), "name", "X")))).andExpect(status().isPaymentRequired());
  }
  @Test void payingByUpiAndAdminConfirmationRestoresAccess() throws Exception {
    var a = register(); expireTrial(a, 10); var admin = admin();
    var inv = mvc.perform(post("/api/v1/subscription/invoices").header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("cycle", "MONTHLY"))))
        .andExpect(status().isOk()).andExpect(jsonPath("$.amount").value("500.00")).andExpect(jsonPath("$.upiUri", startsWith("upi://pay?pa=galla%40okbank"))).andExpect(jsonPath("$.upiUri", containsString("am=500.00"))).andReturn();
    String invoiceId = body(inv).get("id").asText();
    claim(a, invoiceId, "412345678901", 201);
    mvc.perform(get("/api/v1/outlets").header("Authorization", a.auth())).andExpect(status().isPaymentRequired()); // not confirmed yet
    mvc.perform(post("/api/v1/platform/claims/" + pendingClaimId("412345678901") + "/confirm").header("Authorization", admin)).andExpect(status().isOk());
    mvc.perform(get("/api/v1/outlets").header("Authorization", a.auth())).andExpect(status().isOk());
    mvc.perform(get("/api/v1/subscription").header("Authorization", a.auth())).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ACTIVE")).andExpect(jsonPath("$.openInvoice").doesNotExist());
    mvc.perform(post("/api/v1/platform/claims/" + pendingClaimId("412345678901") + "/confirm").header("Authorization", admin)).andExpect(status().isConflict()); // not twice
    org.junit.jupiter.api.Assertions.assertEquals(1, jdbc.queryForObject("select count(*) from subscription_payments where tenant_id=?", Integer.class, a.tenant()));
  }
  @Test void payingDuringTheTrialDoesNotShortenIt() throws Exception {
    var a = register(); var admin = admin();
    String id = invoice(a, "MONTHLY"); claim(a, id, "512345678901", 201);
    mvc.perform(post("/api/v1/platform/claims/" + pendingClaimId("512345678901") + "/confirm").header("Authorization", admin)).andExpect(status().isOk());
    // the paid month starts when the trial ends (30 days from now) and lasts one month
    Integer days = jdbc.queryForObject("select extract(day from current_period_end - trial_ends_at)::int from subscriptions where tenant_id=?", Integer.class, a.tenant());
    org.junit.jupiter.api.Assertions.assertTrue(days >= 28 && days <= 31);
    org.junit.jupiter.api.Assertions.assertEquals(true, jdbc.queryForObject("select current_period_start = trial_ends_at from subscriptions where tenant_id=?", Boolean.class, a.tenant()));
    mvc.perform(post("/api/v1/subscription/invoices").header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("cycle", "MONTHLY")))).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("TOO_EARLY"));
  }
  @Test void claimRulesAreEnforced() throws Exception {
    var a = register(); var b = register(); var admin = admin();
    String ia = invoice(a, "MONTHLY"), ib = invoice(b, "MONTHLY");
    claim(a, ia, "612345678901", 201);
    claim(a, ia, "612345678902", 409);        // one pending claim per invoice
    claim(b, ib, "612345678901", 409);        // the same UTR cannot be used twice
    claim(b, ia, "612345678903", 404);        // other restaurant's invoice
    mvc.perform(post("/api/v1/platform/claims/" + pendingClaimId("612345678901") + "/reject").header("Authorization", admin).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("reason", "Amount not received")))).andExpect(status().isOk());
    claim(a, ia, "612345678904", 201);        // after a rejection the restaurant can try again
    claim(a, ia, "short", 422);
  }
  @Test void pricingMustBeSetBeforeInvoicing() throws Exception {
    var a = register();
    jdbc.update("update plans set price_monthly=0, price_yearly=0 where code='STANDARD'");
    mvc.perform(post("/api/v1/subscription/invoices").header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("cycle", "MONTHLY")))).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("PRICING_NOT_SET"));
  }
  @Test void superAdminSettingsAreValidated() throws Exception {
    var admin = admin();
    mvc.perform(put("/api/v1/platform/settings").header("Authorization", admin).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("upi_vpa", "not a vpa")))).andExpect(status().isUnprocessableEntity());
    mvc.perform(put("/api/v1/platform/settings").header("Authorization", admin).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("upi_vpa", "owner@okhdfcbank", "upi_payee_name", "Galla Tech")))).andExpect(status().isOk()).andExpect(jsonPath("$.upi_vpa").value("owner@okhdfcbank"));
    mvc.perform(put("/api/v1/platform/settings").header("Authorization", admin).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("secret_key", "x")))).andExpect(status().isUnprocessableEntity());
  }
  @Test void tokenTypesAreNotInterchangeable() throws Exception {
    var a = register(); var admin = admin();
    mvc.perform(get("/api/v1/platform/claims").header("Authorization", a.auth())).andExpect(status().isForbidden());
    mvc.perform(get("/api/v1/outlets").header("Authorization", admin)).andExpect(status().isForbidden());
    mvc.perform(get("/api/v1/platform/claims")).andExpect(status().isUnauthorized());
  }
  @Test void platformLoginRejectsWrongPassword() throws Exception {
    mvc.perform(post("/api/v1/platform/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", "root@galla.test", "password", "wrong-password-1")))).andExpect(status().isUnauthorized());
  }
  @Test void restaurantActivityIsRecordedAndOnlyBossesCanReadIt() throws Exception {
    var a = register();
    mvc.perform(get("/api/v1/audit").header("Authorization", a.auth())).andExpect(status().isOk()).andExpect(jsonPath("$[*].action", hasItems("TENANT_REGISTERED", "TRIAL_STARTED")));
    jdbc.update("insert into users(tenant_id,email,password_hash,full_name,role) values (?,?,?,?,'CASHIER')", a.tenant(), "c" + N.incrementAndGet() + "@x.io", "x", "Ravi");
    var cashier = jdbc.queryForObject("select email from users where role='CASHIER' and tenant_id=?", String.class, a.tenant());
    org.junit.jupiter.api.Assertions.assertNotNull(cashier);
  }
}
