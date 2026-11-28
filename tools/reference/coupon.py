"""Section 25.3 coupons: validation with a reason code for every failure + discount amount (cap BEFORE allocation)."""
from datetime import datetime
from decimal import Decimal as D
from bill_calculator import r2

REASONS = ("COUPON_NOT_FOUND","COUPON_INACTIVE","COUPON_NOT_YET_VALID","COUPON_EXPIRED","COUPON_WRONG_OUTLET","COUPON_WEEKDAY",
           "COUPON_ORDER_TYPE","COUPON_MIN_BILL","COUPON_LIMIT_TOTAL","COUPON_LIMIT_DAY","COUPON_LIMIT_CUSTOMER",
           "COUPON_CUSTOMER_REQUIRED","COUPON_NOT_STACKABLE","COUPON_NC_BILL","COUPON_NO_DISCOUNT")

def find(coupons, code):
    """Codes are unique per tenant, case-insensitive (DB: unique index on lower(code))."""
    c = code.strip().lower()
    for x in coupons:
        if x["code"].lower() == c: return x
    return None

def discount_amount(coupon, eligible_subtotal):
    """PERCENT: r2(subtotal * value/100), capped by max_discount. AMOUNT: value. Always capped by the subtotal.
    The result is passed to the bill engine as a flat bill-level discount, so the engine allocates it over lines (largest remainder)."""
    sub = D(eligible_subtotal)
    if coupon["discount_type"] == "PERCENT": d = r2(sub * D(coupon["value"]) / 100)
    else: d = D(coupon["value"])
    if coupon.get("max_discount") is not None: d = min(d, D(coupon["max_discount"]))
    return min(d, sub)

def validate(coupon, *, now_local, outlet_id, order_type, subtotal, customer_id=None, manual_discount=False,
             is_nc=False, active_total=0, active_today=0, active_for_customer=0):
    """Returns (ok, reason). now_local: outlet-local datetime (weekday is the outlet-local ISO weekday).
    active_* = counts of ACTIVE (not RELEASED) redemptions, i.e. a voided / fully refunded bill has given its use back."""
    if coupon is None: return False, "COUPON_NOT_FOUND"
    if not coupon.get("active", True): return False, "COUPON_INACTIVE"
    if is_nc: return False, "COUPON_NC_BILL"
    if manual_discount: return False, "COUPON_NOT_STACKABLE"            # v1: one discount per bill (manual OR coupon)
    if coupon.get("outlet_id") not in (None, outlet_id): return False, "COUPON_WRONG_OUTLET"
    if coupon.get("valid_from") and now_local < coupon["valid_from"]: return False, "COUPON_NOT_YET_VALID"
    if coupon.get("valid_to") and now_local >= coupon["valid_to"]: return False, "COUPON_EXPIRED"      # valid_to is exclusive
    if now_local.isoweekday() not in coupon.get("weekdays", (1,2,3,4,5,6,7)): return False, "COUPON_WEEKDAY"
    if order_type not in coupon.get("order_types", ("DINE_IN","TAKEAWAY","DELIVERY")): return False, "COUPON_ORDER_TYPE"
    if D(subtotal) < D(coupon.get("min_bill", 0)): return False, "COUPON_MIN_BILL"
    if coupon.get("usage_limit_per_customer") is not None and customer_id is None: return False, "COUPON_CUSTOMER_REQUIRED"
    if coupon.get("usage_limit_total") is not None and active_total >= coupon["usage_limit_total"]: return False, "COUPON_LIMIT_TOTAL"
    if coupon.get("usage_limit_per_day") is not None and active_today >= coupon["usage_limit_per_day"]: return False, "COUPON_LIMIT_DAY"
    if coupon.get("usage_limit_per_customer") is not None and active_for_customer >= coupon["usage_limit_per_customer"]: return False, "COUPON_LIMIT_CUSTOMER"
    if discount_amount(coupon, subtotal) <= 0: return False, "COUPON_NO_DISCOUNT"
    return True, None

def apply(coupon, lines, **ctx):
    """Validate, then run the shared engine with the coupon amount as the bill-level discount. Returns (result, reason)."""
    from bill_calculator import calculate
    subtotal = sum((r2(l["qty"] * l["unit_price"]) for l in lines), D("0.00"))
    ok, reason = validate(coupon, subtotal=subtotal, **{k: v for k, v in ctx.items() if k not in ("prices_include_tax","calc")})
    if not ok: return None, reason
    d = discount_amount(coupon, subtotal)
    return calculate(lines, prices_include_tax=ctx["prices_include_tax"], discount=("AMOUNT", d), **ctx.get("calc", {})), None
