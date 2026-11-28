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
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest @AutoConfigureMockMvc
class StaffSessionOutletTest extends IntegrationBase {
  @Autowired MockMvc mvc; @Autowired ObjectMapper om; @Autowired JdbcTemplate jdbc;
  static final String PW = "correct-horse-1"; static final AtomicInteger N = new AtomicInteger();
  record Acct(String auth, UUID tenant, UUID outlet, String email, MvcResult reg) {}

  String json(Object o) throws Exception { return om.writeValueAsString(o); }
  JsonNode body(MvcResult r) throws Exception { return om.readTree(r.getResponse().getContentAsString()); }
  @AfterEach void resetPlan() { jdbc.update("update plans set max_users=10, role_limits='{}'::jsonb where code='STANDARD'"); }

  Acct register() throws Exception {
    String email = "own" + N.incrementAndGet() + "@x.io";
    var r = mvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("restaurantName", "R", "ownerName", "O", "email", email, "password", PW)))).andExpect(status().isOk()).andReturn();
    UUID t = UUID.fromString(body(r).at("/user/tenantId").asText());
    return new Acct("Bearer " + body(r).get("accessToken").asText(), t, jdbc.queryForObject("select id from outlets where tenant_id=?", UUID.class, t), email, r);
  }
  static String cookieOf(MvcResult r) { String h = r.getResponse().getHeader("Set-Cookie"); return h.substring("galla_rt=".length(), h.indexOf(';')); }
  MvcResult login(String email, String pw, int expected) throws Exception {
    return mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", email, "password", pw)))).andExpect(status().is(expected)).andReturn();
  }
  String tokenOf(MvcResult r) throws Exception { return "Bearer " + body(r).get("accessToken").asText(); }
  JsonNode addStaff(Acct a, String role, String email, int expected) throws Exception {
    var r = mvc.perform(post("/api/v1/users").header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("name", "Staff " + role, "email", email, "role", role, "password", PW)))).andExpect(status().is(expected)).andReturn();
    return om.readTree(r.getResponse().getContentAsString());
  }

  // ---------- sessions
  @Test void refreshRotatesAndReuseKillsTheSession() throws Exception {
    var a = register(); String c1 = cookieOf(a.reg());
    String header = a.reg().getResponse().getHeader("Set-Cookie");
    Assertions.assertTrue(header.contains("HttpOnly") && header.contains("SameSite=Strict") && header.contains("Path=/api/v1/auth"), header);
    var r2 = mvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("galla_rt", c1))).andExpect(status().isOk()).andExpect(jsonPath("$.accessToken").isNotEmpty()).andReturn();
    String c2 = cookieOf(r2); Assertions.assertNotEquals(c1, c2);
    mvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("galla_rt", c1))).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("SESSION_REVOKED")); // old token reused
    mvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("galla_rt", c2))).andExpect(status().isUnauthorized()); // whole family is dead now
    mvc.perform(post("/api/v1/auth/refresh")).andExpect(status().isUnauthorized());
  }
  @Test void logoutEndsTheSession() throws Exception {
    var a = register(); String c = cookieOf(a.reg());
    mvc.perform(post("/api/v1/auth/logout").cookie(new Cookie("galla_rt", c))).andExpect(status().isOk());
    mvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("galla_rt", c))).andExpect(status().isUnauthorized());
  }

  // ---------- staff
  @Test void ownerManagesStaffAndRolesAreRespected() throws Exception {
    var a = register();
    var cashier = addStaff(a, "CASHIER", "cash" + N.incrementAndGet() + "@x.io", 201);
    var manager = addStaff(a, "MANAGER", "mgr" + N.incrementAndGet() + "@x.io", 201);
    mvc.perform(get("/api/v1/users").header("Authorization", a.auth())).andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(3)));
    addStaff(a, "CASHIER", cashier.get("email").asText(), 409);
    var mgrTok = tokenOf(login(manager.get("email").asText(), PW, 200));
    var cashTok = tokenOf(login(cashier.get("email").asText(), PW, 200));
    mvc.perform(get("/api/v1/users").header("Authorization", cashTok)).andExpect(status().isForbidden());
    mvc.perform(post("/api/v1/users").header("Authorization", mgrTok).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("name", "X", "email", "x" + N.incrementAndGet() + "@x.io", "role", "OWNER", "password", PW)))).andExpect(status().isForbidden());
    String ownerId = jdbc.queryForObject("select id::text from users where tenant_id=? and role='OWNER'", String.class, a.tenant());
    mvc.perform(patch("/api/v1/users/" + ownerId).header("Authorization", mgrTok).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("name", "Hacked")))).andExpect(status().isForbidden());
    mvc.perform(patch("/api/v1/users/" + ownerId).header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("active", false)))).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("CANNOT_DISABLE_SELF"));
    mvc.perform(patch("/api/v1/users/" + ownerId).header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("role", "MANAGER")))).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("CANNOT_CHANGE_OWN_ROLE"));
  }
  @Test void lastOwnerCannotBeRemoved() throws Exception {
    var a = register(); var second = addStaff(a, "OWNER", "own2" + N.incrementAndGet() + "@x.io", 201);
    var tok2 = tokenOf(login(second.get("email").asText(), PW, 200));
    String firstId = jdbc.queryForObject("select id::text from users where email=?", String.class, a.email());
    mvc.perform(patch("/api/v1/users/" + firstId).header("Authorization", tok2).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("active", false)))).andExpect(status().isOk()); // two owners: fine
    mvc.perform(get("/api/v1/me").header("Authorization", a.auth())).andExpect(status().isUnauthorized()); // disabled -> token stops working at once
    mvc.perform(patch("/api/v1/users/" + second.get("id").asText()).header("Authorization", tok2).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("active", false)))).andExpect(status().isConflict()); // self (checked first)
  }
  @Test void disablingAUserCutsAccessImmediately() throws Exception {
    var a = register(); var cashier = addStaff(a, "CASHIER", "cd" + N.incrementAndGet() + "@x.io", 201);
    var loginRes = login(cashier.get("email").asText(), PW, 200); String tok = tokenOf(loginRes); String rt = cookieOf(loginRes);
    mvc.perform(get("/api/v1/outlets").header("Authorization", tok)).andExpect(status().isOk());
    mvc.perform(patch("/api/v1/users/" + cashier.get("id").asText()).header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("active", false)))).andExpect(status().isOk());
    mvc.perform(get("/api/v1/outlets").header("Authorization", tok)).andExpect(status().isUnauthorized());
    login(cashier.get("email").asText(), PW, 403);
    mvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("galla_rt", rt))).andExpect(status().isUnauthorized());
  }
  @Test void planLimitsApplyToActiveUsers() throws Exception {
    var a = register();
    jdbc.update("update plans set max_users=2, role_limits='{\"CASHIER\":1}'::jsonb where code='STANDARD'");
    addStaff(a, "CASHIER", "pl" + N.incrementAndGet() + "@x.io", 201);                   // owner + 1 cashier = 2 users
    var r = addStaff(a, "MANAGER", "pl" + N.incrementAndGet() + "@x.io", 409); Assertions.assertEquals("PLAN_LIMIT_USERS", r.get("code").asText());
    jdbc.update("update plans set max_users=5 where code='STANDARD'");
    var r2 = addStaff(a, "CASHIER", "pl" + N.incrementAndGet() + "@x.io", 409); Assertions.assertEquals("PLAN_LIMIT_ROLE", r2.get("code").asText());
    addStaff(a, "KITCHEN", "pl" + N.incrementAndGet() + "@x.io", 201);                    // other roles are only limited by the total
  }
  @Test void ownerCanResetAPasswordAndOldSessionsDie() throws Exception {
    var a = register(); var cashier = addStaff(a, "CASHIER", "rp" + N.incrementAndGet() + "@x.io", 201);
    var res = login(cashier.get("email").asText(), PW, 200); String rt = cookieOf(res);
    mvc.perform(post("/api/v1/users/" + cashier.get("id").asText() + "/reset-password").header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("password", "brand-new-password-9")))).andExpect(status().isOk());
    login(cashier.get("email").asText(), PW, 401); login(cashier.get("email").asText(), "brand-new-password-9", 200);
    mvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("galla_rt", rt))).andExpect(status().isUnauthorized());
  }

  // ---------- outlet settings
  @Test void outletSettingsAreValidatedAndVersioned() throws Exception {
    var a = register(); String url = "/api/v1/outlets/" + a.outlet();
    var cur = body(mvc.perform(get(url).header("Authorization", a.auth())).andExpect(status().isOk()).andReturn());
    long v = cur.get("version").asLong();
    mvc.perform(patch(url).header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("gstin", "BAD", "version", v)))).andExpect(status().isUnprocessableEntity());
    mvc.perform(patch(url).header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("gstin", "27ABCDE1234F1Z5", "fssai", "12345678901234", "city", "Pune", "postalCode", "411001", "version", v))))
        .andExpect(status().isOk()).andExpect(jsonPath("$.gstin").value("27ABCDE1234F1Z5")).andExpect(jsonPath("$.version").value(v + 1));
    Assertions.assertEquals("GSTIN", jdbc.queryForObject("select tax_registration_label from outlets where id=?", String.class, a.outlet()));
    mvc.perform(patch(url).header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("city", "Mumbai", "version", v)))).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("STALE_VERSION"));
    mvc.perform(patch(url).header("Authorization", a.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("gstin", "", "version", v + 1)))).andExpect(status().isOk()).andExpect(jsonPath("$.gstin").doesNotExist()).andExpect(jsonPath("$.city").value("Pune"));
  }
  @Test void outletSettingsAreTenantScopedAndOwnerOrManagerOnly() throws Exception {
    var a = register(); var b = register(); var cashier = addStaff(a, "CASHIER", "oc" + N.incrementAndGet() + "@x.io", 201);
    String url = "/api/v1/outlets/" + a.outlet();
    mvc.perform(get(url).header("Authorization", b.auth())).andExpect(status().isNotFound());
    mvc.perform(patch(url).header("Authorization", b.auth()).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("city", "X", "version", 0)))).andExpect(status().isNotFound());
    var ct = tokenOf(login(cashier.get("email").asText(), PW, 200));
    mvc.perform(get(url).header("Authorization", ct)).andExpect(status().isOk());
    mvc.perform(patch(url).header("Authorization", ct).contentType(MediaType.APPLICATION_JSON).content(json(Map.of("city", "X", "version", 0)))).andExpect(status().isForbidden());
  }
}
