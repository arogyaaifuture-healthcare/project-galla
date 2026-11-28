package app.galla.platform;
import java.sql.Timestamp;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
@Repository
class JdbcPlatformUserRepository implements PlatformUserRepository {
  private final JdbcClient db;
  JdbcPlatformUserRepository(JdbcClient db) { this.db = db; }
  @Override public Optional<PUser> findByEmail(String email) {
    return db.sql("SELECT id,email,full_name,password_hash,role,status,locked_until FROM platform_users WHERE lower(email)=lower(:e)").param("e", email).query((r, i) -> {
      Timestamp l = r.getTimestamp("locked_until");
      return new PUser(r.getObject("id", UUID.class), r.getString("email"), r.getString("full_name"), r.getString("password_hash"), r.getString("role"), r.getString("status"), l == null ? null : l.toInstant());
    }).optional();
  }
  @Override public boolean anyExist() { return db.sql("SELECT count(*) FROM platform_users").query(Integer.class).single() > 0; }
  @Override public UUID create(String email, String name, String hash, String role) {
    return db.sql("INSERT INTO platform_users(email,full_name,password_hash,role) VALUES (:e,:n,:p,:r) RETURNING id").param("e", email).param("n", name).param("p", hash).param("r", role).query(UUID.class).single();
  }
  @Override public void recordFailedLogin(UUID id, int max, int lockMinutes) {
    db.sql("UPDATE platform_users SET failed_login_attempts=failed_login_attempts+1, locked_until=CASE WHEN failed_login_attempts+1>=:m THEN now()+make_interval(mins=>:l) ELSE locked_until END, updated_at=now() WHERE id=:id")
      .param("m", max).param("l", lockMinutes).param("id", id).update();
  }
  @Override public void recordSuccessfulLogin(UUID id) { db.sql("UPDATE platform_users SET failed_login_attempts=0, locked_until=NULL, last_login_at=now() WHERE id=:id").param("id", id).update(); }
}
