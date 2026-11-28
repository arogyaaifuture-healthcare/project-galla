package app.galla.outlet;
import jakarta.validation.constraints.*;
import java.util.UUID;
public final class OutletSettings {
  private OutletSettings() {}
  public record View(UUID id, String code, String name, String addressLine1, String addressLine2, String city, String state, String postalCode, String phone, String email,
      String gstin, String fssai, String billHeader, String billFooter, long version) {}
  /** Every field optional: only what is sent changes. A blank string clears an optional field. */
  public record Patch(@Size(min = 1, max = 120) String name, @Size(max = 120) String addressLine1, @Size(max = 120) String addressLine2, @Size(max = 60) String city, @Size(max = 60) String state,
      @Pattern(regexp = "^$|^[0-9]{6}$", message = "PIN code must be 6 digits") String postalCode,
      @Pattern(regexp = "^$|^\\+?[0-9]{8,15}$", message = "Enter a valid phone number") String phone, @Pattern(regexp = "^$|^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", message = "Enter a valid email") String email,
      @Pattern(regexp = "^$|^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$", message = "GSTIN must be 15 characters like 27ABCDE1234F1Z5") String gstin,
      @Pattern(regexp = "^$|^[0-9]{14}$", message = "FSSAI number must be 14 digits") String fssai,
      @Size(max = 200) String billHeader, @Size(max = 200) String billFooter, @NotNull Long version) {}
}
