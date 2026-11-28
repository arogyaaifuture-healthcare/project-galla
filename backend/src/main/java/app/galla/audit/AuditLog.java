package app.galla.audit;
import java.util.List;
import java.util.Map;
import java.util.UUID;
/** Port: services record what happened without knowing how it is stored. */
public interface AuditLog {
  void record(AuditEvent e);
  List<Map<String, Object>> recent(UUID tenantId, int limit, String action);
}
