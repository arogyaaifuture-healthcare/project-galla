package app.galla.subscription;
import app.galla.subscription.SubscriptionDtos.*;
import java.util.UUID;
/** Restaurant-side subscription use cases. */
public interface SubscriptionService {
  /** Called once when a restaurant registers: starts the free trial of the default plan. */
  void startTrial(UUID tenantId);
  SubscriptionView view(UUID tenantId);
  /** Creates (or returns the already open) invoice for the next period, with the UPI payment link. */
  InvoiceView requestInvoice(UUID tenantId, UUID userId, String cycle);
  java.util.List<InvoiceDetail> invoices(UUID tenantId);
  /** Stops renewal at the end of the paid period (access continues until then). */
  void cancel(UUID tenantId, UUID userId);
  void resume(UUID tenantId, UUID userId);
  ClaimView submitClaim(UUID tenantId, UUID userId, UUID invoiceId, String utr);
  /** What this restaurant may currently do; used by the access filter on every request. */
  Access access(UUID tenantId);
}
