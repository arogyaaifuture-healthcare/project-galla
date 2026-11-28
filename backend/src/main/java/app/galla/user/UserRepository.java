package app.galla.user;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
/** Port for restaurant user storage. */
public interface UserRepository {
  record Account(UUID id, UUID tenantId, String name, String email, String passwordHash, String role, String status, Instant lockedUntil, String tenantStatus) {}
  Optional<Account> findByEmail(String email);
  Optional<Account> findById(UUID id);
  void recordFailedLogin(UUID id, int maxAttempts, int lockMinutes);
  void recordSuccessfulLogin(UUID id);
}
