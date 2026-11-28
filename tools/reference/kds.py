"""Section 25.12 kitchen display: status machine (identical to DB trigger fn_order_items_kitchen_transition) and SLA colours."""
from datetime import datetime
STATES = ("NEW", "PREPARING", "READY", "SERVED")
ALLOWED = {("NEW","PREPARING"),("NEW","READY"),("PREPARING","READY"),("READY","SERVED"),   # forward (NEW->READY = quick bump)
           ("PREPARING","NEW"),("READY","PREPARING"),("SERVED","READY")}                   # recall: one step back
def can_move(old, new): return old == new or (old, new) in ALLOWED
def move(old, new):
    if not can_move(old, new): raise ValueError(f"ILLEGAL_KITCHEN_TRANSITION {old} -> {new}")
    return new
def bump(state):
    """The bump button: one step forward; SERVED stays."""
    return {"NEW": "PREPARING", "PREPARING": "READY", "READY": "SERVED", "SERVED": "SERVED"}[state]
def recall(state):
    return {"NEW": "NEW", "PREPARING": "NEW", "READY": "PREPARING", "SERVED": "READY"}[state]
def sla_colour(state, sent_at, now, warn_min, late_min):
    """Timer runs from KOT print time until READY. GREEN < warn <= AMBER < late <= RED. READY/SERVED tickets show no timer (GREY)."""
    if not warn_min < late_min: raise ValueError("VALIDATION_ERROR")
    if state in ("READY", "SERVED"): return "GREY"
    m = (now - sent_at).total_seconds() / 60
    return "GREEN" if m < warn_min else ("AMBER" if m < late_min else "RED")
def expo_ready(item_states):
    """Expo screen: an order is 'ready to run' when every active item is READY or SERVED and at least one is READY (not yet served)."""
    active = [s for s in item_states]
    return bool(active) and all(s in ("READY", "SERVED") for s in active) and any(s == "READY" for s in active)
