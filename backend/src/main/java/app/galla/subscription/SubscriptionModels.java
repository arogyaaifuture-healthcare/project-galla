package app.galla.subscription;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
/** Plain data carriers shared by the subscription ports. */
public final class SubscriptionModels {
  private SubscriptionModels() {}
  public record Plan(UUID id, String code, String name, String currency,
      @com.fasterxml.jackson.annotation.JsonFormat(shape = com.fasterxml.jackson.annotation.JsonFormat.Shape.STRING) BigDecimal priceMonthly,
      @com.fasterxml.jackson.annotation.JsonFormat(shape = com.fasterxml.jackson.annotation.JsonFormat.Shape.STRING) BigDecimal priceYearly, int trialDays, int maxOutlets, int maxUsers, java.util.Map<String, Integer> roleLimits, boolean active) {
    public BigDecimal price(String cycle) { return "YEARLY".equals(cycle) ? priceYearly : priceMonthly; }
  }
  public record Sub(UUID id, UUID tenantId, UUID planId, String cycle, String status, BigDecimal priceSnapshot, String currency, Instant trialEndsAt, Instant anchor,
      int periodNumber, Instant periodStart, Instant periodEnd, int graceDays, boolean cancelAtPeriodEnd) {}
  public record Invoice(UUID id, UUID tenantId, UUID subscriptionId, String number, String planName, String cycle, Instant periodStart, Instant periodEnd,
      BigDecimal amountBeforeTax, String taxLabel, BigDecimal taxPercent, BigDecimal taxAmount, BigDecimal total, String currency, String status, Instant dueAt) {}
  public record Claim(UUID id, UUID tenantId, UUID invoiceId, String utr, String status, Instant createdAt, String reviewNote) {}
}
