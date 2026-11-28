package app.galla.security;
import java.util.UUID;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
/** The signed-in user. Tenant always comes from the token, never from request input. */
public record CurrentUser(UUID userId, UUID tenantId, String role) {
  public static CurrentUser get() {
    Authentication a = SecurityContextHolder.getContext().getAuthentication();
    Jwt j = (Jwt) a.getPrincipal();
    return new CurrentUser(UUID.fromString(j.getSubject()), UUID.fromString(j.getClaimAsString("tid")), j.getClaimAsString("role"));
  }
}
