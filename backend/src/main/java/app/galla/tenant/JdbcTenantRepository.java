package app.galla.tenant;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
@Repository
class JdbcTenantRepository implements TenantRepository {
  private final JdbcClient db;
  JdbcTenantRepository(JdbcClient db) { this.db = db; }
  @Override public Created createWithOwner(String restaurant, String owner, String email, String hash) {
    UUID t = UUID.randomUUID(), o = UUID.randomUUID(), u = UUID.randomUUID();
    db.sql("INSERT INTO tenants(id,name,contact_name,contact_email) VALUES (:id,:n,:cn,:ce)").param("id", t).param("n", restaurant).param("cn", owner).param("ce", email).update();
    db.sql("""
      INSERT INTO outlets(id,tenant_id,code,name,country_code,timezone,currency_code,currency_symbol,prices_include_tax,fiscal_year_start_month)
      VALUES (:id,:t,'MAIN',:n,'IN','Asia/Kolkata','INR','₹',false,4)""").param("id", o).param("t", t).param("n", restaurant).update();
    db.sql("INSERT INTO users(id,tenant_id,email,password_hash,full_name,role) VALUES (:id,:t,:e,:p,:n,'OWNER')").param("id", u).param("t", t).param("e", email).param("p", hash).param("n", owner).update();
    return new Created(t, o, u);
  }
}
