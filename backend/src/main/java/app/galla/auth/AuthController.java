package app.galla.auth;
import app.galla.auth.AuthDtos.*;
import app.galla.security.CurrentUser;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.web.bind.annotation.*;
import java.time.Duration;

/** Thin adapter: HTTP in, HTTP out. All rules live in AuthService. The refresh token travels only in an HttpOnly cookie. */
@RestController @RequestMapping("/api/v1")
public class AuthController {
  private static final String COOKIE = "galla_rt";
  private final AuthService auth; private final boolean secureCookie; private final int days;
  public AuthController(AuthService auth, @Value("${galla.cookie.secure:true}") boolean secureCookie, @Value("${galla.auth.refresh-days:30}") int days) { this.auth = auth; this.secureCookie = secureCookie; this.days = days; }

  private static String ua(HttpServletRequest r) { return r.getHeader(HttpHeaders.USER_AGENT); }
  private ResponseCookie cookie(String value, Duration age) {
    return ResponseCookie.from(COOKIE, value).httpOnly(true).secure(secureCookie).sameSite("Strict").path("/api/v1/auth").maxAge(age).build();
  }
  private TokenResponse send(AuthResult r, HttpServletResponse res) {
    res.addHeader(HttpHeaders.SET_COOKIE, cookie(r.refreshToken(), Duration.ofDays(days)).toString());
    return r.body();
  }
  private static String token(HttpServletRequest req) {
    if (req.getCookies() == null) return null;
    for (var c : req.getCookies()) if (COOKIE.equals(c.getName())) return c.getValue();
    return null;
  }

  @PostMapping("/auth/register") TokenResponse register(@Valid @RequestBody RegisterRequest r, HttpServletRequest req, HttpServletResponse res) { return send(auth.register(r, ua(req)), res); }
  @PostMapping("/auth/login") TokenResponse login(@Valid @RequestBody LoginRequest r, HttpServletRequest req, HttpServletResponse res) { return send(auth.login(r, ua(req)), res); }
  @PostMapping("/auth/refresh") TokenResponse refresh(HttpServletRequest req, HttpServletResponse res) {
    String t = token(req);
    if (t == null) throw new app.galla.common.ApiException(org.springframework.http.HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED", "Please sign in again");
    try { return send(auth.refresh(t, ua(req)), res); }
    catch (app.galla.common.ApiException e) { res.addHeader(HttpHeaders.SET_COOKIE, cookie("", Duration.ZERO).toString()); throw e; }
  }
  @PostMapping("/auth/logout") void logout(HttpServletRequest req, HttpServletResponse res) {
    auth.logout(token(req)); res.addHeader(HttpHeaders.SET_COOKIE, cookie("", Duration.ZERO).toString());
  }
  @GetMapping("/me") UserView me() { var c = CurrentUser.get(); return auth.me(c.userId(), c.tenantId()); }
}
