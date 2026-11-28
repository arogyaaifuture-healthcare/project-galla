package app.galla.security;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.stereotype.Component;
@Component
class JwtTokenIssuer implements TokenIssuer {
  private final JwtEncoder tenantEncoder, platformEncoder; private final long minutes; private final Clock clock;
  JwtTokenIssuer(@Qualifier("tenantJwtEncoder") JwtEncoder t, @Qualifier("platformJwtEncoder") JwtEncoder p, @Value("${galla.jwt.access-minutes}") long minutes, Clock clock) {
    this.tenantEncoder = t; this.platformEncoder = p; this.minutes = minutes; this.clock = clock;
  }
  private Issued issue(JwtEncoder enc, JwtClaimsSet.Builder b) {
    Instant now = clock.instant();
    JwtClaimsSet c = b.issuedAt(now).expiresAt(now.plus(Duration.ofMinutes(minutes))).build();
    return new Issued(enc.encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), c)).getTokenValue(), minutes * 60);
  }
  @Override public Issued tenantToken(UUID userId, UUID tenantId, String role) {
    return issue(tenantEncoder, JwtClaimsSet.builder().subject(userId.toString()).claim("typ", "TENANT").claim("tid", tenantId.toString()).claim("role", role));
  }
  @Override public Issued platformToken(UUID id, String role) {
    return issue(platformEncoder, JwtClaimsSet.builder().subject(id.toString()).claim("typ", "PLATFORM").claim("role", role));
  }
}
