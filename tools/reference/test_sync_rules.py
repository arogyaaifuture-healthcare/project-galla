import random
from datetime import datetime, timedelta, timezone
import pytest
from hypothesis import given, settings, strategies as st
from sync_rules import *

def feed(seqs, last=0, gaps=None):
    gaps = gaps or []
    outs = []
    for s in seqs:
        last, gaps, o = register_seq(last, gaps, s); outs.append(o)
    return last, gaps, outs

def test_OF1_in_order_no_gaps():
    last, gaps, outs = feed([1, 2, 3]); assert (last, gaps, set(outs)) == (3, [], {"IN_ORDER"})
def test_OF2_skip_opens_gap_and_late_arrival_fills_it():
    last, gaps, outs = feed([1, 4]); assert last == 4 and [g.key() for g in gaps] == [(2, 3, "OPEN", "NOT_YET_SYNCED")]
    last, gaps, o = register_seq(last, gaps, 2); assert o == "GAP_FILLED" and [g.key()[:2] for g in gaps] == [(3, 3)]
    last, gaps, o = register_seq(last, gaps, 3); assert o == "GAP_FILLED" and gaps == [] and last == 4
def test_OF3_gap_splits_in_the_middle():
    last, gaps, _ = feed([1, 10]); last, gaps, _ = register_seq(last, gaps, 5)
    assert [g.key()[:2] for g in gaps] == [(2, 4), (6, 9)]
def test_OF4_duplicate_seq_is_detected():
    last, gaps, outs = feed([1, 2, 2, 1]); assert outs == ["IN_ORDER", "IN_ORDER", "DUPLICATE", "DUPLICATE"] and gaps == []
def test_OF5_arrival_into_explained_gap_is_flagged_but_accepted():
    last, gaps, _ = feed([1, 5]); gaps[0].status = "EXPLAINED"
    last, gaps, o = register_seq(last, gaps, 3)
    assert o == "LATE_IN_EXPLAINED_GAP" and [(g.lo, g.hi, g.status) for g in gaps] == [(2, 2, "EXPLAINED"), (4, 4, "EXPLAINED")]
def test_OF6_resume_after_storage_loss_never_reuses_numbers():
    nxt, gap = resume_seq(last_synced=40, last_reported=47, skip=10); assert nxt == 58 and gap == (41, 57)
    nxt, gap = resume_seq(40, None, 10); assert nxt == 51 and gap == (41, 50)
    nxt, gap = resume_seq(0, None, 0); assert nxt == 1 and gap is None
UTC = timezone.utc
T0 = datetime(2026, 11, 23, 10, 0, tzinfo=UTC)
def test_OF7_offline_session_expiry():
    assert session_state(T0, T0 + timedelta(hours=71, minutes=59), 72)[0] == "OFFLINE_ACTIVE"
    assert session_state(T0, T0 + timedelta(hours=72), 72) [:3:2] == ("OFFLINE_LOCKED", "SESSION_EXPIRED")
def test_OF8_offline_never_outlives_subscription_deadline():
    sub = T0 + timedelta(hours=10)
    assert session_state(T0, T0 + timedelta(hours=11), 72, sub_deadline=sub)[0] == "OFFLINE_LOCKED"
    assert session_state(T0, T0 + timedelta(hours=9), 72, sub_deadline=sub)[0] == "OFFLINE_ACTIVE"
def test_OF9_clock_rolled_back_locks_the_terminal():
    st_, _, why = session_state(T0, T0 + timedelta(hours=1), 72, last_seen_client=T0 + timedelta(hours=3)); assert (st_, why) == ("OFFLINE_LOCKED", "CLOCK_MOVED_BACKWARDS")
    assert session_state(T0, T0 + timedelta(hours=1), 72, last_seen_client=T0 + timedelta(hours=1, minutes=4))[0] == "OFFLINE_ACTIVE"
def test_OF10_clock_skew_flag():
    assert clock_skew(T0 + timedelta(minutes=15), T0) == (900, False)
    assert clock_skew(T0 + timedelta(minutes=15, seconds=1), T0)[1] is True
    assert clock_skew(T0 - timedelta(hours=1), T0) == (-3600, True)
def test_OF11_quick_pin():
    salt, it, h = pin_hash("4821", iterations=1000)
    assert pin_verify("4821", salt, it, h) and not pin_verify("4822", salt, it, h)
    for bad in ("12", "1234567", "12a4", ""):
        with pytest.raises(ValueError): pin_hash(bad, iterations=1000)
    f = 0
    for _ in range(4): f, s = pin_attempt(f, False); assert s == "OK"
    f, s = pin_attempt(f, False); assert s == "PIN_DISABLED"
    f, s = pin_attempt(3, True); assert (f, s) == (0, "OK")
def test_OF12_backoff():
    assert [backoff_seconds(a) for a in (1, 2, 3, 4, 5, 6, 7, 8)] == [5, 10, 20, 40, 80, 160, 300, 300]
def mk(i, deps=(), status="PENDING", attempts=0): return dict(id=i, deps=list(deps), status=status, attempts=attempts)
def test_OF13_poison_command_parks_and_blocks_only_dependants():
    q = [mk("order1"), mk("bill1", ["order1"]), mk("pay1", ["bill1"]), mk("order2"), mk("bill2", ["order2"])]
    q[0] = dict(q[0], status="PARKED")            # order1 is poison
    run = {c["id"] for c in next_runnable(q)}
    assert run == {"order2"}                       # bill1/pay1 blocked (dependants); order2 independent
    q[3]["status"] = "DONE"; assert {c["id"] for c in next_runnable(q)} == {"bill2"}
def test_OF14_failures_park_after_max_attempts_or_when_not_retryable():
    c = mk("x")
    for _ in range(MAX_ATTEMPTS - 1): c = record_failure(c); assert c["status"] == "PENDING"
    assert record_failure(c)["status"] == "PARKED"
    assert record_failure(mk("y"), retryable=False)["status"] == "PARKED"
def test_OF15_conflict_classification_never_rejects():
    assert classify({}) == []
    got = dict(classify(dict(calc_mismatch=1, table_conflict=1, price_changed=1, day_closed=1, user_disabled=1, clock_skew=1, gap_opened=1, inactive_items=1)))
    assert got["CALC_MISMATCH"] == "CRITICAL" and got["TABLE_CONFLICT"] == "WARN" and got["PRICE_CHANGED"] == "INFO" and len(got) == 8
DEV = dict(series_code="A", current_schema=3)
def bill(series="A", seq=7, number=None): return dict(type="BILL_GENERATE", schema_version=3, bill=dict(series=series, fy="2026-27", seq=seq, number=number or f"{series}-2026-27-{seq:06d}"))
def test_OF16_only_protocol_violations_are_rejected():
    assert protocol_error(bill(), DEV) is None
    assert protocol_error(bill(), None) == "UNKNOWN_DEVICE"
    assert protocol_error(bill(series="C"), DEV) == "SERIES_MISMATCH"
    assert protocol_error(bill(number="A-2026-27-7"), DEV) == "BILL_NUMBER_MALFORMED"
    assert protocol_error(dict(bill(), schema_version=2), DEV) is None            # last two versions accepted
    assert protocol_error(dict(bill(), schema_version=1), DEV) == "UNSUPPORTED_SCHEMA_VERSION"
    assert protocol_error(dict(bill(), schema_version=4), DEV) == "UNSUPPORTED_SCHEMA_VERSION"
def test_OF17_revoked_device_final_sync_window():
    rev = T0
    assert revoked_device_accepts(rev - timedelta(hours=1), rev, rev + timedelta(days=6))
    assert not revoked_device_accepts(rev - timedelta(hours=1), rev, rev + timedelta(days=8))
    assert not revoked_device_accepts(rev + timedelta(minutes=1), rev, rev + timedelta(days=1))
def test_OF18_idempotent_push_and_dependency_wait():
    s = Server()
    pay = dict(id="p1", type="PAYMENT_ADD", dep="b1", payment="pay1", bill=("A", "2026-27", 1), amount="50.00")
    b = dict(id="b1", type="BILL_GENERATE", series="A", fy="2026-27", seq=1, total="50.00")
    assert s.push(pay) == "WAITING" and s.state()["payments"] == {}
    assert s.push(b) == "APPLIED" and "pay1" in s.state()["payments"] and s.state()["waiting"] == 0
    assert s.push(b) == "DUPLICATE" and s.push(pay) == "DUPLICATE"
def test_OF19_table_conflict_is_independent_of_arrival_order():
    o = {"a": dict(table="T1", t_open=10, t_close=None), "b": dict(table="T1", t_open=12, t_close=None), "c": dict(table="T2", t_open=11, t_close=None)}
    assert table_flags(o) == {"b"}
    o["a"]["t_close"] = 11; assert table_flags(o) == set()          # first order closed before the second opened → no conflict
    o["a"]["t_close"] = 13; assert table_flags(o) == {"b"}

# ---- property test: any permutation / duplication of a valid command stream gives the same final server state ----
@st.composite
def streams(draw):
    n_dev = draw(st.integers(1, 3)); cmds = []; cid = 0
    for d in range(n_dev):
        ser = "ACD"[d]; seqs = list(range(1, draw(st.integers(1, 6)) + 1))
        for sq in seqs:
            oid, bid, cid_b = f"o{d}{sq}", f"b{d}{sq}", f"cb{d}{sq}"
            t = draw(st.integers(0, 50)); table = draw(st.sampled_from(["T1", "T2", "T3"]))
            cmds.append(dict(id=f"co{d}{sq}", type="ORDER_OPEN", order=oid, table=table, t=t, dev_no=sq))
            cmds.append(dict(id=cid_b, type="BILL_GENERATE", dep=f"co{d}{sq}", series=ser, fy="2026-27", seq=sq, total=str(draw(st.integers(1, 999)))))
            cmds.append(dict(id=f"cp{d}{sq}", type="PAYMENT_ADD", dep=cid_b, payment=f"p{d}{sq}", bill=(ser, "2026-27", sq), amount="1"))
            cmds.append(dict(id=f"cc{d}{sq}", type="ORDER_CLOSE", dep=f"cp{d}{sq}", order=oid, t=t + draw(st.integers(1, 30))))
    return cmds
def run(cmds):
    s = Server()
    for c in cmds: s.push(c)
    return s.state()
@settings(max_examples=300, deadline=None)
@given(streams(), st.integers(), st.integers(0, 3))
def test_OF20_property_any_order_and_duplicates_same_final_state(cmds, seed, dups):
    base = run(cmds)
    r = random.Random(seed); shuffled = cmds[:]; r.shuffle(shuffled)
    shuffled += [r.choice(cmds) for _ in range(dups * 3)]; r.shuffle(shuffled)
    got = run(shuffled)
    assert got == base
    assert got["waiting"] == 0 and all(g == [] for g in got["gaps"].values())     # every number arrived → no gap left, nothing stuck waiting
    assert len(got["bills"]) == sum(1 for c in cmds if c["type"] == "BILL_GENERATE")
