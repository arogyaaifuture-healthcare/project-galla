package app.galla.common;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

@RestControllerAdvice
public class GlobalExceptionHandler {
  private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);
  public record Body(String code, String message, List<Map<String, String>> details) {}

  private static ResponseEntity<Body> r(HttpStatus s, String code, String msg, List<Map<String, String>> d) {
    return ResponseEntity.status(s).body(new Body(code, msg, d));
  }
  @ExceptionHandler(ApiException.class) ResponseEntity<Body> api(ApiException e) { return r(e.status(), e.code(), e.getMessage(), List.of()); }
  @ExceptionHandler(MethodArgumentNotValidException.class) ResponseEntity<Body> invalid(MethodArgumentNotValidException e) {
    var d = e.getBindingResult().getFieldErrors().stream().map(f -> Map.of("field", f.getField(), "message", String.valueOf(f.getDefaultMessage()))).toList();
    return r(HttpStatus.UNPROCESSABLE_ENTITY, "VALIDATION_FAILED", "Please correct the highlighted fields", d);
  }
  @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class}) ResponseEntity<Body> bad(Exception e) {
    return r(HttpStatus.BAD_REQUEST, "BAD_REQUEST", "The request could not be read", List.of());
  }
  @ExceptionHandler(AccessDeniedException.class) ResponseEntity<Body> denied(AccessDeniedException e) { return r(HttpStatus.FORBIDDEN, "FORBIDDEN", "You do not have permission for this action", List.of()); }
  @ExceptionHandler(DataIntegrityViolationException.class) ResponseEntity<Body> integrity(DataIntegrityViolationException e) {
    log.warn("integrity violation: {}", e.getMostSpecificCause().getMessage());
    return r(HttpStatus.CONFLICT, "CONFLICT", "This change conflicts with existing data", List.of());
  }
  @ExceptionHandler(Exception.class) ResponseEntity<Body> other(Exception e) {
    log.error("unhandled", e);
    return r(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL", "Something went wrong. Please try again.", List.of());
  }
}
