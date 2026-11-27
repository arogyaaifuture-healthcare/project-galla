"""Galla reference implementation of billing rules (plan Section 5.3). Decimal only, pure."""
from decimal import Decimal as D, ROUND_HALF_UP, ROUND_FLOOR
CENT = D("0.01")
def r2(x): return x.quantize(CENT, rounding=ROUND_HALF_UP)
def to_cents(x): return int((x * 100).to_integral_value())
def from_cents(c): return (D(c) / 100).quantize(CENT)

def allocate(total_cents, weights):
    wsum = sum(weights)
    if wsum == 0 or total_cents == 0: return [0] * len(weights)
    exact = [D(total_cents) * D(w) / D(wsum) for w in weights]
    floors = [int(e.to_integral_value(rounding=ROUND_FLOOR)) for e in exact]
    rest = total_cents - sum(floors)
    order = sorted(range(len(weights)), key=lambda i: (-(exact[i] - floors[i]), i))
    for i in order[:rest]: floors[i] += 1
    return floors

def split_tax_by_rate(tax_cents, rates):
    if sum(rates) == 0: return [0] * len(rates)
    return allocate(tax_cents, [int((r * 100).to_integral_value()) for r in rates])

def _tax_line(net, comps, inclusive):
    if not comps: return net, D("0.00"), [], net
    total_rate = sum(r for _, r in comps)
    if not inclusive:
        taxes = [r2(net * r / 100) for _, r in comps]
        t = sum(taxes, D("0.00"))
        return net, t, [(n, r, tx) for (n, r), tx in zip(comps, taxes)], net + t
    if total_rate == 0: return net, D("0.00"), [(n, r, D("0.00")) for n, r in comps], net
    taxable = r2(net * 100 / (100 + total_rate))
    tax = net - taxable
    parts = split_tax_by_rate(to_cents(tax), [r for _, r in comps])
    return taxable, tax, [(n, r, from_cents(p)) for (n, r), p in zip(comps, parts)], net

def calculate(lines, *, prices_include_tax, round_off_mode="NEAREST_1", discount=None,
              service_charge_percent=D("0"), service_charge_comps=(), delivery_charge=D("0"), delivery_comps=(),
              extra_charges=()):
    # extra_charges: iterable of dict(type="PACKAGING_CHARGE", name=str, amount=Decimal, comps=[(name, rate)]).
    # Like the delivery charge they are NOT discounted, NOT in the service-charge base, taxed by their own components.
    # CANONICAL ORDER: sort by line id (order_item UUID) so tie-breaks never depend on input order
    lines = sorted(lines, key=lambda l: str(l.get("id", "")))
    gross = [r2(l["qty"] * l["unit_price"]) for l in lines]
    subtotal = sum(gross, D("0.00"))
    if discount is None: disc_total = D("0.00")
    else:
        kind, val = discount
        if kind == "PERCENT":
            if not (D("0") < val <= D("100")): raise ValueError("VALIDATION_ERROR")
            disc_total = r2(subtotal * val / 100)
        else:
            if val <= 0: raise ValueError("VALIDATION_ERROR")
            if val > subtotal: raise ValueError("DISCOUNT_EXCEEDS_SUBTOTAL")
            disc_total = val
    alloc = allocate(to_cents(disc_total), [to_cents(g) for g in gross])
    out = []
    for l, g, dc in zip(lines, gross, alloc):
        d = from_cents(dc); net = g - d
        taxable, tax, comps, total = _tax_line(net, l.get("comps", []), prices_include_tax)
        out.append(dict(type="ITEM", name=l["name"], qty=l["qty"], unit_price=l["unit_price"], gross=g,
                        discount=d, taxable=taxable, tax=tax, comps=comps, total=total))
    if service_charge_percent > 0:
        sc = r2((subtotal - disc_total) * service_charge_percent / 100)
        if sc > 0:
            taxable, tax, comps, total = _tax_line(sc, list(service_charge_comps), prices_include_tax)
            out.append(dict(type="SERVICE_CHARGE", name="Service charge", qty=D(1), unit_price=sc, gross=sc,
                            discount=D("0.00"), taxable=taxable, tax=tax, comps=comps, total=total))
    if delivery_charge > 0:
        taxable, tax, comps, total = _tax_line(delivery_charge, list(delivery_comps), prices_include_tax)
        out.append(dict(type="DELIVERY_CHARGE", name="Delivery charge", qty=D(1), unit_price=delivery_charge,
                        gross=delivery_charge, discount=D("0.00"), taxable=taxable, tax=tax, comps=comps, total=total))
    for ec in sorted(extra_charges, key=lambda e: (e["type"], e["name"])):
        amt = ec["amount"]
        if amt <= 0: continue
        taxable, tax, comps, total = _tax_line(amt, list(ec.get("comps", [])), prices_include_tax)
        out.append(dict(type=ec["type"], name=ec["name"], qty=D(1), unit_price=amt, gross=amt,
                        discount=D("0.00"), taxable=taxable, tax=tax, comps=comps, total=total))
    tax_total = sum((o["tax"] for o in out), D("0.00"))
    before = sum((o["total"] for o in out), D("0.00"))
    grand = before if round_off_mode == "NONE" else before.quantize(D("1"), rounding=ROUND_HALF_UP).quantize(CENT)
    return dict(subtotal=subtotal, discount_total=disc_total, tax_total=tax_total,
                total_before_round_off=before, round_off=grand - before, grand_total=grand, lines=out)
