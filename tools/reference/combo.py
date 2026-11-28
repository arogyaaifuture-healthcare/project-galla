"""Section 25.2 combos: allocate a fixed combo price across component lines (largest remainder, sum == combo price exactly)."""
from decimal import Decimal as D
from bill_calculator import allocate, to_cents, from_cents, r2

def allocate_combo(combo_price, components):
    """components: list of dict(id, qty, list_price) (list_price = unit list price of the component, variant-aware).
    Returns {id: fixed_line_amount} - the amount for the WHOLE component line (qty included).
    Weights = component line list value in cents. If every weight is 0 (all components free on the list) the weights
    fall back to the quantities, so the combo price is still fully distributed. Deterministic: ties go to the lower index
    (components are first sorted by id, like the bill engine sorts lines)."""
    if not components: raise ValueError("COMBO_EMPTY")
    if combo_price < 0: raise ValueError("VALIDATION_ERROR")
    comps = sorted(components, key=lambda c: str(c["id"]))
    weights = [to_cents(r2(D(c["qty"]) * D(c["list_price"]))) for c in comps]
    if sum(weights) == 0: weights = [to_cents(D(c["qty"])) if D(c["qty"]) >= 1 else 1 for c in comps]
    parts = allocate(to_cents(combo_price), weights)
    return {c["id"]: from_cents(p) for c, p in zip(comps, parts)}

def to_calc_lines(combo_price, components):
    """Lines for bill_calculator.calculate(): each component is ONE line (qty 1) whose unit_price is the allocated whole-line amount,
    so r2(qty * unit_price) == fixed_line_amount exactly. The display quantity travels in 'name' / the order line, not in the maths."""
    amounts = allocate_combo(combo_price, components)
    out = []
    for c in sorted(components, key=lambda c: str(c["id"])):
        out.append(dict(id=c["id"], name=c.get("name", str(c["id"])), qty=D(1), unit_price=amounts[c["id"]], comps=list(c.get("comps", []))))
    return out

def consumption(combo_qty, components):
    """Stock interface for the inventory module (stream C): ordering N combos consumes N * quantity of every component item/variant."""
    return [(c["item_id"], c.get("variant_id"), D(combo_qty) * D(c["qty"])) for c in components]
