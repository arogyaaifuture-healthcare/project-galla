"""Section 25.9 customer credit (dues): append-only ledger, limit check, FIFO aging. positive amount = customer owes."""
from datetime import date
from decimal import Decimal as D
Z = D("0.00")
def balance(entries): return sum((e["amount"] for e in entries), Z)
def can_charge(limit, current_balance, amount, *, manager_override=False):
    """A new ON_ACCOUNT charge is allowed while balance + amount <= limit (equal to the limit is allowed). limit 0 = credit disabled
    for this customer (only a manager override passes). The override is logged in the audit trail with the reason."""
    if amount <= 0: raise ValueError("VALIDATION_ERROR")
    if current_balance + amount <= D(limit): return True, None
    return (True, "OVERRIDE") if manager_override else (False, "CREDIT_LIMIT_EXCEEDED")
def charge(bill_id, amount, on): return dict(entry_type="CHARGE", amount=D(amount), bill_id=bill_id, business_date=on)
def payment(amount, on, method="CASH"): return dict(entry_type="PAYMENT", amount=-D(amount), method=method, business_date=on)
def credit_note(amount, on): return dict(entry_type="CREDIT_NOTE", amount=-D(amount), business_date=on)
def adjustment(amount, on, reason):
    if len(reason.strip()) < 5: raise ValueError("REASON_REQUIRED")
    return dict(entry_type="ADJUSTMENT", amount=D(amount), reason=reason, business_date=on)
def settle_all(entries, on, method="CASH"):
    b = balance(entries)
    return entries + [payment(b, on, method)] if b > 0 else entries
def aging(entries, as_of, buckets=(30, 60, 90)):
    """FIFO: every credit (PAYMENT / CREDIT_NOTE / negative ADJUSTMENT) is applied to the OLDEST open charge first. What is left of each charge
    is bucketed by days since the charge: 0-30, 31-60, 61-90, 90+. Sum of buckets == max(balance, 0); surplus credit is reported as 'advance'."""
    es = sorted(entries, key=lambda e: e["business_date"])        # stable: same-day order kept
    open_ = []; advance = Z
    for e in es:
        a = e["amount"]
        if a > 0: open_.append([e["business_date"], a])
        else:
            c = -a
            for o in open_:
                if c == 0: break
                t = min(o[1], c); o[1] -= t; c -= t
            advance += c
    out = {f"0-{buckets[0]}": Z, f"{buckets[0]+1}-{buckets[1]}": Z, f"{buckets[1]+1}-{buckets[2]}": Z, f"{buckets[2]}+": Z}
    keys = list(out)
    for d, r in open_:
        if r == 0: continue
        age = (as_of - d).days
        i = 0 if age <= buckets[0] else 1 if age <= buckets[1] else 2 if age <= buckets[2] else 3
        out[keys[i]] += r
    return out, advance
