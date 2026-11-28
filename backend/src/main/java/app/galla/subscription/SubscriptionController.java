package app.galla.subscription;
import app.galla.security.CurrentUser;
import app.galla.subscription.SubscriptionDtos.*;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

/** Only the restaurant owner and managers see or pay the subscription. */
@RestController @RequestMapping("/api/v1/subscription") @PreAuthorize("hasAnyRole('OWNER','MANAGER')")
public class SubscriptionController {
  private final SubscriptionService service;
  public SubscriptionController(SubscriptionService service) { this.service = service; }
  @GetMapping SubscriptionView view() { return service.view(CurrentUser.get().tenantId()); }
  @GetMapping("/invoices") java.util.List<InvoiceDetail> invoices() { return service.invoices(CurrentUser.get().tenantId()); }
  @PostMapping("/cancel") @PreAuthorize("hasRole('OWNER')") void cancel() { var c = CurrentUser.get(); service.cancel(c.tenantId(), c.userId()); }
  @PostMapping("/resume") @PreAuthorize("hasRole('OWNER')") void resume() { var c = CurrentUser.get(); service.resume(c.tenantId(), c.userId()); }
  @PostMapping("/invoices") @PreAuthorize("hasRole('OWNER')") InvoiceView invoice(@Valid @RequestBody InvoiceRequest r) { var c = CurrentUser.get(); return service.requestInvoice(c.tenantId(), c.userId(), r.cycle()); }
  @PostMapping("/invoices/{id}/claim") @PreAuthorize("hasRole('OWNER')") @ResponseStatus(HttpStatus.CREATED)
  ClaimView claim(@PathVariable UUID id, @Valid @RequestBody ClaimRequest r) { var c = CurrentUser.get(); return service.submitClaim(c.tenantId(), c.userId(), id, r.utr()); }
}
