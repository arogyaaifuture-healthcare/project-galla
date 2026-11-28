package app.galla.platform;
import app.galla.audit.AuditEvent;
import app.galla.audit.AuditLog;
import app.galla.common.ApiException;
import app.galla.security.TokenIssuer;
import java.time.Clock;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

/** Sign-in for the platform owner (super admin) and support staff. Separate table, separate token secret. */
@Service
public class PlatformAuthService {
  public record Login(String accessToken, long expiresInSeconds, String name, String role) {}
  private final PlatformUserRepository users; private final PasswordEncoder encoder; private final TokenIssuer tokens; private final AuditLog audit; private final Clock clock;
  private final int maxFailed, lockMinutes; private final String dummy;
  PlatformAuthService(PlatformUserRepository users, PasswordEncoder encoder, TokenIssuer tokens, AuditLog audit, Clock clock,
      @Value("${galla.auth.max-failed-logins}") int maxFailed, @Value("${galla.auth.lock-minutes}") int lockMinutes) {
    this.users = users; this.encoder = encoder; this.tokens = tokens; this.audit = audit; this.clock = clock; this.maxFailed = maxFailed; this.lockMinutes = lockMinutes;
    this.dummy = encoder.encode("not-a-real-password");
  }
  public Login login(String email, String password) {
    var found = users.findByEmail(email.trim());
    if (found.isEmpty()) { encoder.matches(password, dummy); throw bad(); }
    var u = found.get();
    if (u.lockedUntil() != null && u.lockedUntil().isAfter(clock.instant())) throw new ApiException(HttpStatus.LOCKED, "ACCOUNT_LOCKED", "Too many attempts. Try again in a few minutes.");
    if (!encoder.matches(password, u.passwordHash())) { users.recordFailedLogin(u.id(), maxFailed, lockMinutes); throw bad(); }
    if (!"ACTIVE".equals(u.status())) throw new ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_DISABLED", "This account is not active.");
    users.recordSuccessfulLogin(u.id());
    audit.record(AuditEvent.platformUser(null, u.id(), "PLATFORM_LOGIN", "platform_user", u.id(), Map.of(), null));
    var t = tokens.platformToken(u.id(), u.role());
    return new Login(t.token(), t.expiresInSeconds(), u.name(), u.role());
  }
  private static ApiException bad() { return new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "Email or password is incorrect"); }
}
