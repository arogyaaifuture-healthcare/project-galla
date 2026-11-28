package app.galla.staff;
import jakarta.validation.constraints.*;
public final class StaffDtos {
  private StaffDtos() {}
  private static final String ROLE = "OWNER|MANAGER|CASHIER|CAPTAIN|KITCHEN|RIDER|INVENTORY|ACCOUNTANT";
  public record CreateRequest(@NotBlank @Size(max = 120) String name, @NotBlank @Email @Size(max = 200) String email, @Pattern(regexp = "^\\+?[0-9]{8,15}$", message = "Enter a valid phone number") String phone,
      @NotNull @Pattern(regexp = ROLE) String role, @NotBlank @Size(min = 10, max = 100, message = "Password must be 10 to 100 characters") String password) {}
  public record UpdateRequest(@Size(min = 1, max = 120) String name, @Pattern(regexp = ROLE) String role, Boolean active) {}
  public record ResetPasswordRequest(@NotBlank @Size(min = 10, max = 100, message = "Password must be 10 to 100 characters") String password) {}
}
