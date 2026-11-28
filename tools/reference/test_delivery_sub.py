from decimal import Decimal as D
from datetime import datetime, timezone as tz, timedelta
import pytest
from delivery_charge import *
from subscription import *
from bill_calculator import calculate
SL=[(D("0"),D("3"),D("30")),(D("3"),D("6"),D("50")),(D("6"),D("10"),D("80"))]
def U(*a): return datetime(*a, tzinfo=tz.utc)
# ---- delivery
def test_D1_haversine_equator_degree(): assert distance_km(0,0,0,1)==D("111.19")
def test_D2_factor(): assert distance_km(0,0,0,1,D("1.30"))==D("144.55")   # 111.1949*1.3=144.5534
def test_D3_flat(): assert delivery_charge("FLAT",flat=D("40"),subtotal_after_discount=D("100"))==D("40")
def test_D4_slab_boundaries():
    f=lambda d: delivery_charge("DISTANCE_SLABS",distance=D(d),slabs=SL)
    assert f("0.01")==D("30") and f("3.00")==D("30") and f("3.01")==D("50") and f("6.00")==D("50") and f("10.00")==D("80")
def test_D5_beyond_slabs(): 
    with pytest.raises(ChargeError,match="OUT_OF_DELIVERY_RANGE"): delivery_charge("DISTANCE_SLABS",distance=D("10.01"),slabs=SL)
def test_D6_free_above_inclusive():
    kw=dict(distance=D("4"),slabs=SL,free_above=D("500"))
    assert delivery_charge("DISTANCE_SLABS",subtotal_after_discount=D("500.00"),**kw)==D("0.00")
    assert delivery_charge("DISTANCE_SLABS",subtotal_after_discount=D("499.99"),**kw)==D("50")
def test_D7_radius_beats_free_above():
    with pytest.raises(ChargeError,match="OUT_OF_DELIVERY_RANGE"):
        delivery_charge("FLAT",flat=D("40"),distance=D("12"),max_radius=D("10"),free_above=D("100"),subtotal_after_discount=D("900"))
def test_D8_unknown_distance_slabs():
    with pytest.raises(ChargeError,match="DELIVERY_DISTANCE_UNKNOWN"): delivery_charge("DISTANCE_SLABS",slabs=SL)
def test_D9_override_bypasses_all(): assert delivery_charge("DISTANCE_SLABS",distance=D("99"),slabs=SL,override=D("0.00"))==D("0.00")
def test_D10_end_to_end_with_bill():
    ch=delivery_charge("DISTANCE_SLABS",distance=D("4.2"),slabs=SL,subtotal_after_discount=D("180"))
    T5=[("CGST",D("2.5")),("SGST",D("2.5"))]
    r=calculate([dict(id="1",name="A",qty=D(1),unit_price=D(200),comps=[])],prices_include_tax=False,discount=("PERCENT",D(10)),
                delivery_charge=ch,delivery_comps=T5)
    assert ch==D("50")
    assert r["total_before_round_off"]==D("232.50") and r["grand_total"]==D("233.00") and r["round_off"]==D("0.50")
# ---- subscription
def test_S1_trial_30d(): assert trial_end(U(2026,11,22,10),30)==U(2026,12,22,10)
def test_S2_trial_edges():
    s=dict(status="TRIALING",trial_ends_at=U(2026,12,22,10),current_period_end=None,grace_days=7,cancel_at_period_end=False)
    e=lambda t: effective_status(s,t)
    assert e(U(2026,12,22,9,59,59))=="TRIALING" and e(U(2026,12,22,10))=="PAST_DUE"
    assert e(U(2026,12,29,9,59,59))=="PAST_DUE" and e(U(2026,12,29,10))=="SUSPENDED"
def test_S3_month_clamp_no_drift():
    a=U(2027,1,31,6); cyc="MONTHLY"
    assert period(a,cyc,0)==(U(2027,1,31,6),U(2027,2,28,6))
    assert period(a,cyc,1)==(U(2027,2,28,6),U(2027,3,31,6))      # anchored: back to the 31st, no drift to the 28th
    assert period(U(2028,2,29),"YEARLY",0)[1]==U(2029,2,28)
def test_S4_on_time_and_grace_renewal_same_period():
    anchor=U(2026,12,22,10)
    sub=dict(status="ACTIVE",billing_cycle="MONTHLY",billing_anchor_at=anchor,period_number=0,trial_ends_at=None,
             current_period_end=U(2027,1,22,10),grace_days=7,cancel_at_period_end=False)
    for paid in (U(2027,1,20),U(2027,1,25)):            # early and within grace
        a,k,s,e=next_period_after_payment(sub,paid); assert (s,e)==(U(2027,1,22,10),U(2027,2,22,10)) and k==1
def test_S5_after_suspension_reanchors():
    sub=dict(status="ACTIVE",billing_cycle="MONTHLY",billing_anchor_at=U(2026,12,22,10),period_number=0,trial_ends_at=None,
             current_period_end=U(2027,1,22,10),grace_days=7,cancel_at_period_end=False)
    now=U(2027,2,10,8); a,k,s,e=next_period_after_payment(sub,now)
    assert effective_status(sub,now)=="SUSPENDED" and (a,k,s,e)==(now,0,now,U(2027,3,10,8))
def test_S5b_first_payment_after_trial_starts_when_trial_ends():
    sub=dict(status="TRIALING",billing_cycle="YEARLY",billing_anchor_at=None,period_number=0,trial_ends_at=U(2026,12,22,10),
             current_period_end=None,grace_days=7,cancel_at_period_end=False)
    a,k,s,e=next_period_after_payment(sub,U(2026,12,10)); assert (s,e)==(U(2026,12,22,10),U(2027,12,22,10))
def test_S6_user_limits():
    plan=dict(max_users=5,role_limits={"CASHIER":2},max_outlets=1)
    assert can_add_user(plan,{"CASHIER":2,"OWNER":1,"CAPTAIN":1},"CASHIER")==(False,"PLAN_LIMIT_ROLE")
    assert can_add_user(plan,{"CASHIER":2,"OWNER":1,"CAPTAIN":1},"CAPTAIN")==(True,None)
    assert can_add_user(plan,{"CASHIER":2,"OWNER":1,"CAPTAIN":2},"CAPTAIN")==(False,"PLAN_LIMIT_USERS")
    assert can_add_outlet(plan,1)==(False,"PLAN_LIMIT_OUTLETS") and can_add_outlet(plan,0)==(True,None)
def test_S7_cancel_at_period_end():
    s=dict(status="ACTIVE",trial_ends_at=None,current_period_end=U(2027,1,22,10),grace_days=7,cancel_at_period_end=True)
    assert effective_status(s,U(2027,1,22,9))=="ACTIVE" and effective_status(s,U(2027,1,22,10))=="CANCELLED"
def test_S8_extend_trial():
    assert extend_trial(U(2026,12,22,10),U(2026,12,1),7)==U(2026,12,29,10)
    assert extend_trial(U(2026,12,22,10),U(2027,1,5,12),7)==U(2027,1,12,12)       # expired trial: counts from now
def test_S9_access_levels():
    assert [access_level(x) for x in("TRIALING","ACTIVE","PAST_DUE","SUSPENDED","CANCELLED")]==["FULL","FULL","FULL_BANNER","READ_ONLY_SETTLE","READ_ONLY_SETTLE"]
def test_S10_reminders():
    te=U(2026,12,22,10)
    assert reminders_due(te,U(2026,12,14,23))==[] and reminders_due(te,U(2026,12,15,10))==[7]
    assert reminders_due(te,U(2026,12,19,10))==[7,3] and reminders_due(te,U(2026,12,22,10))==[7,3,1,0]

def test_S11_paid_during_trial_job_missed():
    # paid 10 Dec for a monthly plan; trial ends 22 Dec; hourly job never ran
    sub=dict(status="TRIALING",billing_cycle="MONTHLY",billing_anchor_at=U(2026,12,22,10),period_number=0,trial_ends_at=U(2026,12,22,10),
             current_period_start=U(2026,12,22,10),current_period_end=U(2027,1,22,10),grace_days=7,cancel_at_period_end=False)
    assert effective_status(sub,U(2026,12,22,9))=="TRIALING"
    assert effective_status(sub,U(2026,12,22,10))=="ACTIVE" and effective_status(sub,U(2027,1,10))=="ACTIVE"
    assert effective_status(sub,U(2027,1,22,10))=="PAST_DUE"
def test_S12_payment_in_grace_after_unpaid_trial_anchors_at_trial_end():
    sub=dict(status="TRIALING",billing_cycle="MONTHLY",billing_anchor_at=None,period_number=0,trial_ends_at=U(2026,12,22,10),
             current_period_end=None,grace_days=7,cancel_at_period_end=False)
    now=U(2026,12,25); assert effective_status(sub,now)=="PAST_DUE"
    a,k,s,e=next_period_after_payment(sub,now); assert (s,e)==(U(2026,12,22,10),U(2027,1,22,10))
