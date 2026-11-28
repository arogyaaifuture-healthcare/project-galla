from decimal import Decimal as D
from hypothesis import given, strategies as st
from loyalty import *

def test_L1_earn_floor():
    assert earn_points("199.99", 100) == 1 and earn_points("200", 100) == 2 and earn_points("0", 100) == 0 and earn_points("-5", 100) == 0
def test_L2_earn_fractional_rate():
    assert earn_points("100", "12.50") == 8
def test_L3_redemption_amount_rounding():
    assert redemption_amount(3, "0.333") == D("1.00") and redemption_amount(10, "1") == D("10.00")
def test_L4_max_redeemable_cap_percent():
    # bill 500, 50% cap = 250 rupees = 250 points at Rs1; balance 1000
    assert max_redeemable("500", 1000, "1", "50", 100) == 250
def test_L5_max_redeemable_balance_limits():
    assert max_redeemable("500", 120, "1", "50", 100) == 120
def test_L6_min_points_blocks():
    assert max_redeemable("500", 80, "1", "50", 100) == 0
def test_L7_zero_balance_or_bill():
    assert max_redeemable("500", 0, "1", "50", 0) == 0 and max_redeemable("0", 100, "1", "50", 0) == 0
def test_L8_point_worth_more_than_a_rupee():
    assert max_redeemable("100", 1000, "2", "100", 10) == 50
def test_L9_partial_refund_reverses_proportionally():
    # grand 500 -> earned 5; refund 250 -> net 250 -> target 2 -> reverse 3
    assert reversal_for_refund("500", "250", 5, 0, 100) == 3
    # refund the rest: net 0 -> target 0 -> reverse remaining 2
    assert reversal_for_refund("500", "500", 5, 3, 100) == 2
def test_L10_full_restore():
    assert restore_for_refund(100, "100", "100", 0) == 100
    assert restore_for_refund(100, "100", "40", 0) == 40 and restore_for_refund(100, "100", "100", 40) == 60
def test_L11_fifo_expiry_example():
    d = lambda n: n
    entries = [(0,'EARN',100,30),(0,'EARN',50,60),(10,'REDEEM',-120,None)]
    assert expiring_points(entries, 40) == 0       # batch 1 fully spent first
    assert expiring_points(entries, 70) == 30      # 30 left of batch 2
    assert expiring_points(entries, 20) == 0
def test_L12_cannot_spend_expired_batch():
    entries = [(0,'EARN',100,30),(0,'EARN',50,90),(40,'REDEEM',-20,None)]  # at day 40 batch1 is already expired, spend uses batch2
    assert expiring_points(entries, 50) == 100
def test_L13_no_expiry_never_expires():
    assert expiring_points([(0,'EARN',10,None),(0,'ADJUST',5,None)], 10**6) == 0

@given(st.decimals(min_value=D("0.01"), max_value=D("100000"), places=2), st.integers(1,50), st.integers(1,50))
def test_P1_redemption_never_exceeds_bill_or_cap(total, bal_k, rpp_k):
    rpp = D(rpp_k) / D(10)
    pts = max_redeemable(total, bal_k * 100, rpp, "50", 0)
    assert pts <= bal_k * 100
    assert redemption_amount(pts, rpp) <= total
    assert redemption_amount(pts, rpp) <= total * D("0.5") + rpp   # at most one point of rounding slack

@given(st.decimals(min_value=D("1"), max_value=D("50000"), places=2), st.lists(st.integers(1,100), min_size=1, max_size=6))
def test_P2_cumulative_refunds_keep_earn_equal_to_net(grand, cuts):
    spp = 100
    earned = earn_points(grand, spp); rev = 0; cum = D(0)
    total_cut = sum(cuts)
    for c in cuts:
        part = (grand * D(c) / D(total_cut)).quantize(D("0.01"))
        cum = min(grand, cum + part)
        rev += reversal_for_refund(grand, cum, earned, rev, spp)
        assert 0 <= rev <= earned
        assert earned - rev <= earn_points(grand - cum, spp) or grand - cum <= 0 and earned - rev == 0 or earned - rev == earn_points(grand - cum, spp)
    cum = grand
    rev += reversal_for_refund(grand, cum, earned, rev, spp)
    assert earned - rev == 0

@given(st.integers(1,5000), st.lists(st.integers(1,100), min_size=1, max_size=6))
def test_P3_restore_never_exceeds_and_full_refund_restores_all(redeemed, cuts):
    paid = D(redeemed); cum = D(0); got = 0; tc = sum(cuts)
    for c in cuts:
        cum = min(paid, cum + (paid * c / tc).quantize(D("0.01")))
        got += restore_for_refund(redeemed, paid, cum, got)
        assert got <= redeemed
    got += restore_for_refund(redeemed, paid, paid, got)
    assert got == redeemed

def test_L14_spendable_is_balance_minus_expired():
    entries = [(0,'EARN',100,30)]
    bal = 100
    assert bal - expiring_points(entries, 20) == 100      # before expiry everything is spendable
    assert bal - expiring_points(entries, 31) == 0        # after expiry (job not yet run) nothing is spendable

@given(st.lists(st.tuples(st.integers(0,100), st.sampled_from(['EARN','REDEEM']), st.integers(1,100), st.integers(1,100)), max_size=12), st.integers(0,200))
def test_P4_expiring_never_exceeds_balance(raw, now):
    """Rule under test: a redemption may use at most spendable = balance - expiring_points(now); the DB trigger only guards balance >= 0."""
    entries, bal = [], 0
    for ts, typ, pts, ttl in sorted(raw, key=lambda r: r[0]):
        if typ == 'EARN':
            entries.append((ts,'EARN',pts,ts+ttl)); bal += pts
        else:
            spendable = bal - expiring_points(entries, ts)
            take = min(pts, max(spendable, 0))
            if take > 0: entries.append((ts,'REDEEM',-take,None)); bal -= take
    e = expiring_points(entries, now)
    assert 0 <= e <= bal
