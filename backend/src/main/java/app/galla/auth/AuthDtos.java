package app.galla.auth;
import jakarta.validation.constraints.*;
import java.util.UUID;
public final class AuthDtos {
  private AuthDtos() {}
  public record RegisterRequest(
      @NotBlank @Size(max = 120) String restaurantName,
      @NotBlank @Size(max = 120) String ownerName,
      @NotBlank @Email @Size(max = 200) String email,
      @NotBlank @Size(min = 10, max = 100, message = "Password must be 10 to 100 characters") String password) {}
  public record LoginRequest(@NotBlank @Email String email, @NotBlank String password, @Pattern(regexp = "OWNER|MANAGER|CASHIER|CAPTAIN|KITCHEN|RIDER|INVENTORY|ACCOUNTANT") String role) {}
  public record TokenResponse(String accessToken, long expiresInSeconds, UserView user) {}
  public record UserView(UUID id, UUID tenantId, String name, String email, String role) {}
}
