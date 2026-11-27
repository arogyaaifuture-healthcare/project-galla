from decimal import Decimal as D
from bill_calculator import calculate
L=lambda i,q,p,c=((("GST"),D("5")),): dict(id=i,name="Item"+i,qty=D(q),unit_price=D(p),comps=list(c))
def test_X1_packaging_exclusive_tax_not_discounted():
    r=calculate([L("a",2,"100")],prices_include_tax=False,discount=("PERCENT",D("10")),
                extra_charges=[dict(type="PACKAGING_CHARGE",name="Packaging",amount=D("20"),comps=[("GST",D("5"))])])
    assert r["discount_total"]==D("20.00")
    pk=[l for l in r["lines"] if l["type"]=="PACKAGING_CHARGE"][0]
    assert pk["gross"]==D("20.00") and pk["discount"]==D("0.00") and pk["tax"]==D("1.00")
    # item 200-20=180 +9 tax ; packaging 20 + 1 ; total 210
    assert r["total_before_round_off"]==D("210.00") and r["grand_total"]==D("210.00")
def test_X2_packaging_not_in_service_charge_base():
    r=calculate([L("a",1,"100")],prices_include_tax=False,service_charge_percent=D("10"),
                extra_charges=[dict(type="PACKAGING_CHARGE",name="Packaging",amount=D("30"),comps=[])])
    sc=[l for l in r["lines"] if l["type"]=="SERVICE_CHARGE"][0]
    assert sc["gross"]==D("10.00")
def test_X3_packaging_inclusive_and_zero_ignored():
    r=calculate([L("a",1,"105")],prices_include_tax=True,
                extra_charges=[dict(type="PACKAGING_CHARGE",name="Pack",amount=D("10.50"),comps=[("GST",D("5"))]),
                               dict(type="PACKAGING_CHARGE",name="Zero",amount=D("0"),comps=[])])
    assert len(r["lines"])==2 and r["tax_total"]==D("5.50") and r["grand_total"]==D("116.00")
def test_X4_order_of_extra_charges_does_not_matter():
    a=dict(type="PACKAGING_CHARGE",name="A",amount=D("10"),comps=[("GST",D("5"))])
    b=dict(type="PACKAGING_CHARGE",name="B",amount=D("7"),comps=[("GST",D("5"))])
    r1=calculate([L("a",1,"100")],prices_include_tax=False,extra_charges=[a,b])
    r2=calculate([L("a",1,"100")],prices_include_tax=False,extra_charges=[b,a])
    assert r1==r2
