package app.galla.subscription;
import app.galla.subscription.SubscriptionModels.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/** Storage ports for the subscription module (implemented with JDBC; swappable and mockable). */
public final class SubscriptionPorts {
  private SubscriptionPorts() {}

  public interface PlanRepository {
    Optional<Plan> findDefaultActive();
    Optional<Plan> findById(UUID id);
    List<Plan> allPlans();
    Optional<Plan> update(UUID id, String name, BigDecimal monthly, BigDecimal yearly, Integer trialDays, Integer maxUsers, Integer maxOutlets, Boolean active);
  }
  public interface SubscriptionRepository {
    void create(UUID tenantId, Plan plan, Instant trialEndsAt, int graceDays);
    Optional<Sub> findByTenant(UUID tenantId, boolean lock);
    void activate(UUID id, String cycle, BigDecimal price, Instant anchor, int periodNumber, Instant start, Instant end);
    List<Map<String, Object>> overview();
    /** Moves the end of a (still TRIALING) trial; returns false when the subscription is not in trial. */
    boolean setTrialEnd(UUID id, Instant newEnd);
    void setCancelAtPeriodEnd(UUID id, boolean cancel);
    /** Platform switch for a whole restaurant: ACTIVE or SUSPENDED. */
    boolean setTenantStatus(UUID tenantId, String status);
  }
  public interface InvoiceRepository {
    Invoice create(Sub sub, String planName, String cycle, Instant start, Instant end, BigDecimal amount, String taxLabel, BigDecimal taxPercent, BigDecimal taxAmount, Instant dueAt);
    Optional<Invoice> findOpen(UUID tenantId);
    Optional<Invoice> findInvoice(UUID invoiceId, boolean lock);
    List<Invoice> listByTenant(UUID tenantId);
    java.math.BigDecimal paidTotalSince(Instant since);
    void markPaid(UUID id);
    void voidInvoice(UUID id, String reason);
    void recordPayment(UUID tenantId, UUID invoiceId, BigDecimal amount, String reference, UUID platformUserId);
  }
  public interface ClaimRepository {
    Claim create(UUID tenantId, UUID invoiceId, String utr, UUID claimedBy);
    Optional<Claim> findPending(UUID invoiceId);
    Optional<Claim> findClaim(UUID id, boolean lock);
    List<Map<String, Object>> list(String status);
    void review(UUID id, String status, UUID platformUserId, String note);
  }
  public interface PlatformSettings {
    String get(String key, String fallback);
    void put(String key, String value);
    Map<String, String> allSettings();
    /** Next number of a named platform counter (atomic). */
    int nextCounter(String name);
  }
}
