"""Galla Stream D reference: Tally voucher XML (plan Section 28.B). BEST EFFORT: the structure follows Tally's published sample XML
(help.tallysolutions.com/sample-xml, fetched 2026-11-25); it has NOT been imported into a real Tally. Decimal only."""
from decimal import Decimal as D
from xml.sax.saxutils import escape
from collections import OrderedDict
Z = D("0.00")
class MissingLedger(Exception):
    def __init__(self, names): self.names = sorted(names); super().__init__("MISSING_LEDGER_MAPPING: " + ", ".join(self.names))

def voucher_entries(bill, ledgers, tax_ledgers):
    """Returns ordered [(ledger_name, signed_amount)] with CREDIT positive; sum == 0 for a bill whose payments equal its grand total
    (or that is unpaid and is booked to the CREDIT_CUSTOMERS ledger). Missing mappings raise MissingLedger (never a guessed ledger)."""
    need, cr = set(), OrderedDict()
    def add(purpose, amt, kind="P"):
        if amt == 0: return
        key = purpose if kind == "P" else ("TAX", purpose)
        cr[key] = cr.get(key, Z) + amt
    for l in bill["lines"]:
        add({"ITEM": "SALES", "SERVICE_CHARGE": "SERVICE_CHARGE", "DELIVERY_CHARGE": "DELIVERY_CHARGE", "PACKAGING_CHARGE": "PACKAGING_CHARGE"}.get(l["type"], "SALES"), l["taxable"])
        for c in l["comps"]: add(f'{c["name"]}', c["tax"], "T")
    add("ROUND_OFF", bill["round_off"])
    dr = OrderedDict()
    if bill["status"] == "PAID":
        for m, a in bill["payments"]:
            dr[{"CASH": "CASH", "CARD": "CARD", "UPI": "UPI"}.get(m, "OTHER_PAYMENT")] = dr.get({"CASH": "CASH", "CARD": "CARD", "UPI": "UPI"}.get(m, "OTHER_PAYMENT"), Z) + a
    else:
        dr["CREDIT_CUSTOMERS"] = bill["grand_total"]
    out = []
    for k, a in cr.items():
        if isinstance(k, tuple):
            if k[1] not in tax_ledgers: need.add("TAX:" + k[1]); continue
            out.append((tax_ledgers[k[1]], a))
        else:
            if k not in ledgers: need.add(k); continue
            out.append((ledgers[k], a))
    for k, a in dr.items():
        if k not in ledgers: need.add(k); continue
        out.append((ledgers[k], -a))
    if need: raise MissingLedger(need)
    merged = OrderedDict()
    for n, a in out: merged[n] = merged.get(n, Z) + a
    return list(merged.items())

def build_xml(bills, ledgers, tax_ledgers, company=None):
    parts = ['<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Import</TALLYREQUEST><TYPE>Data</TYPE><ID>Vouchers</ID></HEADER><BODY>']
    parts.append('<DESC>' + (f'<STATICVARIABLES><SVCURRENTCOMPANY>{escape(company)}</SVCURRENTCOMPANY></STATICVARIABLES>' if company else '') + '</DESC><DATA>')
    for b in bills:
        if b["status"] == "VOID": continue
        d = b["date"].replace("-", "")
        parts.append(f'<TALLYMESSAGE><VOUCHER VCHTYPE="Sales" ACTION="Create" OBJVIEW="Accounting Voucher View">'
                     f'<DATE>{d}</DATE><VOUCHERTYPENAME>Sales</VOUCHERTYPENAME><VOUCHERNUMBER>{escape(b["number"])}</VOUCHERNUMBER>'
                     f'<PERSISTEDVIEW>Accounting Voucher View</PERSISTEDVIEW><ISINVOICE>No</ISINVOICE>')
        for n, a in voucher_entries(b, ledgers, tax_ledgers):
            parts.append(f'<LEDGERENTRIES.LIST><LEDGERNAME>{escape(n)}</LEDGERNAME><ISDEEMEDPOSITIVE>{"No" if a >= 0 else "Yes"}</ISDEEMEDPOSITIVE>'
                         f'<AMOUNT>{a:.2f}</AMOUNT></LEDGERENTRIES.LIST>')
        parts.append('</VOUCHER></TALLYMESSAGE>')
    parts.append('</DATA></BODY></ENVELOPE>')
    return "".join(parts)

def inr_group(x: D, places=2) -> str:
    """Indian digit grouping 1,00,00,000.00 for display. Pure string work on Decimal (no float, no locale dependence)."""
    q = D(1).scaleb(-places); x = x.quantize(q); neg = x < 0; s = f"{abs(x):.{places}f}"
    ip, _, fp = s.partition(".")
    if len(ip) > 3:
        head, tail = ip[:-3], ip[-3:]; g = []
        while len(head) > 2: g.insert(0, head[-2:]); head = head[:-2]
        if head: g.insert(0, head)
        ip = ",".join(g + [tail])
    return ("-" if neg else "") + ip + (("." + fp) if places else "")
