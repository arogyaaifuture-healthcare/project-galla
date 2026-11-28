package app.galla.platform;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
/** Creates the first super admin from GALLA_BOOTSTRAP_ADMIN_EMAIL / _PASSWORD, only when no platform user exists yet. Remove the variables afterwards. */
@Component
class PlatformBootstrap implements ApplicationRunner {
  private static final Logger log = LoggerFactory.getLogger(PlatformBootstrap.class);
  private final PlatformUserRepository users; private final PasswordEncoder encoder; private final String email, password;
  PlatformBootstrap(PlatformUserRepository users, PasswordEncoder encoder, @Value("${galla.bootstrap.admin-email:}") String email, @Value("${galla.bootstrap.admin-password:}") String password) {
    this.users = users; this.encoder = encoder; this.email = email; this.password = password;
  }
  @Override public void run(ApplicationArguments args) {
    if (email.isBlank() || password.isBlank() || users.anyExist()) return;
    if (password.length() < 12) throw new IllegalStateException("GALLA_BOOTSTRAP_ADMIN_PASSWORD must be at least 12 characters");
    users.create(email.trim().toLowerCase(), "Super Admin", encoder.encode(password), "SUPER_ADMIN");
    log.info("Created the first super admin {}", email);
  }
}
