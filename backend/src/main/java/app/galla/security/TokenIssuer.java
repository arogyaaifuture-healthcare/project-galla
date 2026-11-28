package app.galla.security;
import java.util.UUID;
/** Port for creating access tokens; the implementation (JWT) can change without touching services. */
public interface TokenIssuer {
  record Issued(String token, long expiresInSeconds) {}
  Issued tenantToken(UUID userId, UUID tenantId, String role);
  Issued platformToken(UUID platformUserId, String role);
}
