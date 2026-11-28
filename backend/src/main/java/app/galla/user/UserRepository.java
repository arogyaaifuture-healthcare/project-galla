package app.galla.user;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
/** Port for restaurant user storage. */
public interface UserRepository {
  record Account(UUID id, UUID tenantId, String name, String email, String passwordHash, String role, String status, Instant lockedUntil, String tenantStatus) {}
  Optional<Account> findByEmail(String email);
  Optional<Account> findById(UUID id);
  record Member(UUID id, String name, String email, String phone, String role, String status, Instant lastLoginAt) {}
  List<Member> list(UUID tenantId);
  Optional<Member> findMember(UUID tenantId, UUID id);
  Member create(UUID tenantId, String name, String email, String phone, String role, String passwordHash);
  Optional<Member> update(UUID tenantId, UUID id, String nameOrNull, String roleOrNull, String statusOrNull);
  void setPassword(UUID tenantId, UUID id, String passwordHash);
  int countActive(UUID tenantId);
  int countActiveWithRole(UUID tenantId, String role);
  boolean isActive(UUID userId);
  void recordFailedLogin(UUID id, int maxAttempts, int lockMinutes);
  void recordSuccessfulLogin(UUID id);
}
