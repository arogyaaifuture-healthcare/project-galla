package app.galla.outlet;
import app.galla.audit.AuditEvent;
import app.galla.audit.AuditLog;
import app.galla.common.ApiException;
import app.galla.outlet.OutletSettings.*;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
@Service
class DefaultOutletService implements OutletService {
  private final OutletRepository repo; private final AuditLog audit;
  DefaultOutletService(OutletRepository repo, AuditLog audit) { this.repo = repo; this.audit = audit; }
  @Override public View get(UUID t, UUID id) { return repo.find(t, id).orElseThrow(() -> ApiException.notFound("Outlet")); }
  @Override @Transactional public View update(UUID t, UUID user, UUID id, Patch p) {
    var v = repo.update(t, id, p);
    if (v.isEmpty()) { if (repo.find(t, id).isEmpty()) throw ApiException.notFound("Outlet"); throw ApiException.conflict("STALE_VERSION", "Someone else changed these settings. Reload and try again."); }
    audit.record(AuditEvent.tenantUser(t, user, "OUTLET_UPDATED", "outlet", id, java.util.Map.of("name", v.get().name())));
    return v.get();
  }
}
