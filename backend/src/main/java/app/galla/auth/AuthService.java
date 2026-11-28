package app.galla.auth;
import app.galla.auth.AuthDtos.*;
import app.galla.common.ApiException;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {
  private final JdbcClient db; private final PasswordEncoder enc; private final JwtEncoder jwt;
  private final long accessMinutes; private final int maxFailed; private final int lockMinutes;
  private final String dummyHash;
  public AuthService(JdbcClient db, PasswordEncoder enc, JwtEncoder jwt,
      @Value("${galla.jwt.access-minutes}") long accessMinutes,
      @Value("${galla.auth.max-failed-logins}") int maxFailed, @Value("${galla.auth.lock-minutes}") int lockMinutes) {
    this.db = db; this.enc = enc; this.jwt = jwt; this.accessMinutes = accessMinutes; this.maxFailed = maxFailed; this.lockMinutes = lockMinutes;
    this.dummyHash = enc.encode("not-a-real-password"); // equalises timing for unknown emails
  }

  @Transactional
  public TokenResponse register(RegisterRequest r) {
    UUID tenant = UUID.randomUUID(), outlet = UUID.randomUUID(), user = UUID.randomUUID();
    String email = r.email().trim().toLowerCase();
    try {
      db.sql("INSERT INTO tenants(id,name,contact_name,contact_email) VALUES (:id,:n,:cn,:ce)")
        .param("id", tenant).param("n", r.restaurantName().trim()).param("cn", r.ownerName().trim()).param("ce", email).update();
      db.sql("""
        INSERT INTO outlets(id,tenant_id,code,name,country_code,timezone,currency_code,currency_symbol,prices_include_tax,fiscal_year_start_month)
        VALUES (:id,:t,'MAIN',:n,'IN','Asia/Kolkata','INR','₹',false,4)""")
        .param("id", outlet).param("t", tenant).param("n", r.restaurantName().trim()).update();
      db.sql("INSERT INTO users(id,tenant_id,email,password_hash,full_name,role) VALUES (:id,:t,:e,:p,:n,'OWNER')")
        .param("id", user).param("t", tenant).param("e", email).param("p", enc.encode(r.password())).param("n", r.ownerName().trim()).update();
    } catch (DuplicateKeyException e) {
      throw new ApiException(HttpStatus.CONFLICT, "EMAIL_TAKEN", "An account with this email already exists");
    }
    return token(new UserView(user, tenant, r.ownerName().trim(), email, "OWNER"));
  }

  /** Failed-attempt counting is committed even when the login is rejected, so this method is not transactional as a whole. */
  public TokenResponse login(LoginRequest r) {
    String email = r.email().trim().toLowerCase();
    var rows = db.sql("""
        SELECT u.id,u.tenant_id,u.full_name,u.password_hash,u.role,u.status,u.locked_until,t.status AS tenant_status
        FROM users u JOIN tenants t ON t.id=u.tenant_id WHERE lower(u.email)=:e""")
        .param("e", email).query().listOfRows();
    Map<String, Object> row = rows.isEmpty() ? null : rows.get(0);
    if (row == null) { enc.matches(r.password(), dummyHash); throw bad(); }
    UUID id = (UUID) row.get("id");
    var lockedUntil = (java.sql.Timestamp) row.get("locked_until");
    if (lockedUntil != null && lockedUntil.toInstant().isAfter(Instant.now()))
      throw new ApiException(HttpStatus.LOCKED, "ACCOUNT_LOCKED", "Too many attempts. Try again in a few minutes.");
    if (!enc.matches(r.password(), (String) row.get("password_hash"))) {
      db.sql("""
        UPDATE users SET failed_login_attempts = failed_login_attempts + 1,
          locked_until = CASE WHEN failed_login_attempts + 1 >= :max THEN now() + make_interval(mins => :lock) ELSE locked_until END,
          updated_at = now() WHERE id=:id""").param("max", maxFailed).param("lock", lockMinutes).param("id", id).update();
      throw bad();
    }
    if (!"ACTIVE".equals(row.get("status")) || !"ACTIVE".equals(row.get("tenant_status")))
      throw new ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_DISABLED", "This account is not active. Contact your restaurant owner.");
    String role = (String) row.get("role");
    if (r.role() != null && !r.role().equals(role))
      throw new ApiException(HttpStatus.FORBIDDEN, "ROLE_MISMATCH", "This account is not a " + r.role().toLowerCase() + " account");
    db.sql("UPDATE users SET failed_login_attempts=0, locked_until=NULL, last_login_at=now() WHERE id=:id").param("id", id).update();
    return token(new UserView(id, (UUID) row.get("tenant_id"), (String) row.get("full_name"), email, role));
  }

  private static ApiException bad() { return new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "Email or password is incorrect"); }

  private TokenResponse token(UserView u) {
    Instant now = Instant.now();
    JwtClaimsSet c = JwtClaimsSet.builder().subject(u.id().toString()).issuedAt(now).expiresAt(now.plus(Duration.ofMinutes(accessMinutes)))
        .claim("tid", u.tenantId().toString()).claim("role", u.role()).build();
    String t = jwt.encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), c)).getTokenValue();
    return new TokenResponse(t, accessMinutes * 60, u);
  }
}
