package app.galla.audit;
import java.util.Map;
import java.util.UUID;
public record AuditEvent(String actorType, UUID tenantId, UUID actorId, String action, String entityType, String entityId, Map<String, Object> before, Map<String, Object> after, String reason) {
  public static AuditEvent tenantUser(UUID tenantId, UUID userId, String action, String entityType, Object entityId, Map<String, Object> after) {
    return new AuditEvent("TENANT_USER", tenantId, userId, action, entityType, String.valueOf(entityId), null, after, null);
  }
  public static AuditEvent platformUser(UUID tenantId, UUID platformUserId, String action, String entityType, Object entityId, Map<String, Object> after, String reason) {
    return new AuditEvent("PLATFORM_USER", tenantId, platformUserId, action, entityType, String.valueOf(entityId), null, after, reason);
  }
  public static AuditEvent system(UUID tenantId, String action, String entityType, Object entityId, Map<String, Object> after) {
    return new AuditEvent("SYSTEM", tenantId, null, action, entityType, String.valueOf(entityId), null, after, null);
  }
}
