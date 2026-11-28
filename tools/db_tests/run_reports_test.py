import subprocess,re,sys
import os
S=os.path.dirname(os.path.abspath(__file__))+'/'
DB=os.environ.get('GALLA_DB','dt_rep')
sql=open(S+'reports.sql').read()
parts=re.split(r"^-- (RP\d)",sql,flags=re.M)
q={parts[i]:parts[i+1] for i in range(1,len(parts),2)}
def run(name,outlet='00000000-0000-0000-0000-0000000000a1',dfrom='2026-11-01',dto='2026-12-31'):
    body=q[name].split("\n",1)[1]
    pre=f"\\set tenant_id '00000000-0000-0000-0000-000000000001'\n\\set outlet_id '{outlet}'\n\\set d_from '{dfrom}'\n\\set d_to '{dto}'\n"
    r=subprocess.run(["su","postgres","-c","psql -d "+DB+" -At -F '|'"],input=pre+body,capture_output=True,text=True)
    assert r.returncode==0 and 'ERROR' not in r.stderr, (name,r.stderr)
    return [l for l in r.stdout.splitlines() if l]
exp={
 'RP1':['Starters|2.000|200.00|0.00|200.00|10.00','Uncategorised|2.000|199.99|0.00|199.99|5.00'],
 'RP2':['DINE_IN|DIRECT||1|100.00|0.00|0.00|100.00','TAKEAWAY|DIRECT||2|299.99|0.00|15.00|315.00'],
 'RP3':['D|2|0.00|315.00','Cashier Two|1|0.00|100.00'],
 'RP4':['T5|1|3|100.00|100.00'],
 'RP5':['Asha|+919800000001|2|315.00|157.50|2026-11-01'],
 'RP6':['ALL|ALL|4|699.99|0.00|15.00|715.00','O1|2026-11-01|2|299.99|0.00|15.00|315.00','O1|2026-12-03|1|100.00|0.00|0.00|100.00','O1|ALL|3|399.99|0.00|15.00|415.00','O2|2026-11-01|1|300.00|0.00|0.00|300.00','O2|ALL|1|300.00|0.00|0.00|300.00'],
 'RP7':['2026-11-01|3|615.00|','2026-12-01|1|100.00|-83.74'],
 'RP8':['CASH|CASH|1|210.00','Paytm|UPI|1|105.00'],
 'RP9':[],
}
ok=0
for n,e in exp.items():
    g=run(n); good=(g==e); ok+=good; print(n,'PASS' if good else f'FAIL {g}')
# extra: VOID excluded (b03 50 not counted); date filter excludes December; outlet 2 isolated
assert run('RP2',dto='2026-11-30')==['TAKEAWAY|DIRECT||2|299.99|0.00|15.00|315.00']; ok+=1
assert run('RP2',outlet='00000000-0000-0000-0000-0000000000a2')==['DELIVERY|PARTNER|Zomato|1|300.00|0.00|0.00|300.00']; ok+=1
assert run('RP1',dfrom='2030-01-01',dto='2030-01-02')==[]; ok+=1
# gate must fire when a line is tampered
subprocess.run(["su","postgres","-c","psql -q -d "+DB+" -c \"UPDATE bill_lines SET taxable_amount=taxable_amount+1 WHERE id='00000000-0000-0000-0000-00000000c004'\""],check=True)
g=run('RP9'); assert len(g)==1 and g[0].startswith('category+charges'),g; ok+=1
subprocess.run(["su","postgres","-c","psql -q -d "+DB+" -c \"UPDATE bill_lines SET taxable_amount=taxable_amount-1 WHERE id='00000000-0000-0000-0000-00000000c004'\""],check=True)
assert run('RP9')==[]; ok+=1
print('total passed',ok,'of 14'); sys.exit(0 if ok==14 else 1)
