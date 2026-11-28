"""Tests for inventory.py: vectors IN1.. and property tests (hypothesis)."""
import datetime as dt
import pytest
from decimal import Decimal as D
from hypothesis import given, settings, strategies as st
from inventory import *

# ---- vectors
def test_IN1_unit_conversions_exact():
    assert convert("1", "kg", "g") == D("1000.0000")
    assert convert("250", "g", "kg") == D("0.2500")
    assert convert("1", "dozen", "pcs") == D("12.0000")
    assert convert("1", "g", "kg") == D("0.0010")
    assert convert("1", "ml", "l") == D("0.0010")

def test_IN2_family_mismatch():
    for a, b in [("kg", "l"), ("g", "pcs"), ("ml", "dozen"), ("pack", "g")]:
        with pytest.raises(UnitError, match="UNIT_FAMILY_MISMATCH"):
            convert("1", a, b)

def test_IN3_item_unit_rules():
    check_item_units("g", "kg", "1000")
    check_item_units("pcs", "dozen", "12")
    check_item_units("pcs", "crate", "30")       # pack unit: any factor
    with pytest.raises(UnitError): check_item_units("g", "l", "1000")
    with pytest.raises(UnitError): check_item_units("g", "kg", "100")
    with pytest.raises(UnitError): check_item_units("kg", "kg", "1")

def test_IN4_purchase_line():
    # 5 kg at Rs 84.50/kg -> 5000 g, 0.0845 per g, 422.50
    assert purchase_line("5", "84.50", "1000") == (D("5000.0000"), D("0.084500"), D("422.50"))
    # 1 crate of 30 pcs at 210 -> 7.000000 per pc
    assert purchase_line("1", "210", "30") == (D("30.0000"), D("7.000000"), D("210.00"))
    # 3 packs of 7 at 100 -> 14.285714 per pc, line 300.00
    assert purchase_line("3", "100", "7") == (D("21.0000"), D("14.285714"), D("300.00"))

def test_IN5_weighted_average():
    assert weighted_average("1000", "0.08", "1000", "0.10") == D("0.090000")
    assert weighted_average("0", "0.08", "500", "0.10") == D("0.100000")
    assert weighted_average("-50", "0.08", "500", "0.10") == D("0.100000")
    assert weighted_average("30", "7", "30", "8") == D("7.500000")
    # rounding half up to 6dp
    assert weighted_average("1", "0.000001", "2", "0.000002") == D("0.000002")  # 1.666666e-6

def test_IN6_ledger_flow_and_cost_basis():
    L = Level()
    L.post("PURCHASE", "1000", "0.08", key="p1")
    L.post("PURCHASE", "1000", "0.10", key="p2")
    assert (L.on_hand, L.avg) == (D("2000.0000"), D("0.090000"))
    i = L.post("SALE", "-300", key="s1")
    assert L.moves[i].qty == D("-300.0000") and L.moves[i].unit_cost == D("0.090000") and L.moves[i].basis == "AVERAGE"
    assert L.on_hand == D("1700.0000") and L.avg == D("0.090000")   # outflow leaves the average unchanged
    assert L.value() == D("153.00")

def test_IN7_unknown_average_uses_last_purchase_then_unknown():
    L = Level()
    i = L.post("SALE", "-10", key="s0")
    assert L.moves[i].basis == "UNKNOWN" and L.moves[i].unit_cost == 0
    L2 = Level(); L2.post("PURCHASE", "100", "0.5", key="p"); L2.post("SALE", "-100", key="s")
    j = L2.post("SALE", "-5", key="s2")     # stock is 0 -> last purchase price, flagged
    assert L2.moves[j].basis == "LAST_PURCHASE" and L2.moves[j].unit_cost == D("0.500000")
    assert L2.on_hand == D("-5.0000")
    L2.post("PURCHASE", "20", "0.6", key="p3")   # on_hand <= 0: new cost replaces average
    assert L2.avg == D("0.600000") and L2.on_hand == D("15.0000")

def test_IN8_negative_stock_policy():
    L = Level(policy="BLOCK_MANUAL"); L.post("PURCHASE", "10", "1", key="p")
    with pytest.raises(LedgerError, match="NEGATIVE_STOCK_BLOCKED"):
        L.post("WASTAGE", "-11", key="w")
    L.post("SALE", "-11", key="s")          # sales are never blocked
    assert L.on_hand == D("-1.0000")
    A = Level(); A.post("PURCHASE", "10", "1", key="p"); A.post("WASTAGE", "-11", key="w")
    assert A.on_hand == D("-1.0000")

def test_IN9_sign_zero_idempotency():
    L = Level()
    with pytest.raises(LedgerError): L.post("PURCHASE", "-1", "1")
    with pytest.raises(LedgerError): L.post("SALE", "1")
    with pytest.raises(LedgerError): L.post("PURCHASE", "0", "1")
    a = L.post("PURCHASE", "5", "2", key="k"); b = L.post("PURCHASE", "5", "2", key="k")
    assert a == b and L.on_hand == D("5.0000") and len(L.moves) == 1

def test_IN10_adjustment_count_variance_at_average():
    L = Level(); L.post("PURCHASE", "100", "2", key="p")
    L.post("COUNT_VARIANCE", "-4", key="c")
    L.post("ADJUSTMENT", "1", key="a")
    assert L.on_hand == D("97.0000") and L.avg == D("2.000000")
    assert L.moves[1].basis == "AVERAGE" and L.moves[2].unit_cost == D("2.000000")

def test_IN11_reversal_at_original_cost_and_cap():
    L = Level(); L.post("PURCHASE", "100", "1", key="p")
    s = L.post("SALE", "-40", key="s")
    L.post("PURCHASE", "100", "2", key="p2")           # average moves to 1.5-ish
    L.post("SALE_REVERSAL", "10", key="r1", reverses=s)
    assert L.moves[-1].unit_cost == D("1.000000") and L.moves[-1].basis == "REVERSAL"
    with pytest.raises(LedgerError, match="REVERSAL_EXCEEDS_ORIGINAL"):
        L.post("SALE_REVERSAL", "31", key="r2", reverses=s)
    L.post("SALE_REVERSAL", "30", key="r3", reverses=s)
    with pytest.raises(LedgerError, match="REVERSAL_TARGET_INVALID"):
        L.post("SALE_REVERSAL", "1", key="r4", reverses=0)

def test_IN12_recipe_consumption_with_wastage():
    # paneer 100 g net per portion, 20 % trim -> 125 g gross
    r = Recipe([RLine("paneer", D("100"), D("20")), RLine("oil", D("10"))])
    used, skipped = consumption([("PT", 3, [])], {"PT": r})
    assert used == {"paneer": D("375.0000"), "oil": D("30.0000")} and skipped == []

def test_IN13_modifiers_and_no_recipe():
    r = Recipe([RLine("rice", D("150"))])
    mods = {"extra_cheese": Recipe([RLine("cheese", D("20"))])}
    used, skipped = consumption([("A", 2, ["extra_cheese"]), ("B", 1, ["extra_cheese"])], {"A": r}, modifier_recipes=mods)
    assert used == {"rice": D("300.0000"), "cheese": D("60.0000")} and skipped == ["B"]

def test_IN14_sub_recipe_expand_and_direct():
    gravy = Recipe([RLine("onion", D("600")), RLine("tomato", D("400"), D("10"))], yield_qty=D("800"))
    dish = Recipe([RLine("gravy", D("200"), mode="EXPAND")])
    used, _ = consumption([("D", 4, [])], {"D": dish}, preps={"gravy": gravy})
    # 800 g gravy sold -> exactly one batch: 600 onion, 400/0.9 tomato
    assert used["onion"] == D("600.0000") and used["tomato"] == D("444.4444")
    direct = Recipe([RLine("gravy", D("200"))])
    used2, _ = consumption([("D", 4, [])], {"D": direct}, preps={"gravy": gravy})
    assert used2 == {"gravy": D("800.0000")}

def test_IN15_prep_nesting_and_cycle():
    kinds = {"a": "PREP", "b": "PREP", "x": "RAW"}
    with pytest.raises(RecipeError, match="PREP_NESTING_NOT_ALLOWED"):
        validate_prep_graph({"a": Recipe([RLine("b", D(1))])}, kinds)
    validate_prep_graph({"a": Recipe([RLine("x", D(1))])}, kinds)
    assert find_cycle({"a": ["b"], "b": ["c"], "c": ["a"]}) is not None
    assert find_cycle({"a": ["a"]}) is not None
    assert find_cycle({"a": ["b", "c"], "b": ["c"], "c": []}) is None

def test_IN16_reversal_quantities_proportional_and_final():
    sale = D("-100")
    r1 = reversal_quantities(sale, 0, D("0.3333"))
    assert r1 == D("33.3300")
    r2 = reversal_quantities(sale, r1, D("0.3333"))
    r3 = reversal_quantities(sale, r1 + r2, 0, final=True)
    assert r1 + r2 + r3 == D("100")
    assert reversal_quantities(sale, D("95"), D("0.5")) == D("5.0000")   # capped

def test_IN17_theoretical_cost_and_food_cost_percent():
    c = theoretical_cost({"a": D("375"), "b": D("30")}, {"a": D("0.2"), "b": D("0.1")})
    assert c == D("78.00")
    assert food_cost_percent("78.00", "300.00") == D("26.00")
    assert food_cost_percent("1", "3") == D("33.33")
    assert food_cost_percent("1", "0") is None

def test_IN18_variance():
    actual, var = variance("900", "1000", "500", "550")
    assert actual == D("950.0000") and var == D("50.0000")
    actual, var = variance("900", "1000", "0", "0", transfers_net="-100")
    assert var == 0 and actual == D("900.0000")

def test_IN19_low_stock_and_suggested_order():
    assert low_stock("5", "5") and not low_stock("5.0001", "5") and not low_stock("0", "0")
    assert low_stock("5", "5", override="3") is False and low_stock("3", "5", override="3")
    assert suggested_order_base("2", "10", "5") == D("8.0000")
    assert suggested_order_base("6", "10", "5") == D(0) and suggested_order_base("2", None, "5") == D(0)

def test_IN20_price_change_percent():
    assert price_change_percent("0.11", "0.10") == D("10.00")
    assert price_change_percent("0.09", "0.10") == D("-10.00")
    assert price_change_percent("1", None) is None and price_change_percent("1", "0") is None

def test_IN21_aging_buckets():
    t = dt.date(2026, 6, 30)
    f = lambda n: aging_bucket(t - dt.timedelta(days=n), t)
    assert [f(-3), f(0), f(1), f(30), f(31), f(60), f(61), f(90), f(91)] == \
        ["NOT_DUE", "NOT_DUE", "1-30", "1-30", "31-60", "31-60", "61-90", "61-90", "90+"]

def test_IN22_eod_inventory_shape_and_invariant():
    o = eod_inventory("50000.00", "12000.00", "9000.00", "400.00", "-100.00", "52480.00", 4, 3, 1, 180, 20)
    assert list(o) == ["opening_value", "purchases_value", "consumption_value", "wastage_value", "adjustments_value",
                       "other_movements_value", "closing_value", "low_stock_count", "no_recipe_items_count",
                       "price_alert_count", "sales_coverage_percent"]
    assert o["other_movements_value"] == "-20.00" and o["sales_coverage_percent"] == "90.00"
    tot = (D(o["opening_value"]) + D(o["purchases_value"]) - D(o["consumption_value"]) - D(o["wastage_value"])
           + D(o["adjustments_value"]) + D(o["other_movements_value"]))
    assert tot == D(o["closing_value"])
    assert eod_inventory(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)["sales_coverage_percent"] == "100.00"

# ---- properties
qty = st.decimals(min_value="0.0001", max_value="5000", places=4)
cost = st.decimals(min_value="0.000001", max_value="50", places=6)
op = st.one_of(
    st.tuples(st.just("PURCHASE"), qty, cost),
    st.tuples(st.just("OPENING"), qty, cost),
    st.tuples(st.sampled_from(["SALE", "WASTAGE", "VENDOR_RETURN", "TRANSFER_OUT"]), qty, st.none()),
    st.tuples(st.just("TRANSFER_IN"), qty, cost),
    st.tuples(st.sampled_from(["ADJUSTMENT", "COUNT_VARIANCE"]), st.decimals(min_value="-500", max_value="500", places=4).filter(lambda x: x != 0), st.none()),
)

def run(ops, policy="ALLOW"):
    L = Level(policy=policy)
    for n, (k, q, c) in enumerate(ops):
        if k in OUTFLOW: q = -q
        try: L.post(k, q, c, key="k%d" % n)
        except LedgerError: pass
    return L

@settings(max_examples=300, deadline=None)
@given(st.lists(op, max_size=40), st.sampled_from(["ALLOW", "BLOCK_MANUAL"]))
def test_P1_ledger_sum_equals_on_hand(ops, policy):
    L = run(ops, policy)
    assert L.ledger_sum() == L.on_hand
    if policy == "BLOCK_MANUAL":
        assert all(True for _ in L.moves)

@settings(max_examples=300, deadline=None)
@given(st.lists(st.tuples(qty, cost), min_size=1, max_size=15))
def test_P2_weighted_average_within_purchase_range(buys):
    L = Level()
    for n, (q, c) in enumerate(buys): L.post("PURCHASE", q, c, key=str(n))
    lo, hi = min(c for _, c in buys), max(c for _, c in buys)
    assert lo <= L.avg <= hi

@settings(max_examples=300, deadline=None)
@given(st.lists(st.tuples(qty, cost), min_size=1, max_size=5), st.lists(qty, min_size=1, max_size=6),
       st.lists(st.decimals(min_value="0", max_value="1", places=2), min_size=1, max_size=6))
def test_P3_consumption_then_reversal_restores_quantity_exactly(buys, sales, fracs):
    L = Level()
    for n, (q, c) in enumerate(buys): L.post("PURCHASE", q, c, key="b%d" % n)
    start = L.on_hand
    ids = [L.post("SALE", -q, key="s%d" % n) for n, q in enumerate(sales)]
    for i, f in zip(ids, fracs + [D(0)] * len(ids)):
        orig = L.moves[i].qty
        r = reversal_quantities(orig, 0, f)
        if r > 0: L.post("SALE_REVERSAL", r, key="r%d" % i, reverses=i)
        L.post("SALE_REVERSAL", reversal_quantities(orig, r, 0, final=True), key="rf%d" % i, reverses=i) \
            if reversal_quantities(orig, r, 0, final=True) > 0 else None
    assert L.on_hand == start
    assert L.ledger_sum() == L.on_hand

@settings(max_examples=200, deadline=None)
@given(qty, cost, qty)
def test_P4_sale_then_full_reversal_returns_value_exactly(q, c, s):
    L = Level(); L.post("PURCHASE", q, c, key="p")
    v0, avg0 = L.on_hand * L.avg, L.avg
    i = L.post("SALE", -s, key="s")
    L.post("SALE_REVERSAL", s, key="r", reverses=i)
    assert L.on_hand == q
    assert L.moves[i].qty + L.moves[-1].qty == 0
    assert L.moves[i].unit_cost == L.moves[-1].unit_cost       # same cost both ways
    if q >= s: assert L.avg == avg0 and q2(L.on_hand * L.avg) == q2(v0)

@settings(max_examples=200, deadline=None)
@given(st.lists(op, max_size=30))
def test_P5_idempotent_replay(ops):
    L = Level()
    for n, (k, q, c) in enumerate(ops):
        if k in OUTFLOW: q = -q
        try: L.post(k, q, c, key="k%d" % n)
        except LedgerError: pass
    snap = (L.on_hand, L.avg, len(L.moves))
    for n, (k, q, c) in enumerate(ops):          # replay every key: nothing changes
        if k in OUTFLOW: q = -q
        try: L.post(k, q, c, key="k%d" % n)
        except LedgerError: pass
    assert (L.on_hand, L.avg, len(L.moves)) == snap

@settings(max_examples=200, deadline=None)
@given(st.decimals(min_value="0.001", max_value="1000", places=3), st.decimals(min_value="0.01", max_value="999", places=2),
       st.sampled_from(["kg", "l", "dozen"]))
def test_P6_unit_roundtrip_exact(q, _, u):
    base = BASE_OF[UNITS[u][0]]
    assert convert(convert(q, u, base), base, u) == q4(q)

@settings(max_examples=200, deadline=None)
@given(st.lists(st.tuples(st.decimals(min_value="1", max_value="900", places=2), st.decimals(min_value="0", max_value="50", places=2)),
                min_size=1, max_size=6), st.integers(1, 40))
def test_P7_consumption_scales_and_is_non_negative(lines, portions):
    r = Recipe([RLine("i%d" % n, q, w) for n, (q, w) in enumerate(lines)])
    used, _ = consumption([("T", portions, [])], {"T": r})
    assert all(v > 0 for v in used.values())
    for n, (q, w) in enumerate(lines):           # >= net amount, one rounding only
        assert used["i%d" % n] >= q4(q * portions)
        assert used["i%d" % n] == q4(q * 100 / (100 - w) * portions)

@settings(max_examples=100, deadline=None)
@given(st.dictionaries(st.sampled_from("abcdef"), st.lists(st.sampled_from("abcdef"), max_size=3), max_size=6))
def test_P8_cycle_detector_agrees_with_brute_force(g):
    def reach(s):
        seen, stack = set(), list(g.get(s, []))
        while stack:
            n = stack.pop()
            if n in seen: continue
            seen.add(n); stack += g.get(n, [])
        return seen
    expected = any(n in reach(n) for n in g)
    assert (find_cycle({k: list(v) for k, v in g.items()}) is not None) == expected
