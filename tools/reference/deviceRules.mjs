// Rules a terminal needs while offline (plan 5.5 / 5.6 / 24.x). Must match the server and golden_bill_vectors.json.
export function fiscalYearLabel(localDateIso, startMonth) {          // localDateIso = "YYYY-MM-DD" in the OUTLET's time zone
  const y = Number(localDateIso.slice(0, 4)), m = Number(localDateIso.slice(5, 7));
  if (startMonth === 1) return String(y);
  const s = m >= startMonth ? y : y - 1;
  return `${s}-${String((s + 1) % 100).padStart(2, "0")}`;
}
export function businessDate(instantIso, timeZone, dayStartHour) {    // (local time − dayStartHour hours).toLocalDate()
  const t = new Date(instantIso).getTime() - dayStartHour * 3600_000;  // shift first, then read the local calendar date
  // NOTE: shifting by a fixed number of hours and then taking the local date is exactly what the plan specifies
  // (it subtracts hours from the local time); around DST changes this is the documented behaviour.
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date(t));
  const g = (k) => parts.find((p) => p.type === k).value;
  return `${g("year")}-${g("month")}-${g("day")}`;
}
export const billNumber = (series, fiscalYear, seq) => `${series}-${fiscalYear}-${String(seq).padStart(6, "0")}`;
