package app.galla.staff;
import app.galla.staff.StaffDtos.*;
import app.galla.user.UserRepository.Member;
import java.util.List;
import java.util.UUID;
public interface StaffService {
  List<Member> list(UUID tenantId);
  Member create(UUID tenantId, UUID actorId, String actorRole, CreateRequest r);
  Member update(UUID tenantId, UUID actorId, String actorRole, UUID id, UpdateRequest r);
  void resetPassword(UUID tenantId, UUID actorId, UUID id, String newPassword);
}
