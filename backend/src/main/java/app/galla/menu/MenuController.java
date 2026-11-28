package app.galla.menu;
import app.galla.menu.MenuDtos.*;
import app.galla.security.CurrentUser;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

/** Thin adapter: identity comes from the token, rules live in MenuService, storage behind MenuRepository. */
@RestController @RequestMapping("/api/v1")
public class MenuController {
  private static final String WRITE = "hasAnyRole('OWNER','MANAGER')";
  private final MenuService menu;
  public MenuController(MenuService menu) { this.menu = menu; }
  @GetMapping("/outlets") List<OutletView> outlets() { return menu.outlets(CurrentUser.get().tenantId()); }
  @GetMapping("/menu/categories") List<CategoryView> categories(@RequestParam UUID outletId) { return menu.categories(CurrentUser.get().tenantId(), outletId); }
  @PostMapping("/menu/categories") @PreAuthorize(WRITE) @ResponseStatus(HttpStatus.CREATED)
  CategoryView createCategory(@Valid @RequestBody CategoryIn in) { var c = CurrentUser.get(); return menu.createCategory(c.tenantId(), c.userId(), in); }
  @PatchMapping("/menu/categories/{id}") @PreAuthorize(WRITE)
  CategoryView patchCategory(@PathVariable UUID id, @Valid @RequestBody CategoryPatch p) { var c = CurrentUser.get(); return menu.updateCategory(c.tenantId(), c.userId(), id, p); }
  @GetMapping("/menu/items") List<ItemView> items(@RequestParam UUID outletId, @RequestParam(required = false) UUID categoryId) { return menu.items(CurrentUser.get().tenantId(), outletId, categoryId); }
  @PostMapping("/menu/items") @PreAuthorize(WRITE) @ResponseStatus(HttpStatus.CREATED)
  ItemView createItem(@Valid @RequestBody ItemIn in) { var c = CurrentUser.get(); return menu.createItem(c.tenantId(), c.userId(), in); }
  @PatchMapping("/menu/items/{id}") @PreAuthorize(WRITE)
  ItemView patchItem(@PathVariable UUID id, @Valid @RequestBody ItemPatch p) { var c = CurrentUser.get(); return menu.updateItem(c.tenantId(), c.userId(), id, p); }
}
