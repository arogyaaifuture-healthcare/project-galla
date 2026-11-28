package app.galla.menu;
import app.galla.menu.MenuDtos.*;
import java.util.List;
import java.util.UUID;
public interface MenuService {
  List<OutletView> outlets(UUID tenantId);
  List<CategoryView> categories(UUID tenantId, UUID outletId);
  CategoryView createCategory(UUID tenantId, UUID userId, CategoryIn in);
  CategoryView updateCategory(UUID tenantId, UUID userId, UUID id, CategoryPatch patch);
  List<ItemView> items(UUID tenantId, UUID outletId, UUID categoryIdOrNull);
  ItemView createItem(UUID tenantId, UUID userId, ItemIn in);
  ItemView updateItem(UUID tenantId, UUID userId, UUID id, ItemPatch patch);
}
