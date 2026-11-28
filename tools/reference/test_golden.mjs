// Node test: reproduce EVERY golden vector exactly. Run: npm install && node test_golden.mjs
import fs from "node:fs";
import { calculate } from "./billCalculator.mjs";
import { fiscalYearLabel, businessDate, billNumber } from "./deviceRules.mjs";
const g = JSON.parse(fs.readFileSync(new URL("./golden_bill_vectors.json", import.meta.url)));
let pass = 0, fail = 0; const failures = [];
const m = (x) => x.toFixed(2);
for (const c of g.billCases) {
  try {
    let r, err = null;
    try { r = calculate(c.input.lines, c.input); } catch (e) { err = e.message; }
    if (c.expected.error) {
      if (err !== c.expected.error) throw new Error(`expected error ${c.expected.error}, got ${err ?? "result"}`);
    } else {
      if (err) throw new Error("unexpected error " + err);
      const e = c.expected;
      const top = { subtotal: m(r.subtotal), discountTotal: m(r.discountTotal), taxTotal: m(r.taxTotal),
        totalBeforeRoundOff: m(r.totalBeforeRoundOff), roundOff: m(r.roundOff), grandTotal: m(r.grandTotal) };
      for (const k of Object.keys(top)) if (top[k] !== e[k]) throw new Error(`${k}: ${top[k]} != ${e[k]}`);
      if (r.lines.length !== e.lines.length) throw new Error(`line count ${r.lines.length} != ${e.lines.length}`);
      r.lines.forEach((l, i) => {
        const x = e.lines[i];
        const got = [l.type, l.name, m(l.gross), m(l.discount), m(l.taxable), m(l.tax), m(l.total)];
        const want = [x.type, x.name, x.gross, x.discount, x.taxable, x.tax, x.total];
        if (got.join("|") !== want.join("|")) throw new Error(`line ${i}: ${got} != ${want}`);
        if (l.comps.length !== x.comps.length) throw new Error(`line ${i} comps count`);
        l.comps.forEach(([n, rt, tx], j) => {
          if (n !== x.comps[j][0] || !rt.eq(x.comps[j][1]) || m(tx) !== x.comps[j][2]) throw new Error(`line ${i} comp ${j}: ${n} ${rt} ${m(tx)} != ${x.comps[j]}`);
        });
      });
    }
    pass++;
  } catch (e) { fail++; failures.push(`${c.name}: ${e.message}`); }
}
for (const d of g.deviceRuleCases) {
  try {
    if (d.fiscalYear) { const x = d.fiscalYear, got = fiscalYearLabel(x.localDate, x.startMonth); if (got !== x.expected) throw new Error(`fy ${x.localDate}/${x.startMonth}: ${got} != ${x.expected}`); }
    else { const x = d.businessDate, got = businessDate(x.instant, x.tz, x.dayStartHour); if (got !== x.expected) throw new Error(`bd ${x.instant} ${x.tz}: ${got} != ${x.expected}`); }
    pass++;
  } catch (e) { fail++; failures.push(e.message); }
}
// the order of input lines must not matter (canonical sort) — shuffle every case and compare totals
let shuffled = 0;
for (const c of g.billCases.filter((c) => !c.expected.error)) {
  const rev = [...c.input.lines].reverse();
  const a = calculate(c.input.lines, c.input), b = calculate(rev, c.input);
  if (m(a.grandTotal) !== m(b.grandTotal) || m(a.taxTotal) !== m(b.taxTotal)) { fail++; failures.push(`${c.name}: order dependent`); } else shuffled++;
}
if (billNumber("A", "2026-27", 123) !== "A-2026-27-000123") { fail++; failures.push("billNumber"); } else pass++;
console.log(`golden: ${pass} passed, ${fail} failed (${g.billCases.length} bill cases, ${g.deviceRuleCases.length} device-rule cases, ${shuffled} order-independence checks)`);
if (fail) { console.log(failures.slice(0, 15).join("\n")); process.exit(1); }
