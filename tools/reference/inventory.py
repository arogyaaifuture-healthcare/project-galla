"""Reference spec for Galla Section 26 (inventory, recipes, purchasing).
Pure Decimal arithmetic; mirrors the V014 triggers so the Java implementation can be tested against it.
Quantities: 4 decimals (NUMERIC(14,4)). Unit cost: 6 decimals per BASE unit. Values: 2 decimals (ROUND_HALF_UP)."""
from dataclasses import dataclass, field
from decimal import Decimal as D, ROUND_HALF_UP, getcontext
from typing import Optional

getcontext().prec = 40
Q4, Q6, Q2 = D("0.0001"), D("0.000001"), D("0.01")

def q4(x): return D(x).quantize(Q4, ROUND_HALF_UP)
def q6(x): return D(x).quantize(Q6, ROUND_HALF_UP)
def q2(x): return D(x).quantize(Q2, ROUND_HALF_UP)

# ---------------------------------------------------------------- 1 units
UNITS = {  # code: (family, factor_to_base)
    "g": ("MASS", D(1)), "kg": ("MASS", D(1000)),
    "ml": ("VOLUME", D(1)), "l": ("VOLUME", D(1000)),
    "pcs": ("COUNT", D(1)), "dozen": ("COUNT", D(12)),
}
PACK_UNITS = {"pack", "box", "bottle", "can", "tray", "bag", "crate"}
BASE_OF = {"MASS": "g", "VOLUME": "ml", "COUNT": "pcs"}

class UnitError(ValueError):
    pass

def to_base(qty, unit):
    if unit not in UNITS: raise UnitError("UNIT_FAMILY_MISMATCH: %s has no table factor" % unit)
    return q4(D(qty) * UNITS[unit][1])

def convert(qty, frm, to):
    """Exact conversion inside one family; result rounded once to 4 decimals."""
    if frm not in UNITS or to not in UNITS or UNITS[frm][0] != UNITS[to][0]:
        raise UnitError("UNIT_FAMILY_MISMATCH: %s -> %s" % (frm, to))
    return q4(D(qty) * UNITS[frm][1] / UNITS[to][1])

def check_item_units(base_unit, purchase_unit, purchase_to_base):
    """Mirror of trg_stock_item_units."""
    if base_unit not in BASE_OF.values(): raise UnitError("base unit must be g, ml or pcs")
    if purchase_unit in PACK_UNITS: return
    fam, f = UNITS[purchase_unit]
    if BASE_OF[fam] != base_unit: raise UnitError("UNIT_FAMILY_MISMATCH")
    if D(purchase_to_base) != f: raise UnitError("UNIT_FACTOR_MISMATCH")

def purchase_line(qty_purchase, unit_price, purchase_to_base):
    """GRN line: qty_base, unit_cost_base (6 dp), line_amount (2 dp) exactly as the V014 CHECKs."""
    qb = q4(D(qty_purchase) * D(purchase_to_base))
    return qb, q6(D(unit_price) / D(purchase_to_base)), q2(D(qty_purchase) * D(unit_price))

def price_change_percent(new_unit_cost, previous_cost):
    if previous_cost is None or D(previous_cost) == 0: return None
    return ((D(new_unit_cost) - D(previous_cost)) / D(previous_cost) * 100).quantize(Q2, ROUND_HALF_UP)

# ---------------------------------------------------------------- 5 costing
def weighted_average(on_hand, avg, qty, unit_cost):
    """Moving average after an inflow. If on_hand <= 0 the new cost simply replaces the average."""
    on_hand, avg, qty, unit_cost = D(on_hand), D(avg), D(qty), D(unit_cost)
    if on_hand <= 0: return q6(unit_cost)
    return q6((on_hand * avg + qty * unit_cost) / (on_hand + qty))

INFLOW = {"OPENING", "PURCHASE", "SALE_REVERSAL", "TRANSFER_IN", "PRODUCTION_OUTPUT"}
OUTFLOW = {"SALE", "WASTAGE", "VENDOR_RETURN", "TRANSFER_OUT", "PRODUCTION_CONSUME"}
SIGNED = {"ADJUSTMENT", "COUNT_VARIANCE"}
MANUAL_OUT = {"WASTAGE", "ADJUSTMENT", "TRANSFER_OUT", "VENDOR_RETURN", "PRODUCTION_CONSUME"}

class LedgerError(Exception):
    pass

@dataclass
class Movement:
    kind: str; qty: D; unit_cost: D; basis: str; key: str
    reverses: Optional[int] = None
    @property
    def value(self): return q2(self.qty * self.unit_cost)

@dataclass
class Level:
    """One (outlet, item) pair: ledger + level, updated together (as the DB triggers do)."""
    policy: str = "ALLOW"            # ALLOW | BLOCK_MANUAL
    on_hand: D = D(0); avg: D = D(0); known: bool = False
    last_purchase: Optional[D] = None
    moves: list = field(default_factory=list)
    keys: set = field(default_factory=set)

    def outflow_cost(self):
        if self.on_hand > 0 and self.known: return "AVERAGE", self.avg
        if self.last_purchase is not None: return "LAST_PURCHASE", self.last_purchase
        return "UNKNOWN", D(0)

    def post(self, kind, qty, unit_cost=None, key=None, reverses=None):
        """Returns the index of the new movement, or the index of the existing one when `key` repeats (idempotent)."""
        qty = q4(qty)
        if key is not None and key in self.keys:
            return next(i for i, m in enumerate(self.moves) if m.key == key)
        if qty == 0: raise LedgerError("quantity_base <> 0")
        if kind in INFLOW and qty < 0 or kind in OUTFLOW and qty > 0: raise LedgerError("SIGN")
        if qty < 0:
            basis, cost = self.outflow_cost()
            if self.policy == "BLOCK_MANUAL" and kind in MANUAL_OUT and self.on_hand + qty < 0:
                raise LedgerError("NEGATIVE_STOCK_BLOCKED")
        else:
            if kind == "SALE_REVERSAL":
                orig = self.moves[reverses]
                if orig.kind != "SALE": raise LedgerError("REVERSAL_TARGET_INVALID")
                done = sum((m.qty for m in self.moves if m.reverses == reverses), D(0))
                if done + qty > -orig.qty: raise LedgerError("REVERSAL_EXCEEDS_ORIGINAL")
                basis, cost = "REVERSAL", orig.unit_cost       # always at the ORIGINAL sale cost
            elif kind in ("ADJUSTMENT", "COUNT_VARIANCE"):
                basis, cost = "AVERAGE", self.avg
            else:
                if unit_cost is None: raise LedgerError("unit cost required")
                basis, cost = "ACTUAL", q6(unit_cost)
        m = Movement(kind, qty, cost, basis, key or "k%d" % len(self.moves), reverses)
        if qty > 0 and basis in ("ACTUAL", "REVERSAL"):
            self.avg = weighted_average(self.on_hand, self.avg, qty, cost)
            if basis == "ACTUAL": self.known = True
        if kind == "PURCHASE": self.last_purchase = cost
        self.on_hand += qty
        self.moves.append(m); self.keys.add(m.key)
        return len(self.moves) - 1

    # invariants used by the property tests and by the DB check query
    def ledger_sum(self): return sum((m.qty for m in self.moves), D(0))
    def value(self): return q2(self.on_hand * self.avg)

# ---------------------------------------------------------------- 3 recipes
@dataclass(frozen=True)
class RLine:
    item: str; qty_base: D; wastage: D = D(0); mode: str = "DIRECT"   # qty_base = NET per portion

def gross_per_portion(line):
    """net / (1 - wastage%). Wastage is the share of the PURCHASED amount that is lost (peel, trim)."""
    return D(line.qty_base) * 100 / (100 - D(line.wastage))

@dataclass
class Recipe:
    lines: list
    yield_qty: Optional[D] = None        # PREP: output of one batch
    portion_factor: D = D(1)

class RecipeError(Exception):
    pass

def validate_prep_graph(preps, items_kind):
    """preps: {prep_item: Recipe}. v1 allows ONE level: a prep recipe may only use RAW/RETAIL items."""
    for p, r in preps.items():
        for l in r.lines:
            if items_kind.get(l.item) == "PREP": raise RecipeError("PREP_NESTING_NOT_ALLOWED")

def find_cycle(graph):
    """General cycle detector for a {node: [children]} graph (used when importing recipes before the one-level rule is applied)."""
    WHITE, GREY, BLACK = 0, 1, 2
    colour = {n: WHITE for n in graph}
    def visit(n, path):
        colour[n] = GREY
        for c in graph.get(n, []):
            if colour.get(c, WHITE) == GREY: return path + [n, c]
            if colour.get(c, WHITE) == WHITE:
                r = visit(c, path + [n])
                if r: return r
        colour[n] = BLACK
    for n in list(graph):
        if colour[n] == WHITE:
            r = visit(n, [])
            if r: return r
    return None

def consumption(sold_lines, recipes, preps=None, modifier_recipes=None):
    """sold_lines: [(target, qty_portions, [modifier,...])]. recipes: {target: Recipe}.
    Returns (dict item -> consumed base qty (4 dp, one rounding per item), skipped targets).
    DIRECT prep lines consume the prep item; EXPAND lines consume raw ingredients pro rata (line gross / yield)."""
    preps = preps or {}; modifier_recipes = modifier_recipes or {}
    acc, skipped = {}, []
    def add(item, qty): acc[item] = acc.get(item, D(0)) + qty
    def apply(rec, portions):
        for l in rec.lines:
            g = gross_per_portion(l) * D(portions) * rec.portion_factor
            if l.mode == "EXPAND":
                p = preps[l.item]
                for pl in p.lines:
                    add(pl.item, gross_per_portion(pl) * g / p.yield_qty)
            else:
                add(l.item, g)
    for target, qty, mods in sold_lines:
        rec = recipes.get(target)
        if rec is None or not rec.lines: skipped.append(target)
        else: apply(rec, qty)
        for m in mods:                          # modifier recipes apply even when the item itself has none
            mr = modifier_recipes.get(m)
            if mr: apply(mr, qty)
    return {k: q4(v) for k, v in acc.items() if q4(v) > 0}, skipped

def reversal_quantities(original, already_reversed, fraction, final=False):
    """Proportional reversal of one SALE movement (negative qty). Returns the positive qty to return.
    `final` (full void / last credit note) returns exactly what is left, so the sum of reversals is exactly the sale."""
    total = -D(original); left = total - D(already_reversed)
    if final: return q4(left)
    return min(q4(total * D(fraction)), q4(left))

def theoretical_cost(consumed, avg_costs):
    """Cost of a consumption at the given per-base-unit costs; one rounding per item, then summed."""
    return sum((q2(q * D(avg_costs[i])) for i, q in consumed.items()), D(0))

def food_cost_percent(cost, net_sales):
    if D(net_sales) == 0: return None
    return (D(cost) / D(net_sales) * 100).quantize(Q2, ROUND_HALF_UP)

def variance(theoretical_qty, counted_opening, purchases, counted_closing, transfers_net=D(0)):
    """Actual use = opening + purchases + net transfers in - closing; variance = actual - theoretical (positive = loss)."""
    actual = D(counted_opening) + D(purchases) + D(transfers_net) - D(counted_closing)
    return q4(actual), q4(actual - D(theoretical_qty))

# ---------------------------------------------------------------- 9 alerts, EOD, vendors
def low_stock(on_hand, reorder_level, override=None):
    lvl = D(override) if override is not None else D(reorder_level)
    return D(on_hand) <= lvl and lvl > 0

def suggested_order_base(on_hand, par, reorder_level, override=None):
    if par is None or not low_stock(on_hand, reorder_level, override): return D(0)
    return max(D(0), q4(D(par) - D(on_hand)))

def aging_bucket(due_date, today):
    d = (today - due_date).days
    return "NOT_DUE" if d <= 0 else "1-30" if d <= 30 else "31-60" if d <= 60 else "61-90" if d <= 90 else "90+"

def eod_inventory(opening_value, purchases, consumption_value, wastage, adjustments, closing_value,
                  low_count, no_recipe_count, price_alerts, covered, uncovered):
    """Exact shape of the `inventory` object of the EOD summary (Section 10.3). All money as strings.
    Invariant: closing = opening + purchases - consumption - wastage + adjustments (+ other = transfers/returns/production net)."""
    other = D(closing_value) - (D(opening_value) + D(purchases) - D(consumption_value) - D(wastage) + D(adjustments))
    return {
        "opening_value": str(q2(opening_value)), "purchases_value": str(q2(purchases)),
        "consumption_value": str(q2(consumption_value)), "wastage_value": str(q2(wastage)),
        "adjustments_value": str(q2(adjustments)), "other_movements_value": str(q2(other)),
        "closing_value": str(q2(closing_value)), "low_stock_count": low_count,
        "no_recipe_items_count": no_recipe_count, "price_alert_count": price_alerts,
        "sales_coverage_percent": str(((D(covered) / (D(covered) + D(uncovered)) * 100) if D(covered) + D(uncovered) else D(100)).quantize(Q2, ROUND_HALF_UP)),
    }
