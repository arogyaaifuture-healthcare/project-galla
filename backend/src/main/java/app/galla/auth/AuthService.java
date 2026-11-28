package app.galla.auth;
import app.galla.auth.AuthDtos.*;
public interface AuthService {
  TokenResponse register(RegisterRequest request);
  TokenResponse login(LoginRequest request);
  UserView me(java.util.UUID userId, java.util.UUID tenantId);
}
