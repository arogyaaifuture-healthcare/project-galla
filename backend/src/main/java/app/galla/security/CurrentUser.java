package app.galla.security;
import java.util.UUID;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
/** The signed-in restaurant user. The tenant always comes from the token, never from request input. */
public record CurrentUser(UUID userId, UUID tenantId, String role) {
  public static CurrentUser get() {
    Jwt j = jwt();
    if (!"TENANT".equals(j.getClaimAsString("typ"))) throw new AccessDeniedException("restaurant endpoint");
    return new CurrentUser(UUID.fromString(j.getSubject()), UUID.fromString(j.getClaimAsString("tid")), j.getClaimAsString("role"));
  }
  /** The signed-in platform (super admin / support) user. */
  public record Platform(UUID userId, String role) {
    public static Platform get() {
      Jwt j = jwt();
      if (!"PLATFORM".equals(j.getClaimAsString("typ"))) throw new AccessDeniedException("platform endpoint");
      return new Platform(UUID.fromString(j.getSubject()), j.getClaimAsString("role"));
    }
  }
  private static Jwt jwt() { return (Jwt) SecurityContextHolder.getContext().getAuthentication().getPrincipal(); }
}
