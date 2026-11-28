package app.galla.menu;
import app.galla.menu.MenuDtos.*;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
/** Port for menu storage. Every method takes the tenant explicitly: there is no way to read another restaurant's rows. */
public interface MenuRepository {
  boolean outletBelongsToTenant(UUID tenantId, UUID outletId);
  List<OutletView> outlets(UUID tenantId);
  List<CategoryView> categories(UUID tenantId, UUID outletId);
  CategoryView createCategory(UUID tenantId, UUID outletId, String name, int sortOrder);
  Optional<CategoryView> updateCategory(UUID tenantId, UUID id, String name, Integer sortOrder, Boolean active);
  boolean categoryInOutlet(UUID tenantId, UUID outletId, UUID categoryId);
  List<ItemView> items(UUID tenantId, UUID outletId, UUID categoryIdOrNull);
  ItemView createItem(UUID tenantId, UUID outletId, UUID categoryId, String name, BigDecimal price, String foodType, String shortCodeOrNull);
  Optional<ItemView> updateItem(UUID tenantId, UUID id, long version, String nameOrNull, BigDecimal priceOrNull, Boolean available, Boolean active);
  boolean itemExists(UUID tenantId, UUID id);
}
