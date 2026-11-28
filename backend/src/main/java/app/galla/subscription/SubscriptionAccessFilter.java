package app.galla.subscription;
import app.galla.security.SecurityConfig;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * After the trial (and grace days) a restaurant that has not paid can only open the subscription page.
 * Mode LOCKED (default) blocks everything else; READ_ONLY still lets it view data (GET). Registered only inside the security chain.
 */
@Component
public class SubscriptionAccessFilter extends OncePerRequestFilter {
  private final SubscriptionService subscriptions;
  public SubscriptionAccessFilter(SubscriptionService subscriptions) { this.subscriptions = subscriptions; }

  @Override protected boolean shouldNotFilterAsyncDispatch() { return true; }
  /** Spring Boot would also register a @Component filter with the servlet container; the security chain is the only place it must run. */
  @org.springframework.context.annotation.Bean
  static org.springframework.boot.web.servlet.FilterRegistrationBean<SubscriptionAccessFilter> noServletRegistration(SubscriptionAccessFilter f) {
    var r = new org.springframework.boot.web.servlet.FilterRegistrationBean<>(f); r.setEnabled(false); return r;
  }

  @Override protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain) throws ServletException, IOException {
    Authentication a = SecurityContextHolder.getContext().getAuthentication();
    if (a != null && a.getPrincipal() instanceof Jwt j && "TENANT".equals(j.getClaimAsString("typ"))) {
      String path = req.getRequestURI();
      boolean alwaysAllowed = path.startsWith("/api/v1/subscription") || path.equals("/api/v1/me") || path.startsWith("/api/v1/auth/");
      if (!alwaysAllowed) {
        var access = subscriptions.access(UUID.fromString(j.getClaimAsString("tid")));
        if (!access.full()) {
          boolean read = req.getMethod().equals("GET") || req.getMethod().equals("HEAD");
          if (!(access.readOnlyAllowed() && read)) { SecurityConfig.json(res, 402, "SUBSCRIPTION_INACTIVE", "Your free trial or subscription has ended. Please pay to continue."); return; }
        } else if ("PAST_DUE".equals(access.effective())) res.setHeader("X-Subscription-Warning", "PAST_DUE");
      }
    }
    chain.doFilter(req, res);
  }
}
