package app.galla.subscription;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
/** Pure rules for subscription state and billing periods (plan 18.4). No database, no clock of its own: everything is passed in, so it is easy to test. */
public final class SubscriptionPolicy {
  private SubscriptionPolicy() {}
  public enum Effective { TRIALING, ACTIVE, PAST_DUE, SUSPENDED, CANCELLED;
    public boolean fullAccess() { return this == TRIALING || this == ACTIVE || this == PAST_DUE; } }

  /** Persisted status is TRIALING, ACTIVE or CANCELLED; PAST_DUE and SUSPENDED are computed from the clock, so a missed job can never grant or deny access wrongly. */
  public static Effective effective(String status, Instant trialEndsAt, Instant periodEnd, int graceDays, boolean cancelAtPeriodEnd, Instant now) {
    if ("CANCELLED".equals(status)) return Effective.CANCELLED;
    boolean trial = "TRIALING".equals(status);
    Instant end = trial ? trialEndsAt : periodEnd;
    if (end == null) return Effective.SUSPENDED;
    if (now.isBefore(end)) return trial ? Effective.TRIALING : Effective.ACTIVE;
    if (cancelAtPeriodEnd && !trial) return Effective.CANCELLED;
    return now.isBefore(end.plus(Duration.ofDays(graceDays))) ? Effective.PAST_DUE : Effective.SUSPENDED;
  }

  /** Calendar arithmetic from the anchor (not from the previous end), so 31 Jan + 1 month = 28 Feb but + 2 months = 31 Mar: no drift. */
  public static Instant addCycles(Instant anchor, String cycle, int n) {
    var z = anchor.atZone(ZoneOffset.UTC);
    return ("YEARLY".equals(cycle) ? z.plusYears(n) : z.plusMonths(n)).toInstant();
  }
}
