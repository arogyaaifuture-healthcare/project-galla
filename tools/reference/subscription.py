"""Subscription lifecycle + plan limits (plan Section 18). Pure functions, UTC datetimes."""
from datetime import datetime, timedelta, timezone
from dateutil.relativedelta import relativedelta
def add_cycles(anchor, cycle, k):
    return anchor + (relativedelta(months=k) if cycle == "MONTHLY" else relativedelta(years=k))
def period(anchor, cycle, k):
    return add_cycles(anchor, cycle, k), add_cycles(anchor, cycle, k + 1)
def trial_end(start, trial_days): return start + timedelta(days=trial_days)
def effective_status(sub, now):
    """sub: dict(status, trial_ends_at, current_period_end, grace_days, cancel_at_period_end). Returns TRIALING|ACTIVE|PAST_DUE|SUSPENDED|CANCELLED"""
    st = sub["status"]; grace = timedelta(days=sub["grace_days"])
    if st == "CANCELLED": return "CANCELLED"
    if st == "SUSPENDED": return "SUSPENDED"
    # paid in advance during the trial: first paid period is stored while status is still TRIALING;
    # from trial_ends_at the subscription is ACTIVE even if the hourly job has not flipped it yet
    if st == "TRIALING" and sub.get("current_period_end") and now >= sub["trial_ends_at"]: st = "ACTIVE"
    due = sub["trial_ends_at"] if st == "TRIALING" else sub["current_period_end"]
    if now < due: return st if st in ("TRIALING", "ACTIVE") else "ACTIVE"
    if st == "ACTIVE" and sub.get("cancel_at_period_end"): return "CANCELLED"   # cancelled subscriptions get no grace
    return "PAST_DUE" if now < due + grace else "SUSPENDED"
def access_level(eff):
    return {"TRIALING": "FULL", "ACTIVE": "FULL", "PAST_DUE": "FULL_BANNER",
            "SUSPENDED": "READ_ONLY_SETTLE", "CANCELLED": "READ_ONLY_SETTLE"}[eff]
def next_period_after_payment(sub, now):
    """Returns (anchor, k, start, end). On time / within grace: continue the existing anchor (no gap, no free days).
    After suspension (or expired trial beyond grace): re-anchor at 'now'."""
    eff = effective_status(sub, now)
    if eff in ("ACTIVE", "PAST_DUE") and sub["status"] != "TRIALING":
        k = sub["period_number"] + 1; s, e = period(sub["billing_anchor_at"], sub["billing_cycle"], k)
        return sub["billing_anchor_at"], k, s, e
    if eff in ("TRIALING", "PAST_DUE") and sub["status"] == "TRIALING":   # first payment during/just after trial: starts when trial ends
        anchor = sub["trial_ends_at"]; s, e = period(anchor, sub["billing_cycle"], 0); return anchor, 0, s, e
    s, e = period(now, sub["billing_cycle"], 0); return now, 0, s, e
def extend_trial(trial_ends_at, now, days): return max(trial_ends_at, now) + timedelta(days=days)
def reminders_due(trial_ends_at, now, offsets=(7, 3, 1, 0)):
    return sorted((k for k in offsets if now >= trial_ends_at - timedelta(days=k)), reverse=True)
def can_add_user(plan, active_counts, role):
    total = sum(active_counts.values())
    if total + 1 > plan["max_users"]: return False, "PLAN_LIMIT_USERS"
    lim = plan["role_limits"].get(role)
    if lim is not None and active_counts.get(role, 0) + 1 > lim: return False, "PLAN_LIMIT_ROLE"
    return True, None
def can_add_outlet(plan, active_outlets): return (active_outlets + 1 <= plan["max_outlets"], None if active_outlets + 1 <= plan["max_outlets"] else "PLAN_LIMIT_OUTLETS")
