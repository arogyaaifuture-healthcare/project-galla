package app.galla.subscription;
import app.galla.audit.AuditEvent;
import app.galla.audit.AuditLog;
import app.galla.common.ApiException;
import app.galla.subscription.SubscriptionDtos.*;
import app.galla.subscription.SubscriptionModels.*;
import app.galla.subscription.SubscriptionPolicy.Effective;
import app.galla.subscription.SubscriptionPorts.*;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class DefaultSubscriptionService implements SubscriptionService {
  private final PlanRepository plans; private final SubscriptionRepository subs; private final InvoiceRepository invoices; private final ClaimRepository claims;
  private final PlatformSettings settings; private final AuditLog audit; private final Clock clock;
  DefaultSubscriptionService(PlanRepository plans, SubscriptionRepository subs, InvoiceRepository invoices, ClaimRepository claims, PlatformSettings settings, AuditLog audit, Clock clock) {
    this.plans = plans; this.subs = subs; this.invoices = invoices; this.claims = claims; this.settings = settings; this.audit = audit; this.clock = clock;
  }
  private int intSetting(String key, int fallback) { try { return Integer.parseInt(settings.get(key, String.valueOf(fallback))); } catch (NumberFormatException e) { return fallback; } }
  private Effective effective(Sub s) { return SubscriptionPolicy.effective(s.status(), s.trialEndsAt(), s.periodEnd(), s.graceDays(), s.cancelAtPeriodEnd(), clock.instant()); }
  private Sub sub(UUID tenant, boolean lock) { return subs.findByTenant(tenant, lock).orElseThrow(() -> ApiException.notFound("Subscription")); }

  @Override @Transactional public void startTrial(UUID tenantId) {
    Plan p = plans.findDefaultActive().orElseThrow(() -> new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "NO_PLAN_AVAILABLE", "Sign-up is not open yet. Please try again later."));
    Instant end = clock.instant().plus(Duration.ofDays(p.trialDays()));
    subs.create(tenantId, p, end, intSetting("default_grace_days", 7));
    audit.record(AuditEvent.system(tenantId, "TRIAL_STARTED", "subscription", tenantId, Map.of("plan", p.code(), "trialEndsAt", end.toString())));
  }

  private InvoiceView invoiceView(Invoice i) {
    String vpa = settings.get("upi_vpa", ""), name = settings.get("upi_payee_name", "");
    String uri = vpa.isBlank() || name.isBlank() ? null : UpiLink.build(vpa, name, i.total(), i.number());
    return new InvoiceView(i.id(), i.number(), i.total().toPlainString(), i.currency(), i.cycle(), i.periodStart(), i.periodEnd(), i.status(), uri);
  }

  @Override @Transactional(readOnly = true) public SubscriptionView view(UUID tenantId) {
    Sub s = sub(tenantId, false); Plan p = plans.findById(s.planId()).orElseThrow(() -> ApiException.notFound("Plan"));
    Effective e = effective(s); Instant now = clock.instant();
    Instant end = "TRIALING".equals(s.status()) ? s.trialEndsAt() : s.periodEnd();
    long days = end != null && now.isBefore(end) ? (Duration.between(now, end).toHours() + 23) / 24 : 0;
    var open = invoices.findOpen(tenantId);
    ClaimView pending = open.flatMap(i -> claims.findPending(i.id())).map(c -> new ClaimView(c.id(), c.utr(), c.status(), c.createdAt(), c.reviewNote())).orElse(null);
    return new SubscriptionView(e.name(), p.name(), s.cycle(), s.trialEndsAt(), s.periodEnd(), days, p.priceMonthly().signum() > 0 && p.priceYearly().signum() > 0,
        p.priceMonthly().toPlainString(), p.priceYearly().toPlainString(), p.currency(), settings.get("expired_access_mode", "LOCKED"),
        !settings.get("upi_vpa", "").isBlank(), open.map(this::invoiceView).orElse(null), pending);
  }

  @Override @Transactional public InvoiceView requestInvoice(UUID tenantId, UUID userId, String cycle) {
    Sub s = sub(tenantId, true); Plan p = plans.findById(s.planId()).orElseThrow(() -> ApiException.notFound("Plan"));
    Instant now = clock.instant(); Effective e = effective(s);
    if (e == Effective.CANCELLED) throw ApiException.conflict("SUBSCRIPTION_CANCELLED", "This subscription was cancelled. Contact support to restart it.");
    BigDecimal price = p.price(cycle);
    if (price.signum() <= 0) throw ApiException.conflict("PRICING_NOT_SET", "Pricing is not available yet. Please contact support.");

    Instant start; Instant anchor; int k;
    boolean reanchor = s.anchor() == null || !cycle.equals(s.cycle()) || e == Effective.TRIALING || e == Effective.SUSPENDED;
    switch (e) {
      case TRIALING -> start = s.trialEndsAt();
      case SUSPENDED -> start = now;
      case ACTIVE -> {
        if (now.isBefore(s.periodEnd().minus(Duration.ofDays(intSetting("invoice_lead_days", 7)))))
          throw ApiException.conflict("TOO_EARLY", "You can renew in the last " + intSetting("invoice_lead_days", 7) + " days of your current period.");
        start = s.periodEnd();
      }
      default -> start = s.periodEnd();
    }
    if (reanchor) { anchor = start; k = 0; } else { anchor = s.anchor(); k = s.periodNumber() + 1; }
    Instant periodStart = reanchor ? start : SubscriptionPolicy.addCycles(anchor, cycle, k);
    Instant periodEnd = SubscriptionPolicy.addCycles(anchor, cycle, k + 1);

    var open = invoices.findOpen(tenantId);
    if (open.isPresent()) {
      Invoice o = open.get();
      boolean same = o.cycle().equals(cycle) && o.periodStart().equals(periodStart) && o.periodEnd().equals(periodEnd);
      if (same || claims.findPending(o.id()).isPresent()) return invoiceView(o);
      invoices.voidInvoice(o.id(), "Replaced by a new invoice");
    }
    BigDecimal pct = new BigDecimal(settings.get("invoice_tax_percent", "0"));
    BigDecimal tax = price.multiply(pct).divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
    Invoice inv = invoices.create(s, p.name(), cycle, periodStart, periodEnd, price, settings.get("invoice_tax_label", "GST"), pct, tax, periodStart.isBefore(now) ? now : periodStart);
    audit.record(AuditEvent.tenantUser(tenantId, userId, "INVOICE_ISSUED", "subscription_invoice", inv.id(), Map.of("number", inv.number(), "total", inv.total().toPlainString())));
    return invoiceView(inv);
  }

  @Override @Transactional public ClaimView submitClaim(UUID tenantId, UUID userId, UUID invoiceId, String utr) {
    Invoice inv = invoices.findInvoice(invoiceId, true).filter(i -> i.tenantId().equals(tenantId)).orElseThrow(() -> ApiException.notFound("Invoice"));
    if (!"DUE".equals(inv.status())) throw ApiException.conflict("INVOICE_NOT_DUE", "This invoice is not waiting for payment");
    if (claims.findPending(invoiceId).isPresent()) throw ApiException.conflict("CLAIM_PENDING", "Your payment is already waiting for confirmation");
    try {
      var c = claims.create(tenantId, invoiceId, utr.trim().toUpperCase(), userId);
      audit.record(AuditEvent.tenantUser(tenantId, userId, "PAYMENT_CLAIMED", "payment_claim", c.id(), Map.of("invoice", inv.number(), "utr", c.utr())));
      return new ClaimView(c.id(), c.utr(), c.status(), c.createdAt(), c.reviewNote());
    } catch (DuplicateKeyException e) { throw ApiException.conflict("UTR_ALREADY_USED", "This reference number was already submitted"); }
  }

  @Override @Transactional(readOnly = true) public Access access(UUID tenantId) {
    var s = subs.findByTenant(tenantId, false);
    if (s.isEmpty()) return new Access(false, "SUSPENDED", false);
    Effective e = effective(s.get());
    return new Access(e.fullAccess(), e.name(), "READ_ONLY".equals(settings.get("expired_access_mode", "LOCKED")));
  }
}
