package app.galla.security;
import app.galla.subscription.SubscriptionAccessFilter;
import com.nimbusds.jose.jwk.source.ImmutableSecret;
import java.nio.charset.StandardCharsets;
import java.util.List;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;

/** Restaurant tokens and platform tokens are signed with different secrets and carry a `typ` claim; each kind is rejected by the other's endpoints. */
@Configuration
@EnableMethodSecurity
public class SecurityConfig {
  private final SecretKey tenantKey, platformKey;
  public SecurityConfig(@Value("${galla.jwt.secret:}") String t, @Value("${galla.jwt.platform-secret:}") String p) {
    this.tenantKey = key(t, "GALLA_JWT_SECRET"); this.platformKey = key(p, "GALLA_PLATFORM_JWT_SECRET");
    if (t.equals(p)) throw new IllegalStateException("The two JWT secrets must be different");
  }
  private static SecretKey key(String s, String name) {
    if (s.getBytes(StandardCharsets.UTF_8).length < 32) throw new IllegalStateException(name + " must be set to at least 32 characters");
    return new SecretKeySpec(s.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
  }
  @Bean PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(12); }
  @Bean(name = "tenantJwtEncoder") JwtEncoder tenantJwtEncoder() { return new NimbusJwtEncoder(new ImmutableSecret<>(tenantKey)); }
  @Bean(name = "platformJwtEncoder") JwtEncoder platformJwtEncoder() { return new NimbusJwtEncoder(new ImmutableSecret<>(platformKey)); }

  @Bean JwtDecoder jwtDecoder() {
    JwtDecoder tenant = NimbusJwtDecoder.withSecretKey(tenantKey).macAlgorithm(MacAlgorithm.HS256).build();
    JwtDecoder platform = NimbusJwtDecoder.withSecretKey(platformKey).macAlgorithm(MacAlgorithm.HS256).build();
    return token -> {
      try { Jwt j = tenant.decode(token); if ("TENANT".equals(j.getClaimAsString("typ"))) return j; throw new BadJwtException("wrong token type"); }
      catch (BadJwtException first) {
        Jwt j = platform.decode(token);
        if (!"PLATFORM".equals(j.getClaimAsString("typ"))) throw new BadJwtException("wrong token type");
        return j;
      }
    };
  }

  @Bean SecurityFilterChain chain(HttpSecurity http, SubscriptionAccessFilter access) throws Exception {
    var conv = new JwtAuthenticationConverter();
    conv.setJwtGrantedAuthoritiesConverter(j -> List.of(new SimpleGrantedAuthority("ROLE_" + j.getClaimAsString("role"))));
    http.csrf(AbstractHttpConfigurer::disable) // stateless bearer-token API; the refresh cookie is SameSite=Strict and path-limited
        .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .authorizeHttpRequests(a -> a
            .requestMatchers("/api/v1/auth/login", "/api/v1/auth/register", "/api/v1/auth/refresh", "/api/v1/platform/auth/login", "/actuator/health/**", "/actuator/info").permitAll()
            .requestMatchers("/api/v1/platform/**").hasAnyRole("SUPER_ADMIN", "SUPPORT")
            .anyRequest().hasAnyRole("OWNER", "MANAGER", "CASHIER", "CAPTAIN", "KITCHEN", "RIDER", "INVENTORY", "ACCOUNTANT"))
        .oauth2ResourceServer(o -> o.jwt(j -> j.jwtAuthenticationConverter(conv))
            .authenticationEntryPoint((req, res, ex) -> json(res, 401, "UNAUTHENTICATED", "Please sign in again")))
        .addFilterAfter(access, BearerTokenAuthenticationFilter.class)
        .exceptionHandling(e -> e.accessDeniedHandler((req, res, ex) -> json(res, 403, "FORBIDDEN", "You do not have permission for this action")));
    return http.build();
  }
  public static void json(jakarta.servlet.http.HttpServletResponse res, int status, String code, String msg) throws java.io.IOException {
    res.setStatus(status); res.setContentType(MediaType.APPLICATION_JSON_VALUE);
    res.getWriter().write("{\"code\":\"" + code + "\",\"message\":\"" + msg + "\",\"details\":[]}");
  }
}
