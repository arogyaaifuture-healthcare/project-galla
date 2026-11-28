package app.galla.auth;
import app.galla.auth.AuthDtos.*;
public interface AuthService {
  AuthResult register(RegisterRequest request, String userAgent);
  AuthResult login(LoginRequest request, String userAgent);
  AuthResult refresh(String refreshToken, String userAgent);
  void logout(String refreshToken);
  UserView me(java.util.UUID userId, java.util.UUID tenantId);
}
