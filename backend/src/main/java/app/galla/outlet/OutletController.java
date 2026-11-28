package app.galla.outlet;
import app.galla.outlet.OutletSettings.*;
import app.galla.security.CurrentUser;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1/outlets/{id}")
public class OutletController {
  private final OutletService outlets;
  public OutletController(OutletService outlets) { this.outlets = outlets; }
  @GetMapping View get(@PathVariable UUID id) { return outlets.get(CurrentUser.get().tenantId(), id); }
  @PatchMapping @PreAuthorize("hasAnyRole('OWNER','MANAGER')") View patch(@PathVariable UUID id, @Valid @RequestBody Patch p) { var c = CurrentUser.get(); return outlets.update(c.tenantId(), c.userId(), id, p); }
}
