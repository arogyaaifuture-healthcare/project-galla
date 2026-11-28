package app.galla.auth;
import app.galla.auth.AuthDtos.*;
import app.galla.security.CurrentUser;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/v1")
public class AuthController {
  private final AuthService auth; private final JdbcClient db;
  public AuthController(AuthService auth, JdbcClient db) { this.auth = auth; this.db = db; }
  @PostMapping("/auth/register") TokenResponse register(@Valid @RequestBody RegisterRequest r) { return auth.register(r); }
  @PostMapping("/auth/login") TokenResponse login(@Valid @RequestBody LoginRequest r) { return auth.login(r); }
  @GetMapping("/me") Map<String, Object> me() {
    var c = CurrentUser.get();
    return db.sql("SELECT id, tenant_id AS \"tenantId\", full_name AS name, email, role FROM users WHERE id=:id AND tenant_id=:t")
        .param("id", c.userId()).param("t", c.tenantId()).query().singleRow();
  }
}
