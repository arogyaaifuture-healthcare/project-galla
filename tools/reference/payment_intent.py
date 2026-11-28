"""Galla Stream D reference: payment-intent resolver for gateway Mode B (plan Section 27.B).
Pure, Decimal only. Design rule: the intent's state is a DERIVED value, a commutative fold over the set of
distinct provider events (deduplicated by event_id). Arrival order and duplicates therefore cannot change it.
The only order-dependent input is `bill`, the state of the bill when the money is applied (manual confirmation
by the cashier vs. provider success); that dependence is real and is handled by the duplicate-payment guard.
"""
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal as D
import hmac, hashlib

STATES = ("CREATED", "PENDING", "SUCCESS", "FAILED", "EXPIRED")
# allowed state-machine edges (what the database row may do over time)
EDGES = {
    "CREATED": {"PENDING", "SUCCESS", "FAILED", "EXPIRED"},
    "PENDING": {"SUCCESS", "FAILED", "EXPIRED"},
    "FAILED": {"SUCCESS"},      # provider-specific: a retry on the same QR before expiry (design rule, see 27.B.4)
    "EXPIRED": {"SUCCESS"},     # only for an in-time payment whose event arrived late
    "SUCCESS": set(),           # terminal
}
ATTENTION_PRIORITY = ("DUPLICATE_PAYMENT", "BILL_NOT_PAYABLE", "AMOUNT_MISMATCH", "LATE_SUCCESS")  # highest first

def can_transition(a, b): return a == b or b in EDGES[a]

@dataclass(frozen=True)
class Event:
    event_id: str
    kind: str                 # SUCCESS | FAILED | OTHER | EXPIRE_TICK (our own timer, event_id "tick")
    amount: D | None = None
    occurred_at: datetime | None = None

@dataclass(frozen=True)
class Intent:
    amount: D                 # locked at creation
    expires_at: datetime
    pending_marked: bool = False   # QR shown / provider acknowledged creation

@dataclass(frozen=True)
class BillCtx:
    status: str = "GENERATED"      # GENERATED | PAID | VOID, at the time the success is applied
    remaining: D | None = None     # remaining balance; None = equals intent.amount

@dataclass
class Result:
    status: str
    attention: str | None
    received_amount: D | None
    apply_to_bill: bool            # True => create SUCCESS payment + bill-paid logic
    outcomes: dict = field(default_factory=dict)   # event_id -> outcome label

def _in_time(ev, it): return ev.occurred_at is not None and ev.occurred_at <= it.expires_at

def resolve(intent: Intent, events, bill: BillCtx = BillCtx()) -> Result:
    uniq = {}
    for e in events: uniq.setdefault(e.event_id, e)         # duplicate event ids are no-ops
    evs = [uniq[k] for k in sorted(uniq)]                   # deterministic evaluation order
    succ = [e for e in evs if e.kind == "SUCCESS"]
    exact = [e for e in succ if e.amount == intent.amount]
    wrong = [e for e in succ if e.amount != intent.amount]
    exact_in_time = [e for e in exact if _in_time(e, intent)]
    exact_late = [e for e in exact if not _in_time(e, intent)]
    failed = any(e.kind == "FAILED" for e in evs)
    ticked = any(e.kind == "EXPIRE_TICK" for e in evs)
    remaining = intent.amount if bill.remaining is None else bill.remaining
    out = {e.event_id: "IGNORED" for e in evs}
    attention = None
    received = None
    apply = False
    payable = bill.status == "GENERATED" and remaining >= intent.amount
    # which exact success is "the" one: earliest in-time (ties broken by event_id), else none
    chosen = None
    if exact_in_time:
        chosen = min(exact_in_time, key=lambda e: (e.occurred_at, e.event_id))
    if chosen is not None:
        received = intent.amount
        if payable:
            status, apply = "SUCCESS", True
            out[chosen.event_id] = "APPLIED"
        else:
            status = "SUCCESS"      # the money really arrived in time: intent is SUCCESS, the bill is NOT touched
            out[chosen.event_id] = "BILL_NOT_PAYABLE" if bill.status == "VOID" else "DUPLICATE_PAYMENT"
            attention = "BILL_NOT_PAYABLE" if bill.status == "VOID" else "DUPLICATE_PAYMENT"
        extra = [e for e in exact if e is not chosen]
        for e in extra: out[e.event_id] = "DUPLICATE_PAYMENT"
        if extra: attention = "DUPLICATE_PAYMENT"          # money arrived more than once
        for e in wrong: out[e.event_id] = "AMOUNT_MISMATCH"
        return Result(status, attention, received, apply, out)
    # no valid in-time success
    if failed: status = "FAILED"
    elif ticked or any(True for _ in exact_late): status = "EXPIRED"
    elif intent.pending_marked: status = "PENDING"
    else: status = "CREATED"
    if exact_late:
        attention = "LATE_SUCCESS"; received = exact_late[0].amount
        for e in exact_late: out[e.event_id] = "LATE_SUCCESS"
        if len(exact_late) > 1: attention = "DUPLICATE_PAYMENT"
    if wrong:
        for e in wrong: out[e.event_id] = "AMOUNT_MISMATCH"
        if attention is None: attention = "AMOUNT_MISMATCH"
        if received is None: received = min(e.amount for e in wrong) if all(e.amount is not None for e in wrong) else None
    for e in evs:
        if e.kind == "FAILED": out[e.event_id] = "FAILED_RECORDED"
    if attention:
        attention = next(a for a in ATTENTION_PRIORITY if a == attention)
    return Result(status, attention, received, False, out)

# ---------------------------------------------------------------- manual confirmation vs provider (Section 5.9 guard)
def manual_confirm_allowed(intent_status: str, bill: BillCtx, intent_amount: D, manual_amount: D):
    """The cashier presses 'Payment received' on a bill that has a live intent.
    Returns (allowed, action_on_intent). The live intent is closed first (EXPIRED, superseded) so that two live
    QR codes can never both complete; a provider success that still arrives later is then flagged, not applied."""
    if bill.status != "GENERATED": return (False, None)
    remaining = intent_amount if bill.remaining is None else bill.remaining
    if manual_amount > remaining: return (False, None)
    return (True, "EXPIRE_INTENT" if intent_status in ("CREATED", "PENDING") else None)

# ---------------------------------------------------------------- webhook signature (generic HMAC-SHA256 helper)
def verify_hmac_sha256_hex(secret: bytes, raw_body: bytes, signature_hex: str) -> bool:
    """Generic helper. A real provider defines its own scheme (header name, encoding, what is signed);
    that comes from the provider's documentation. Always constant-time compare, always over the RAW bytes."""
    want = hmac.new(secret, raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(want, (signature_hex or "").lower())

# ---------------------------------------------------------------- settlement matching
def match_settlement_lines(lines, intents_by_txn):
    """lines: [(txn_id, amount)]; intents_by_txn: {txn_id: (intent_id, amount, intent_status)}.
    Returns [(txn_id, status, intent_id)] with status MATCHED | AMOUNT_DIFF | UNMATCHED. Pure lookup, no interpretation."""
    out = []
    for txn, amt in lines:
        hit = intents_by_txn.get(txn)
        if hit is None: out.append((txn, "UNMATCHED", None))
        elif hit[1] == amt and hit[2] == "SUCCESS": out.append((txn, "MATCHED", hit[0]))
        else: out.append((txn, "AMOUNT_DIFF", hit[0]))
    return out
def settlement_check(gross: D, fee: D, net: D): return gross - fee == net
