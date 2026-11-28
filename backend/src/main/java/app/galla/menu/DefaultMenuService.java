package app.galla.menu;
import app.galla.audit.AuditEvent;
import app.galla.audit.AuditLog;
import app.galla.common.ApiException;
import app.galla.menu.MenuDtos.*;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class DefaultMenuService implements MenuService {
  private final MenuRepository repo; private final AuditLog audit;
  DefaultMenuService(MenuRepository repo, AuditLog audit) { this.repo = repo; this.audit = audit; }

  private void requireOutlet(UUID tenant, UUID outlet) { if (!repo.outletBelongsToTenant(tenant, outlet)) throw ApiException.notFound("Outlet"); }
  private static ApiException categoryExists() { return ApiException.conflict("CATEGORY_EXISTS", "A category with this name already exists"); }

  @Override public List<OutletView> outlets(UUID t) { return repo.outlets(t); }
  @Override public List<CategoryView> categories(UUID t, UUID o) { requireOutlet(t, o); return repo.categories(t, o); }
  @Override public List<ItemView> items(UUID t, UUID o, UUID c) { requireOutlet(t, o); return repo.items(t, o, c); }

  @Override @Transactional public CategoryView createCategory(UUID t, UUID user, CategoryIn in) {
    requireOutlet(t, in.outletId());
    try {
      var c = repo.createCategory(t, in.outletId(), in.name().trim(), in.sortOrder() == null ? 0 : in.sortOrder());
      audit.record(AuditEvent.tenantUser(t, user, "MENU_CATEGORY_CREATED", "menu_category", c.id(), Map.of("name", c.name())));
      return c;
    } catch (DuplicateKeyException e) { throw categoryExists(); }
  }
  @Override @Transactional public CategoryView updateCategory(UUID t, UUID user, UUID id, CategoryPatch p) {
    try {
      var c = repo.updateCategory(t, id, p.name() == null ? null : p.name().trim(), p.sortOrder(), p.active()).orElseThrow(() -> ApiException.notFound("Category"));
      audit.record(AuditEvent.tenantUser(t, user, "MENU_CATEGORY_UPDATED", "menu_category", id, Map.of("name", c.name(), "active", c.active())));
      return c;
    } catch (DuplicateKeyException e) { throw categoryExists(); }
  }
  @Override @Transactional public ItemView createItem(UUID t, UUID user, ItemIn in) {
    requireOutlet(t, in.outletId());
    if (!repo.categoryInOutlet(t, in.outletId(), in.categoryId())) throw ApiException.notFound("Category");
    try {
      var i = repo.createItem(t, in.outletId(), in.categoryId(), in.name().trim(), new BigDecimal(in.basePrice()), in.foodType() == null ? "NA" : in.foodType(),
          in.shortCode() == null || in.shortCode().isBlank() ? null : in.shortCode().trim());
      audit.record(AuditEvent.tenantUser(t, user, "MENU_ITEM_CREATED", "menu_item", i.id(), Map.of("name", i.name(), "price", i.basePrice())));
      return i;
    } catch (DuplicateKeyException e) { throw ApiException.conflict("SHORT_CODE_EXISTS", "This short code is already used"); }
  }
  /** Optimistic locking: the client sends the version it saw; a stale edit gets 409 STALE_VERSION. */
  @Override @Transactional public ItemView updateItem(UUID t, UUID user, UUID id, ItemPatch p) {
    var updated = repo.updateItem(t, id, p.version(), p.name() == null ? null : p.name().trim(), p.basePrice() == null ? null : new BigDecimal(p.basePrice()), p.available(), p.active());
    if (updated.isEmpty()) {
      if (!repo.itemExists(t, id)) throw ApiException.notFound("Item");
      throw ApiException.conflict("STALE_VERSION", "Someone else changed this item. Reload and try again.");
    }
    var i = updated.get();
    audit.record(AuditEvent.tenantUser(t, user, "MENU_ITEM_UPDATED", "menu_item", id, Map.of("name", i.name(), "price", i.basePrice(), "available", i.available(), "active", i.active())));
    return i;
  }
}
