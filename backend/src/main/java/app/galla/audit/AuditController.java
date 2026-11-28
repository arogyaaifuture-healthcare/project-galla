package app.galla.audit;
import app.galla.security.CurrentUser;
import java.util.List;
import java.util.Map;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1/audit")
public class AuditController {
  private final AuditLog audit;
  public AuditController(AuditLog audit) { this.audit = audit; }
  @GetMapping @PreAuthorize("hasAnyRole('OWNER','MANAGER')")
  List<Map<String, Object>> recent(@RequestParam(defaultValue = "50") int limit, @RequestParam(required = false) String action) {
    return audit.recent(CurrentUser.get().tenantId(), limit, action);
  }
}
