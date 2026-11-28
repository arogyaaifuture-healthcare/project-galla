package app.galla;
import static app.galla.subscription.SubscriptionPolicy.Effective.*;
import static org.junit.jupiter.api.Assertions.*;
import app.galla.subscription.SubscriptionPolicy;
import app.galla.subscription.UpiLink;
import java.math.BigDecimal;
import java.time.Instant;
import org.junit.jupiter.api.Test;

/** Pure-rule tests: the boundary vectors of plan section 18.4. */
class SubscriptionPolicyTest {
  static final Instant TRIAL_START = Instant.parse("2026-11-22T10:00:00Z");
  static final Instant TRIAL_END = Instant.parse("2026-12-22T10:00:00Z");
  static SubscriptionPolicy.Effective trial(String now) { return SubscriptionPolicy.effective("TRIALING", TRIAL_END, null, 7, false, Instant.parse(now)); }

  @Test void trialBoundariesAreExclusiveAtTheEnd() {
    assertEquals(TRIALING, trial("2026-12-22T09:59:59Z"));
    assertEquals(PAST_DUE, trial("2026-12-22T10:00:00Z"));
    assertEquals(PAST_DUE, trial("2026-12-29T09:59:59Z"));
    assertEquals(SUSPENDED, trial("2026-12-29T10:00:00Z"));
  }
  @Test void activeBecomesPastDueThenSuspended() {
    var end = Instant.parse("2027-01-22T10:00:00Z");
    assertEquals(ACTIVE, SubscriptionPolicy.effective("ACTIVE", TRIAL_END, end, 7, false, end.minusSeconds(1)));
    assertEquals(PAST_DUE, SubscriptionPolicy.effective("ACTIVE", TRIAL_END, end, 7, false, end));
    assertEquals(SUSPENDED, SubscriptionPolicy.effective("ACTIVE", TRIAL_END, end, 7, false, end.plusSeconds(7 * 86400)));
  }
  @Test void cancelAtPeriodEndHasNoGrace() {
    var end = Instant.parse("2027-01-22T10:00:00Z");
    assertEquals(ACTIVE, SubscriptionPolicy.effective("ACTIVE", null, end, 7, true, end.minusSeconds(1)));
    assertEquals(CANCELLED, SubscriptionPolicy.effective("ACTIVE", null, end, 7, true, end));
    assertEquals(CANCELLED, SubscriptionPolicy.effective("CANCELLED", null, end, 7, false, end.minusSeconds(5)));
  }
  @Test void monthlyPeriodsAnchorWithoutDrift() {
    var anchor = Instant.parse("2027-01-31T00:00:00Z");
    assertEquals(Instant.parse("2027-02-28T00:00:00Z"), SubscriptionPolicy.addCycles(anchor, "MONTHLY", 1));
    assertEquals(Instant.parse("2027-03-31T00:00:00Z"), SubscriptionPolicy.addCycles(anchor, "MONTHLY", 2));
  }
  @Test void yearlyFromLeapDay() {
    assertEquals(Instant.parse("2029-02-28T00:00:00Z"), SubscriptionPolicy.addCycles(Instant.parse("2028-02-29T00:00:00Z"), "YEARLY", 1));
  }
  @Test void upiLinkCarriesTheAmountAndEncodesText() {
    String u = UpiLink.build("shop@okbank", "Galla Tech & Co", new BigDecimal("499"), "GL-INV-000001");
    assertEquals("upi://pay?pa=shop%40okbank&pn=Galla%20Tech%20%26%20Co&am=499.00&cu=INR&tn=GL-INV-000001", u);
    assertThrows(IllegalArgumentException.class, () -> UpiLink.build("not a vpa", "X", BigDecimal.ONE, "n"));
  }
}
