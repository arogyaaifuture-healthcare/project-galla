package app.galla.platform;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
public interface PlatformUserRepository {
  record PUser(UUID id, String email, String name, String passwordHash, String role, String status, Instant lockedUntil) {}
  Optional<PUser> findByEmail(String email);
  boolean anyExist();
  UUID create(String email, String name, String passwordHash, String role);
  void recordFailedLogin(UUID id, int max, int lockMinutes);
  void recordSuccessfulLogin(UUID id);
}
