import { useCallback, useEffect, useState } from 'react'
import { api, ApiError } from '../lib/api'
import { day, rupees, when } from '../lib/format'
type Claim = { id: string; status: string; utr: string; createdAt: string; restaurant: string; invoiceNumber: string; amount: string; cycle: string }
type Plan = { id: string; name: string; priceMonthly: string; priceYearly: string; trialDays: number; maxUsers: number; maxOutlets: number; active: boolean }
type Restaurant = { tenantId: string; name: string; email: string; plan: string | null; effectiveStatus?: string; trialEndsAt: string | null; periodEnd: string | null }
type Tab = 'payments' | 'settings' | 'plans' | 'restaurants'
const msg = (e: unknown) => (e instanceof ApiError ? (e.details[0]?.message ?? e.message) : 'Something went wrong.')

export default function PlatformConsole({ onLogout }: { onLogout: () => void }) {
  const [tab, setTab] = useState<Tab>('payments')
  return (
    <main className="app platform">
      <header className="bar"><strong>Galla · Platform <span className="badge">PLATFORM</span></strong><button className="btn" onClick={onLogout}>Sign out</button></header>
      <nav className="tabs" aria-label="Platform sections">
        {(['payments', 'settings', 'plans', 'restaurants'] as Tab[]).map((t) => <button key={t} className={tab === t ? 'on' : ''} onClick={() => setTab(t)}>{t[0].toUpperCase() + t.slice(1)}</button>)}
      </nav>
      {tab === 'payments' && <Payments />}{tab === 'settings' && <Settings />}{tab === 'plans' && <Plans />}{tab === 'restaurants' && <Restaurants />}
    </main>)
}

function Payments() {
  const [rows, setRows] = useState<Claim[] | null>(null); const [error, setError] = useState<string | null>(null)
  const load = useCallback(() => { api<Claim[]>('/platform/claims?status=PENDING').then((r) => { setRows(r); setError(null) }).catch((e) => setError(msg(e))) }, [])
  useEffect(load, [load])
  async function confirm(c: Claim) { if (!window.confirm(`Confirm ${rupees(c.amount)} from ${c.restaurant}? Only confirm if the money is in your account.`)) return
    try { await api(`/platform/claims/${c.id}/confirm`, { method: 'POST' }); load() } catch (e) { setError(msg(e)) } }
  async function reject(c: Claim) { const reason = window.prompt('Reason for rejecting (the restaurant will not see this yet):'); if (!reason) return
    try { await api(`/platform/claims/${c.id}/reject`, { method: 'POST', body: JSON.stringify({ reason }) }); load() } catch (e) { setError(msg(e)) } }
  return (
    <section className="panel"><h2>Payments waiting for you</h2>
      {error && <div role="alert" className="alert">{error}</div>}
      {!rows ? <p role="status">Loading…</p> : rows.length === 0 ? <p className="muted">No payments waiting.</p> : (
        <table className="tbl"><thead><tr><th>Restaurant</th><th>Invoice</th><th>Amount</th><th>UTR</th><th>Submitted</th><th /></tr></thead>
          <tbody>{rows.map((c) => <tr key={c.id}><td>{c.restaurant}</td><td>{c.invoiceNumber}</td><td>{rupees(c.amount)}</td><td>{c.utr}</td><td>{when(c.createdAt)}</td>
            <td className="actions"><button className="btn primary" onClick={() => void confirm(c)}>Confirm</button><button className="btn" onClick={() => void reject(c)}>Reject</button></td></tr>)}</tbody></table>)}
      <p className="muted">Check your bank/UPI app for the credit (amount and UTR) before confirming.</p>
    </section>)
}

function Settings() {
  const [s, setS] = useState<Record<string, string> | null>(null); const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null)
  useEffect(() => { api<Record<string, string>>('/platform/settings').then(setS).catch((e) => setNote({ ok: false, text: msg(e) })) }, [])
  if (!s) return note ? <div role="alert" className="alert">{note.text}</div> : <p role="status">Loading…</p>
  const set = (k: string, v: string) => setS({ ...s, [k]: v })
  async function save(e: React.FormEvent) {
    e.preventDefault()
    try { const body = Object.fromEntries(['upi_vpa', 'upi_payee_name', 'expired_access_mode', 'default_grace_days', 'invoice_tax_percent'].map((k) => [k, s![k] ?? '']))
      setS(await api<Record<string, string>>('/platform/settings', { method: 'PUT', body: JSON.stringify(body) })); setNote({ ok: true, text: 'Saved.' }) }
    catch (err) { setNote({ ok: false, text: msg(err) }) }
  }
  return (
    <form className="panel stack" onSubmit={save}><h2>Payment settings</h2>
      {note && <div role={note.ok ? 'status' : 'alert'} className={note.ok ? 'ok' : 'alert'}>{note.text}</div>}
      <label>Your UPI ID (restaurants pay to this)<input value={s.upi_vpa ?? ''} onChange={(e) => set('upi_vpa', e.target.value)} placeholder="name@bank" /></label>
      <label>Name shown in the UPI app<input value={s.upi_payee_name ?? ''} onChange={(e) => set('upi_payee_name', e.target.value)} maxLength={60} /></label>
      <label>After the trial ends<select value={s.expired_access_mode ?? 'LOCKED'} onChange={(e) => set('expired_access_mode', e.target.value)}>
        <option value="LOCKED">Lock everything until they pay</option><option value="READ_ONLY">Let them view data, but not add anything</option></select></label>
      <label>Grace days after the trial or period ends<input inputMode="numeric" value={s.default_grace_days ?? ''} onChange={(e) => set('default_grace_days', e.target.value)} /></label>
      <label>Tax % on your invoices (0 if none)<input inputMode="decimal" value={s.invoice_tax_percent ?? ''} onChange={(e) => set('invoice_tax_percent', e.target.value)} /></label>
      <button className="btn primary">Save</button>
    </form>)
}

function Plans() {
  const [plans, setPlans] = useState<Plan[] | null>(null); const [note, setNote] = useState<string | null>(null)
  useEffect(() => { api<Plan[]>('/platform/plans').then(setPlans).catch((e) => setNote(msg(e))) }, [])
  async function save(e: React.FormEvent<HTMLFormElement>, p: Plan) {
    e.preventDefault(); const f = new FormData(e.currentTarget)
    try { const u = await api<Plan>(`/platform/plans/${p.id}`, { method: 'PATCH', body: JSON.stringify({ priceMonthly: f.get('m'), priceYearly: f.get('y'), trialDays: Number(f.get('t')) }) })
      setPlans((ps) => ps!.map((x) => (x.id === u.id ? u : x))); setNote(`${u.name} saved.`) } catch (err) { setNote(msg(err)) }
  }
  if (!plans) return note ? <div role="alert" className="alert">{note}</div> : <p role="status">Loading…</p>
  return (
    <section className="panel stack"><h2>Plans</h2>{note && <div role="status" className="ok">{note}</div>}
      {plans.map((p) => (
        <form key={p.id} className="inline" onSubmit={(e) => void save(e, p)}><strong>{p.name}</strong>
          <label>Monthly ₹<input name="m" defaultValue={p.priceMonthly} inputMode="decimal" /></label>
          <label>Yearly ₹<input name="y" defaultValue={p.priceYearly} inputMode="decimal" /></label>
          <label>Trial days<input name="t" defaultValue={p.trialDays} inputMode="numeric" /></label>
          <button className="btn primary">Save</button></form>))}
      <p className="muted">A price of 0 means “not set”: restaurants cannot pay until you set real prices.</p>
    </section>)
}

function Restaurants() {
  const [rows, setRows] = useState<Restaurant[] | null>(null); const [error, setError] = useState<string | null>(null)
  useEffect(() => { api<Restaurant[]>('/platform/tenants').then(setRows).catch((e) => setError(msg(e))) }, [])
  if (error) return <div role="alert" className="alert">{error}</div>
  if (!rows) return <p role="status">Loading…</p>
  return (
    <section className="panel"><h2>Restaurants ({rows.length})</h2>
      {rows.length === 0 ? <p className="muted">No restaurants yet.</p> : (
        <table className="tbl"><thead><tr><th>Name</th><th>Email</th><th>Plan</th><th>Status</th><th>Ends</th></tr></thead>
          <tbody>{rows.map((r) => <tr key={r.tenantId}><td>{r.name}</td><td>{r.email}</td><td>{r.plan ?? '—'}</td><td>{r.effectiveStatus ?? '—'}</td><td>{day(r.effectiveStatus === 'TRIALING' ? r.trialEndsAt : r.periodEnd)}</td></tr>)}</tbody></table>)}
    </section>)
}
