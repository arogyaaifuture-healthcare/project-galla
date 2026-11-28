package app.galla.outlet;
import app.galla.outlet.OutletSettings.*;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
@Repository
class JdbcOutletRepository implements OutletRepository {
  private static final String COLS = "id, code, name, address_line1, address_line2, city, state, postal_code, phone, email, tax_registration_no, license_no, bill_header, bill_footer, version";
  private static final RowMapper<View> MAP = (r, i) -> new View(r.getObject("id", UUID.class), r.getString("code"), r.getString("name"), r.getString("address_line1"), r.getString("address_line2"), r.getString("city"),
      r.getString("state"), r.getString("postal_code"), r.getString("phone"), r.getString("email"), r.getString("tax_registration_no"), r.getString("license_no"), r.getString("bill_header"), r.getString("bill_footer"), r.getLong("version"));
  private final JdbcClient db;
  JdbcOutletRepository(JdbcClient db) { this.db = db; }
  @Override public Optional<View> find(UUID t, UUID id) { return db.sql("SELECT " + COLS + " FROM outlets WHERE tenant_id=:t AND id=:id").param("t", t).param("id", id).query(MAP).optional(); }
  /** CASE WHEN param IS NULL keeps the old value; an empty string clears (NULLIF). */
  @Override public Optional<View> update(UUID t, UUID id, Patch p) {
    return db.sql("""
      UPDATE outlets SET name=coalesce(:name,name),
        address_line1=CASE WHEN CAST(:a1 AS text) IS NULL THEN address_line1 ELSE NULLIF(:a1,'') END, address_line2=CASE WHEN CAST(:a2 AS text) IS NULL THEN address_line2 ELSE NULLIF(:a2,'') END,
        city=CASE WHEN CAST(:city AS text) IS NULL THEN city ELSE NULLIF(:city,'') END, state=CASE WHEN CAST(:state AS text) IS NULL THEN state ELSE NULLIF(:state,'') END,
        postal_code=CASE WHEN CAST(:pin AS text) IS NULL THEN postal_code ELSE NULLIF(:pin,'') END, phone=CASE WHEN CAST(:phone AS text) IS NULL THEN phone ELSE NULLIF(:phone,'') END,
        email=CASE WHEN CAST(:email AS text) IS NULL THEN email ELSE NULLIF(:email,'') END,
        tax_registration_no=CASE WHEN CAST(:gstin AS text) IS NULL THEN tax_registration_no ELSE NULLIF(:gstin,'') END,
        tax_registration_label=CASE WHEN CAST(:gstin AS text) IS NULL THEN tax_registration_label WHEN :gstin='' THEN NULL ELSE 'GSTIN' END,
        license_no=CASE WHEN CAST(:fssai AS text) IS NULL THEN license_no ELSE NULLIF(:fssai,'') END,
        license_label=CASE WHEN CAST(:fssai AS text) IS NULL THEN license_label WHEN :fssai='' THEN NULL ELSE 'FSSAI' END,
        bill_header=CASE WHEN CAST(:hdr AS text) IS NULL THEN bill_header ELSE NULLIF(:hdr,'') END, bill_footer=CASE WHEN CAST(:ftr AS text) IS NULL THEN bill_footer ELSE NULLIF(:ftr,'') END,
        version=version+1, updated_at=now()
      WHERE tenant_id=:t AND id=:id AND version=:v RETURNING """ + " " + COLS)
      .param("name", p.name() == null ? null : p.name().trim()).param("a1", p.addressLine1()).param("a2", p.addressLine2()).param("city", p.city()).param("state", p.state()).param("pin", p.postalCode())
      .param("phone", p.phone()).param("email", p.email()).param("gstin", p.gstin()).param("fssai", p.fssai()).param("hdr", p.billHeader()).param("ftr", p.billFooter())
      .param("t", t).param("id", id).param("v", p.version()).query(MAP).optional();
  }
}
