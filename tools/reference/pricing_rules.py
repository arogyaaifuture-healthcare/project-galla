"""Section 25.4 time-based pricing. Resolved at line-add time; the result is SNAPSHOTTED on the order line (price_source, price_rule_id)."""
from datetime import datetime, time, timedelta, date
from decimal import Decimal as D
from bill_calculator import r2

SPEC = {"VARIANT": 3, "ITEM": 2, "CATEGORY": 1}

def window_start_date(now_local, start, end):
    """If the window crosses midnight (end < start) and `now` is in the after-midnight part, the window STARTED yesterday.
    Returns the calendar date on which the matching window started, or None if `now` is outside the window."""
    t = now_local.time(); d = now_local.date()
    if start < end:
        return d if start <= t < end else None
    if t >= start: return d                       # evening part: started today
    if t < end: return d - timedelta(days=1)      # after-midnight part: started yesterday
    return None

def matches(rule, now_local, order_type, item_id, variant_id, category_id):
    if not rule.get("active", True): return False
    s = rule["scope_type"]
    if s == "ITEM" and rule["menu_item_id"] != item_id: return False
    if s == "VARIANT" and rule["variant_id"] != variant_id: return False
    if s == "CATEGORY" and rule["category_id"] != category_id: return False
    if order_type not in rule.get("order_types", ("DINE_IN","TAKEAWAY","DELIVERY")): return False
    sd = window_start_date(now_local, rule["start_time"], rule["end_time"])
    if sd is None: return False
    if sd.isoweekday() not in rule.get("weekdays", (1,2,3,4,5,6,7)): return False      # weekday of the window's START day
    if rule.get("valid_from") and sd < rule["valid_from"]: return False                 # dates also refer to the start day
    if rule.get("valid_to") and sd > rule["valid_to"]: return False
    return True

def rule_price(rule, base_price):
    if rule["action"] == "PRICE_OVERRIDE": return r2(D(rule["price"]))
    return r2(D(base_price) * (100 - D(rule["percent_off"])) / 100)

def resolve(rules, *, now_local, order_type, item_id, variant_id, category_id, base_price):
    """Pick ONE rule (no stacking): highest priority; tie -> more specific scope (VARIANT > ITEM > CATEGORY);
    tie -> lower resulting price (customer-friendly, deterministic); tie -> lower rule id.
    Returns dict(price, source, rule_id, rule_name, list_price)."""
    cands = [r for r in rules if matches(r, now_local, order_type, item_id, variant_id, category_id)]
    base = r2(D(base_price))
    if not cands: return dict(price=base, source="LIST", rule_id=None, rule_name=None, list_price=base)
    best = min(cands, key=lambda r: (-r["priority"], -SPEC[r["scope_type"]], rule_price(r, base), str(r["id"])))
    return dict(price=rule_price(best, base), source="PRICE_RULE", rule_id=best["id"], rule_name=best["name"], list_price=base)
