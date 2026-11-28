package app.galla.staff;
import app.galla.audit.AuditEvent;
import app.galla.audit.AuditLog;
import app.galla.auth.RefreshTokens;
import app.galla.common.ApiException;
import app.galla.staff.StaffDtos.*;
import app.galla.subscription.PlanLimits;
import app.galla.user.UserRepository;
import app.galla.user.UserRepository.Member;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Staff rules: managers cannot touch owners, nobody disables themselves, a restaurant always keeps one active owner, plan limits apply to every active user. */
@Service
class DefaultStaffService implements StaffService {
  private final UserRepository users; private final PlanLimits limits; private final PasswordEncoder encoder; private final RefreshTokens sessions; private final AuditLog audit;
  DefaultStaffService(UserRepository users, PlanLimits limits, PasswordEncoder encoder, RefreshTokens sessions, AuditLog audit) { this.users = users; this.limits = limits; this.encoder = encoder; this.sessions = sessions; this.audit = audit; }

  private static ApiException forbidden(String msg) { return new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", msg); }
  @Override public List<Member> list(UUID t) { return users.list(t); }

  @Override @Transactional public Member create(UUID t, UUID actor, String actorRole, CreateRequest r) {
    if (r.role().equals("OWNER") && !actorRole.equals("OWNER")) throw forbidden("Only an owner can add another owner");
    limits.checkCanAddUser(t, r.role());
    try {
      var m = users.create(t, r.name().trim(), r.email().trim().toLowerCase(), r.phone(), r.role(), encoder.encode(r.password()));
      audit.record(AuditEvent.tenantUser(t, actor, "USER_CREATED", "user", m.id(), Map.of("email", m.email(), "role", m.role())));
      return m;
    } catch (DuplicateKeyException e) { throw ApiException.conflict("EMAIL_TAKEN", "A user with this email already exists"); }
  }

  @Override @Transactional public Member update(UUID t, UUID actor, String actorRole, UUID id, UpdateRequest r) {
    Member cur = users.findMember(t, id).orElseThrow(() -> ApiException.notFound("User"));
    boolean actorIsOwner = actorRole.equals("OWNER");
    if (cur.role().equals("OWNER") && !actorIsOwner) throw forbidden("Only an owner can change an owner");
    if (r.role() != null && r.role().equals("OWNER") && !actorIsOwner) throw forbidden("Only an owner can make someone an owner");
    if (id.equals(actor) && r.role() != null && !r.role().equals(cur.role())) throw ApiException.conflict("CANNOT_CHANGE_OWN_ROLE", "You cannot change your own role");
    String status = r.active() == null ? null : (r.active() ? "ACTIVE" : "DISABLED");
    if (status != null && id.equals(actor) && status.equals("DISABLED")) throw ApiException.conflict("CANNOT_DISABLE_SELF", "You cannot disable your own account");
    boolean leavingActiveOwner = cur.role().equals("OWNER") && cur.status().equals("ACTIVE")
        && ((status != null && status.equals("DISABLED")) || (r.role() != null && !r.role().equals("OWNER")));
    if (leavingActiveOwner && users.countActiveWithRole(t, "OWNER") <= 1) throw ApiException.conflict("LAST_OWNER", "A restaurant must keep at least one active owner");
    boolean becomingActive = "ACTIVE".equals(status) && !cur.status().equals("ACTIVE");
    String newRole = r.role() == null ? cur.role() : r.role();
    if (becomingActive) limits.checkCanAddUser(t, newRole);
    else if (r.role() != null && !r.role().equals(cur.role()) && cur.status().equals("ACTIVE")) limits.checkRoleCap(t, newRole);
    var m = users.update(t, id, r.name() == null ? null : r.name().trim(), r.role(), status).orElseThrow(() -> ApiException.notFound("User"));
    if ("DISABLED".equals(status)) sessions.endAllSessions(id);
    audit.record(AuditEvent.tenantUser(t, actor, status != null ? (r.active() ? "USER_ENABLED" : "USER_DISABLED") : "USER_UPDATED", "user", id, Map.of("role", m.role(), "status", m.status())));
    return m;
  }
  @Override @Transactional public void resetPassword(UUID t, UUID actor, UUID id, String pw) {
    users.findMember(t, id).orElseThrow(() -> ApiException.notFound("User"));
    users.setPassword(t, id, encoder.encode(pw)); sessions.endAllSessions(id);
    audit.record(AuditEvent.tenantUser(t, actor, "USER_PASSWORD_RESET", "user", id, Map.of()));
  }
}
