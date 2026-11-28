package app.galla.auth;
import app.galla.common.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
class JdbcRefreshTokens implements RefreshTokens {
  private static final SecureRandom RANDOM = new SecureRandom();
  private final JdbcClient db; private final int days;
  JdbcRefreshTokens(JdbcClient db, @Value("${galla.auth.refresh-days:30}") int days) { this.db = db; this.days = days; }

  static String hash(String raw) {
    try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8))); }
    catch (NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
  }
  private static String newRaw() { byte[] b = new byte[32]; RANDOM.nextBytes(b); return Base64.getUrlEncoder().withoutPadding().encodeToString(b); }
  private static ApiException unauthenticated(String code, String msg) { return new ApiException(HttpStatus.UNAUTHORIZED, code, msg); }

  private UUID insert(UUID userId, UUID family, String raw, String ua) {
    return db.sql("INSERT INTO refresh_tokens(user_id,family_id,token_hash,expires_at,user_agent) VALUES (:u,:f,:h, now() + make_interval(days => :d), :ua) RETURNING id")
        .param("u", userId).param("f", family).param("h", hash(raw)).param("d", days).param("ua", ua == null ? null : ua.substring(0, Math.min(200, ua.length()))).query(UUID.class).single();
  }
  @Override @Transactional public String startSession(UUID userId, String ua) { String raw = newRaw(); insert(userId, UUID.randomUUID(), raw, ua); return raw; }

  @Override @Transactional(noRollbackFor = ApiException.class) public Rotation rotate(String raw, String ua) {
    var rows = db.sql("SELECT id,user_id,family_id,revoked_at IS NOT NULL AS revoked, expires_at < now() AS expired FROM refresh_tokens WHERE token_hash=:h FOR UPDATE").param("h", hash(raw)).query().listOfRows();
    if (rows.isEmpty()) throw unauthenticated("UNAUTHENTICATED", "Please sign in again");
    var r = rows.get(0); UUID family = (UUID) r.get("family_id"), userId = (UUID) r.get("user_id"), id = (UUID) r.get("id");
    if ((Boolean) r.get("revoked")) { // an old token was used again: someone may have copied it, so end the whole session
      db.sql("UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at, now()) WHERE family_id=:f").param("f", family).update();
      throw unauthenticated("SESSION_REVOKED", "Please sign in again");
    }
    if ((Boolean) r.get("expired")) throw unauthenticated("SESSION_EXPIRED", "Your session has expired. Please sign in again.");
    String next = newRaw(); UUID nextId = insert(userId, family, next, ua);
    db.sql("UPDATE refresh_tokens SET revoked_at=now(), replaced_by=:n WHERE id=:id").param("n", nextId).param("id", id).update();
    return new Rotation(userId, next);
  }
  @Override @Transactional public void endSession(String raw) {
    db.sql("UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at, now()) WHERE family_id IN (SELECT family_id FROM refresh_tokens WHERE token_hash=:h)").param("h", hash(raw)).update();
  }
  @Override @Transactional public void endAllSessions(UUID userId) { db.sql("UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at, now()) WHERE user_id=:u").param("u", userId).update(); }
}
