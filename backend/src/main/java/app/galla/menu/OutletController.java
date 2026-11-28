package app.galla.menu;
import app.galla.security.CurrentUser;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1/outlets")
public class OutletController {
  private final JdbcClient db;
  public OutletController(JdbcClient db) { this.db = db; }
  @GetMapping List<Map<String, Object>> list() {
    return db.sql("SELECT id, code, name, currency_symbol AS \"currencySymbol\" FROM outlets WHERE tenant_id=:t AND status='ACTIVE' ORDER BY code")
        .param("t", CurrentUser.get().tenantId()).query().listOfRows();
  }
}
