package app.galla;
import static org.hamcrest.Matchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest @AutoConfigureMockMvc
class AuthMenuApiTest extends IntegrationBase {
  @Autowired MockMvc mvc; @Autowired ObjectMapper om; @Autowired JdbcTemplate jdbc; @Autowired PasswordEncoder enc;
  static final String PW = "correct-horse-1";

  record Acct(String token, UUID tenant, UUID outlet) {}

  String json(Object o) throws Exception { return om.writeValueAsString(o); }
  JsonNode body(org.springframework.test.web.servlet.MvcResult r) throws Exception { return om.readTree(r.getResponse().getContentAsString()); }

  Acct register(String email) throws Exception {
    var r = mvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("restaurantName", "Spice " + email, "ownerName", "Asha", "email", email, "password", PW))))
        .andExpect(status().isOk()).andReturn();
    var b = body(r); UUID tenant = UUID.fromString(b.at("/user/tenantId").asText());
    UUID outlet = jdbc.queryForObject("select id from outlets where tenant_id=?", UUID.class, tenant);
    return new Acct(b.get("accessToken").asText(), tenant, outlet);
  }
  String auth(Acct a) { return "Bearer " + a.token(); }
  UUID category(Acct a, String name) throws Exception {
    var r = mvc.perform(post("/api/v1/menu/categories").header("Authorization", auth(a)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("outletId", a.outlet(), "name", name)))).andExpect(status().isCreated()).andReturn();
    return UUID.fromString(body(r).get("id").asText());
  }

  @Test void registerThenLoginAndMe() throws Exception {
    var a = register("owner1@x.io");
    mvc.perform(get("/api/v1/me").header("Authorization", auth(a))).andExpect(status().isOk()).andExpect(jsonPath("$.role").value("OWNER"));
    mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", "OWNER1@x.io", "password", PW, "role", "OWNER"))))
        .andExpect(status().isOk()).andExpect(jsonPath("$.accessToken").isNotEmpty());
  }
  @Test void duplicateEmailIsConflict() throws Exception {
    register("dup@x.io");
    mvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("restaurantName", "B", "ownerName", "B", "email", "DUP@x.io", "password", PW))))
        .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("EMAIL_TAKEN"));
  }
  @Test void shortPasswordIsRejected() throws Exception {
    mvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("restaurantName", "B", "ownerName", "B", "email", "s@x.io", "password", "short"))))
        .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
  }
  @Test void wrongPasswordAndUnknownEmailLookTheSame() throws Exception {
    register("same@x.io");
    for (String e : new String[] {"same@x.io", "nobody@x.io"})
      mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", e, "password", "wrong-password"))))
          .andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_CREDENTIALS"));
  }
  @Test void accountLocksAfterFiveFailures() throws Exception {
    register("lock@x.io");
    for (int i = 0; i < 5; i++)
      mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", "lock@x.io", "password", "wrong-password"))))
          .andExpect(status().isUnauthorized());
    mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", "lock@x.io", "password", PW))))
        .andExpect(status().isLocked()).andExpect(jsonPath("$.code").value("ACCOUNT_LOCKED"));
  }
  @Test void roleSelectorMustMatchTheAccount() throws Exception {
    register("role@x.io");
    mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", "role@x.io", "password", PW, "role", "CASHIER"))))
        .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ROLE_MISMATCH"));
  }
  @Test void missingOrBadTokenGivesJson401() throws Exception {
    mvc.perform(get("/api/v1/me")).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    mvc.perform(get("/api/v1/me").header("Authorization", "Bearer abc.def.ghi")).andExpect(status().isUnauthorized());
  }
  @Test void menuMoneyIsAStringAndValidated() throws Exception {
    var a = register("menu@x.io"); var cat = category(a, "Starters");
    mvc.perform(post("/api/v1/menu/items").header("Authorization", auth(a)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("outletId", a.outlet(), "categoryId", cat, "name", "Paneer Tikka", "basePrice", "120.50", "foodType", "VEG"))))
        .andExpect(status().isCreated()).andExpect(jsonPath("$.basePrice").value("120.50"));
    mvc.perform(post("/api/v1/menu/items").header("Authorization", auth(a)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("outletId", a.outlet(), "categoryId", cat, "name", "Bad", "basePrice", "12.345"))))
        .andExpect(status().isUnprocessableEntity());
    mvc.perform(get("/api/v1/menu/items").param("outletId", a.outlet().toString()).header("Authorization", auth(a)))
        .andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(1)));
    mvc.perform(post("/api/v1/menu/categories").header("Authorization", auth(a)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("outletId", a.outlet(), "name", "Starters")))).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("CATEGORY_EXISTS"));
  }
  @Test void otherTenantsDataIs404() throws Exception {
    var a = register("ta@x.io"); var b = register("tb@x.io"); var cat = category(a, "Mains");
    var item = mvc.perform(post("/api/v1/menu/items").header("Authorization", auth(a)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("outletId", a.outlet(), "categoryId", cat, "name", "Dal", "basePrice", "90")))).andReturn();
    String itemId = body(item).get("id").asText();
    mvc.perform(get("/api/v1/menu/categories").param("outletId", a.outlet().toString()).header("Authorization", auth(b))).andExpect(status().isNotFound());
    mvc.perform(patch("/api/v1/menu/items/" + itemId).header("Authorization", auth(b)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("name", "Hacked", "version", 0)))).andExpect(status().isNotFound());
    mvc.perform(post("/api/v1/menu/items").header("Authorization", auth(b)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("outletId", b.outlet(), "categoryId", cat, "name", "X", "basePrice", "1")))).andExpect(status().isNotFound());
  }
  @Test void cashierCanReadButNotEditTheMenu() throws Exception {
    var a = register("own@x.io");
    jdbc.update("insert into users(tenant_id,email,password_hash,full_name,role) values (?,?,?,?,'CASHIER')", a.tenant(), "cash@x.io", enc.encode(PW), "Ravi");
    var r = mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(json(Map.of("email", "cash@x.io", "password", PW, "role", "CASHIER")))).andExpect(status().isOk()).andReturn();
    String h = "Bearer " + body(r).get("accessToken").asText();
    mvc.perform(get("/api/v1/menu/categories").param("outletId", a.outlet().toString()).header("Authorization", h)).andExpect(status().isOk());
    mvc.perform(post("/api/v1/menu/categories").header("Authorization", h).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("outletId", a.outlet(), "name", "Nope")))).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("FORBIDDEN"));
  }
  @Test void staleItemEditIsRejected() throws Exception {
    var a = register("ver@x.io"); var cat = category(a, "Drinks");
    var item = mvc.perform(post("/api/v1/menu/items").header("Authorization", auth(a)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("outletId", a.outlet(), "categoryId", cat, "name", "Tea", "basePrice", "20")))).andReturn();
    String id = body(item).get("id").asText();
    mvc.perform(patch("/api/v1/menu/items/" + id).header("Authorization", auth(a)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("basePrice", "25.00", "version", 0)))).andExpect(status().isOk()).andExpect(jsonPath("$.version").value(1)).andExpect(jsonPath("$.basePrice").value("25.00"));
    mvc.perform(patch("/api/v1/menu/items/" + id).header("Authorization", auth(a)).contentType(MediaType.APPLICATION_JSON)
        .content(json(Map.of("basePrice", "30.00", "version", 0)))).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("STALE_VERSION"));
  }
}
