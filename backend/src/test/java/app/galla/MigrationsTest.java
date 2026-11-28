package app.galla;
import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
@SpringBootTest
class MigrationsTest extends IntegrationBase {
  @Autowired JdbcTemplate jdbc;
  @Test void allMigrationsApplyAndCreate132Tables() {
    assertEquals(132, jdbc.queryForObject("select count(*) from information_schema.tables where table_schema='public' and table_name <> 'flyway_schema_history'", Integer.class));
  }
}
