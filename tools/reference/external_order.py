"""Galla Stream D reference: aggregator inbox rules (plan Section 27.A). Provider-agnostic; no provider detail is assumed.
Pure functions: status machine, intake decision (mapping + auto-accept), SLA, idempotent receive, reconciliation."""
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal as D

STATUSES = ("RECEIVED","NEEDS_MAPPING","MAPPED","ACCEPTED","REJECTED","PREPARING","READY","HANDED_OVER","CANCELLED","EXPIRED")
TERMINAL = {"REJECTED","HANDED_OVER","CANCELLED","EXPIRED"}
EDGES = {
  "RECEIVED": {"NEEDS_MAPPING","MAPPED","REJECTED","CANCELLED","EXPIRED"},
  "NEEDS_MAPPING": {"MAPPED","REJECTED","CANCELLED","EXPIRED"},
  "MAPPED": {"ACCEPTED","REJECTED","CANCELLED","EXPIRED","NEEDS_MAPPING"},   # NEEDS_MAPPING again if a mapping is deleted
  "ACCEPTED": {"PREPARING","READY","CANCELLED"},
  "PREPARING": {"READY","CANCELLED"},
  "READY": {"HANDED_OVER","CANCELLED"},
  "REJECTED": set(), "HANDED_OVER": set(), "CANCELLED": set(), "EXPIRED": set(),
}
def can_transition(a, b): return b in EDGES[a]

@dataclass(frozen=True)
class Line:
    ext_item_id: str
    ext_variant_id: str = ""
    qty: int = 1
    price: D = D("0")

def classify_lines(lines, mappings):
    """mappings: {(item,variant): 'MAPPED'|'IGNORED'}. Returns (billable, ignored, unmapped)."""
    bill, ign, un = [], [], []
    for l in lines:
        m = mappings.get((l.ext_item_id, l.ext_variant_id))
        if m is None and l.ext_variant_id != "":
            m = None                       # a variant needs its own mapping row: no silent fallback to the base item
        (un if m is None else ign if m == "IGNORED" else bill).append(l)
    return bill, ign, un

def intake_decision(lines, mappings, *, auto_accept, store_open=True, now=None, accept_by=None):
    """What the server does right after a new order is stored. Unmapped lines ALWAYS block auto-accept.
    A closed store or a passed deadline never auto-accepts."""
    if not lines: return "NEEDS_MAPPING"              # nothing billable to build an order from: a human looks at it
    bill, ign, un = classify_lines(lines, mappings)
    if un: return "NEEDS_MAPPING"
    if not bill: return "NEEDS_MAPPING"
    if now is not None and accept_by is not None and now >= accept_by: return "EXPIRED"
    if auto_accept and store_open: return "AUTO_ACCEPT"
    return "MAPPED"

def accept_deadline(received_at, sla_seconds): return received_at + timedelta(seconds=sla_seconds)
def sla_state(now, accept_by, warn_seconds=60):
    left = (accept_by - now).total_seconds()
    return "EXPIRED" if left <= 0 else "WARN" if left <= warn_seconds else "OK"

class Inbox:
    """In-memory model of the idempotent inbox: unique (account, external_order_id)."""
    def __init__(self): self.rows = {}; self.events = set()
    def receive(self, account, ext_id, payload, now, sla):
        k = (account, ext_id)
        if k in self.rows: return "DUPLICATE_IGNORED"
        self.rows[k] = dict(status="RECEIVED", payload=payload, received_at=now, accept_by=accept_deadline(now, sla)); return "STORED"
    def event(self, account, ext_id, provider_event_id):
        k = (account, ext_id, provider_event_id)
        if k in self.events: return "DUPLICATE_IGNORED"
        self.events.add(k); return "STORED"
    def move(self, account, ext_id, to):
        r = self.rows[(account, ext_id)]
        if r["status"] == to: return "NO_CHANGE"
        if not can_transition(r["status"], to): raise ValueError(f"ILLEGAL {r['status']}->{to}")
        r["status"] = to; return "MOVED"

def cancel_effect(status):
    """What a provider cancel does. Food already prepared is a human decision; never silently deleted."""
    if status in ("RECEIVED","NEEDS_MAPPING","MAPPED"): return "CANCEL_INBOX_ONLY"
    if status in ("ACCEPTED","PREPARING","READY"): return "CANCEL_ORDER_AND_ALERT_KITCHEN"   # internal order cancelled by rule, kitchen alerted, manager sees it
    return "IGNORE"

def price_diff(menu_total: D, provider_total: D | None):
    """Informational only. The bill uses Galla's menu prices; the provider's figure is stored as reported."""
    if provider_total is None: return None
    return provider_total - menu_total

def reconcile(orders, payouts):
    """orders: [(status, settlement_amount|None)], payouts: [amount_received]. No interpretation of commission:
    expected = sum of typed/reported settlement amounts of HANDED_OVER orders; difference = received - expected."""
    exp = sum((s for st, s in orders if st == "HANDED_OVER" and s is not None), D("0.00"))
    missing = sum(1 for st, s in orders if st == "HANDED_OVER" and s is None)
    rec = sum(payouts, D("0.00"))
    return dict(expected=exp, received=rec, difference=rec - exp, orders_without_settlement_amount=missing)
