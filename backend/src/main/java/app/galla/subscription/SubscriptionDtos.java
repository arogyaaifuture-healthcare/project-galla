package app.galla.subscription;
import jakarta.validation.constraints.*;
import java.time.Instant;
import java.util.UUID;
public final class SubscriptionDtos {
  private SubscriptionDtos() {}
  public record InvoiceView(UUID id, String number, String amount, String currency, String cycle, Instant periodStart, Instant periodEnd, String status, String upiUri) {}
  public record ClaimView(UUID id, String utr, String status, Instant createdAt, String reviewNote) {}
  public record SubscriptionView(String status, String planName, String cycle, Instant trialEndsAt, Instant periodEnd, long daysLeft, boolean pricingSet,
      String priceMonthly, String priceYearly, String currency, String accessMode, boolean upiConfigured, InvoiceView openInvoice, ClaimView pendingClaim) {}
  public record InvoiceRequest(@NotNull @Pattern(regexp = "MONTHLY|YEARLY") String cycle) {}
  public record ClaimRequest(@NotBlank @Pattern(regexp = "^[A-Za-z0-9]{10,30}$", message = "Enter the 12-digit UTR / reference number from your UPI app") String utr) {}
  public record Access(boolean full, String effective, boolean readOnlyAllowed) {}
}
