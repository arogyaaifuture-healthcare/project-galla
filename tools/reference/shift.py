"""Section 25.8 cashier shift: expected drawer cash and variance. All Decimal."""
from decimal import Decimal as D
Z = D("0.00")
def expected_cash(opening_float, *, cash_payments=Z, cash_refunds=Z, pay_ins=Z, pay_outs=Z, drops=Z, cash_tips=Z, cash_credit_settlements=Z):
    """expected = opening + cash payments APPLIED to bills (change already returned, so tendered-change) - cash refunds
    + pay-ins - pay-outs - drops. Two additions the brief did not list, both physically in the drawer:
    cash_tips (tip paid in cash with a cash payment; a later hand-out to staff is recorded as a PAY_OUT with reason TIP_PAYOUT)
    and cash_credit_settlements (customer pays a due in cash, ledger PAYMENT with shift_id)."""
    for v in (opening_float, cash_payments, cash_refunds, pay_ins, pay_outs, drops, cash_tips, cash_credit_settlements):
        if v < 0: raise ValueError("VALIDATION_ERROR")
    return D(opening_float) + cash_payments + cash_tips + cash_credit_settlements + pay_ins - cash_refunds - pay_outs - drops
def variance(counted, expected): return D(counted) - D(expected)       # > 0 over, < 0 short
def close(shift, counted):
    if shift["status"] != "OPEN": raise ValueError("SHIFT_NOT_OPEN")
    e = expected_cash(shift["opening_float"], **shift.get("flows", {}))
    return dict(shift, status="CLOSED", counted_cash=D(counted), expected_cash=e, variance=variance(counted, e))
def can_open(open_shifts, cashier_id, device_id=None):
    """One open shift per cashier and per device (DB: partial unique indexes)."""
    for s in open_shifts:
        if s["cashier_id"] == cashier_id: return False, "SHIFT_ALREADY_OPEN_CASHIER"
        if device_id is not None and s.get("device_id") == device_id: return False, "SHIFT_ALREADY_OPEN_DEVICE"
    return True, None
def can_close_day(shifts): return all(s["status"] == "CLOSED" for s in shifts)       # DB: trigger OPEN_SHIFTS_EXIST
