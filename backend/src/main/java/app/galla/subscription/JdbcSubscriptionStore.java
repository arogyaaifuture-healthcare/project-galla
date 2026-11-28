package app.galla.subscription;
import app.galla.subscription.SubscriptionModels.*;
import app.galla.subscription.SubscriptionPorts.*;
import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** JDBC adapters for all subscription ports. */
@Repository
class JdbcSubscriptionStore implements PlanRepository, SubscriptionRepository, InvoiceRepository, ClaimRepository, PlatformSettings {
  private final JdbcClient db;
  JdbcSubscriptionStore(JdbcClient db) { this.db = db; }

  private static Instant ts(ResultSet r, String c) throws SQLException { OffsetDateTime o = r.getObject(c, OffsetDateTime.class); return o == null ? null : o.toInstant(); }
  private static final RowMapper<Plan> PLAN = (r, i) -> new Plan(r.getObject("id", UUID.class), r.getString("code"), r.getString("name"), r.getString("currency_code").trim(),
      r.getBigDecimal("price_monthly"), r.getBigDecimal("price_yearly"), r.getInt("trial_days"), r.getInt("max_outlets"), r.getInt("max_users"), roleLimits(r.getString("role_limits")), r.getBoolean("active"));
  private static final RowMapper<Sub> SUB = (r, i) -> new Sub(r.getObject("id", UUID.class), r.getObject("tenant_id", UUID.class), r.getObject("plan_id", UUID.class), r.getString("billing_cycle"),
      r.getString("status"), r.getBigDecimal("price_snapshot"), r.getString("currency_code").trim(), ts(r, "trial_ends_at"), ts(r, "billing_anchor_at"), r.getInt("period_number"),
      ts(r, "current_period_start"), ts(r, "current_period_end"), r.getInt("grace_days"), r.getBoolean("cancel_at_period_end"));
  private static final RowMapper<Invoice> INV = (r, i) -> new Invoice(r.getObject("id", UUID.class), r.getObject("tenant_id", UUID.class), r.getObject("subscription_id", UUID.class),
      r.getString("invoice_number"), r.getString("plan_name"), r.getString("billing_cycle"), ts(r, "period_start"), ts(r, "period_end"), r.getBigDecimal("amount_before_tax"),
      r.getString("tax_label"), r.getBigDecimal("tax_percent"), r.getBigDecimal("tax_amount"), r.getBigDecimal("total_amount"), r.getString("currency_code").trim(), r.getString("status"), ts(r, "due_at"));
  private static final RowMapper<Claim> CLAIM = (r, i) -> new Claim(r.getObject("id", UUID.class), r.getObject("tenant_id", UUID.class), r.getObject("invoice_id", UUID.class),
      r.getString("utr"), r.getString("status"), ts(r, "created_at"), r.getString("review_note"));
  private static final com.fasterxml.jackson.databind.ObjectMapper JSON = new com.fasterxml.jackson.databind.ObjectMapper();
  private static java.util.Map<String, Integer> roleLimits(String json) {
    try { return json == null ? java.util.Map.of() : JSON.readValue(json, new com.fasterxml.jackson.core.type.TypeReference<java.util.Map<String, Integer>>() {}); }
    catch (com.fasterxml.jackson.core.JsonProcessingException e) { return java.util.Map.of(); }
  }
  private static String lock(boolean l) { return l ? " FOR UPDATE" : ""; }

  // ---- plans
  @Override public Optional<Plan> findDefaultActive() { return db.sql("SELECT * FROM plans WHERE active ORDER BY sort_order, created_at LIMIT 1").query(PLAN).optional(); }
  @Override public Optional<Plan> findById(UUID id) { return db.sql("SELECT * FROM plans WHERE id=:id").param("id", id).query(PLAN).optional(); }
  @Override public List<Plan> allPlans() { return db.sql("SELECT * FROM plans ORDER BY sort_order, code").query(PLAN).list(); }
  @Override public Optional<Plan> update(UUID id, String name, BigDecimal m, BigDecimal y, Integer trial, Integer users, Integer outlets, Boolean active) {
    return db.sql("""
      UPDATE plans SET name=coalesce(:n,name), price_monthly=coalesce(:m,price_monthly), price_yearly=coalesce(:y,price_yearly), trial_days=coalesce(:t,trial_days),
        max_users=coalesce(:u,max_users), max_outlets=coalesce(:o,max_outlets), active=coalesce(:a,active), version=version+1, updated_at=now() WHERE id=:id RETURNING *""")
      .param("n", name).param("m", m).param("y", y).param("t", trial).param("u", users).param("o", outlets).param("a", active).param("id", id).query(PLAN).optional();
  }

  // ---- subscriptions
  @Override public void create(UUID tenantId, Plan p, Instant trialEndsAt, int graceDays) {
    db.sql("""
      INSERT INTO subscriptions(tenant_id,plan_id,billing_cycle,status,price_snapshot,currency_code,trial_ends_at,grace_days)
      VALUES (:t,:p,'MONTHLY','TRIALING',:price,:c,:te,:g)""")
      .param("t", tenantId).param("p", p.id()).param("price", p.priceMonthly()).param("c", p.currency()).param("te", java.sql.Timestamp.from(trialEndsAt)).param("g", graceDays).update();
  }
  @Override public Optional<Sub> findByTenant(UUID t, boolean lock) { return db.sql("SELECT * FROM subscriptions WHERE tenant_id=:t" + lock(lock)).param("t", t).query(SUB).optional(); }
  @Override public void activate(UUID id, String cycle, BigDecimal price, Instant anchor, int pn, Instant start, Instant end) {
    db.sql("""
      UPDATE subscriptions SET status='ACTIVE', billing_cycle=:c, price_snapshot=:p, billing_anchor_at=:a, period_number=:pn, current_period_start=:s, current_period_end=:e,
        suspended_at=NULL, version=version+1, updated_at=now() WHERE id=:id""")
      .param("c", cycle).param("p", price).param("a", java.sql.Timestamp.from(anchor)).param("pn", pn).param("s", java.sql.Timestamp.from(start)).param("e", java.sql.Timestamp.from(end)).param("id", id).update();
  }
  @Override public List<Map<String, Object>> overview() {
    return db.sql("""
      SELECT t.id AS "tenantId", t.name, t.status AS "tenantStatus", t.contact_email AS email, p.name AS "plan", s.status, s.trial_ends_at AS "trialEndsAt",
             s.current_period_end AS "periodEnd", s.grace_days AS "graceDays", s.cancel_at_period_end AS "cancelAtPeriodEnd", t.created_at AS "createdAt"
      FROM tenants t LEFT JOIN subscriptions s ON s.tenant_id=t.id LEFT JOIN plans p ON p.id=s.plan_id ORDER BY t.created_at DESC LIMIT 500""").query().listOfRows();
  }

  @Override public boolean setTrialEnd(UUID id, Instant end) {
    return db.sql("UPDATE subscriptions SET trial_ends_at=:e, version=version+1, updated_at=now() WHERE id=:id AND status='TRIALING'").param("e", java.sql.Timestamp.from(end)).param("id", id).update() == 1;
  }
  @Override public void setCancelAtPeriodEnd(UUID id, boolean c) { db.sql("UPDATE subscriptions SET cancel_at_period_end=:c, version=version+1, updated_at=now() WHERE id=:id").param("c", c).param("id", id).update(); }
  @Override public boolean setTenantStatus(UUID t, String status) { return db.sql("UPDATE tenants SET status=:s, updated_at=now() WHERE id=:id").param("s", status).param("id", t).update() == 1; }

  // ---- invoices
  @Override public List<Invoice> listByTenant(UUID t) { return db.sql("SELECT * FROM subscription_invoices WHERE tenant_id=:t ORDER BY issued_at DESC LIMIT 100").param("t", t).query(INV).list(); }
  @Override public BigDecimal paidTotalSince(Instant since) { return db.sql("SELECT coalesce(sum(total_amount),0) FROM subscription_invoices WHERE status='PAID' AND paid_at >= :s").param("s", java.sql.Timestamp.from(since)).query(BigDecimal.class).single(); }
  @Override public Invoice create(Sub s, String planName, String cycle, Instant start, Instant end, BigDecimal amount, String taxLabel, BigDecimal taxPct, BigDecimal tax, Instant due) {
    String number = String.format("GL-INV-%06d", nextCounter("subscription_invoice"));
    return db.sql("""
      INSERT INTO subscription_invoices(tenant_id,subscription_id,invoice_number,plan_name,billing_cycle,period_start,period_end,amount_before_tax,tax_label,tax_percent,tax_amount,total_amount,currency_code,due_at)
      VALUES (:t,:s,:n,:pn,:c,:ps,:pe,:a,:tl,:tp,:ta,:tot,:cur,:due) RETURNING *""")
      .param("t", s.tenantId()).param("s", s.id()).param("n", number).param("pn", planName).param("c", cycle).param("ps", java.sql.Timestamp.from(start)).param("pe", java.sql.Timestamp.from(end))
      .param("a", amount).param("tl", taxLabel).param("tp", taxPct).param("ta", tax).param("tot", amount.add(tax)).param("cur", s.currency()).param("due", java.sql.Timestamp.from(due)).query(INV).single();
  }
  @Override public Optional<Invoice> findOpen(UUID t) { return db.sql("SELECT * FROM subscription_invoices WHERE tenant_id=:t AND status='DUE' ORDER BY issued_at DESC LIMIT 1").param("t", t).query(INV).optional(); }
  @Override public Optional<Invoice> findInvoice(UUID id, boolean lock) { return db.sql("SELECT * FROM subscription_invoices WHERE id=:id" + lock(lock)).param("id", id).query(INV).optional(); }
  @Override public void markPaid(UUID id) { db.sql("UPDATE subscription_invoices SET status='PAID', paid_at=now() WHERE id=:id").param("id", id).update(); }
  @Override public void voidInvoice(UUID id, String reason) { db.sql("UPDATE subscription_invoices SET status='VOID', void_reason=:r WHERE id=:id").param("r", reason).param("id", id).update(); }
  @Override public void recordPayment(UUID t, UUID inv, BigDecimal amount, String ref, UUID by) {
    db.sql("INSERT INTO subscription_payments(tenant_id,invoice_id,method,amount,reference,received_at,recorded_by) VALUES (:t,:i,'UPI',:a,:r,now(),:b)")
      .param("t", t).param("i", inv).param("a", amount).param("r", ref).param("b", by).update();
  }

  // ---- claims
  @Override public Claim create(UUID t, UUID inv, String utr, UUID by) {
    return db.sql("INSERT INTO payment_claims(tenant_id,invoice_id,utr,claimed_by) VALUES (:t,:i,:u,:b) RETURNING *").param("t", t).param("i", inv).param("u", utr).param("b", by).query(CLAIM).single();
  }
  @Override public Optional<Claim> findPending(UUID inv) { return db.sql("SELECT * FROM payment_claims WHERE invoice_id=:i AND status='PENDING'").param("i", inv).query(CLAIM).optional(); }
  @Override public Optional<Claim> findClaim(UUID id, boolean lock) { return db.sql("SELECT * FROM payment_claims WHERE id=:id" + lock(lock)).param("id", id).query(CLAIM).optional(); }
  @Override public List<Map<String, Object>> list(String status) {
    return db.sql("""
      SELECT c.id, c.status, c.utr, c.created_at AS "createdAt", t.name AS restaurant, i.invoice_number AS "invoiceNumber", i.total_amount::text AS amount, i.billing_cycle AS "cycle",
             i.period_start AS "periodStart", i.period_end AS "periodEnd", c.review_note AS "reviewNote"
      FROM payment_claims c JOIN tenants t ON t.id=c.tenant_id JOIN subscription_invoices i ON i.id=c.invoice_id
      WHERE (CAST(:s AS text) IS NULL OR c.status=CAST(:s AS text)) ORDER BY c.created_at DESC LIMIT 200""").param("s", status).query().listOfRows();
  }
  @Override public void review(UUID id, String status, UUID by, String note) {
    db.sql("UPDATE payment_claims SET status=:s, reviewed_by=:b, reviewed_at=now(), review_note=:n WHERE id=:id").param("s", status).param("b", by).param("n", note).param("id", id).update();
  }

  // ---- settings and counters
  @Override public String get(String key, String fallback) { return db.sql("SELECT value FROM platform_settings WHERE key=:k").param("k", key).query(String.class).optional().orElse(fallback); }
  @Override public void put(String key, String value) {
    db.sql("INSERT INTO platform_settings(key,value) VALUES (:k,:v) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=now()").param("k", key).param("v", value).update();
  }
  @Override public Map<String, String> allSettings() {
    var m = new java.util.TreeMap<String, String>();
    db.sql("SELECT key, value FROM platform_settings").query((r, i) -> { m.put(r.getString(1), r.getString(2)); return 0; }).list();
    return m;
  }
  @Override public int nextCounter(String name) {
    return db.sql("INSERT INTO platform_counters(name,last_no) VALUES (:n,1) ON CONFLICT (name) DO UPDATE SET last_no=platform_counters.last_no+1 RETURNING last_no").param("n", name).query(Integer.class).single();
  }
}
