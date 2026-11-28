from datetime import datetime, timedelta
from decimal import Decimal as D
import pytest
from hypothesis import given, strategies as st
from external_order import *
N = datetime(2026,11,25,13,0,0)
L = lambda i, v="", q=1: Line(i, v, q, D("100"))
def test_A1_all_mapped_manual_accept_path():
    assert intake_decision([L("a")], {("a",""):"MAPPED"}, auto_accept=False) == "MAPPED"
def test_A2_auto_accept_needs_all_mapped():
    m = {("a",""):"MAPPED"}
    assert intake_decision([L("a")], m, auto_accept=True) == "AUTO_ACCEPT"
    assert intake_decision([L("a"), L("b")], m, auto_accept=True) == "NEEDS_MAPPING"
def test_A3_variant_has_its_own_mapping_no_fallback():
    assert intake_decision([L("a","large")], {("a",""):"MAPPED"}, auto_accept=True) == "NEEDS_MAPPING"
def test_A4_ignored_lines_skipped_but_order_of_only_ignored_lines_needs_a_human():
    m = {("fee",""):"IGNORED", ("a",""):"MAPPED"}
    assert classify_lines([L("fee"), L("a")], m)[1][0].ext_item_id == "fee"
    assert intake_decision([L("fee")], m, auto_accept=True) == "NEEDS_MAPPING"
def test_A5_store_closed_or_deadline_passed_never_auto_accepts():
    m = {("a",""):"MAPPED"}
    assert intake_decision([L("a")], m, auto_accept=True, store_open=False) == "MAPPED"
    assert intake_decision([L("a")], m, auto_accept=True, now=N, accept_by=N) == "EXPIRED"
def test_A6_empty_order():
    assert intake_decision([], {}, auto_accept=True) == "NEEDS_MAPPING"
def test_A7_sla():
    ab = accept_deadline(N, 180); assert ab == N + timedelta(seconds=180)
    assert sla_state(N, ab) == "OK" and sla_state(N + timedelta(seconds=130), ab) == "WARN" and sla_state(ab, ab) == "EXPIRED"
def test_A8_idempotent_receive_and_events():
    ib = Inbox()
    assert ib.receive("acc", "X1", {}, N, 180) == "STORED" and ib.receive("acc", "X1", {"changed": 1}, N, 180) == "DUPLICATE_IGNORED"
    assert ib.receive("acc2", "X1", {}, N, 180) == "STORED"               # same id under another account is another order
    assert ib.rows[("acc","X1")]["payload"] == {}                          # replay never overwrites the first payload
    assert ib.event("acc","X1","ev1") == "STORED" and ib.event("acc","X1","ev1") == "DUPLICATE_IGNORED"
def test_A9_machine():
    assert can_transition("MAPPED","ACCEPTED") and can_transition("ACCEPTED","PREPARING") and can_transition("READY","HANDED_OVER")
    assert not can_transition("RECEIVED","ACCEPTED")           # must be mapped first
    assert not can_transition("REJECTED","ACCEPTED") and not can_transition("HANDED_OVER","CANCELLED")
    assert not can_transition("EXPIRED","ACCEPTED")
def test_A10_move_and_replay():
    ib = Inbox(); ib.receive("a","1",{},N,60)
    assert ib.move("a","1","MAPPED") == "MOVED" and ib.move("a","1","MAPPED") == "NO_CHANGE"
    with pytest.raises(ValueError): ib.move("a","1","READY")
def test_A11_cancel_effects():
    assert cancel_effect("MAPPED") == "CANCEL_INBOX_ONLY" and cancel_effect("PREPARING") == "CANCEL_ORDER_AND_ALERT_KITCHEN"
    assert cancel_effect("HANDED_OVER") == "IGNORE" and cancel_effect("REJECTED") == "IGNORE"
def test_A12_reconcile_no_interpretation():
    r = reconcile([("HANDED_OVER",D("90.50")),("HANDED_OVER",D("100.00")),("HANDED_OVER",None),("CANCELLED",D("5"))], [D("190.00")])
    assert r == dict(expected=D("190.50"), received=D("190.00"), difference=D("-0.50"), orders_without_settlement_amount=1)
def test_A13_price_diff():
    assert price_diff(D("250.00"), D("260.00")) == D("10.00") and price_diff(D("1"), None) is None
@given(st.lists(st.sampled_from(STATUSES), max_size=12))
def test_AP1_terminal_states_are_sticky_and_no_edge_leaves_terminal(path):
    for t in TERMINAL: assert EDGES[t] == set()
    cur = "RECEIVED"
    for nxt in path:
        if can_transition(cur, nxt): cur = nxt
    assert cur in STATUSES
@given(st.lists(st.tuples(st.sampled_from("ab"), st.sampled_from(["1","2","3"])), max_size=20))
def test_AP2_receive_replay_stores_each_key_once(keys):
    ib = Inbox(); stored = sum(ib.receive(a, i, {}, N, 60) == "STORED" for a, i in keys)
    assert stored == len(set(keys)) == len(ib.rows)
