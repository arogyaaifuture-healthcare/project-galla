import xml.etree.ElementTree as ET
from decimal import Decimal as D
import random, pytest
from hypothesis import given, settings, strategies as st
from bill_calculator import calculate
from registers import make_bill
from tally_export import *
from test_registers import rand_bill, GST
LED = dict(SALES="Sales", SERVICE_CHARGE="Service Charges", DELIVERY_CHARGE="Delivery Income", PACKAGING_CHARGE="Packaging Income", ROUND_OFF="Round Off",
           CASH="Cash", CARD="Card Receipts", UPI="UPI Receipts", OTHER_PAYMENT="Other Receipts", CREDIT_CUSTOMERS="Sundry Debtors")
TAX = {"CGST": "Output CGST", "SGST": "Output SGST", "GST": "Output GST"}
def test_T1_voucher_balances_and_signs():
    c = calculate([dict(id="a", name="Tikka", qty=D(2), unit_price=D("100"), comps=GST("5"))], prices_include_tax=False)
    b = make_bill(c, "B-1", "2026-11-25")
    e = dict(voucher_entries(b, LED, TAX)); assert e == {"Sales": D("200.00"), "Output CGST": D("5.00"), "Output SGST": D("5.00"), "Cash": D("-210.00")}
    root = ET.fromstring(build_xml([b], LED, TAX, "My Co & Sons"))
    v = root.find(".//VOUCHER"); assert v.get("VCHTYPE") == "Sales" and v.find("DATE").text == "20261125"
    assert sum(D(x.find("AMOUNT").text) for x in v.findall("LEDGERENTRIES.LIST")) == 0
    cash = [x for x in v.findall("LEDGERENTRIES.LIST") if x.find("LEDGERNAME").text == "Cash"][0]
    assert cash.find("ISDEEMEDPOSITIVE").text == "Yes" and cash.find("AMOUNT").text == "-210.00"
    assert root.find(".//SVCURRENTCOMPANY").text == "My Co & Sons"
def test_T2_unpaid_goes_to_credit_customers_void_skipped():
    c = calculate([dict(id="a", name="X", qty=D(1), unit_price=D("100"), comps=[])], prices_include_tax=False)
    b = make_bill(c, "B", "2026-11-25", status="GENERATED"); v = make_bill(c, "V", "2026-11-25", status="VOID")
    assert dict(voucher_entries(b, LED, TAX))["Sundry Debtors"] == D("-100.00")
    assert ET.fromstring(build_xml([b, v], LED, TAX)).findall(".//VOUCHER").__len__() == 1
def test_T3_missing_mapping_raises_never_guesses():
    c = calculate([dict(id="a", name="X", qty=D(1), unit_price=D("100"), comps=GST("5"))], prices_include_tax=False)
    with pytest.raises(MissingLedger) as ex: voucher_entries(make_bill(c, "B", "2026-11-25"), {"SALES": "Sales"}, {})
    assert "TAX:CGST" in ex.value.names and "CASH" in ex.value.names
def test_T4_special_characters_escaped():
    c = calculate([dict(id="a", name="X", qty=D(1), unit_price=D("100"), comps=[])], prices_include_tax=False)
    b = make_bill(c, "B<&>1", "2026-11-25"); led = dict(LED, SALES="Food & Beverages <5%>")
    r = ET.fromstring(build_xml([b], led, TAX)); assert r.find(".//VOUCHERNUMBER").text == "B<&>1"
@settings(max_examples=150, deadline=None)
@given(st.randoms(use_true_random=False), st.integers(1, 15))
def test_TP1_every_random_voucher_balances_to_zero(rnd, n):
    bills = [rand_bill(rnd, i, status=rnd.choice(["PAID", "GENERATED"])) for i in range(n)]
    root = ET.fromstring(build_xml(bills, LED, dict(TAX, **{"CGST": "C", "SGST": "S"})))
    for v in root.findall(".//VOUCHER"):
        assert sum(D(x.find("AMOUNT").text) for x in v.findall("LEDGERENTRIES.LIST")) == 0
def test_I1_inr_grouping():
    for s, want in [("0", "0.00"), ("999.5", "999.50"), ("1000", "1,000.00"), ("100000", "1,00,000.00"), ("12345678.9", "1,23,45,678.90"), ("-1234567.891", "-12,34,567.89")]:
        assert inr_group(D(s)) == want
    assert inr_group(D("1234567"), 0) == "12,34,567"
@given(st.decimals(min_value=D("-999999999.99"), max_value=D("999999999.99"), places=2))
def test_IP1_grouping_roundtrip(x): assert D(inr_group(x).replace(",", "")) == x
