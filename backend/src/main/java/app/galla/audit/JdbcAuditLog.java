package app.galla.audit;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
/** Writes in the caller's transaction, so an action and its audit row succeed or fail together. */
@Repository
class JdbcAuditLog implements AuditLog {
  private final JdbcClient db; private final ObjectMapper om;
  JdbcAuditLog(JdbcClient db, ObjectMapper om) { this.db = db; this.om = om; }
  private String json(Map<String, Object> m) {
    try { return m == null ? null : om.writeValueAsString(m); } catch (JsonProcessingException e) { throw new IllegalStateException(e); }
  }
  @Override public void record(AuditEvent e) {
    db.sql("""
      INSERT INTO audit_logs(tenant_id,user_id,action,entity_type,entity_id,before_data,after_data,reason,actor_type)
      VALUES (:t,:u,:a,:et,:ei,CAST(:b AS jsonb),CAST(:af AS jsonb),:r,:at)""")
      .param("t", e.tenantId()).param("u", "TENANT_USER".equals(e.actorType()) ? e.actorId() : null).param("a", e.action()).param("et", e.entityType()).param("ei", e.entityId())
      .param("b", json(e.before())).param("af", json(e.after())).param("r", e.reason()).param("at", e.actorType()).update();
  }
  @Override public List<Map<String, Object>> recent(UUID tenantId, int limit, String action) {
    return db.sql("""
      SELECT a.id, a.created_at AS "at", a.actor_type AS "actorType", coalesce(u.full_name,'') AS actor, a.action, a.entity_type AS "entityType", a.entity_id AS "entityId", a.after_data::text AS details
      FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id
      WHERE a.tenant_id=:t AND (CAST(:act AS text) IS NULL OR a.action=CAST(:act AS text)) ORDER BY a.id DESC LIMIT :l""")
      .param("t", tenantId).param("act", action).param("l", Math.min(Math.max(limit, 1), 200)).query().listOfRows();
  }
}
