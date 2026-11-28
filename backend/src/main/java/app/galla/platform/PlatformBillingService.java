package app.galla.platform;
import app.galla.audit.AuditEvent;
import app.galla.audit.AuditLog;
import app.galla.common.ApiException;
import app.galla.subscription.SubscriptionModels.*;
import app.galla.subscription.SubscriptionPolicy;
import app.galla.subscription.SubscriptionPorts.*;
import app.galla.subscription.UpiLink;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** What the super admin does: confirm or reject payments, set the UPI id, prices and policies. */
@Service
public class PlatformBillingService {
  private final ClaimRepository claims; private final InvoiceRepository invoices; private final SubscriptionRepository subs; private final PlanRepository plans;
  private final PlatformSettings settings; private final AuditLog audit; private final Clock clock;
  PlatformBillingService(ClaimRepository claims, InvoiceRepository invoices, SubscriptionRepository subs, PlanRepository plans, PlatformSettings settings, AuditLog audit, Clock clock) {
    this.claims = claims; this.invoices = invoices; this.subs = subs; this.plans = plans; this.settings = settings; this.audit = audit; this.clock = clock;
  }

  public List<Map<String, Object>> claims(String status) { return claims.list(status); }

  /** Confirming a claim = "I saw the money in my account". Records the payment, marks the invoice paid and (re)activates the subscription. */
  @Transactional public void confirm(UUID claimId, UUID adminId) {
    Claim c = claims.findClaim(claimId, true).orElseThrow(() -> ApiException.notFound("Claim"));
    if (!"PENDING".equals(c.status())) throw ApiException.conflict("CLAIM_NOT_PENDING", "This claim was already reviewed");
    Invoice inv = invoices.findInvoice(c.invoiceId(), true).orElseThrow(() -> ApiException.notFound("Invoice"));
    if (!"DUE".equals(inv.status())) throw ApiException.conflict("INVOICE_NOT_DUE", "This invoice is no longer due");
    Sub s = subs.findByTenant(inv.tenantId(), true).orElseThrow(() -> ApiException.notFound("Subscription"));
    boolean reanchor = s.anchor() == null || !inv.cycle().equals(s.cycle()) || s.periodEnd() == null || inv.periodStart().isAfter(s.periodEnd());
    invoices.recordPayment(inv.tenantId(), inv.id(), inv.total(), c.utr(), adminId);
    invoices.markPaid(inv.id());
    subs.activate(s.id(), inv.cycle(), inv.amountBeforeTax(), reanchor ? inv.periodStart() : s.anchor(), reanchor ? 0 : s.periodNumber() + 1, inv.periodStart(), inv.periodEnd());
    claims.review(claimId, "CONFIRMED", adminId, null);
    audit.record(AuditEvent.platformUser(inv.tenantId(), adminId, "PAYMENT_CONFIRMED", "payment_claim", claimId, Map.of("invoice", inv.number(), "utr", c.utr(), "periodEnd", inv.periodEnd().toString()), null));
  }

  @Transactional public void reject(UUID claimId, UUID adminId, String note) {
    if (note == null || note.trim().length() < 3) throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "REASON_REQUIRED", "Please give a reason");
    Claim c = claims.findClaim(claimId, true).orElseThrow(() -> ApiException.notFound("Claim"));
    if (!"PENDING".equals(c.status())) throw ApiException.conflict("CLAIM_NOT_PENDING", "This claim was already reviewed");
    claims.review(claimId, "REJECTED", adminId, note.trim());
    audit.record(AuditEvent.platformUser(c.tenantId(), adminId, "PAYMENT_REJECTED", "payment_claim", claimId, Map.of("utr", c.utr()), note.trim()));
  }

  // ---- settings
  private static final Set<String> EDITABLE = Set.of("upi_vpa", "upi_payee_name", "expired_access_mode", "default_grace_days", "invoice_tax_percent", "invoice_tax_label", "invoice_lead_days");
  public Map<String, String> settings() { return settings.allSettings(); }
  @Transactional public Map<String, String> updateSettings(UUID adminId, Map<String, String> in) {
    for (var e : in.entrySet()) {
      if (!EDITABLE.contains(e.getKey())) throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "VALIDATION_FAILED", "Unknown setting " + e.getKey());
      String v = e.getValue() == null ? "" : e.getValue().trim(); validate(e.getKey(), v);
      settings.put(e.getKey(), v);
    }
    audit.record(AuditEvent.platformUser(null, adminId, "PLATFORM_SETTINGS_CHANGED", "platform_settings", "settings", Map.copyOf(in), null));
    return settings.allSettings();
  }
  private static void validate(String k, String v) {
    boolean ok = switch (k) {
      case "upi_vpa" -> UpiLink.VPA.matcher(v).matches();
      case "upi_payee_name" -> v.length() >= 2 && v.length() <= 60 && v.matches("^[\\p{L}0-9 .&'-]+$");
      case "expired_access_mode" -> v.equals("LOCKED") || v.equals("READ_ONLY");
      case "default_grace_days", "invoice_lead_days" -> v.matches("^\\d{1,2}$") && Integer.parseInt(v) <= 60;
      case "invoice_tax_percent" -> v.matches("^\\d{1,3}(\\.\\d{1,2})?$") && new BigDecimal(v).compareTo(BigDecimal.valueOf(100)) <= 0;
      default -> v.length() <= 20;
    };
    if (!ok) throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "VALIDATION_FAILED", "Invalid value for " + k);
  }

  // ---- plans and restaurants
  public List<Plan> plans() { return plans.allPlans(); }
  @Transactional public Plan updatePlan(UUID adminId, UUID id, String name, String monthly, String yearly, Integer trial, Integer users, Integer outlets, Boolean active) {
    BigDecimal m = monthly == null ? null : new BigDecimal(monthly), y = yearly == null ? null : new BigDecimal(yearly);
    var p = plans.update(id, name, m, y, trial, users, outlets, active).orElseThrow(() -> ApiException.notFound("Plan"));
    audit.record(AuditEvent.platformUser(null, adminId, "PLAN_UPDATED", "plan", id, Map.of("monthly", p.priceMonthly().toPlainString(), "yearly", p.priceYearly().toPlainString()), null));
    return p;
  }
  public List<Map<String, Object>> restaurants() {
    var out = new ArrayList<Map<String, Object>>(); var now = clock.instant();
    for (var r : subs.overview()) {
      var m = new java.util.LinkedHashMap<>(r);
      if (r.get("status") != null) {
        var te = (java.sql.Timestamp) r.get("trialEndsAt"); var pe = (java.sql.Timestamp) r.get("periodEnd");
        m.put("effectiveStatus", SubscriptionPolicy.effective((String) r.get("status"), te == null ? null : te.toInstant(), pe == null ? null : pe.toInstant(), (Integer) r.get("graceDays"), (Boolean) r.get("cancelAtPeriodEnd"), now).name());
      }
      out.add(m);
    }
    return out;
  }

  // ---- restaurant actions
  /** Gives a restaurant still in its trial more days, counted from the later of now and the current end. */
  @Transactional public Instant extendTrial(UUID adminId, UUID tenantId, int days, String reason) {
    if (days < 1 || days > 90) throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "VALIDATION_FAILED", "Days must be between 1 and 90");
    requireReason(reason);
    Sub s = subs.findByTenant(tenantId, true).orElseThrow(() -> ApiException.notFound("Restaurant"));
    Instant base = s.trialEndsAt() != null && s.trialEndsAt().isAfter(clock.instant()) ? s.trialEndsAt() : clock.instant();
    Instant end = base.plus(java.time.Duration.ofDays(days));
    if (!subs.setTrialEnd(s.id(), end)) throw ApiException.conflict("NOT_IN_TRIAL", "This restaurant is not on a free trial");
    audit.record(AuditEvent.platformUser(tenantId, adminId, "TRIAL_EXTENDED", "subscription", s.id(), Map.of("days", days, "trialEndsAt", end.toString()), reason.trim()));
    return end;
  }
  @Transactional public void suspendRestaurant(UUID adminId, UUID tenantId, String reason) { setStatus(adminId, tenantId, "SUSPENDED", "RESTAURANT_SUSPENDED", reason); }
  @Transactional public void reactivateRestaurant(UUID adminId, UUID tenantId, String reason) { setStatus(adminId, tenantId, "ACTIVE", "RESTAURANT_REACTIVATED", reason); }
  private void setStatus(UUID adminId, UUID tenantId, String status, String action, String reason) {
    requireReason(reason);
    if (!subs.setTenantStatus(tenantId, status)) throw ApiException.notFound("Restaurant");
    audit.record(AuditEvent.platformUser(tenantId, adminId, action, "tenant", tenantId, Map.of("status", status), reason.trim()));
  }
  private static void requireReason(String r) { if (r == null || r.trim().length() < 3) throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "REASON_REQUIRED", "Please give a reason"); }

  /** Headline numbers for the platform home screen. */
  public Map<String, Object> dashboard() {
    var counts = new java.util.TreeMap<String, Integer>();
    int suspendedByAdmin = 0;
    for (var r : restaurants()) {
      if ("SUSPENDED".equals(r.get("tenantStatus"))) { suspendedByAdmin++; continue; }
      counts.merge(String.valueOf(r.getOrDefault("effectiveStatus", "NO_SUBSCRIPTION")), 1, Integer::sum);
    }
    var monthStart = clock.instant().atZone(java.time.ZoneOffset.UTC).withDayOfMonth(1).toLocalDate().atStartOfDay(java.time.ZoneOffset.UTC).toInstant();
    var m = new java.util.LinkedHashMap<String, Object>();
    m.put("restaurantsByStatus", counts); m.put("suspendedByAdmin", suspendedByAdmin);
    m.put("pendingPayments", claims.list("PENDING").size());
    m.put("collectedThisMonth", invoices.paidTotalSince(monthStart).toPlainString());
    return m;
  }
}
