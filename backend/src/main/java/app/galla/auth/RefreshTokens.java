package app.galla.auth;
import java.util.UUID;
/** Port for long-lived session tokens. Only a hash is stored; each use rotates the token and reuse of an old one kills the whole session family. */
public interface RefreshTokens {
  record Rotation(UUID userId, String newToken) {}
  String startSession(UUID userId, String userAgent);
  Rotation rotate(String rawToken, String userAgent);
  void endSession(String rawToken);
  void endAllSessions(UUID userId);
}
