from decimal import Decimal as D
import random
from hypothesis import given, settings, strategies as st
from bill_calculator import calculate
from registers import *

GST = lambda r: [("CGST", D(r) / 2), ("SGST", D(r) / 2)]
def rand_bill(rnd, i, incl=None, status="PAID"):
    incl = rnd.random() < .5 if incl is None else incl
    lines = []
    for k in range(rnd.randint(1, 6)):
        rate = rnd.choice(["0", "5", "12", "18", "28"])
        lines.append(dict(id=f"{i}-{k}", name=f"Item{k}", qty=D(rnd.randint(1, 9)) / rnd.choice([1, 1, 2]), unit_price=D(rnd.randint(100, 99999)) / 100,
                          comps=GST(rate) if rate != "0" else []))
    disc = rnd.choice([None, ("PERCENT", D(rnd.randint(1, 50))), ("AMOUNT", D("1.00"))])
    ec = rnd.choice([[], [dict(type="PACKAGING_CHARGE", name="Packaging", amount=D(rnd.randint(1, 50)), comps=GST("18"))]])
    try:
        c = calculate(lines, prices_include_tax=incl, discount=disc, service_charge_percent=rnd.choice([D(0), D(5), D(10)]),
                      service_charge_comps=GST("18"), delivery_charge=rnd.choice([D(0), D(40)]), delivery_comps=GST("18"), extra_charges=ec,
                      round_off_mode=rnd.choice(["NEAREST_1", "NONE"]))
    except ValueError:
        c = calculate(lines, prices_include_tax=incl)
    hsn = {f"Item{k}": rnd.choice([None, "9963", "21069099"]) for k in range(6)}
    return make_bill(c, f"B-{i:06d}", f"2026-11-{rnd.randint(1, 28):02d}", hsn, status,
                     methods=rnd.choice([None, [("CASH", D("0.3")), ("UPI", D("0.7"))], [("CARD", D(1))]]))

@settings(max_examples=150, deadline=None)
@given(st.randoms(use_true_random=False), st.integers(1, 40))
def test_R1_registers_reconcile_exactly_for_random_bills(rnd, n):
    bills = [rand_bill(rnd, i, status=rnd.choice(["PAID", "PAID", "GENERATED", "VOID"])) for i in range(n)]
    rec = reconcile(bills)
    assert all(v == D("0.00") for v in rec.values()), rec

def test_R2_void_bills_are_excluded_from_every_register():
    rnd = random.Random(1); b = [rand_bill(rnd, 0, status="VOID"), rand_bill(rnd, 1)]
    assert [r[1] for r in sales_register(b)] == ["B-000001"]
    assert all(r[0] != "B-000000" for r in sales_by_rate(b))
def test_R3_known_vector_exclusive_and_inclusive():
    c = calculate([dict(id="a", name="Tikka", qty=D(2), unit_price=D("100"), comps=GST("5"))], prices_include_tax=False)
    b = make_bill(c, "B1", "2026-11-01", {"Tikka": "9963"})
    assert sales_register([b])[0][9:] == [D("200.00"), D("10.00"), D("0.00"), D("210.00")]
    assert hsn_summary([b]) == [["9963", D("5.00"), D("2"), D("200.00"), D("10.00"), D("210.00"), False]]
    assert tax_summary([b]) == [["CGST", D("2.50"), D("200.00"), D("5.00")], ["SGST", D("2.50"), D("200.00"), D("5.00")]]
    c2 = calculate([dict(id="a", name="Tikka", qty=D(1), unit_price=D("105"), comps=GST("5"))], prices_include_tax=True)
    b2 = make_bill(c2, "B2", "2026-11-01"); r = sales_register([b2])[0]
    assert r[9] == D("100.00") and r[10] == D("5.00") and r[12] == D("105.00")
    assert hsn_summary([b2])[0][0] == "" and hsn_summary([b2])[0][-1] is True        # missing HSN is flagged, not hidden
def test_R4_round_off_is_its_own_column_never_folded_into_tax():
    c = calculate([dict(id="a", name="X", qty=D(1), unit_price=D("10.30"), comps=[])], prices_include_tax=False)
    b = make_bill(c, "B", "2026-11-01"); r = sales_register([b])[0]
    assert r[9] == D("10.30") and r[10] == D("0.00") and r[11] == D("-0.30") and r[12] == D("10.00")
def test_R5_by_rate_groups_cgst_sgst_into_one_rate():
    c = calculate([dict(id="a", name="X", qty=D(1), unit_price=D("100"), comps=GST("5")), dict(id="b", name="Y", qty=D(1), unit_price=D("100"), comps=GST("18"))], prices_include_tax=False)
    rows = sales_by_rate([make_bill(c, "B", "2026-11-01")]); assert [r[1] for r in rows] == [D("5.00"), D("18.00")]
def test_R6_payment_mode_summary_splits():
    c = calculate([dict(id="a", name="X", qty=D(1), unit_price=D("1000"), comps=[])], prices_include_tax=False)
    b = make_bill(c, "B", "2026-11-01", methods=[("CASH", D("0.3")), ("UPI", D("0.7"))])
    assert payment_mode_summary([b]) == [["CASH", 1, D("300.00")], ["UPI", 1, D("700.00")]]
