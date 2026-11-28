from decimal import Decimal as D
import pytest
from bill_calculator import calculate
T5=[("CGST",D("2.50")),("SGST",D("2.50"))]
def L(n,q,p,c=T5): return dict(name=n,qty=D(q),unit_price=D(p),comps=c)
def test_V1():
    r=calculate([L("A",2,100),L("B",1,150)],prices_include_tax=False,discount=("PERCENT",D(10)))
    assert [l["discount"] for l in r["lines"]]==[D("20.00"),D("15.00")]
    assert r["tax_total"]==D("15.76") and r["total_before_round_off"]==D("330.76")
    assert r["grand_total"]==D("331.00") and r["round_off"]==D("0.24")
def test_V2():
    l=calculate([L("A",1,100)],prices_include_tax=True)["lines"][0]
    assert l["taxable"]==D("95.24") and l["tax"]==D("4.76") and [c[2] for c in l["comps"]]==[D("2.38")]*2
def test_V3():
    r=calculate([L("a",1,10,[]),L("b",1,10,[]),L("c",1,10,[])],prices_include_tax=False,discount=("AMOUNT",D("10.00")))
    assert [l["discount"] for l in r["lines"]]==[D("3.34"),D("3.33"),D("3.33")]
def test_V4():
    with pytest.raises(ValueError,match="DISCOUNT_EXCEEDS_SUBTOTAL"):
        calculate([L("a",1,50,[])],prices_include_tax=False,discount=("AMOUNT",D("50.01")))
    for bad in (D(0),D("100.01")):
        with pytest.raises(ValueError,match="VALIDATION_ERROR"):
            calculate([L("a",1,50,[])],prices_include_tax=False,discount=("PERCENT",bad))
def test_V5():
    r=calculate([L("a",1,200,[])],prices_include_tax=False,service_charge_percent=D(10),service_charge_comps=T5)
    assert [c[2] for c in r["lines"][1]["comps"]]==[D("0.50")]*2 and r["grand_total"]==D("221.00")
def test_V6():
    assert calculate([L("a",1,D("99.99"),[])],prices_include_tax=False,discount=("PERCENT",D(15)))["discount_total"]==D("15.00")
def test_V7():
    for amt,g,ro in (("100.50","101.00","0.50"),("100.49","100.00","-0.49"),("100.00","100.00","0.00")):
        r=calculate([L("a",1,D(amt),[])],prices_include_tax=False); assert (r["grand_total"],r["round_off"])==(D(g),D(ro))
def test_V8():
    l=calculate([L("a",3,D("33.33"),[])],prices_include_tax=False,round_off_mode="NONE")["lines"][0]
    assert (l["gross"],l["taxable"],l["tax"])==(D("99.99"),D("99.99"),D("0.00"))
def test_V9():
    r=calculate([L("A",2,100),L("B",1,150)],prices_include_tax=False,discount=("PERCENT",D(10)),round_off_mode="NONE")
    assert r["grand_total"]==D("330.76") and r["round_off"]==D("0.00")
def test_V10_delivery_exclusive():
    r=calculate([L("A",1,200,[])],prices_include_tax=False,discount=("PERCENT",D(10)),service_charge_percent=D(10),
                service_charge_comps=[],delivery_charge=D("40.00"),delivery_comps=T5)
    assert r["discount_total"]==D("20.00") and r["lines"][1]["gross"]==D("18.00") and r["lines"][2]["tax"]==D("2.00")
    assert r["total_before_round_off"]==D("240.00") and r["grand_total"]==D("240.00")
def test_V11_delivery_inclusive():
    r=calculate([L("A",1,100,[])],prices_include_tax=True,delivery_charge=D("52.50"),delivery_comps=T5)
    d=r["lines"][1]; assert (d["taxable"],d["tax"],d["total"])==(D("50.00"),D("2.50"),D("52.50"))
    assert r["grand_total"]==D("153.00") and r["round_off"]==D("0.50")
