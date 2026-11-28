from datetime import datetime, date, time, timedelta
from decimal import Decimal as D
import pytest
from hypothesis import given, settings, strategies as st
from bill_calculator import calculate, to_cents, from_cents, r2
import combo, coupon, pricing_rules as pr, nc, kds, shift, credit, credit_note as cn

GST5 = [("CGST", D("2.5")), ("SGST", D("2.5"))]
def L(i, q, p, comps=GST5): return dict(id=i, name="I" + i, qty=D(q), unit_price=D(p), comps=list(comps))
dec = lambda lo, hi: st.decimals(min_value=D(lo), max_value=D(hi), places=2)

# ---------------- combos (BX01..BX06) ----------------
def test_BX01_combo_allocation_proportional():
    a = combo.allocate_combo(D("250"), [dict(id="a", qty=D(1), list_price=D("200")), dict(id="b", qty=D(2), list_price=D("50"))])
    assert a == {"a": D("166.67"), "b": D("83.33")} and sum(a.values()) == D("250.00")
def test_BX02_combo_three_way_cent_exact():
    comps = [dict(id=x, qty=D(1), list_price=D("100")) for x in "abc"]
    a = combo.allocate_combo(D("100"), comps)
    assert sorted(a.values()) == [D("33.33"), D("33.33"), D("33.34")] and sum(a.values()) == D("100.00")
def test_BX03_combo_all_free_components_falls_back_to_qty():
    a = combo.allocate_combo(D("90"), [dict(id="a", qty=D(1), list_price=D(0)), dict(id="b", qty=D(2), list_price=D(0))])
    assert a == {"a": D("30.00"), "b": D("60.00")}
def test_BX04_combo_in_engine_keeps_each_component_tax_profile():
    comps = [dict(id="a", qty=D(1), list_price=D("100"), comps=[("GST", D("5"))]), dict(id="b", qty=D(1), list_price=D("100"), comps=[("GST", D("18"))])]
    r = calculate(combo.to_calc_lines(D("200"), comps), prices_include_tax=False)
    assert [l["tax"] for l in r["lines"]] == [D("5.00"), D("18.00")] and r["subtotal"] == D("200.00")
def test_BX05_combo_stock_consumption_interface():
    assert combo.consumption(D(3), [dict(item_id="x", variant_id=None, qty=D("2")), dict(item_id="y", variant_id="v", qty=D("0.5"))]) == [("x", None, D(6)), ("y", "v", D("1.5"))]
def test_BX06_combo_empty_rejected():
    with pytest.raises(ValueError): combo.allocate_combo(D(10), [])
@given(price=dec("0", "5000"), parts=st.lists(st.tuples(st.integers(1, 5), dec("0", "900")), min_size=1, max_size=8))
@settings(max_examples=300, deadline=None)
def test_BX07_prop_combo_sum_is_exact(price, parts):
    comps = [dict(id=f"c{i}", qty=D(q), list_price=p, comps=GST5) for i, (q, p) in enumerate(parts)]
    a = combo.allocate_combo(price, comps)
    assert sum(a.values()) == price and all(v >= 0 for v in a.values())
    r = calculate(combo.to_calc_lines(price, comps), prices_include_tax=False, round_off_mode="NONE")
    assert r["subtotal"] == price
@given(price=dec("1", "3000"), parts=st.lists(st.tuples(st.integers(1, 4), dec("1", "500")), min_size=2, max_size=6))
@settings(max_examples=100, deadline=None)
def test_BX08_prop_combo_order_independent(price, parts):
    comps = [dict(id=f"c{i}", qty=D(q), list_price=p) for i, (q, p) in enumerate(parts)]
    assert combo.allocate_combo(price, comps) == combo.allocate_combo(price, list(reversed(comps)))

# ---------------- coupons (BX10..BX26) ----------------
NOW = datetime(2026, 11, 25, 13, 0)    # a Wednesday
def C(**kw):
    c = dict(id="c1", code="WELCOME10", discount_type="PERCENT", value=D("10"), max_discount=None, min_bill=D(0), active=True, outlet_id=None)
    c.update(kw); return c
def V(c, **kw):
    a = dict(now_local=NOW, outlet_id="o1", order_type="DINE_IN", subtotal=D("500")); a.update(kw)
    return coupon.validate(c, **a)
def test_BX10_percent_and_cap():
    assert coupon.discount_amount(C(), D("333.33")) == D("33.33")
    assert coupon.discount_amount(C(max_discount=D("20")), D("500")) == D("20")
def test_BX11_amount_never_exceeds_subtotal():
    assert coupon.discount_amount(C(discount_type="AMOUNT", value=D("100")), D("60")) == D("60")
def test_BX12_every_reason_code_reachable():
    got = set()
    cases = [(None, {}), (C(active=False), {}), (C(), dict(is_nc=True)), (C(), dict(manual_discount=True)), (C(outlet_id="o2"), {}),
             (C(valid_from=NOW + timedelta(days=1)), {}), (C(valid_to=NOW), {}), (C(weekdays=(1,)), {}), (C(order_types=("DELIVERY",)), {}),
             (C(min_bill=D("501")), {}), (C(usage_limit_per_customer=1), {}), (C(usage_limit_total=5), dict(active_total=5)),
             (C(usage_limit_per_day=2), dict(active_today=2)), (C(usage_limit_per_customer=1), dict(customer_id="u", active_for_customer=1))]
    for c, kw in cases:
        ok, why = V(c, **kw); assert not ok; got.add(why)
    ok, why = V(C(), subtotal=D(0)); got.add(why)
    assert got == set(coupon.REASONS) - {"COUPON_NOT_FOUND"} | {"COUPON_NOT_FOUND"}
def test_BX13_valid_to_exclusive_valid_from_inclusive():
    assert V(C(valid_from=NOW))[0] is True and V(C(valid_to=NOW))[1] == "COUPON_EXPIRED"
def test_BX14_released_use_is_counted_again():
    assert V(C(usage_limit_total=1), active_total=0)[0] is True        # a RELEASED redemption is not in active_total
def test_BX15_find_case_insensitive():
    assert coupon.find([C()], " welcome10 ")["id"] == "c1" and coupon.find([C()], "x") is None
def test_BX16_apply_cap_before_allocation_sum_exact():
    lines = [L("a", 1, "100"), L("b", 1, "100"), L("c", 1, "100")]
    r, why = coupon.apply(C(max_discount=D("10")), lines, now_local=NOW, outlet_id="o1", order_type="DINE_IN", prices_include_tax=False)
    assert why is None and r["discount_total"] == D("10.00") and sum(l["discount"] for l in r["lines"]) == D("10.00")
def test_BX17_apply_failure_returns_reason_no_result():
    assert coupon.apply(C(min_bill=D("1000")), [L("a", 1, "100")], now_local=NOW, outlet_id="o1", order_type="DINE_IN", prices_include_tax=False) == (None, "COUPON_MIN_BILL")
def test_BX18_weekday_is_outlet_local():
    assert V(C(weekdays=(3,)))[0] is True      # 2026-11-25 is a Wednesday = ISO 3
@given(sub=dec("1", "5000"), val=dec("1", "100"), cap=st.one_of(st.none(), dec("1", "500")))
@settings(max_examples=200, deadline=None)
def test_BX19_prop_coupon_discount_bounds(sub, val, cap):
    d = coupon.discount_amount(C(value=val, max_discount=cap), sub)
    assert 0 <= d <= sub and (cap is None or d <= cap)
    r, why = coupon.apply(C(value=val, max_discount=cap), [L("a", 1, sub)], now_local=NOW, outlet_id="o1", order_type="DINE_IN", prices_include_tax=False)
    if r: assert r["discount_total"] == d

# ---------------- time-based pricing (BX30..BX40) ----------------
def R(**kw):
    r = dict(id="r1", name="Happy hour", scope_type="ITEM", menu_item_id="i1", variant_id=None, category_id=None, weekdays=(1,2,3,4,5,6,7),
             start_time=time(16), end_time=time(19), valid_from=None, valid_to=None, action="PERCENT_OFF", percent_off=D("20"), price=None, priority=0, active=True)
    r.update(kw); return r
def RES(rules, when, **kw):
    a = dict(now_local=when, order_type="DINE_IN", item_id="i1", variant_id=None, category_id="cat", base_price=D("100")); a.update(kw)
    return pr.resolve(rules, **a)
WED = lambda h, m=0: datetime(2026, 11, 25, h, m)
def test_BX30_inside_and_outside_window():
    assert RES([R()], WED(17))["price"] == D("80.00") and RES([R()], WED(17))["source"] == "PRICE_RULE"
    assert RES([R()], WED(19))["source"] == "LIST" and RES([R()], WED(15, 59))["price"] == D("100.00")     # end exclusive
    assert RES([R()], WED(16))["source"] == "PRICE_RULE"                                                     # start inclusive
def test_BX31_midnight_crossing_weekday_is_start_day():
    night = R(start_time=time(22), end_time=time(2), weekdays=(1,))                 # Mondays 22:00 - 02:00
    mon_23 = datetime(2026, 11, 23, 23); tue_01 = datetime(2026, 11, 24, 1); tue_23 = datetime(2026, 11, 24, 23); mon_01 = datetime(2026, 11, 23, 1)
    assert RES([night], mon_23)["source"] == "PRICE_RULE" and RES([night], tue_01)["source"] == "PRICE_RULE"   # Tue 01:00 belongs to MONDAY's window
    assert RES([night], tue_23)["source"] == "LIST" and RES([night], mon_01)["source"] == "LIST"               # Mon 01:00 belongs to SUNDAY's window
def test_BX32_valid_dates_refer_to_window_start_day():
    r = R(start_time=time(22), end_time=time(2), valid_to=date(2026, 11, 23))
    assert RES([r], datetime(2026, 11, 24, 1))["source"] == "PRICE_RULE"          # started on the 23rd: still valid
    assert RES([r], datetime(2026, 11, 24, 23))["source"] == "LIST"
def test_BX33_priority_wins():
    a = R(id="a", priority=1, action="PRICE_OVERRIDE", price=D("90"), percent_off=None); b = R(id="b", priority=5, percent_off=D("50"))
    assert RES([a, b], WED(17))["rule_id"] == "b" and RES([a, b], WED(17))["price"] == D("50.00")
def test_BX34_priority_tie_specificity_then_price_then_id():
    item = R(id="x", priority=3); var = R(id="y", priority=3, scope_type="VARIANT", menu_item_id=None, variant_id="v1")
    assert RES([item, var], WED(17), variant_id="v1")["rule_id"] == "y"
    cheap = R(id="m", percent_off=D("30")); dear = R(id="n", percent_off=D("10"))
    assert RES([dear, cheap], WED(17))["rule_id"] == "m"
    same1 = R(id="b1"); same2 = R(id="a1")
    assert RES([same1, same2], WED(17))["rule_id"] == "a1"
def test_BX35_category_scope_percent_only_and_order_type_and_inactive():
    c = R(scope_type="CATEGORY", menu_item_id=None, category_id="cat")
    assert RES([c], WED(17))["price"] == D("80.00")
    assert RES([R(order_types=("DELIVERY",))], WED(17))["source"] == "LIST" and RES([R(active=False)], WED(17))["source"] == "LIST"
def test_BX36_snapshot_contract():
    x = RES([R()], WED(17)); assert set(x) == {"price", "source", "rule_id", "rule_name", "list_price"} and x["list_price"] == D("100.00")
def test_BX37_override_price_can_be_zero_and_rounds():
    assert RES([R(action="PRICE_OVERRIDE", price=D("0"), percent_off=None)], WED(17))["price"] == D("0.00")
    assert RES([R(percent_off=D("33.33"))], WED(17), base_price=D("99.99"))["price"] == D("66.66")
def test_BX38_calendar_vs_business_date_late_night():
    """01:30 on Tuesday is business date Monday for a bar that closes at 03:00; the pricing window (22-02, Monday) still applies,
    because it is decided by the window START day, not by the order's business_date."""
    r = R(start_time=time(22), end_time=time(2), weekdays=(1,))
    assert RES([r], datetime(2026, 11, 24, 1, 30))["source"] == "PRICE_RULE"
@given(h=st.integers(0, 23), m=st.integers(0, 59), s_h=st.integers(0, 23), e_h=st.integers(0, 23))
@settings(max_examples=300, deadline=None)
def test_BX39_prop_window_membership(h, m, s_h, e_h):
    if s_h == e_h: return
    when = datetime(2026, 11, 25, h, m); t = when.time(); s, e = time(s_h), time(e_h)
    inside = (s <= t < e) if s < e else (t >= s or t < e)
    assert (pr.window_start_date(when, s, e) is not None) == inside

# ---------------- NC (BX45..BX48) ----------------
def test_BX45_nc_zero_tax():
    b, liab, val = nc.nc_bill([L("a", 2, "100")], prices_include_tax=False, mode="ZERO_TAX")
    assert b["grand_total"] == D("0.00") and b["tax_total"] == D("0.00") and liab == D("0.00") and val == D("200.00")
def test_BX46_nc_tax_on_list_price_exclusive():
    b, liab, val = nc.nc_bill([L("a", 2, "100"), L("b", 1, "50", [("IGST", D("18"))])], prices_include_tax=False, mode="TAX_ON_LIST_PRICE")
    assert b["grand_total"] == D("0.00") and liab == D("10.00") + D("9.00")
def test_BX47_nc_tax_on_list_price_inclusive():
    b, liab, _ = nc.nc_bill([L("a", 1, "105", [("GST", D("5"))])], prices_include_tax=True, mode="TAX_ON_LIST_PRICE")
    assert liab == D("5.00") and b["grand_total"] == D("0.00")
def test_BX48_nc_unknown_mode():
    with pytest.raises(ValueError): nc.nc_bill([L("a", 1, "1")], prices_include_tax=False, mode="X")

# ---------------- KDS (BX50..BX55) ----------------
def test_BX50_all_pairs_match_db_trigger_list():
    ok = {(a, b) for a in kds.STATES for b in kds.STATES if a != b and kds.can_move(a, b)}
    assert ok == {("NEW","PREPARING"),("NEW","READY"),("PREPARING","READY"),("READY","SERVED"),("PREPARING","NEW"),("READY","PREPARING"),("SERVED","READY")}
def test_BX51_illegal_moves():
    for a, b in [("NEW", "SERVED"), ("PREPARING", "SERVED"), ("SERVED", "NEW"), ("SERVED", "PREPARING"), ("READY", "NEW")]:
        with pytest.raises(ValueError, match="ILLEGAL_KITCHEN_TRANSITION"): kds.move(a, b)
def test_BX52_bump_then_recall_roundtrip():
    s = "NEW"
    for _ in range(3): s = kds.bump(s)
    assert s == "SERVED" and kds.bump(s) == "SERVED" and kds.recall(kds.recall(s)) == "PREPARING"
    for a in kds.STATES: assert kds.can_move(a, kds.bump(a)) and kds.can_move(a, kds.recall(a))
def test_BX53_sla_colours():
    t0 = datetime(2026, 1, 1, 12, 0); f = lambda m, s="NEW": kds.sla_colour(s, t0, t0 + timedelta(minutes=m), 10, 20)
    assert (f(9.9), f(10), f(19.9), f(20), f(5, "READY")) == ("GREEN", "AMBER", "AMBER", "RED", "GREY")
def test_BX54_expo_ready():
    assert kds.expo_ready(["READY", "READY"]) and not kds.expo_ready(["READY", "PREPARING"]) and not kds.expo_ready(["SERVED"]) and not kds.expo_ready([])
@given(path=st.lists(st.sampled_from(kds.STATES), max_size=30))
def test_BX55_prop_random_walk_only_legal_moves_never_leave_states(path):
    s = "NEW"
    for n in path:
        if kds.can_move(s, n): s = kds.move(s, n)
    assert s in kds.STATES

# ---------------- shifts (BX60..BX66) ----------------
def test_BX60_expected_and_variance():
    e = shift.expected_cash(D("1000"), cash_payments=D("5000"), cash_refunds=D("200"), pay_ins=D("100"), pay_outs=D("300"), drops=D("4000"))
    assert e == D("1600.00") and shift.variance(D("1590"), e) == D("-10.00")
def test_BX61_tips_and_credit_settlements_count():
    assert shift.expected_cash(D(0), cash_tips=D("30"), cash_credit_settlements=D("70")) == D("100")
def test_BX62_close_and_double_close():
    s = dict(status="OPEN", opening_float=D("500"), flows=dict(cash_payments=D("100")))
    c = shift.close(s, D("600")); assert c["status"] == "CLOSED" and c["variance"] == D("0.00")
    with pytest.raises(ValueError): shift.close(c, D(1))
def test_BX63_one_open_shift_rules():
    o = [dict(cashier_id="u1", device_id="d1")]
    assert shift.can_open(o, "u1")[1] == "SHIFT_ALREADY_OPEN_CASHIER" and shift.can_open(o, "u2", "d1")[1] == "SHIFT_ALREADY_OPEN_DEVICE" and shift.can_open(o, "u2", "d2")[0]
def test_BX64_day_close_needs_all_closed():
    assert shift.can_close_day([dict(status="CLOSED")]) and not shift.can_close_day([dict(status="CLOSED"), dict(status="OPEN")])
@given(op=dec("0", "5000"), flows=st.lists(st.tuples(st.sampled_from(["cp", "cr", "pi", "po", "dr"]), dec("0", "2000")), max_size=40))
@settings(max_examples=200, deadline=None)
def test_BX65_prop_expected_is_running_sum_and_variance_zero_when_counted_equals(op, flows):
    names = dict(cp="cash_payments", cr="cash_refunds", pi="pay_ins", po="pay_outs", dr="drops")
    tot = {v: D("0.00") for v in names.values()}; run = D(op)
    for k, a in flows:
        tot[names[k]] += a; run += a if k in ("cp", "pi") else -a
    e = shift.expected_cash(op, **tot)
    assert e == run and shift.variance(e, e) == 0
@given(op=dec("0", "500"), counted=dec("0", "9000"), cp=dec("0", "9000"))
def test_BX66_prop_variance_sign(op, counted, cp):
    e = shift.expected_cash(op, cash_payments=cp); v = shift.variance(counted, e)
    assert v == counted - e and (v > 0) == (counted > e)

# ---------------- credit (BX70..BX78) ----------------
T = date(2026, 11, 1)
def test_BX70_limit_boundary():
    assert credit.can_charge(D("1000"), D("900"), D("100")) == (True, None)
    assert credit.can_charge(D("1000"), D("900"), D("100.01")) == (False, "CREDIT_LIMIT_EXCEEDED")
    assert credit.can_charge(D("1000"), D("900"), D("100.01"), manager_override=True) == (True, "OVERRIDE")
    assert credit.can_charge(D("0"), D("0"), D("1")) == (False, "CREDIT_LIMIT_EXCEEDED")
def test_BX71_balance_and_settle():
    e = [credit.charge("b1", D("300"), T), credit.charge("b2", D("200"), T), credit.payment(D("100"), T), credit.credit_note(D("50"), T)]
    assert credit.balance(e) == D("350") and credit.balance(credit.settle_all(e, T)) == D("0")
def test_BX72_adjustment_needs_reason():
    with pytest.raises(ValueError): credit.adjustment(D("10"), T, "ab")
def test_BX73_aging_fifo():
    e = [credit.charge("b1", D("100"), date(2026, 8, 1)), credit.charge("b2", D("100"), date(2026, 10, 1)), credit.charge("b3", D("100"), date(2026, 11, 20)),
         credit.payment(D("120"), date(2026, 11, 21))]
    b, adv = credit.aging(e, date(2026, 11, 25))
    assert b["90+"] == D("0") and b["31-60"] == D("80") and b["0-30"] == D("100") and adv == 0 and sum(b.values()) == credit.balance(e)
def test_BX74_aging_overpayment_is_advance():
    b, adv = credit.aging([credit.charge("b", D("50"), T), credit.payment(D("80"), T)], T)
    assert sum(b.values()) == 0 and adv == D("30")
@given(items=st.lists(st.tuples(st.sampled_from(["C", "P", "N"]), dec("0.01", "800"), st.integers(0, 200)), max_size=40))
@settings(max_examples=200, deadline=None)
def test_BX75_prop_ledger(items):
    es = []
    for k, a, d in items:
        on = T + timedelta(days=d)
        es.append(credit.charge("b", a, on) if k == "C" else credit.payment(a, on) if k == "P" else credit.credit_note(a, on))
    bal = credit.balance(es)
    assert bal == sum((e["amount"] for e in es), D("0.00"))
    b, adv = credit.aging(es, T + timedelta(days=400))
    assert sum(b.values()) - adv == bal and all(v >= 0 for v in b.values()) and adv >= 0
    if bal > 0: assert credit.balance(credit.settle_all(es, T)) == 0

# ---------------- credit notes (BX80..BX92) ----------------
def stored(bill_line):
    comps = [(n, r, bill_line["taxable"], t) for n, r, t in bill_line["comps"]]
    return dict(qty=bill_line["qty"], gross=bill_line["gross"], discount=bill_line["discount"], taxable=bill_line["taxable"], tax=bill_line["tax"], total=bill_line["total"], comps=comps)
def bill_of(lines, **kw):
    r = calculate(lines, prices_include_tax=kw.pop("inc", False), **kw); return r, [stored(l) for l in r["lines"]]
def test_BX80_partial_refund_proportional():
    r, ls = bill_of([L("a", 4, "100", [("GST", D("5"))])], round_off_mode="NONE")
    x = cn.refund_line(ls[0], cn.zero_state(1), D(1))
    assert x["taxable"] == D("100.00") and x["tax"] == D("5.00") and x["total"] == D("105.00") and x["comp_tax"] == [D("5.00")]
def test_BX81_full_refund_equals_original_exactly_after_partials():
    r, ls = bill_of([L("a", 3, "33.33", GST5)], discount=("AMOUNT", D("7.77")), round_off_mode="NONE")
    o = ls[0]; stt = cn.zero_state(2)
    for q in (D(1), D(1), D(1)):
        x = cn.refund_line(o, stt, q); stt = cn.add_state(stt, x)
    assert (stt["taxable"], stt["tax"], stt["total"], stt["qty"]) == (o["taxable"], o["tax"], o["total"], o["qty"])
    assert stt["comps"] == [c[3] for c in o["comps"]]
def test_BX82_over_quantity_rejected():
    r, ls = bill_of([L("a", 2, "10")])
    with pytest.raises(ValueError, match="REFUND_EXCEEDS_QUANTITY"): cn.refund_line(ls[0], cn.zero_state(2), D(3))
    x = cn.refund_line(ls[0], cn.zero_state(2), D(2)); st_ = cn.add_state(cn.zero_state(2), x)
    with pytest.raises(ValueError, match="REFUND_EXCEEDS_QUANTITY"): cn.refund_line(ls[0], st_, D("0.001"))
def test_BX83_header_round_down_then_final_note_returns_remainder():
    r, ls = bill_of([L("a", 2, "100.40", [])])             # total 200.80 -> grand 201
    o = ls[0]; s0 = cn.zero_state(0)
    x1 = cn.refund_line(o, s0, D(1)); h1 = cn.credit_note_total([x1], bill_grand_total=r["grand_total"], refunded_grand_so_far=D(0),
                                                                  bill_total_before_round_off=r["total_before_round_off"], refunded_before_round_so_far=D(0))
    assert h1["grand_total"] == D("100.00") and not h1["complete"]
    s1 = cn.add_state(s0, x1); x2 = cn.refund_line(o, s1, D(1))
    h2 = cn.credit_note_total([x2], bill_grand_total=r["grand_total"], refunded_grand_so_far=h1["grand_total"],
                              bill_total_before_round_off=r["total_before_round_off"], refunded_before_round_so_far=s1["total"])
    assert h2["complete"] and h1["grand_total"] + h2["grand_total"] == r["grand_total"] == D("201.00")
def test_BX84_too_small_refused():
    with pytest.raises(ValueError, match="REFUND_TOO_SMALL"):
        cn.credit_note_total([dict(total=D("0.40"))], bill_grand_total=D("200"), refunded_grand_so_far=D(0), bill_total_before_round_off=D("200"), refunded_before_round_so_far=D(0))
def test_BX85_refund_destination():
    assert cn.refund_destination("CASH") == "DRAWER" and cn.refund_destination("UPI") == "MANUAL" and cn.refund_destination("ON_ACCOUNT", "c") == "LEDGER"
    with pytest.raises(ValueError): cn.refund_destination("ON_ACCOUNT")
def test_BX86_inclusive_price_bill_refund():
    r, ls = bill_of([L("a", 3, "105", [("GST", D("5"))])], inc=True, round_off_mode="NONE")
    a = cn.refund_line(ls[0], cn.zero_state(1), D(1)); b = cn.refund_line(ls[0], cn.add_state(cn.zero_state(1), a), D(2))
    assert a["total"] + b["total"] == ls[0]["total"] and a["tax"] + b["tax"] == ls[0]["tax"]

@st.composite
def bills(draw):
    n = draw(st.integers(1, 5)); lines = []
    for i in range(n):
        comps = draw(st.sampled_from([[], [("GST", D("5"))], GST5, [("CGST", D("9")), ("SGST", D("9"))], [("GST", D("18")), ("CESS", D("12"))]]))
        lines.append(L(f"l{i}", draw(st.integers(1, 6)), draw(dec("0.01", "999")), comps))
    disc = draw(st.sampled_from([None, ("PERCENT", D("10")), ("PERCENT", D("33.33")), ("AMOUNT", D("5.55"))]))
    inc = draw(st.booleans()); ro = draw(st.sampled_from(["NONE", "NEAREST_1"]))
    return lines, disc, inc, ro
@given(bills(), st.randoms(use_true_random=False))
@settings(max_examples=250, deadline=None)
def test_BX90_prop_refund_everything_in_random_pieces_equals_original(b, rnd):
    lines, disc, inc, ro = b
    try: r = calculate(lines, prices_include_tax=inc, discount=disc, round_off_mode=ro)
    except ValueError: return
    ls = [stored(l) for l in r["lines"]]
    sts = [cn.zero_state(len(o["comps"])) for o in ls]
    grand_done = D("0.00"); pre_done = D("0.00")
    pieces = [(i, o["qty"]) for i, o in enumerate(ls)]
    work = []
    for i, q in pieces:
        left = q; 
        while left > 0:
            take = left if left == 1 or rnd.random() < .4 else D(rnd.randint(1, int(left)))
            take = min(take, left); work.append((i, take)); left -= take
    rnd.shuffle(work)
    notes = []
    while work:
        k = rnd.randint(1, len(work)); batch, work = work[:k], work[k:]
        got = []; 
        for i, q in batch:
            x = cn.refund_line(ls[i], sts[i], q); sts[i] = cn.add_state(sts[i], x); got.append(x)
        pre_before = pre_done
        try:
            h = cn.credit_note_total(got, bill_grand_total=r["grand_total"], refunded_grand_so_far=grand_done, bill_total_before_round_off=r["total_before_round_off"],
                                     refunded_before_round_so_far=pre_done, round_off_mode=ro)
        except ValueError as e:
            assert str(e) == "REFUND_TOO_SMALL" and not work is None; return        # legal refusal of a sub-rupee partial note
        pre_done += h["total_before_round_off"]; grand_done += h["grand_total"]
        assert grand_done <= r["grand_total"]                                            # property: sum of refunds <= original
    for o, s_ in zip(ls, sts):
        assert (s_["taxable"], s_["tax"], s_["total"], s_["qty"]) == (o["taxable"], o["tax"], o["total"], o["qty"])
        assert s_["comps"] == [c[3] for c in o["comps"]]
    assert grand_done == r["grand_total"] and pre_done == r["total_before_round_off"]     # refunding everything equals the original EXACTLY
@given(bills(), st.data())
@settings(max_examples=150, deadline=None)
def test_BX91_prop_partial_refunds_never_exceed_line(b, data):
    lines, disc, inc, ro = b
    try: r = calculate(lines, prices_include_tax=inc, discount=disc, round_off_mode=ro)
    except ValueError: return
    o = stored(r["lines"][0]); s_ = cn.zero_state(len(o["comps"]))
    for _ in range(6):
        left = o["qty"] - s_["qty"]
        if left <= 0: break
        q = D(data.draw(st.integers(1, int(left))))
        x = cn.refund_line(o, s_, q); s_ = cn.add_state(s_, x)
        assert s_["taxable"] <= o["taxable"] and s_["tax"] <= o["tax"] and s_["total"] <= o["total"] and all(c >= 0 for c in x["comp_tax"]) and sum(x["comp_tax"], D(0)) == x["tax"]
