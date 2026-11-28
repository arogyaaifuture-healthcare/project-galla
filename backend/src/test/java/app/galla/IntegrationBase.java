package app.galla;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
/** One shared PostgreSQL 16 container for all integration tests (started once per JVM). */
abstract class IntegrationBase {
  static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>("postgres:16");
  static { PG.start(); }
  @DynamicPropertySource static void props(DynamicPropertyRegistry r) {
    r.add("spring.datasource.url", PG::getJdbcUrl); r.add("spring.datasource.username", PG::getUsername); r.add("spring.datasource.password", PG::getPassword);
    r.add("galla.jwt.secret", () -> "test-secret-test-secret-test-secret-123456");
    r.add("galla.jwt.platform-secret", () -> "platform-secret-platform-secret-654321");
    r.add("galla.bootstrap.admin-email", () -> "root@galla.test");
    r.add("galla.bootstrap.admin-password", () -> "super-admin-pass-1");
  }
}
