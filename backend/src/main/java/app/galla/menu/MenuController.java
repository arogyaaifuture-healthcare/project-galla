package app.galla.menu;
import app.galla.common.ApiException;
import app.galla.menu.MenuDtos.*;
import app.galla.security.CurrentUser;
import jakarta.validation.Valid;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

/** Every query is filtered by the tenant from the token. A row of another tenant is reported as 404, never 403. */
@RestController @RequestMapping("/api/v1/menu")
public class MenuController {
  private final JdbcClient db;
  public MenuController(JdbcClient db) { this.db = db; }
  private static final String WRITE = "hasAnyRole('OWNER','MANAGER')";

  private void requireOutlet(UUID tenant, UUID outlet) {
    if (db.sql("SELECT 1 FROM outlets WHERE id=:o AND tenant_id=:t").param("o", outlet).param("t", tenant).query().listOfRows().isEmpty())
      throw ApiException.notFound("Outlet");
  }

  @GetMapping("/categories")
  List<Map<String, Object>> categories(@RequestParam UUID outletId) {
    var c = CurrentUser.get(); requireOutlet(c.tenantId(), outletId);
    return db.sql("SELECT id, name, sort_order AS \"sortOrder\", active FROM menu_categories WHERE tenant_id=:t AND outlet_id=:o ORDER BY sort_order, name")
        .param("t", c.tenantId()).param("o", outletId).query().listOfRows();
  }

  @PostMapping("/categories") @PreAuthorize(WRITE) @ResponseStatus(HttpStatus.CREATED)
  Map<String, Object> createCategory(@Valid @RequestBody CategoryIn in) {
    var c = CurrentUser.get(); requireOutlet(c.tenantId(), in.outletId());
    try {
      return db.sql("INSERT INTO menu_categories(tenant_id,outlet_id,name,sort_order) VALUES (:t,:o,:n,:s) RETURNING id, name, sort_order AS \"sortOrder\", active")
          .param("t", c.tenantId()).param("o", in.outletId()).param("n", in.name().trim()).param("s", in.sortOrder() == null ? 0 : in.sortOrder()).query().singleRow();
    } catch (DuplicateKeyException e) { throw new ApiException(HttpStatus.CONFLICT, "CATEGORY_EXISTS", "A category with this name already exists"); }
  }

  @PatchMapping("/categories/{id}") @PreAuthorize(WRITE)
  Map<String, Object> patchCategory(@PathVariable UUID id, @Valid @RequestBody CategoryPatch p) {
    var c = CurrentUser.get();
    try {
      var rows = db.sql("""
        UPDATE menu_categories SET name=coalesce(:n,name), sort_order=coalesce(:s,sort_order), active=coalesce(:a,active), updated_at=now()
        WHERE id=:id AND tenant_id=:t RETURNING id, name, sort_order AS "sortOrder", active""")
        .param("n", p.name() == null ? null : p.name().trim()).param("s", p.sortOrder()).param("a", p.active()).param("id", id).param("t", c.tenantId()).query().listOfRows();
      if (rows.isEmpty()) throw ApiException.notFound("Category");
      return rows.get(0);
    } catch (DuplicateKeyException e) { throw new ApiException(HttpStatus.CONFLICT, "CATEGORY_EXISTS", "A category with this name already exists"); }
  }

  @GetMapping("/items")
  List<Map<String, Object>> items(@RequestParam UUID outletId, @RequestParam(required = false) UUID categoryId) {
    var c = CurrentUser.get(); requireOutlet(c.tenantId(), outletId);
    return db.sql("""
        SELECT id, category_id AS "categoryId", name, short_code AS "shortCode", base_price::text AS "basePrice", food_type AS "foodType", available, active, version
        FROM menu_items WHERE tenant_id=:t AND outlet_id=:o AND active AND (CAST(:c AS uuid) IS NULL OR category_id=CAST(:c AS uuid))
        ORDER BY sort_order, name""")
        .param("t", c.tenantId()).param("o", outletId).param("c", categoryId).query().listOfRows();
  }

  @PostMapping("/items") @PreAuthorize(WRITE) @ResponseStatus(HttpStatus.CREATED)
  Map<String, Object> createItem(@Valid @RequestBody ItemIn in) {
    var c = CurrentUser.get(); requireOutlet(c.tenantId(), in.outletId());
    if (db.sql("SELECT 1 FROM menu_categories WHERE id=:c AND tenant_id=:t AND outlet_id=:o").param("c", in.categoryId()).param("t", c.tenantId()).param("o", in.outletId()).query().listOfRows().isEmpty())
      throw ApiException.notFound("Category");
    try {
      return db.sql("""
        INSERT INTO menu_items(tenant_id,outlet_id,category_id,name,base_price,food_type,short_code) VALUES (:t,:o,:c,:n,:p,:f,:sc)
        RETURNING id, category_id AS "categoryId", name, short_code AS "shortCode", base_price::text AS "basePrice", food_type AS "foodType", available, active, version""")
        .param("t", c.tenantId()).param("o", in.outletId()).param("c", in.categoryId()).param("n", in.name().trim())
        .param("p", new BigDecimal(in.basePrice())).param("f", in.foodType() == null ? "NA" : in.foodType())
        .param("sc", in.shortCode() == null || in.shortCode().isBlank() ? null : in.shortCode().trim()).query().singleRow();
    } catch (DuplicateKeyException e) { throw new ApiException(HttpStatus.CONFLICT, "SHORT_CODE_EXISTS", "This short code is already used"); }
  }

  /** Optimistic locking: the client sends the version it saw; a stale edit gets 409 STALE_VERSION. */
  @PatchMapping("/items/{id}") @PreAuthorize(WRITE)
  Map<String, Object> patchItem(@PathVariable UUID id, @Valid @RequestBody ItemPatch p) {
    var c = CurrentUser.get();
    var rows = db.sql("""
        UPDATE menu_items SET name=coalesce(:n,name), base_price=coalesce(:p,base_price), available=coalesce(:av,available),
          active=coalesce(:ac,active), version=version+1, updated_at=now()
        WHERE id=:id AND tenant_id=:t AND version=:v
        RETURNING id, category_id AS "categoryId", name, short_code AS "shortCode", base_price::text AS "basePrice", food_type AS "foodType", available, active, version""")
        .param("n", p.name() == null ? null : p.name().trim()).param("p", p.basePrice() == null ? null : new BigDecimal(p.basePrice()))
        .param("av", p.available()).param("ac", p.active()).param("id", id).param("t", c.tenantId()).param("v", p.version()).query().listOfRows();
    if (!rows.isEmpty()) return rows.get(0);
    boolean exists = !db.sql("SELECT 1 FROM menu_items WHERE id=:id AND tenant_id=:t").param("id", id).param("t", c.tenantId()).query().listOfRows().isEmpty();
    if (!exists) throw ApiException.notFound("Item");
    throw new ApiException(HttpStatus.CONFLICT, "STALE_VERSION", "Someone else changed this item. Reload and try again.");
  }
}
