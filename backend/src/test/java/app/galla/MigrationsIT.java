package app.galla;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import static org.junit.jupiter.api.Assertions.assertEquals;
@Testcontainers @SpringBootTest
class MigrationsIT {
  @Container static PostgreSQLContainer<?> pg = new PostgreSQLContainer<>("postgres:16");
  @DynamicPropertySource static void p(DynamicPropertyRegistry r) { r.add("spring.datasource.url", pg::getJdbcUrl); r.add("spring.datasource.username", pg::getUsername); r.add("spring.datasource.password", pg::getPassword); r.add("spring.jpa.hibernate.ddl-auto", () -> "none"); }
  @Autowired JdbcTemplate jdbc;
  @Test void allMigrationsApplyAndCreate132Tables() {
    assertEquals(132, jdbc.queryForObject("select count(*) from information_schema.tables where table_schema='public' and table_name <> 'flyway_schema_history'", Integer.class));
  }
}
