// Galla offline billing — JS/TS port of reference/bill_calculator.py (plan Section 5.3). Pure, Decimal only.
// Must reproduce golden_bill_vectors.json exactly. Python's Decimal context = precision 28, ROUND_HALF_EVEN for division;
// money rounding is always explicit HALF_UP.
import DecimalLib from "decimal.js";
const Decimal = DecimalLib.clone({ precision: 28, rounding: DecimalLib.ROUND_HALF_EVEN });
const HALF_UP = Decimal.ROUND_HALF_UP;
const D = (x) => new Decimal(x);
const ZERO = D("0.00");
const r2 = (x) => x.toDecimalPlaces(2, HALF_UP);
const toCents = (x) => x.times(100).toDecimalPlaces(0, Decimal.ROUND_HALF_EVEN).toNumber();
const fromCents = (c) => D(c).dividedBy(100).toDecimalPlaces(2, HALF_UP);

export function allocate(totalCents, weights) {
  const wsum = weights.reduce((a, b) => a + b, 0);
  if (wsum === 0 || totalCents === 0) return weights.map(() => 0);
  const exact = weights.map((w) => D(totalCents).times(D(w)).dividedBy(D(wsum)));
  const floors = exact.map((e) => e.floor().toNumber());
  const rest = totalCents - floors.reduce((a, b) => a + b, 0);
  const order = [...weights.keys()].sort((i, j) => {
    const fi = exact[i].minus(floors[i]), fj = exact[j].minus(floors[j]);
    const c = fj.comparedTo(fi);          // larger remainder first
    return c !== 0 ? c : i - j;           // then lower index
  });
  for (const i of order.slice(0, rest)) floors[i] += 1;
  return floors;
}

function splitTaxByRate(taxCents, rates) {
  if (rates.reduce((a, r) => a.plus(r), D(0)).isZero()) return rates.map(() => 0);
  return allocate(taxCents, rates.map((r) => toCents(r)));
}

function taxLine(net, comps, inclusive) {
  if (!comps.length) return { taxable: net, tax: ZERO, comps: [], total: net };
  const totalRate = comps.reduce((a, [, r]) => a.plus(r), D(0));
  if (!inclusive) {
    const taxes = comps.map(([, r]) => r2(net.times(r).dividedBy(100)));
    const t = taxes.reduce((a, b) => a.plus(b), ZERO);
    return { taxable: net, tax: t, comps: comps.map(([n, r], i) => [n, r, taxes[i]]), total: net.plus(t) };
  }
  if (totalRate.isZero()) return { taxable: net, tax: ZERO, comps: comps.map(([n, r]) => [n, r, ZERO]), total: net };
  const taxable = r2(net.times(100).dividedBy(D(100).plus(totalRate)));
  const tax = net.minus(taxable);
  const parts = splitTaxByRate(toCents(tax), comps.map(([, r]) => r));
  return { taxable, tax, comps: comps.map(([n, r], i) => [n, r, fromCents(parts[i])]), total: net };
}

const cmpStr = (a, b) => (a < b ? -1 : a > b ? 1 : 0);   // code-point order for ASCII ids/names, same as Python's str ordering
const asComps = (c) => (c || []).map(([n, r]) => [n, D(r)]);

/** opts: {pricesIncludeTax, roundOffMode, discount:[kind,value]|null, serviceChargePercent, serviceChargeComps,
 *         deliveryCharge, deliveryComps, extraCharges:[{type,name,amount,comps}]}  — money/qty as strings or Decimals */
export function calculate(rawLines, opts) {
  const o = {
    inclusive: !!opts.pricesIncludeTax, roundOffMode: opts.roundOffMode ?? "NEAREST_1",
    discount: opts.discount ?? null, scp: D(opts.serviceChargePercent ?? 0), scc: asComps(opts.serviceChargeComps),
    dc: D(opts.deliveryCharge ?? 0), dcc: asComps(opts.deliveryComps), extra: opts.extraCharges ?? [],
  };
  // CANONICAL ORDER: sort by line id so tie-breaks never depend on input order (stable sort)
  const lines = [...rawLines].sort((a, b) => cmpStr(String(a.id ?? ""), String(b.id ?? "")));
  const gross = lines.map((l) => r2(D(l.qty).times(D(l.unitPrice))));
  const subtotal = gross.reduce((a, b) => a.plus(b), ZERO);
  let discTotal = ZERO;
  if (o.discount) {
    const [kind, v] = o.discount, val = D(v);
    if (kind === "PERCENT") {
      if (!(val.gt(0) && val.lte(100))) throw new Error("VALIDATION_ERROR");
      discTotal = r2(subtotal.times(val).dividedBy(100));
    } else {
      if (val.lte(0)) throw new Error("VALIDATION_ERROR");
      if (val.gt(subtotal)) throw new Error("DISCOUNT_EXCEEDS_SUBTOTAL");
      discTotal = val;
    }
  }
  const alloc = allocate(toCents(discTotal), gross.map(toCents));
  const out = [];
  lines.forEach((l, i) => {
    const d = fromCents(alloc[i]), net = gross[i].minus(d);
    const t = taxLine(net, asComps(l.comps), o.inclusive);
    out.push({ type: "ITEM", name: l.name, gross: gross[i], discount: d, ...t });
  });
  const pushCharge = (type, name, amount, comps) => {
    const t = taxLine(amount, comps, o.inclusive);
    out.push({ type, name, gross: amount, discount: ZERO, ...t });
  };
  if (o.scp.gt(0)) {
    const sc = r2(subtotal.minus(discTotal).times(o.scp).dividedBy(100));
    if (sc.gt(0)) pushCharge("SERVICE_CHARGE", "Service charge", sc, o.scc);
  }
  if (o.dc.gt(0)) pushCharge("DELIVERY_CHARGE", "Delivery charge", o.dc, o.dcc);
  [...o.extra].sort((a, b) => cmpStr(a.type, b.type) || cmpStr(a.name, b.name)).forEach((e) => {
    const amt = D(e.amount);
    if (amt.gt(0)) pushCharge(e.type, e.name, amt, asComps(e.comps));
  });
  const taxTotal = out.reduce((a, l) => a.plus(l.tax), ZERO);
  const before = out.reduce((a, l) => a.plus(l.total), ZERO);
  const grand = o.roundOffMode === "NONE" ? before : before.toDecimalPlaces(0, HALF_UP).toDecimalPlaces(2, HALF_UP);
  return { subtotal, discountTotal: discTotal, taxTotal, totalBeforeRoundOff: before, roundOff: grand.minus(before), grandTotal: grand, lines: out };
}
