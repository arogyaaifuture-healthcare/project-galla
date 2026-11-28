from whatsapp import *
def test_W1_phone_normalisation():
    assert normalize_phone("98765 43210","IN")==("+919876543210",None)
    assert normalize_phone("09876543210","IN")==("+919876543210",None)        # leading trunk 0
    assert normalize_phone("+91 98765-43210","IN")==("+919876543210",None)
    assert normalize_phone("+1 415 555 2671","IN")==("+14155552671",None)    # explicit country code wins
def test_W2_invalid_never_guessed():
    for bad in ("12345","","abcdefghij","98765","0000000000","5987654321"):
        assert normalize_phone(bad,"IN")==(None,"INVALID_PHONE_NUMBER")
    # well-formed but not a mobile pattern: accepted with a warning (the UI asks the cashier to confirm)
    assert normalize_phone("1234567890","IN")==("+911234567890","NOT_A_MOBILE_NUMBER")
def test_W3_landline_warns():
    e,w=normalize_phone("022 2345 6789","IN"); assert e=="+912223456789" and w=="NOT_A_MOBILE_NUMBER"
def test_W4_wa_me():
    assert wa_me_url("+919876543210","Bill GL-1: Rs 331.00 https://x.in/b/abc")=="https://wa.me/919876543210?text=Bill%20GL-1%3A%20Rs%20331.00%20https%3A%2F%2Fx.in%2Fb%2Fabc"
def test_W5_params():
    assert clean_param("  Asha\n\tKumar   Rao ")=="Asha Kumar Rao" and clean_param("")=="Guest" and clean_param(None)=="Guest"
    assert len(clean_param("x"*100))==40
    assert bill_template_params("Asha","Cafe Z","GL-2026-27-000123","Rs","331.00")==["Asha","Cafe Z","GL-2026-27-000123","Rs 331.00"]
def test_W6_consent_newest_wins():
    h=[dict(phone="+91", purpose="BILL", status="OPTED_IN", at=1, seq=1), dict(phone="+91", purpose="BILL", status="OPTED_OUT", at=5, seq=2),
       dict(phone="+92", purpose="BILL", status="OPTED_IN", at=2, seq=3)]
    assert current_consent(h,"+91","BILL")=="OPTED_OUT" and not may_send(h,"+91","BILL") and may_send(h,"+92","BILL")
    assert current_consent(h,"+93","BILL")=="NONE" and not may_send(h,"+91","DELIVERY_UPDATES")   # purposes are separate
    h.append(dict(phone="+91", purpose="BILL", status="OPTED_IN", at=9, seq=4)); assert may_send(h,"+91","BILL")
def test_W7_stop_words():
    for t in ("STOP","stop.","  Unsubscribe ","Opt out"): assert is_stop_message(t)
    for t in ("please stop by tomorrow","thanks","hello",""): assert not is_stop_message(t)
def test_W8_status_merge_out_of_order():
    assert merge_status("QUEUED","SENT")=="SENT" and merge_status("DELIVERED","SENT")=="DELIVERED"       # late 'sent' cannot downgrade
    assert merge_status("SENT","READ")=="READ" and merge_status("READ","DELIVERED")=="READ"
    assert merge_status("DELIVERED","FAILED")=="DELIVERED" and merge_status("READ","FAILED")=="READ"
    assert merge_status("SENT","FAILED")=="FAILED" and merge_status("QUEUED","FAILED")=="FAILED"
    assert merge_status("FAILED","DELIVERED")=="DELIVERED" and merge_status("FAILED","SENT")=="FAILED"   # duplicates/late events are harmless
def test_W9_merge_is_idempotent_and_order_free():
    import itertools
    evs=["SENT","DELIVERED","READ"]
    for perm in itertools.permutations(evs):
        s="QUEUED"
        for e in perm: s=merge_status(s,e)
        assert s=="READ"
        for e in perm: s=merge_status(s,e)   # replaying changes nothing
        assert s=="READ"
def test_W10_failure_classes():
    assert classify_failure(131026)==dict(kind="UNDELIVERABLE",retry=False,ui="NOT_ON_WHATSAPP_OR_BLOCKED",alert_admin=False)
    assert classify_failure("130429")["retry"] and not classify_failure("132001")["retry"] and classify_failure("132000")["alert_admin"]
    assert classify_failure("131048")["kind"]=="ACCOUNT_RESTRICTED" and classify_failure(99999)["kind"]=="UNKNOWN"
def test_W11_budget():
    now=100000; msgs=[dict(to="a",at=now-10,status="SENT"),dict(to="a",at=now-20,status="DELIVERED"),dict(to="b",at=now-86401,status="SENT"),
                      dict(to="c",at=now-30,status="FAILED"),dict(to="d",at=now-86399,status="READ")]
    assert unique_recipients_24h(msgs,now)==2       # a (counted once) and d; b is >24h old; c failed
    assert limit_state(199,250)=="OK" and limit_state(200,250)=="WARN" and limit_state(249,250)=="WARN" and limit_state(159,200)=="OK" and limit_state(160,200)=="WARN"
    assert limit_state(250,250)=="AT_LIMIT" and limit_state(5,None)=="UNKNOWN" and TIERS["TIER_250"]==250
def test_W12_resend_cap(): assert can_resend(4) and not can_resend(5)
