package app.galla.user;
import java.sql.Timestamp;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
@Repository
class JdbcUserRepository implements UserRepository {
  private static final String SELECT = """
      SELECT u.id,u.tenant_id,u.full_name,u.email,u.password_hash,u.role,u.status,u.locked_until,t.status AS tenant_status
      FROM users u JOIN tenants t ON t.id=u.tenant_id""";
  private final JdbcClient db;
  JdbcUserRepository(JdbcClient db) { this.db = db; }
  private static Account map(java.util.Map<String, Object> r) {
    Timestamp l = (Timestamp) r.get("locked_until");
    return new Account((UUID) r.get("id"), (UUID) r.get("tenant_id"), (String) r.get("full_name"), (String) r.get("email"), (String) r.get("password_hash"),
        (String) r.get("role"), (String) r.get("status"), l == null ? null : l.toInstant(), (String) r.get("tenant_status"));
  }
  @Override public Optional<Account> findByEmail(String email) {
    return db.sql(SELECT + " WHERE lower(u.email)=lower(:e)").param("e", email).query().listOfRows().stream().findFirst().map(JdbcUserRepository::map);
  }
  @Override public Optional<Account> findById(UUID id) {
    return db.sql(SELECT + " WHERE u.id=:id").param("id", id).query().listOfRows().stream().findFirst().map(JdbcUserRepository::map);
  }
  @Override public void recordFailedLogin(UUID id, int max, int lockMinutes) {
    db.sql("""
      UPDATE users SET failed_login_attempts = failed_login_attempts + 1,
        locked_until = CASE WHEN failed_login_attempts + 1 >= :max THEN now() + make_interval(mins => :lock) ELSE locked_until END, updated_at = now()
      WHERE id=:id""").param("max", max).param("lock", lockMinutes).param("id", id).update();
  }
  @Override public void recordSuccessfulLogin(UUID id) {
    db.sql("UPDATE users SET failed_login_attempts=0, locked_until=NULL, last_login_at=now() WHERE id=:id").param("id", id).update();
  }
}
