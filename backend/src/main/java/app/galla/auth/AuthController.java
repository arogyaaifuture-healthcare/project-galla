package app.galla.auth;
import app.galla.auth.AuthDtos.*;
import app.galla.security.CurrentUser;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

/** Thin adapter: HTTP in, HTTP out. All rules live in AuthService. */
@RestController @RequestMapping("/api/v1")
public class AuthController {
  private final AuthService auth;
  public AuthController(AuthService auth) { this.auth = auth; }
  @PostMapping("/auth/register") TokenResponse register(@Valid @RequestBody RegisterRequest r) { return auth.register(r); }
  @PostMapping("/auth/login") TokenResponse login(@Valid @RequestBody LoginRequest r) { return auth.login(r); }
  @GetMapping("/me") UserView me() { var c = CurrentUser.get(); return auth.me(c.userId(), c.tenantId()); }
}
