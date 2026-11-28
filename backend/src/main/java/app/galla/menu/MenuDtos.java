package app.galla.menu;
import jakarta.validation.constraints.*;
import java.util.UUID;
public final class MenuDtos {
  private MenuDtos() {}
  public record CategoryIn(@NotNull UUID outletId, @NotBlank @Size(max = 80) String name, @Min(0) @Max(100000) Integer sortOrder) {}
  public record CategoryPatch(@Size(min = 1, max = 80) String name, @Min(0) @Max(100000) Integer sortOrder, Boolean active) {}
  /** Money travels as a string with at most 2 decimals, never as a float. */
  public record ItemIn(@NotNull UUID outletId, @NotNull UUID categoryId, @NotBlank @Size(max = 120) String name,
      @NotBlank @Pattern(regexp = "^\\d{1,10}(\\.\\d{1,2})?$", message = "Price must be a number with at most 2 decimals") String basePrice,
      @Pattern(regexp = "VEG|NON_VEG|EGG|NA") String foodType, @Size(max = 20) String shortCode) {}
  public record ItemPatch(@Size(min = 1, max = 120) String name,
      @Pattern(regexp = "^\\d{1,10}(\\.\\d{1,2})?$", message = "Price must be a number with at most 2 decimals") String basePrice,
      Boolean available, Boolean active, @NotNull Long version) {}
  public record CategoryView(UUID id, String name, int sortOrder, boolean active) {}
  public record ItemView(UUID id, UUID categoryId, String name, String shortCode, String basePrice, String foodType, boolean available, boolean active, long version) {}
  public record OutletView(UUID id, String code, String name, String currencySymbol) {}
}
