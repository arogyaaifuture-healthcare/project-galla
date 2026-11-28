"""Generates golden_bill_vectors.json: inputs + expected outputs of reference/bill_calculator.py.
Both the Java BillCalculator and the TypeScript/JS port used for offline billing must reproduce EVERY case exactly.
Run:  python gen_golden.py   (needs bill_calculator.py next to this file)
"""
import json, random, sys, os
from decimal import Decimal as D
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bill_calculator import calculate, CENT

T5 = [("CGST", D("2.50")), ("SGST", D("2.50"))]

def money(x):
    assert x == x.quantize(CENT), x
    return format(x.quantize(CENT), ".2f")

def enc_lines(lines):
    return [dict(id=l["id"], name=l["name"], qty=str(l["qty"]), unitPrice=str(l["unit_price"]),
                 comps=[[n, str(r)] for n, r in l["comps"]]) for l in lines]

def enc_comps(c): return [[n, str(r)] for n, r in c]

def build(name, lines, **kw):
    lines = [dict(l, id=l.get("id", f"l{i+1:03d}")) for i, l in enumerate(lines)]
    opts = dict(prices_include_tax=kw.get("prices_include_tax", False), round_off_mode=kw.get("round_off_mode", "NEAREST_1"),
                discount=kw.get("discount"), service_charge_percent=kw.get("service_charge_percent", D(0)),
                service_charge_comps=kw.get("service_charge_comps", ()), delivery_charge=kw.get("delivery_charge", D(0)),
                delivery_comps=kw.get("delivery_comps", ()), extra_charges=kw.get("extra_charges", ()))
    case = dict(name=name, input=dict(
        lines=enc_lines(lines), pricesIncludeTax=opts["prices_include_tax"], roundOffMode=opts["round_off_mode"],
        discount=None if opts["discount"] is None else [opts["discount"][0], str(opts["discount"][1])],
        serviceChargePercent=str(opts["service_charge_percent"]), serviceChargeComps=enc_comps(opts["service_charge_comps"]),
        deliveryCharge=str(opts["delivery_charge"]), deliveryComps=enc_comps(opts["delivery_comps"]),
        extraCharges=[dict(type=e["type"], name=e["name"], amount=str(e["amount"]), comps=enc_comps(e.get("comps", []))) for e in opts["extra_charges"]]))
    try:
        r = calculate(lines, **opts)
    except ValueError as e:
        case["expected"] = dict(error=str(e)); return case
    case["expected"] = dict(
        subtotal=money(r["subtotal"]), discountTotal=money(r["discount_total"]), taxTotal=money(r["tax_total"]),
        totalBeforeRoundOff=money(r["total_before_round_off"]), roundOff=money(r["round_off"]), grandTotal=money(r["grand_total"]),
        lines=[dict(type=l["type"], name=l["name"], gross=money(l["gross"]), discount=money(l["discount"]), taxable=money(l["taxable"]),
                    tax=money(l["tax"]), total=money(l["total"]), comps=[[n, str(rt), money(tx)] for n, rt, tx in l["comps"]]) for l in r["lines"]])
    return case

def L(n, q, p, c=T5): return dict(name=n, qty=D(str(q)), unit_price=D(str(p)), comps=list(c))

def named():
    C = []
    C.append(build("V1", [L("A",2,100), L("B",1,150)], discount=("PERCENT", D(10))))
    C.append(build("V2", [L("A",1,100)], prices_include_tax=True))
    C.append(build("V3", [L("a",1,10,[]), L("b",1,10,[]), L("c",1,10,[])], discount=("AMOUNT", D("10.00"))))
    C.append(build("V4a", [L("a",1,50,[])], discount=("AMOUNT", D("50.01"))))
    C.append(build("V4b", [L("a",1,50,[])], discount=("PERCENT", D(0))))
    C.append(build("V4c", [L("a",1,50,[])], discount=("PERCENT", D("100.01"))))
    C.append(build("V5", [L("a",1,200,[])], service_charge_percent=D(10), service_charge_comps=T5))
    C.append(build("V6", [L("a",1,"99.99",[])], discount=("PERCENT", D(15))))
    for i, amt in enumerate(("100.50", "100.49", "100.00")):
        C.append(build(f"V7{'abc'[i]}", [L("a",1,amt,[])]))
    C.append(build("V8", [L("a",3,"33.33",[])], round_off_mode="NONE"))
    C.append(build("V9", [L("A",2,100), L("B",1,150)], discount=("PERCENT", D(10)), round_off_mode="NONE"))
    C.append(build("V10", [L("A",1,200,[])], discount=("PERCENT", D(10)), service_charge_percent=D(10), service_charge_comps=[],
                   delivery_charge=D("40.00"), delivery_comps=T5))
    C.append(build("V11", [L("A",1,100,[])], prices_include_tax=True, delivery_charge=D("52.50"), delivery_comps=T5))
    pk = lambda n, a, c: dict(type="PACKAGING_CHARGE", name=n, amount=D(a), comps=c)
    C.append(build("X1", [L("Item",2,100,[("GST",D(5))])], discount=("PERCENT", D(10)), extra_charges=[pk("Packaging","20",[("GST",D(5))])]))
    C.append(build("X2", [L("Item",1,100,[("GST",D(5))])], service_charge_percent=D(10), extra_charges=[pk("Packaging","30",[])]))
    C.append(build("X3", [L("Item",1,105,[("GST",D(5))])], prices_include_tax=True,
                   extra_charges=[pk("Pack","10.50",[("GST",D(5))]), pk("Zero","0",[])]))
    C.append(build("X4", [L("Item",1,100,[("GST",D(5))])], extra_charges=[pk("B","7",[("GST",D(5))]), pk("A","10",[("GST",D(5))])]))
    C.append(build("E1-full-discount", [L("A",3,"12.34"), L("B",2,"7.77",[])], discount=("PERCENT", D(100))))
    C.append(build("E2-half-paise-tax", [L("A",1,"0.10",[("GST",D("2.5"))])]))
    C.append(build("E3-zero-price-line", [L("Free",1,0), L("Paid",1,"10.00",[])]))
    C.append(build("E4-three-way-tax-split-inclusive", [L("A",1,"99.99",[("A",D("2.5")),("B",D("2.5")),("C",D("6"))])], prices_include_tax=True))
    C.append(build("E5-many-equal-lines-amount-discount", [L(f"i{i}",1,"3.33",[]) for i in range(7)], discount=("AMOUNT", D("0.10"))))
    return C

RATES = [D(x) for x in ("0", "2.5", "5", "6", "9", "12", "14", "18", "28")]

def rnd_comps(r):
    return [(f"C{i}", r.choice(RATES)) for i in range(r.randint(0, 3))]

def rnd_money(r, hi=5000):
    return D(r.randint(0, hi * 100)) / 100

def random_cases(n, seed=2026):
    r = random.Random(seed); out = []
    for k in range(n):
        lines = [dict(name=f"I{i}", qty=D(r.randint(1, 20000)) / 1000 if r.random() < .3 else D(r.randint(1, 12)),
                      unit_price=rnd_money(r, 2000), comps=rnd_comps(r), id=f"l{i+1:03d}") for i in range(r.randint(1, 8))]
        disc = r.choice([None, None, ("PERCENT", D(r.randint(1, 10000)) / 100), ("AMOUNT", rnd_money(r, 3000) or D("0.01"))])
        ec = [dict(type="PACKAGING_CHARGE", name=f"Pk{j}", amount=rnd_money(r, 100), comps=rnd_comps(r)) for j in range(r.choice([0, 0, 1, 2]))]
        out.append(build(f"R{k+1:04d}", lines, prices_include_tax=r.random() < .5, round_off_mode=r.choice(["NONE", "NEAREST_1"]),
                         discount=disc, service_charge_percent=r.choice([D(0), D(5), D(10)]), service_charge_comps=rnd_comps(r),
                         delivery_charge=r.choice([D(0), rnd_money(r, 200)]), delivery_comps=rnd_comps(r), extra_charges=ec))
    return out

def device_rules_cases():
    """fiscal-year labels and business dates (plan 5.5 / 5.6), ported to the terminal."""
    fy = [("2026-11-23", 4, "2026-27"), ("2026-03-31", 4, "2025-26"), ("2026-04-01", 4, "2026-27"), ("2026-12-31", 1, "2026"),
          ("2027-01-01", 1, "2027"), ("2099-05-05", 4, "2099-00"), ("2026-01-15", 4, "2025-26"), ("2026-07-01", 7, "2026-27"), ("2026-06-30", 7, "2025-26")]
    bd = [("2026-11-22T20:00:00Z", "Asia/Kolkata", 4, "2026-11-22"),   # 01:30 IST on 23 Nov -> still trading day 22 Nov
          ("2026-11-22T22:29:59Z", "Asia/Kolkata", 4, "2026-11-22"),   # 03:59:59 IST
          ("2026-11-22T22:30:00Z", "Asia/Kolkata", 4, "2026-11-23"),   # 04:00:00 IST
          ("2026-11-23T05:00:00Z", "Asia/Kolkata", 0, "2026-11-23"),
          ("2026-12-31T20:00:00Z", "Asia/Kolkata", 4, "2026-12-31"),
          ("2026-01-01T00:30:00Z", "Asia/Kolkata", 4, "2026-01-01"),
          ("2025-12-31T21:00:00Z", "Asia/Kolkata", 4, "2025-12-31"),
          ("2026-07-01T03:00:00Z", "America/New_York", 4, "2026-06-30"),
          ("2026-03-08T07:30:00Z", "America/New_York", 4, "2026-03-07")]
    return [dict(fiscalYear=dict(localDate=d, startMonth=m, expected=e)) for d, m, e in fy] + \
           [dict(businessDate=dict(instant=i, tz=tz, dayStartHour=h, expected=e)) for i, tz, h, e in bd]

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    cases = named() + random_cases(400)
    # business date expected values computed independently with zoneinfo
    from zoneinfo import ZoneInfo
    from datetime import datetime, timedelta, timezone
    def py_business_date(instant, tz, h):
        t = datetime.fromisoformat(instant.replace("Z", "+00:00")).astimezone(ZoneInfo(tz))
        return (t - timedelta(hours=h)).date().isoformat()
    def py_fy(local_date, m):
        y, mo = int(local_date[:4]), int(local_date[5:7])
        if m == 1: return str(y)
        s = y if mo >= m else y - 1
        return f"{s}-{(s + 1) % 100:02d}"
    dev = device_rules_cases()
    for d in dev:
        if "fiscalYear" in d: assert py_fy(d["fiscalYear"]["localDate"], d["fiscalYear"]["startMonth"]) == d["fiscalYear"]["expected"], d
        else:
            b = d["businessDate"]; assert py_business_date(b["instant"], b["tz"], b["dayStartHour"]) == b["expected"], d
    json.dump(dict(version=1, billCases=cases, deviceRuleCases=dev), open(os.path.join(here, "golden_bill_vectors.json"), "w"), indent=0)
    errs = sum(1 for c in cases if "error" in c["expected"])
    print(f"wrote {len(cases)} bill cases ({errs} expected errors) and {len(dev)} device-rule cases")
