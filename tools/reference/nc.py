"""Section 25.7 complimentary (NC) bills. Two tax modes (legal treatment NOT verified - the owner/CA chooses per outlet):
ZERO_TAX: bill shows zero tax. TAX_ON_LIST_PRICE: the bill still totals 0 for the guest; the tax that WOULD be due on the list price is
computed by a separate function and stored in bills.nc_tax_liability (informational: reported to the owner, never charged to the guest)."""
from decimal import Decimal as D
from bill_calculator import calculate

def nc_bill(lines, *, prices_include_tax, mode, round_off_mode="NEAREST_1"):
    """Returns (guest_bill, nc_tax_liability, list_value). The guest bill is the shared engine with a 100% discount: every line
    keeps its list price in 'gross' and shows discount == gross, taxable 0, tax 0, total 0, so grand_total == 0 (DB: bills_nc_shape)."""
    if mode not in ("ZERO_TAX", "TAX_ON_LIST_PRICE"): raise ValueError("VALIDATION_ERROR")
    bill = calculate(lines, prices_include_tax=prices_include_tax, round_off_mode=round_off_mode, discount=("PERCENT", D("100")))
    liability = tax_on_list_price(lines, prices_include_tax=prices_include_tax) if mode == "TAX_ON_LIST_PRICE" else D("0.00")
    return bill, liability, bill["subtotal"]

def tax_on_list_price(lines, *, prices_include_tax):
    """Tax the same lines would carry at full list price, no discount, no service charge. Separate from the 100%-discount bill on purpose."""
    return calculate(lines, prices_include_tax=prices_include_tax, round_off_mode="NONE")["tax_total"]
