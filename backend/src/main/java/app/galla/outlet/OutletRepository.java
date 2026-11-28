package app.galla.outlet;
import app.galla.outlet.OutletSettings.*;
import java.util.Optional;
import java.util.UUID;
public interface OutletRepository {
  Optional<View> find(UUID tenantId, UUID id);
  /** Optimistic update: empty if the id is unknown or the version is stale. */
  Optional<View> update(UUID tenantId, UUID id, Patch p);
}
