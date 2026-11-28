import { useCallback, useEffect, useState } from 'react'
import { api, ApiError } from '../lib/api'
import { day, rupees } from '../lib/format'
import Qr from '../ui/Qr'

export type Invoice = { id: string; number: string; amount: string; currency: string; cycle: string; periodStart: string; periodEnd: string; status: string; upiUri: string | null }
export type Sub = { status: string; planName: string; cycle: string; trialEndsAt: string | null; periodEnd: string | null; daysLeft: number; pricingSet: boolean; priceMonthly: string; priceYearly: string
  accessMode: string; upiConfigured: boolean; openInvoice: Invoice | null; pendingClaim: { utr: string; status: string } | null }
const STATUS_TEXT: Record<string, string> = { TRIALING: 'Free trial', ACTIVE: 'Active', PAST_DUE: 'Payment overdue', SUSPENDED: 'Subscription ended', CANCELLED: 'Cancelled' }

export default function SubscriptionPage({ isOwner }: { isOwner: boolean }) {
  const [sub, setSub] = useState<Sub | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [cycle, setCycle] = useState<'MONTHLY' | 'YEARLY'>('MONTHLY')
  const [busy, setBusy] = useState(false)
  const [utr, setUtr] = useState('')
  const load = useCallback(async () => {
    try { setSub(await api<Sub>('/subscription')); setError(null) }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Could not load the subscription.') }
  }, [])
  useEffect(() => { void load() }, [load])

  async function pay() {
    setBusy(true); setError(null)
    try { await api('/subscription/invoices', { method: 'POST', body: JSON.stringify({ cycle }) }); await load() }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Could not create the invoice.') } finally { setBusy(false) }
  }
  async function submitClaim(invoiceId: string) {
    setBusy(true); setError(null)
    try { await api(`/subscription/invoices/${invoiceId}/claim`, { method: 'POST', body: JSON.stringify({ utr }) }); setUtr(''); await load() }
    catch (e) { setError(e instanceof ApiError ? (e.details[0]?.message ?? e.message) : 'Could not submit the payment.') } finally { setBusy(false) }
  }

  if (!sub) return error ? <div role="alert" className="alert">{error} <button className="btn" onClick={() => void load()}>Retry</button></div> : <p role="status">Loading…</p>
  const inv = sub.openInvoice
  const needsPay = sub.status !== 'ACTIVE' || sub.daysLeft <= 7
  return (
    <section className="panel stack">
      <h2>Subscription</h2>
      <p><strong>{STATUS_TEXT[sub.status] ?? sub.status}</strong> · {sub.planName}
        {(sub.status === 'TRIALING' || sub.status === 'ACTIVE') && <> · {sub.daysLeft} day{sub.daysLeft === 1 ? '' : 's'} left (till {day(sub.status === 'TRIALING' ? sub.trialEndsAt : sub.periodEnd)})</>}</p>
      {sub.status === 'SUSPENDED' && <div role="alert" className="alert">Your free trial has ended. Pay to continue using Galla. Your data is safe.</div>}
      {error && <div role="alert" className="alert">{error}</div>}
      {!isOwner && <p className="muted">Only the restaurant owner can pay. Please ask them.</p>}
      {isOwner && !sub.pricingSet && <p className="alert" role="status">Pricing is not available yet. Please contact support.</p>}
      {isOwner && sub.pricingSet && !sub.upiConfigured && <p className="alert" role="status">Payments are not set up yet. Please contact support.</p>}
      {isOwner && sub.pricingSet && !inv && needsPay && (
        <div className="stack">
          <div className="seg" role="radiogroup" aria-label="Billing period">
            <button type="button" role="radio" aria-checked={cycle === 'MONTHLY'} className={cycle === 'MONTHLY' ? 'on' : ''} onClick={() => setCycle('MONTHLY')}>Monthly {rupees(sub.priceMonthly)}</button>
            <button type="button" role="radio" aria-checked={cycle === 'YEARLY'} className={cycle === 'YEARLY' ? 'on' : ''} onClick={() => setCycle('YEARLY')}>Yearly {rupees(sub.priceYearly)}</button>
          </div>
          <button className="btn primary" disabled={busy} onClick={() => void pay()}>{busy ? 'Please wait…' : 'Pay now'}</button>
        </div>)}
      {isOwner && inv && (
        <div className="stack center">
          <p>Invoice <strong>{inv.number}</strong> · <strong>{rupees(inv.amount)}</strong> for {day(inv.periodStart)} – {day(inv.periodEnd)}</p>
          {inv.upiUri ? (<>
            <Qr value={inv.upiUri} />
            <a className="btn primary" href={inv.upiUri}>Open in UPI app</a>
            <p className="muted">Scan with any UPI app (PhonePe, Google Pay, Paytm…). The amount is filled in. Pay exactly {rupees(inv.amount)}.</p></>)
            : <p className="alert" role="status">Payments are not set up yet. Please contact support.</p>}
          {sub.pendingClaim ? (
            <p role="status" className="ok">Payment reference <strong>{sub.pendingClaim.utr}</strong> received. We will confirm it shortly.</p>
          ) : (
            <form className="stack" onSubmit={(e) => { e.preventDefault(); void submitClaim(inv.id) }}>
              <label>After paying, enter the 12-digit UTR / reference number
                <input value={utr} onChange={(e) => setUtr(e.target.value)} inputMode="text" autoComplete="off" required minLength={10} maxLength={30} placeholder="e.g. 412345678901" /></label>
              <button className="btn primary" disabled={busy || utr.trim().length < 10}>I have paid</button>
            </form>)}
        </div>)}
    </section>)
}
