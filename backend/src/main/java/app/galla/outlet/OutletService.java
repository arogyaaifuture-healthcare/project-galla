package app.galla.outlet;
import app.galla.outlet.OutletSettings.*;
import java.util.UUID;
public interface OutletService {
  View get(UUID tenantId, UUID id);
  View update(UUID tenantId, UUID userId, UUID id, Patch patch);
}
