from datetime import datetime, timedelta
from decimal import Decimal as D
import itertools, random
from hypothesis import given, strategies as st, settings
from payment_intent import *

T0 = datetime(2026, 11, 25, 12, 0, 0)
EXP = T0 + timedelta(minutes=15)
IT = Intent(amount=D("340.00"), expires_at=EXP, pending_marked=True)
ok = lambda i="e1", at=T0 + timedelta(minutes=3), amt=D("340.00"): Event(i, "SUCCESS", amt, at)

def test_P1_success_in_time_applies():
    r = resolve(IT, [ok()]); assert (r.status, r.apply_to_bill, r.attention) == ("SUCCESS", True, None)
def test_P2_duplicate_delivery_of_same_event_is_noop():
    assert resolve(IT, [ok(), ok(), ok()]) == resolve(IT, [ok()])
def test_P3_two_different_events_both_exact_means_money_twice():
    r = resolve(IT, [ok("a"), ok("b", T0 + timedelta(minutes=4))])
    assert r.status == "SUCCESS" and r.apply_to_bill and r.attention == "DUPLICATE_PAYMENT"
    assert r.outcomes == {"a": "APPLIED", "b": "DUPLICATE_PAYMENT"}
def test_P4_amount_mismatch_leaves_intent_open():
    r = resolve(IT, [ok(amt=D("300.00"))]); assert (r.status, r.attention, r.apply_to_bill) == ("PENDING", "AMOUNT_MISMATCH", False)
    assert r.received_amount == D("300.00")
def test_P5_late_success_after_expiry_is_flagged_not_applied():
    r = resolve(IT, [Event("t", "EXPIRE_TICK"), ok(at=EXP + timedelta(minutes=1))])
    assert (r.status, r.attention, r.apply_to_bill) == ("EXPIRED", "LATE_SUCCESS", False)
def test_P6_in_time_success_delivered_after_expiry_tick_still_wins():
    r = resolve(IT, [Event("t", "EXPIRE_TICK"), ok(at=EXP - timedelta(seconds=1))])
    assert (r.status, r.apply_to_bill, r.attention) == ("SUCCESS", True, None)
def test_P7_boundary_exactly_at_expiry_counts_as_in_time():
    assert resolve(IT, [ok(at=EXP)]).status == "SUCCESS"
    assert resolve(IT, [ok(at=EXP + timedelta(microseconds=1))]).attention == "LATE_SUCCESS"
def test_P8_failed_then_in_time_success_succeeds_failed_after_success_ignored():
    f = Event("f", "FAILED", None, T0)
    assert resolve(IT, [f, ok()]).status == "SUCCESS"
    assert resolve(IT, [ok(), f]).status == "SUCCESS"
def test_P9_failed_alone_and_failed_beats_expire_tick():
    assert resolve(IT, [Event("f", "FAILED")]).status == "FAILED"
    assert resolve(IT, [Event("t", "EXPIRE_TICK"), Event("f", "FAILED")]).status == "FAILED"
def test_P10_bill_already_paid_manually_is_duplicate_payment_not_applied():
    r = resolve(IT, [ok()], BillCtx("PAID", D("0.00")))
    assert (r.status, r.attention, r.apply_to_bill) == ("SUCCESS", "DUPLICATE_PAYMENT", False)
def test_P11_void_bill_flagged():
    assert resolve(IT, [ok()], BillCtx("VOID")).attention == "BILL_NOT_PAYABLE"
def test_P12_bill_remaining_smaller_than_intent_is_not_applied():
    assert resolve(IT, [ok()], BillCtx("GENERATED", D("100.00"))).attention == "DUPLICATE_PAYMENT"
def test_P13_no_events_states():
    assert resolve(Intent(D("1"), EXP), []).status == "CREATED"
    assert resolve(IT, []).status == "PENDING"
    assert resolve(IT, [Event("t", "EXPIRE_TICK")]).status == "EXPIRED"
def test_P14_amount_compared_exactly_not_as_float():
    assert resolve(IT, [ok(amt=D("340.0"))]).apply_to_bill          # Decimal 340.0 == 340.00
    assert not resolve(IT, [ok(amt=D("340.01"))]).apply_to_bill
def test_P15_exact_success_plus_wrong_amount_event():
    r = resolve(IT, [ok("a"), ok("b", amt=D("10.00"))]); assert r.apply_to_bill and r.outcomes["b"] == "AMOUNT_MISMATCH"
def test_P16_transitions():
    assert can_transition("CREATED", "PENDING") and can_transition("PENDING", "SUCCESS")
    assert not can_transition("SUCCESS", "FAILED") and not can_transition("SUCCESS", "EXPIRED")
    assert not can_transition("PENDING", "CREATED") and can_transition("EXPIRED", "SUCCESS")
def test_P17_manual_confirm_guard():
    assert manual_confirm_allowed("PENDING", BillCtx(), D("340"), D("340")) == (True, "EXPIRE_INTENT")
    assert manual_confirm_allowed("SUCCESS", BillCtx("PAID", D("0")), D("340"), D("340"))[0] is False
    assert manual_confirm_allowed("PENDING", BillCtx("GENERATED", D("340")), D("340"), D("341"))[0] is False
def test_P18_hmac():
    import hmac, hashlib
    body = b'{"id":"x"}'; sig = hmac.new(b"k", body, hashlib.sha256).hexdigest()
    assert verify_hmac_sha256_hex(b"k", body, sig) and verify_hmac_sha256_hex(b"k", body, sig.upper())
    assert not verify_hmac_sha256_hex(b"k", body + b" ", sig) and not verify_hmac_sha256_hex(b"k", body, "") and not verify_hmac_sha256_hex(b"z", body, sig)
def test_P19_settlement_matching():
    m = match_settlement_lines([("t1", D("340.00")), ("t2", D("100.00")), ("t3", D("5.00"))],
                               {"t1": ("i1", D("340.00"), "SUCCESS"), "t2": ("i2", D("90.00"), "SUCCESS")})
    assert [x[1] for x in m] == ["MATCHED", "AMOUNT_DIFF", "UNMATCHED"]
    assert settlement_check(D("340.00"), D("6.80"), D("333.20")) and not settlement_check(D("340"), D("6.80"), D("333.21"))

# ---------------- property tests: any permutation / duplication of provider events -> same final state
ev_strat = st.one_of(
    st.builds(lambda i, m, a: Event(f"s{i}", "SUCCESS", D("340.00") if a else D("340.01"), T0 + timedelta(minutes=m)),
              st.integers(0, 3), st.integers(0, 30), st.booleans()),
    st.builds(lambda i: Event(f"f{i}", "FAILED", None, T0), st.integers(0, 2)),
    st.just(Event("tick", "EXPIRE_TICK")),
    st.builds(lambda i: Event(f"o{i}", "OTHER"), st.integers(0, 2)))
bills = st.sampled_from([BillCtx(), BillCtx("PAID", D("0")), BillCtx("VOID")])

def canon(evs):   # events with the same id must be identical in a real system (provider retries)
    d = {}
    for e in evs: d.setdefault(e.event_id, e)
    return list(d.values())

@settings(max_examples=400, deadline=None)
@given(st.lists(ev_strat, max_size=7), st.randoms(use_true_random=False), bills, st.booleans())
def test_PP1_permutation_and_duplication_invariant(evs, rnd, bill, pm):
    it = Intent(D("340.00"), EXP, pm)
    evs = canon(evs)
    base = resolve(it, evs, bill)
    shuffled = evs + [rnd.choice(evs) for _ in evs] if evs else []
    rnd.shuffle(shuffled)
    assert resolve(it, shuffled, bill) == base

@settings(max_examples=300, deadline=None)
@given(st.lists(ev_strat, max_size=7), bills)
def test_PP2_money_applied_at_most_once_and_only_when_exact(evs, bill):
    evs = canon(evs); r = resolve(Intent(D("340.00"), EXP, True), evs, bill)
    assert list(r.outcomes.values()).count("APPLIED") <= 1
    if r.apply_to_bill:
        assert r.status == "SUCCESS" and r.received_amount == D("340.00") and bill.status == "GENERATED"
    if r.status == "SUCCESS": assert r.received_amount == D("340.00")        # mirrors the DB CHECK
    assert r.status in STATES

@settings(max_examples=300, deadline=None)
@given(st.lists(ev_strat, max_size=6), ev_strat, bills)
def test_PP3_adding_events_never_moves_state_backwards_out_of_success(evs, extra, bill):
    it = Intent(D("340.00"), EXP, True); evs = canon(evs)
    a = resolve(it, evs, bill)
    b = resolve(it, canon(evs + [extra]), bill)
    if a.status == "SUCCESS": assert b.status == "SUCCESS"              # SUCCESS is terminal
