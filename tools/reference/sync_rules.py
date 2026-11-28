"""Galla offline mode — reference rules (plan Section 24). Pure functions + a tiny in-memory 'server' used by the property test."""
import hashlib, hmac, os
from datetime import datetime, timedelta

# ---------- 24.5 bill-number contiguity and gaps ----------
class Gap:
    __slots__ = ("lo", "hi", "status", "cause")
    def __init__(s, lo, hi, status="OPEN", cause="NOT_YET_SYNCED"): s.lo, s.hi, s.status, s.cause = lo, hi, status, cause
    def key(s): return (s.lo, s.hi, s.status, s.cause)
    def __repr__(s): return f"Gap{s.key()}"

def register_seq(last_no, gaps, seq):
    """A bill with sequence `seq` of one (outlet, series, fiscal_year) reaches the server.
    last_no = highest sequence seen so far (bill_counters.last_no). gaps = list of Gap (non FILLED). Returns (last_no, gaps, outcome)."""
    gaps = [Gap(g.lo, g.hi, g.status, g.cause) for g in gaps]
    if seq < 1: raise ValueError("VALIDATION_ERROR")
    if seq == last_no + 1: return seq, gaps, "IN_ORDER"
    if seq > last_no + 1:
        gaps.append(Gap(last_no + 1, seq - 1)); return seq, sorted(gaps, key=lambda g: g.lo), "GAP_OPENED"
    for g in gaps:                                   # seq <= last_no: either fills a gap or is a duplicate
        if g.lo <= seq <= g.hi:
            new = []
            if g.lo <= seq - 1: new.append(Gap(g.lo, seq - 1, g.status, g.cause))
            if seq + 1 <= g.hi: new.append(Gap(seq + 1, g.hi, g.status, g.cause))
            gaps.remove(g); gaps.extend(new)
            return last_no, sorted(gaps, key=lambda x: x.lo), ("GAP_FILLED" if g.status == "OPEN" else "LATE_IN_EXPLAINED_GAP")
    return last_no, gaps, "DUPLICATE"

def resume_seq(last_synced, last_reported, skip=10):
    """Terminal lost its browser data and re-pairs. It must never reuse a number the customer may already hold.
    Resume after the highest number the server has heard of, plus a safety skip. Returns (next_seq, gap|None)."""
    base = max(last_synced, last_reported or 0)
    nxt = base + skip + 1
    gap = (last_synced + 1, nxt - 1) if nxt - 1 >= last_synced + 1 else None
    return nxt, gap

# ---------- 24.6 offline session ----------
def session_state(last_validated, now, max_hours, last_seen_client=None, sub_deadline=None, tamper_minutes=5):
    """ONLINE is decided by connectivity, not here. Returns OFFLINE_ACTIVE or OFFLINE_LOCKED and the deadline."""
    deadline = last_validated + timedelta(hours=max_hours)
    if sub_deadline is not None: deadline = min(deadline, sub_deadline)       # never extends the subscription rule (18.4)
    if last_seen_client is not None and now < last_seen_client - timedelta(minutes=tamper_minutes):
        return "OFFLINE_LOCKED", deadline, "CLOCK_MOVED_BACKWARDS"
    if now >= deadline: return "OFFLINE_LOCKED", deadline, "SESSION_EXPIRED"
    return "OFFLINE_ACTIVE", deadline, None

def clock_skew(client_ts, server_ts, threshold_s=900):
    d = int((client_ts - server_ts).total_seconds()); return d, abs(d) > threshold_s

PBKDF2_ITER = 600_000   # placeholder: use the iteration count current OWASP guidance recommends at build time (not verified here)
def pin_hash(pin, salt=None, iterations=PBKDF2_ITER):
    if not (pin.isdigit() and 4 <= len(pin) <= 6): raise ValueError("VALIDATION_ERROR")
    salt = salt or os.urandom(16); return salt, iterations, hashlib.pbkdf2_hmac("sha256", pin.encode(), salt, iterations)
def pin_verify(pin, salt, iterations, expected):
    return hmac.compare_digest(hashlib.pbkdf2_hmac("sha256", pin.encode(), salt, iterations), expected)
def pin_attempt(fails, ok, max_fails=5):
    """returns (new_fail_count, state): after 5 wrong PINs the quick-PIN is disabled until the user signs in online with the password"""
    fails = 0 if ok else fails + 1
    return fails, ("PIN_DISABLED" if fails >= max_fails else "OK")

# ---------- 24.5 client queue: back-off, poison commands, dependencies ----------
def backoff_seconds(attempt, base=5, cap=300, jitter=0.0):
    return min(cap, base * (2 ** max(0, attempt - 1))) * (1 + jitter)

MAX_ATTEMPTS = 5
def next_runnable(queue):
    """queue: list of dict(id, deps=[ids], status in PENDING|DONE|PARKED, attempts, retry_at). Commands are sent in device_seq order.
    A PARKED command blocks only the commands that (transitively) depend on it."""
    byid = {c["id"]: c for c in queue}
    def blocked(c, seen=()):
        for d in c["deps"]:
            dc = byid.get(d)
            if dc is None: continue
            if dc["status"] == "PARKED": return True
            if dc["status"] != "DONE": return True      # dependency not applied yet → wait
        return False
    return [c for c in queue if c["status"] == "PENDING" and not blocked(c)]

def record_failure(cmd, retryable=True):
    cmd = dict(cmd); cmd["attempts"] += 1
    if not retryable or cmd["attempts"] >= MAX_ATTEMPTS: cmd["status"] = "PARKED"
    return cmd

# ---------- 24.5 server-side conflict classification (never rejects a completed bill) ----------
def classify(facts):
    """facts: dict with optional keys. Returns list of (type, severity)."""
    out = []
    if facts.get("calc_mismatch"): out.append(("CALC_MISMATCH", "CRITICAL"))
    if facts.get("gap_opened"): out.append(("NUMBER_GAP", "WARN"))
    if facts.get("table_conflict"): out.append(("TABLE_CONFLICT", "WARN"))
    if facts.get("inactive_items"): out.append(("ITEM_INACTIVE", "INFO"))
    if facts.get("price_changed"): out.append(("PRICE_CHANGED", "INFO"))
    if facts.get("clock_skew"): out.append(("CLOCK_SKEW", "WARN"))
    if facts.get("user_disabled"): out.append(("USER_DEACTIVATED", "WARN"))
    if facts.get("day_closed"): out.append(("LATE_FOR_CLOSED_DAY", "WARN"))
    return out

def protocol_error(cmd, device):
    """The only reasons a command is REJECTED (payload is still kept for manual repair). Business-rule conflicts never reject."""
    if device is None: return "UNKNOWN_DEVICE"
    if cmd.get("schema_version") not in (device["current_schema"], device["current_schema"] - 1): return "UNSUPPORTED_SCHEMA_VERSION"
    if cmd["type"] == "BILL_GENERATE":
        b = cmd["bill"]
        if b["series"] != device["series_code"]: return "SERIES_MISMATCH"
        if b["number"] != f'{b["series"]}-{b["fy"]}-{b["seq"]:06d}': return "BILL_NUMBER_MALFORMED"
    return None

def revoked_device_accepts(client_created_at, revoked_at, now, window_days=7):
    """A revoked terminal can still deliver what it issued BEFORE revocation, for a limited window."""
    return client_created_at <= revoked_at and now <= revoked_at + timedelta(days=window_days)

# ---------- in-memory server model (used by the property test) ----------
def table_flags(orders):
    """orders: id -> dict(table, t_open, t_close|None). flagged(o) = an EARLIER-opened order on the same table was still open when o opened.
    Depends only on client times, never on arrival order."""
    flagged = set()
    for o, od in orders.items():
        for p, pd in orders.items():
            if p == o or pd["table"] != od["table"]: continue
            if (pd["t_open"], p) < (od["t_open"], o) and (pd["t_close"] is None or pd["t_close"] > od["t_open"]): flagged.add(o)
    return flagged

class Server:
    def __init__(s):
        s.cmds = {}; s.orders = {}; s.bills = {}; s.payments = {}; s.last = {}; s.gaps = {}; s.waiting = []
    def push(s, cmd):
        """idempotent by cmd['id']; returns APPLIED | DUPLICATE | WAITING"""
        if cmd["id"] in s.cmds: return "DUPLICATE"
        if cmd.get("dep") and cmd["dep"] not in s.cmds:
            if all(w["id"] != cmd["id"] for w in s.waiting): s.waiting.append(cmd)
            return "WAITING"
        s._apply(cmd); s._drain(); return "APPLIED"
    def _drain(s):
        progress = True
        while progress:
            progress = False
            for w in list(s.waiting):
                if w["dep"] in s.cmds: s.waiting.remove(w); s._apply(w); progress = True
    def _apply(s, c):
        s.cmds[c["id"]] = c["type"]
        if c["type"] == "ORDER_OPEN": s.orders[c["order"]] = dict(table=c["table"], t_open=c["t"], t_close=None, dev_no=c["dev_no"])
        elif c["type"] == "BILL_GENERATE":
            key = (c["series"], c["fy"])
            last, gaps, _ = register_seq(s.last.get(key, 0), s.gaps.get(key, []), c["seq"])
            s.last[key], s.gaps[key] = last, gaps
            s.bills[(c["series"], c["fy"], c["seq"])] = c["total"]
        elif c["type"] == "PAYMENT_ADD": s.payments[c["payment"]] = (c["bill"], c["amount"])
        elif c["type"] == "ORDER_CLOSE": s.orders[c["order"]]["t_close"] = c["t"]
    def state(s):
        return dict(orders={k: (v["table"], v["t_open"], v["t_close"], v["dev_no"]) for k, v in s.orders.items()},
                    bills=dict(s.bills), payments=dict(s.payments), last=dict(s.last),
                    gaps={k: [g.key() for g in v] for k, v in s.gaps.items()}, flagged=sorted(table_flags(s.orders)), waiting=len(s.waiting))
