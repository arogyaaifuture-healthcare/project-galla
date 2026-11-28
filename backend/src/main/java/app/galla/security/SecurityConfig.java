package app.galla.security;
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
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {
  private final SecretKey key;
  public SecurityConfig(@Value("${galla.jwt.secret:}") String secret) {
    if (secret.getBytes(StandardCharsets.UTF_8).length < 32)
      throw new IllegalStateException("GALLA_JWT_SECRET must be set to at least 32 characters");
    this.key = new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
  }
  @Bean PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(12); }
  @Bean JwtEncoder jwtEncoder() { return new NimbusJwtEncoder(new ImmutableSecret<>(key)); }
  @Bean JwtDecoder jwtDecoder() { return NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build(); }

  @Bean SecurityFilterChain chain(HttpSecurity http) throws Exception {
    var conv = new JwtAuthenticationConverter();
    conv.setJwtGrantedAuthoritiesConverter(j -> List.of(new SimpleGrantedAuthority("ROLE_" + j.getClaimAsString("role"))));
    http.csrf(AbstractHttpConfigurer::disable) // stateless bearer-token API, no cookies
        .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .authorizeHttpRequests(a -> a
            .requestMatchers("/api/v1/auth/login", "/api/v1/auth/register", "/actuator/health/**", "/actuator/info").permitAll()
            .anyRequest().authenticated())
        .oauth2ResourceServer(o -> o.jwt(j -> j.jwtAuthenticationConverter(conv))
            .authenticationEntryPoint((req, res, ex) -> json(res, 401, "UNAUTHENTICATED", "Please sign in again")))
        .exceptionHandling(e -> e.accessDeniedHandler((req, res, ex) -> json(res, 403, "FORBIDDEN", "You do not have permission for this action")));
    return http.build();
  }
  private static void json(jakarta.servlet.http.HttpServletResponse res, int status, String code, String msg) throws java.io.IOException {
    res.setStatus(status); res.setContentType(MediaType.APPLICATION_JSON_VALUE);
    res.getWriter().write("{\"code\":\"" + code + "\",\"message\":\"" + msg + "\",\"details\":[]}");
  }
}
