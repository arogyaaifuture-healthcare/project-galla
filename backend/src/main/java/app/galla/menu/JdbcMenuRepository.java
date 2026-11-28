package app.galla.menu;
import app.galla.menu.MenuDtos.*;
import java.math.BigDecimal;
import java.sql.ResultSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class JdbcMenuRepository implements MenuRepository {
  private final JdbcClient db;
  JdbcMenuRepository(JdbcClient db) { this.db = db; }
  private static final RowMapper<CategoryView> CAT = (ResultSet r, int i) -> new CategoryView(r.getObject("id", UUID.class), r.getString("name"), r.getInt("sort_order"), r.getBoolean("active"));
  private static final RowMapper<ItemView> ITEM = (ResultSet r, int i) -> new ItemView(r.getObject("id", UUID.class), r.getObject("category_id", UUID.class), r.getString("name"),
      r.getString("short_code"), r.getBigDecimal("base_price").toPlainString(), r.getString("food_type"), r.getBoolean("available"), r.getBoolean("active"), r.getLong("version"));
  private static final String ITEM_COLS = "id, category_id, name, short_code, base_price, food_type, available, active, version";

  @Override public boolean outletBelongsToTenant(UUID t, UUID o) { return db.sql("SELECT 1 FROM outlets WHERE id=:o AND tenant_id=:t").param("o", o).param("t", t).query().listOfRows().size() == 1; }
  @Override public List<OutletView> outlets(UUID t) {
    return db.sql("SELECT id, code, name, currency_symbol FROM outlets WHERE tenant_id=:t AND status='ACTIVE' ORDER BY code").param("t", t)
        .query((r, i) -> new OutletView(r.getObject("id", UUID.class), r.getString("code"), r.getString("name"), r.getString("currency_symbol").trim())).list();
  }
  @Override public List<CategoryView> categories(UUID t, UUID o) {
    return db.sql("SELECT id,name,sort_order,active FROM menu_categories WHERE tenant_id=:t AND outlet_id=:o ORDER BY sort_order, name").param("t", t).param("o", o).query(CAT).list();
  }
  @Override public CategoryView createCategory(UUID t, UUID o, String name, int sort) {
    return db.sql("INSERT INTO menu_categories(tenant_id,outlet_id,name,sort_order) VALUES (:t,:o,:n,:s) RETURNING id,name,sort_order,active")
        .param("t", t).param("o", o).param("n", name).param("s", sort).query(CAT).single();
  }
  @Override public Optional<CategoryView> updateCategory(UUID t, UUID id, String name, Integer sort, Boolean active) {
    return db.sql("""
        UPDATE menu_categories SET name=coalesce(:n,name), sort_order=coalesce(:s,sort_order), active=coalesce(:a,active), updated_at=now()
        WHERE id=:id AND tenant_id=:t RETURNING id,name,sort_order,active""").param("n", name).param("s", sort).param("a", active).param("id", id).param("t", t).query(CAT).optional();
  }
  @Override public boolean categoryInOutlet(UUID t, UUID o, UUID c) {
    return db.sql("SELECT 1 FROM menu_categories WHERE id=:c AND tenant_id=:t AND outlet_id=:o").param("c", c).param("t", t).param("o", o).query().listOfRows().size() == 1;
  }
  @Override public List<ItemView> items(UUID t, UUID o, UUID cat) {
    return db.sql("SELECT " + ITEM_COLS + " FROM menu_items WHERE tenant_id=:t AND outlet_id=:o AND active AND (CAST(:c AS uuid) IS NULL OR category_id=CAST(:c AS uuid)) ORDER BY sort_order, name")
        .param("t", t).param("o", o).param("c", cat).query(ITEM).list();
  }
  @Override public ItemView createItem(UUID t, UUID o, UUID c, String name, BigDecimal price, String food, String shortCode) {
    return db.sql("INSERT INTO menu_items(tenant_id,outlet_id,category_id,name,base_price,food_type,short_code) VALUES (:t,:o,:c,:n,:p,:f,:sc) RETURNING " + ITEM_COLS)
        .param("t", t).param("o", o).param("c", c).param("n", name).param("p", price).param("f", food).param("sc", shortCode).query(ITEM).single();
  }
  @Override public Optional<ItemView> updateItem(UUID t, UUID id, long version, String name, BigDecimal price, Boolean available, Boolean active) {
    return db.sql("""
        UPDATE menu_items SET name=coalesce(:n,name), base_price=coalesce(:p,base_price), available=coalesce(:av,available), active=coalesce(:ac,active), version=version+1, updated_at=now()
        WHERE id=:id AND tenant_id=:t AND version=:v RETURNING """ + ITEM_COLS)
        .param("n", name).param("p", price).param("av", available).param("ac", active).param("id", id).param("t", t).param("v", version).query(ITEM).optional();
  }
  @Override public boolean itemExists(UUID t, UUID id) { return db.sql("SELECT 1 FROM menu_items WHERE id=:id AND tenant_id=:t").param("id", id).param("t", t).query().listOfRows().size() == 1; }
}
