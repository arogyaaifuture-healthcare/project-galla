"""Section 25.10 credit notes: refund by bill line + quantity, tax reversed proportionally from the ORIGINAL line's stored amounts."""
from decimal import Decimal as D, ROUND_HALF_UP, ROUND_FLOOR
from bill_calculator import allocate, to_cents, from_cents, r2
Z = D("0.00")

def refund_line(orig, refunded_so_far, qty):
    """orig: dict(qty, gross, discount, taxable, tax, total, comps=[(name, rate, taxable, tax)]) = the bill_line as stored.
    refunded_so_far: dict(qty, gross, taxable, tax, total, comps=[tax per comp]) of earlier credit notes (zeros if none).
    The refund that takes the LAST remaining quantity gets exactly what is left (so a full refund equals the original to the paisa);
    a partial refund is proportional: x = r2(orig_x * qty / orig_qty), clamped to what is left, and component taxes are split by
    largest remainder over the original component taxes so that sum(components) == tax exactly."""
    qty = D(qty); Q = D(orig["qty"]); rem_q = Q - refunded_so_far["qty"]
    if qty <= 0: raise ValueError("VALIDATION_ERROR")
    if qty > rem_q: raise ValueError("REFUND_EXCEEDS_QUANTITY")
    left = lambda k: D(orig[k]) - refunded_so_far[k]
    if qty == rem_q:
        gross, taxable, tax = left("gross"), left("taxable"), left("tax")
        comp_tax = [from_cents(to_cents(c[3])) - rt for c, rt in zip(orig["comps"], refunded_so_far["comps"])]
    else:
        f = qty / Q
        gross = min(r2(D(orig["gross"]) * f), left("gross"))
        taxable = min(r2(D(orig["taxable"]) * f), left("taxable"))
        tax = min(r2(D(orig["tax"]) * f), left("tax"))
        w = [to_cents(c[3]) for c in orig["comps"]]
        parts = allocate(to_cents(tax), w) if sum(w) else [0] * len(w)
        comp_tax = [from_cents(p) for p in parts]
        # a component may not exceed what is left of it; push any excess to a component that still has room (stays deterministic)
        room = [D(c[3]) - rt - ct for c, rt, ct in zip(orig["comps"], refunded_so_far["comps"], comp_tax)]
        for i in range(len(comp_tax)):
            if room[i] < 0:
                ex = -room[i]; comp_tax[i] -= ex; room[i] = Z
                for j in range(len(comp_tax)):
                    if j != i and room[j] > 0:
                        mv = min(ex, room[j]); comp_tax[j] += mv; room[j] -= mv; ex -= mv
                        if ex == 0: break
    assert sum(comp_tax, Z) == tax, "component taxes must add up"
    return dict(qty=qty, gross=gross, discount=gross - taxable if gross >= taxable else Z, taxable=taxable, tax=tax, total=taxable + tax, comp_tax=comp_tax)

def credit_note_total(refund_lines, *, bill_grand_total, refunded_grand_so_far, bill_total_before_round_off, refunded_before_round_so_far, round_off_mode="NEAREST_1"):
    """Credit note header amounts. If this note completes the bill (cumulative pre-round-off refunds == bill total_before_round_off) it hands back
    exactly what is left of the bill's grand total (so the round-off paisa the bill had is returned too). Otherwise the note is rounded DOWN to a
    whole rupee (never over-refunds; the remainder returns with the final note). Decision 38 documents this. A note that would be 0 is refused."""
    tb = sum((r["total"] for r in refund_lines), Z)
    complete = refunded_before_round_so_far + tb == bill_total_before_round_off
    if complete: gt = bill_grand_total - refunded_grand_so_far
    elif round_off_mode == "NONE": gt = tb
    else: gt = tb.quantize(D("1"), rounding=ROUND_FLOOR).quantize(D("0.01"))
    if gt <= 0: raise ValueError("REFUND_TOO_SMALL")
    if refunded_grand_so_far + gt > bill_grand_total: raise ValueError("REFUND_EXCEEDS_BILL_TOTAL")
    return dict(total_before_round_off=tb, round_off=gt - tb, grand_total=gt, complete=complete)

def zero_state(n_comps): return dict(qty=D(0), gross=Z, taxable=Z, tax=Z, total=Z, comps=[Z] * n_comps)
def add_state(st, r):
    return dict(qty=st["qty"] + r["qty"], gross=st["gross"] + r["gross"], taxable=st["taxable"] + r["taxable"], tax=st["tax"] + r["tax"],
                total=st["total"] + r["total"], comps=[a + b for a, b in zip(st["comps"], r["comp_tax"])])

def refund_destination(method, customer_id=None):
    """Where the money goes. ON_ACCOUNT reduces the customer's balance (ledger CREDIT_NOTE entry, negative amount); it needs a customer
    (DB: credit_notes CHECK). 'Original method' is chosen by the UI from the bill's payments; for UPI/CARD the actual money movement is manual
    in v1 (no provider refund API call) and the reference is typed by the cashier."""
    if method not in ("CASH", "CARD", "UPI", "OTHER", "ON_ACCOUNT"): raise ValueError("VALIDATION_ERROR")
    if method == "ON_ACCOUNT" and customer_id is None: raise ValueError("CUSTOMER_REQUIRED")
    return "LEDGER" if method == "ON_ACCOUNT" else ("DRAWER" if method == "CASH" else "MANUAL")
