package app.galla.auth;
import app.galla.audit.AuditEvent;
import app.galla.audit.AuditLog;
import app.galla.auth.AuthDtos.*;
import app.galla.common.ApiException;
import app.galla.security.TokenIssuer;
import app.galla.subscription.SubscriptionService;
import app.galla.tenant.TenantRepository;
import app.galla.user.UserRepository;
import java.time.Clock;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class DefaultAuthService implements AuthService {
  private final UserRepository users; private final TenantRepository tenants; private final SubscriptionService subscriptions;
  private final PasswordEncoder encoder; private final TokenIssuer tokens; private final AuditLog audit; private final Clock clock;
  private final int maxFailed, lockMinutes; private final String dummyHash;

  DefaultAuthService(UserRepository users, TenantRepository tenants, SubscriptionService subscriptions, PasswordEncoder encoder, TokenIssuer tokens, AuditLog audit, Clock clock,
      @Value("${galla.auth.max-failed-logins}") int maxFailed, @Value("${galla.auth.lock-minutes}") int lockMinutes) {
    this.users = users; this.tenants = tenants; this.subscriptions = subscriptions; this.encoder = encoder; this.tokens = tokens; this.audit = audit; this.clock = clock;
    this.maxFailed = maxFailed; this.lockMinutes = lockMinutes;
    this.dummyHash = encoder.encode("not-a-real-password"); // equalises timing for unknown e-mails
  }

  @Override @Transactional
  public TokenResponse register(RegisterRequest r) {
    String email = r.email().trim().toLowerCase();
    TenantRepository.Created c;
    try { c = tenants.createWithOwner(r.restaurantName().trim(), r.ownerName().trim(), email, encoder.encode(r.password())); }
    catch (DuplicateKeyException e) { throw ApiException.conflict("EMAIL_TAKEN", "An account with this email already exists"); }
    subscriptions.startTrial(c.tenantId());
    audit.record(AuditEvent.tenantUser(c.tenantId(), c.ownerId(), "TENANT_REGISTERED", "tenant", c.tenantId(), Map.of("email", email)));
    return respond(new UserView(c.ownerId(), c.tenantId(), r.ownerName().trim(), email, "OWNER"));
  }

  /** Not transactional as a whole: a failed-attempt counter must be saved even though the login is rejected. */
  @Override
  public TokenResponse login(LoginRequest r) {
    var found = users.findByEmail(r.email().trim());
    if (found.isEmpty()) { encoder.matches(r.password(), dummyHash); throw invalid(); }
    var u = found.get();
    if (u.lockedUntil() != null && u.lockedUntil().isAfter(clock.instant()))
      throw new ApiException(HttpStatus.LOCKED, "ACCOUNT_LOCKED", "Too many attempts. Try again in a few minutes.");
    if (!encoder.matches(r.password(), u.passwordHash())) {
      users.recordFailedLogin(u.id(), maxFailed, lockMinutes);
      audit.record(AuditEvent.tenantUser(u.tenantId(), u.id(), "LOGIN_FAILED", "user", u.id(), Map.of()));
      throw invalid();
    }
    if (!"ACTIVE".equals(u.status()) || !"ACTIVE".equals(u.tenantStatus()))
      throw new ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_DISABLED", "This account is not active. Contact your restaurant owner.");
    if (r.role() != null && !r.role().equals(u.role()))
      throw new ApiException(HttpStatus.FORBIDDEN, "ROLE_MISMATCH", "This account is not a " + r.role().toLowerCase() + " account");
    users.recordSuccessfulLogin(u.id());
    audit.record(AuditEvent.tenantUser(u.tenantId(), u.id(), "LOGIN", "user", u.id(), Map.of()));
    return respond(new UserView(u.id(), u.tenantId(), u.name(), u.email(), u.role()));
  }

  @Override public UserView me(java.util.UUID userId, java.util.UUID tenantId) {
    var u = users.findById(userId).filter(x -> x.tenantId().equals(tenantId)).orElseThrow(() -> ApiException.notFound("User"));
    return new UserView(u.id(), u.tenantId(), u.name(), u.email(), u.role());
  }

  private static ApiException invalid() { return new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "Email or password is incorrect"); }
  private TokenResponse respond(UserView v) {
    var t = tokens.tenantToken(v.id(), v.tenantId(), v.role());
    return new TokenResponse(t.token(), t.expiresInSeconds(), v);
  }
}
