"""Galla Stream D reference: register definitions (plan Section 28.B). Python mirror of the SQL in the plan; used to prove that
every register reconciles exactly to the bill totals. Decimal only. Bills are dicts built from bill_calculator.calculate()."""
from decimal import Decimal as D
from collections import defaultdict
Z = D("0.00")
SALES_COLUMNS = ["business_date","bill_number","document_title","status","customer_name","buyer_gstin","place_of_supply_state_code",
                 "gross_items","discount_total","taxable_value","tax_total","round_off","grand_total"]
BY_RATE_COLUMNS = ["bill_number","rate_percent","taxable_value","tax_amount","line_total"]
HSN_COLUMNS = ["hsn_sac_code","rate_percent","quantity","taxable_value","tax_amount","line_total","lines_without_hsn_flag"]
TAX_COLUMNS = ["component_name","rate_percent","taxable_value","tax_amount"]
PAYMODE_COLUMNS = ["method","payments","amount"]

def make_bill(calc, number, date, hsn_by_name=None, status="PAID", methods=None, **kw):
    """methods: list of (method, fraction-of-grand-total as Decimal); the last one takes the remainder."""
    hsn_by_name = hsn_by_name or {}
    lines = []
    for l in calc["lines"]:
        lines.append(dict(type=l["type"], name=l["name"], qty=l["qty"] if l["type"] == "ITEM" else D(1), hsn=hsn_by_name.get(l["name"]),
                          gross=l["gross"], discount=l["discount"], taxable=l["taxable"], tax=l["tax"], total=l["total"],
                          comps=[dict(name=n, rate=r, tax=t) for n, r, t in l["comps"]]))
    pays = []
    if status in ("PAID",) and calc["grand_total"] > 0:
        rest = calc["grand_total"]; ms = methods or [("CASH", D(1))]
        for i, (m, f) in enumerate(ms):
            amt = rest if i == len(ms) - 1 else (calc["grand_total"] * f).quantize(D("0.01"))
            if amt > 0: pays.append((m, amt)); rest -= amt
    return dict(number=number, date=date, status=status, document_title=kw.get("document_title", "BILL"), customer_name=kw.get("customer_name"),
                buyer_gstin=kw.get("buyer_gstin"), pos=kw.get("pos"), lines=lines, discount_total=calc["discount_total"], tax_total=calc["tax_total"],
                round_off=calc["round_off"], grand_total=calc["grand_total"], payments=pays)

def line_rate(l): return sum((c["rate"] for c in l["comps"]), D("0.00"))
def live(bills): return [b for b in bills if b["status"] != "VOID"]

def sales_register(bills):
    rows = []
    for b in sorted(live(bills), key=lambda b: (b["date"], b["number"])):
        gi = sum((l["gross"] for l in b["lines"] if l["type"] == "ITEM"), Z)
        tv = sum((l["taxable"] for l in b["lines"]), Z)
        rows.append([b["date"], b["number"], b["document_title"], b["status"], b["customer_name"], b["buyer_gstin"], b["pos"],
                     gi, b["discount_total"], tv, b["tax_total"], b["round_off"], b["grand_total"]])
    return rows

def sales_by_rate(bills):
    acc = defaultdict(lambda: [Z, Z, Z])
    for b in live(bills):
        for l in b["lines"]:
            a = acc[(b["number"], line_rate(l))]; a[0] += l["taxable"]; a[1] += l["tax"]; a[2] += l["total"]
    return [[n, r, *v] for (n, r), v in sorted(acc.items())]

def hsn_summary(bills):
    acc = defaultdict(lambda: [D(0), Z, Z, Z, 0])
    for b in live(bills):
        for l in b["lines"]:
            k = (l["hsn"] or "", line_rate(l)); a = acc[k]
            a[0] += l["qty"] if l["type"] == "ITEM" else D(0); a[1] += l["taxable"]; a[2] += l["tax"]; a[3] += l["total"]
            a[4] += 0 if l["hsn"] else 1
    return [[h, r, *v[:4], v[4] > 0] for (h, r), v in sorted(acc.items())]

def tax_summary(bills):
    acc = defaultdict(lambda: [Z, Z])
    for b in live(bills):
        for l in b["lines"]:
            for c in l["comps"]:
                a = acc[(c["name"], c["rate"])]; a[0] += l["taxable"]; a[1] += c["tax"]
    return [[n, r, *v] for (n, r), v in sorted(acc.items())]

def payment_mode_summary(bills):
    acc = defaultdict(lambda: [0, Z])
    for b in live(bills):
        for m, a in b["payments"]: acc[m][0] += 1; acc[m][1] += a
    return [[m, *v] for m, v in sorted(acc.items())]

def reconcile(bills):
    """Returns a dict of differences; every value must be exactly 0.00."""
    sr = sales_register(bills); lv = live(bills)
    br = sales_by_rate(bills); hs = hsn_summary(bills); ts = tax_summary(bills)
    ok = lambda x: x
    tot = lambda rows, i: sum((r[i] for r in rows), Z)
    out = {}
    out["per_bill_identity"] = sum((abs(r[9] + r[10] + r[11] - r[12]) for r in sr), Z)         # taxable+tax+round_off-grand, per bill
    out["sales_vs_bills_grand"] = tot(sr, 12) - sum((b["grand_total"] for b in lv), Z)
    out["by_rate_taxable_vs_sales"] = tot(br, 2) - tot(sr, 9)
    out["by_rate_tax_vs_sales"] = tot(br, 3) - tot(sr, 10)
    out["by_rate_total_plus_roundoff_vs_grand"] = tot(br, 4) + tot(sr, 11) - tot(sr, 12)
    out["hsn_taxable_vs_sales"] = tot(hs, 3) - tot(sr, 9)
    out["hsn_tax_vs_sales"] = tot(hs, 4) - tot(sr, 10)
    out["tax_summary_tax_vs_sales"] = tot(ts, 3) - tot(sr, 10)
    out["paymodes_vs_paid_bills"] = tot(payment_mode_summary(bills), 2) - sum((b["grand_total"] for b in lv if b["status"] == "PAID"), Z)
    return out
