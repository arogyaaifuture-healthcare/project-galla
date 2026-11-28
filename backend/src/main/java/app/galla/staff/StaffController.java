package app.galla.staff;
import app.galla.security.CurrentUser;
import app.galla.staff.StaffDtos.*;
import app.galla.user.UserRepository.Member;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/v1/users") @PreAuthorize("hasAnyRole('OWNER','MANAGER')")
public class StaffController {
  private final StaffService staff;
  public StaffController(StaffService staff) { this.staff = staff; }
  @GetMapping List<Member> list() { return staff.list(CurrentUser.get().tenantId()); }
  @PostMapping @ResponseStatus(HttpStatus.CREATED) Member create(@Valid @RequestBody CreateRequest r) { var c = CurrentUser.get(); return staff.create(c.tenantId(), c.userId(), c.role(), r); }
  @PatchMapping("/{id}") Member update(@PathVariable UUID id, @Valid @RequestBody UpdateRequest r) { var c = CurrentUser.get(); return staff.update(c.tenantId(), c.userId(), c.role(), id, r); }
  @PostMapping("/{id}/reset-password") @PreAuthorize("hasRole('OWNER')") void reset(@PathVariable UUID id, @Valid @RequestBody ResetPasswordRequest r) { var c = CurrentUser.get(); staff.resetPassword(c.tenantId(), c.userId(), id, r.password()); }
}
