"""Galla reference: loyalty points (Section 30.3). Decimal only; points are integers."""
from decimal import Decimal as D, ROUND_HALF_UP, ROUND_FLOOR

def earn_points(amount, spend_per_point):
    """1 point per `spend_per_point` rupees, floor. Negative/zero amounts earn nothing."""
    amount, spp = D(amount), D(spend_per_point)
    if amount <= 0: return 0
    return int((amount / spp).to_integral_value(rounding=ROUND_FLOOR))

def redemption_amount(points, rupees_per_point):
    return (D(points) * D(rupees_per_point)).quantize(D("0.01"), rounding=ROUND_HALF_UP)

def max_redeemable(bill_total, balance, rupees_per_point, max_percent, min_points):
    """Largest number of points that may be redeemed on this bill (0 = not allowed)."""
    bill_total, rpp = D(bill_total), D(rupees_per_point)
    if balance <= 0 or bill_total <= 0: return 0
    cap_amount = (bill_total * D(max_percent) / D(100))
    by_cap = int((cap_amount / rpp).to_integral_value(rounding=ROUND_FLOOR))
    pts = min(int(balance), by_cap)
    # never let rounding push the amount above the bill
    while pts > 0 and redemption_amount(pts, rpp) > bill_total: pts -= 1
    return pts if pts >= min_points and pts > 0 else 0

def reversal_for_refund(grand_total, refunded_cum, earned, reversed_so_far, spend_per_point):
    """Points to reverse now so that earned-minus-reversed equals what the remaining net amount would earn."""
    net = D(grand_total) - D(refunded_cum)
    target = earn_points(net, spend_per_point) if net > 0 else 0
    target = min(target, earned)
    return max(0, earned - reversed_so_far - target)

def restore_for_refund(redeemed_points, loyalty_paid, loyalty_refunded_cum, restored_so_far):
    """Points handed back when part of the loyalty-paid amount is refunded; a full refund restores exactly all."""
    paid, ref = D(loyalty_paid), D(loyalty_refunded_cum)
    if paid <= 0 or ref <= 0: return 0
    if ref >= paid: target = redeemed_points
    else: target = int((D(redeemed_points) * ref / paid).to_integral_value(rounding=ROUND_FLOOR))
    return max(0, target - restored_so_far)

def expiring_points(entries, now):
    """entries: list of (ts, entry_type, points, expires_at|None) in any order. FIFO: spending uses the batches that expire first
    (batches without an expiry last) and can never use a batch that was already expired at that moment. Returns the points that
    are expired at `now` and still unspent (the EXPIRE entry the daily job must write)."""
    batches = []   # [expires_at|None, remaining]
    for ts, typ, pts, exp in sorted(entries, key=lambda e: (e[0], 0 if e[2] > 0 else 1)):
        if pts > 0:
            batches.append([exp if typ == 'EARN' else None, pts])
        else:
            need = -pts
            live = [b for b in batches if b[1] > 0 and (b[0] is None or b[0] > ts)]
            live.sort(key=lambda b: (b[0] is None, b[0] if b[0] is not None else 0))
            for b in live:
                take = min(b[1], need); b[1] -= take; need -= take
                if need == 0: break
            # need > 0 left means the ledger spent more than the live balance: allowed only for REVERSE_EARN (balance may go negative)
    return sum(b[1] for b in batches if b[0] is not None and b[0] <= now and b[1] > 0)
