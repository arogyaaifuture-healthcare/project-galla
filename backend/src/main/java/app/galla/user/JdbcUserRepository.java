package app.galla.user;
import java.sql.Timestamp;
import java.util.List;
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
  private static final org.springframework.jdbc.core.RowMapper<Member> MEMBER = (r, i) -> {
    Timestamp l = r.getTimestamp("last_login_at");
    return new Member(r.getObject("id", UUID.class), r.getString("full_name"), r.getString("email"), r.getString("phone"), r.getString("role"), r.getString("status"), l == null ? null : l.toInstant());
  };
  private static final String MEMBER_COLS = "id, full_name, email, phone, role, status, last_login_at";
  @Override public List<Member> list(UUID t) { return db.sql("SELECT " + MEMBER_COLS + " FROM users WHERE tenant_id=:t ORDER BY (role='OWNER') DESC, full_name").param("t", t).query(MEMBER).list(); }
  @Override public Optional<Member> findMember(UUID t, UUID id) { return db.sql("SELECT " + MEMBER_COLS + " FROM users WHERE tenant_id=:t AND id=:id").param("t", t).param("id", id).query(MEMBER).optional(); }
  @Override public Member create(UUID t, String name, String email, String phone, String role, String hash) {
    return db.sql("INSERT INTO users(tenant_id,email,password_hash,full_name,phone,role) VALUES (:t,:e,:h,:n,:p,:r) RETURNING " + MEMBER_COLS)
        .param("t", t).param("e", email).param("h", hash).param("n", name).param("p", phone).param("r", role).query(MEMBER).single();
  }
  @Override public Optional<Member> update(UUID t, UUID id, String name, String role, String status) {
    return db.sql("UPDATE users SET full_name=coalesce(:n,full_name), role=coalesce(:r,role), status=coalesce(:s,status), version=version+1, updated_at=now() WHERE tenant_id=:t AND id=:id RETURNING " + MEMBER_COLS)
        .param("n", name).param("r", role).param("s", status).param("t", t).param("id", id).query(MEMBER).optional();
  }
  @Override public void setPassword(UUID t, UUID id, String hash) {
    db.sql("UPDATE users SET password_hash=:h, failed_login_attempts=0, locked_until=NULL, updated_at=now() WHERE tenant_id=:t AND id=:id").param("h", hash).param("t", t).param("id", id).update();
  }
  @Override public int countActive(UUID t) { return db.sql("SELECT count(*) FROM users WHERE tenant_id=:t AND status='ACTIVE'").param("t", t).query(Integer.class).single(); }
  @Override public int countActiveWithRole(UUID t, String role) { return db.sql("SELECT count(*) FROM users WHERE tenant_id=:t AND status='ACTIVE' AND role=:r").param("t", t).param("r", role).query(Integer.class).single(); }
  @Override public boolean isActive(UUID id) { return db.sql("SELECT 1 FROM users u JOIN tenants t ON t.id=u.tenant_id WHERE u.id=:id AND u.status='ACTIVE' AND t.status='ACTIVE'").param("id", id).query().listOfRows().size() == 1; }
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
