from decimal import Decimal as D
from hypothesis import given, settings, strategies as st
from bill_calculator import calculate
import random
rate=st.sampled_from([D("0"),D("2.5"),D("5"),D("6"),D("9"),D("12"),D("14"),D("18"),D("28")])
comps=st.lists(rate,min_size=0,max_size=3).map(lambda rs:[(f"C{i}",r) for i,r in enumerate(rs)])
money=st.decimals(min_value=D("0"),max_value=D("5000"),places=2)
qty=st.decimals(min_value=D("0.001"),max_value=D("20"),places=3)
line=st.fixed_dictionaries({"name":st.just("x"),"qty":qty,"unit_price":money,"comps":comps})
lines_st=st.lists(line,min_size=1,max_size=8).map(lambda ls:[dict(l,id=f"{i:04d}") for i,l in enumerate(ls)])
disc=st.one_of(st.none(),st.tuples(st.just("PERCENT"),st.decimals(min_value=D("0.01"),max_value=D("100"),places=2)),
    st.tuples(st.just("AMOUNT"),st.decimals(min_value=D("0.01"),max_value=D("5000"),places=2)))
A=dict(lines=lines_st,incl=st.booleans(),ro=st.sampled_from(["NONE","NEAREST_1"]),d=disc,
       scp=st.sampled_from([D(0),D(5),D(10)]),scc=comps,dc=st.one_of(st.just(D(0)),money),dcc=comps)
def run(lines,incl,ro,d,scp,scc,dc,dcc):
    try: return calculate(lines,prices_include_tax=incl,round_off_mode=ro,discount=d,service_charge_percent=scp,
                          service_charge_comps=scc,delivery_charge=dc,delivery_comps=dcc)
    except ValueError as e:
        assert str(e) in("DISCOUNT_EXCEEDS_SUBTOTAL","VALIDATION_ERROR"); return None
@settings(max_examples=10000,deadline=None)
@given(**A)
def test_invariants(lines,incl,ro,d,scp,scc,dc,dcc):
    r=run(lines,incl,ro,d,scp,scc,dc,dcc)
    if r is None: return
    Ls=r["lines"]; items=[l for l in Ls if l["type"]=="ITEM"]
    assert sum(l["discount"] for l in items)==r["discount_total"]
    assert sum(l["total"] for l in Ls)==r["total_before_round_off"]
    assert r["grand_total"]==r["total_before_round_off"]+r["round_off"]
    for l in Ls:
        assert min(l["gross"],l["discount"],l["taxable"],l["tax"],l["total"])>=0 and l["discount"]<=l["gross"]
        assert (l["total"]==l["taxable"]+l["tax"]) if not incl else (l["total"]==l["gross"]-l["discount"])
        if l["comps"]: assert sum(c[2] for c in l["comps"])==l["tax"]
    assert sum(c[2] for l in Ls for c in l["comps"])==r["tax_total"] and r["grand_total"]>=0
    assert run(lines,incl,ro,d,scp,scc,dc,dcc)==r
@settings(max_examples=10000,deadline=None)
@given(**A,seed=st.integers())
def test_line_order_independence(lines,incl,ro,d,scp,scc,dc,dcc,seed):
    a=run(lines,incl,ro,d,scp,scc,dc,dcc); sh=lines[:]; random.Random(seed).shuffle(sh); b=run(sh,incl,ro,d,scp,scc,dc,dcc)
    if a is None or b is None: assert a is None and b is None; return
    assert a["grand_total"]==b["grand_total"] and a["tax_total"]==b["tax_total"]
