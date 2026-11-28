package app.galla.tenant;
import java.util.UUID;
public interface TenantRepository {
  record Created(UUID tenantId, UUID outletId, UUID ownerId) {}
  /** Creates the restaurant, its first outlet and its OWNER user. Throws DuplicateKeyException if the e-mail is taken. */
  Created createWithOwner(String restaurantName, String ownerName, String email, String passwordHash);
}
