import { useEffect, useState, type FormEvent } from 'react'
import { api, ApiError } from '../lib/api'
type Outlet = { id: string; name: string; addressLine1?: string; addressLine2?: string; city?: string; state?: string; postalCode?: string; phone?: string; email?: string; gstin?: string; fssai?: string; billHeader?: string; billFooter?: string; version: number }
const FIELDS: [keyof Outlet, string, string?][] = [
  ['name', 'Restaurant / outlet name'], ['addressLine1', 'Address line 1'], ['addressLine2', 'Address line 2'], ['city', 'City'], ['state', 'State'], ['postalCode', 'PIN code'],
  ['phone', 'Phone'], ['email', 'Email'], ['gstin', 'GSTIN', 'e.g. 27ABCDE1234F1Z5'], ['fssai', 'FSSAI licence number', '14 digits'], ['billHeader', 'Bill header'], ['billFooter', 'Bill footer'],
]
export default function OutletPage({ canEdit }: { canEdit: boolean }) {
  const [o, setO] = useState<Outlet | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    api<{ id: string }[]>('/outlets').then((l) => (l.length ? api<Outlet>('/outlets/' + l[0].id).then(setO) : Promise.reject(new ApiError(404, 'NO_OUTLET', 'No outlet found for this restaurant.')))).catch((e) => setError(e instanceof ApiError ? e.message : 'Could not load settings.'))
  }, [])
  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault(); if (!o) return
    setError(null); setSaved(false); setBusy(true)
    const f = new FormData(e.currentTarget); const body: Record<string, unknown> = { version: o.version }
    for (const [k] of FIELDS) body[k] = String(f.get(k) ?? '').trim()
    try { setO(await api<Outlet>('/outlets/' + o.id, { method: 'PATCH', body: JSON.stringify(body) })); setSaved(true) }
    catch (err) {
      if (err instanceof ApiError && err.code === 'STALE_VERSION') setError('Someone else changed these settings. Reload the page and try again.')
      else setError(err instanceof ApiError ? (err.details.length ? err.details.map((d) => d.message).join(' ') : err.message) : 'Could not save.')
    } finally { setBusy(false) }
  }
  if (!o) return error ? <div role="alert" className="alert">{error}</div> : <p role="status">Loading…</p>
  return (
    <section className="panel"><h2>Restaurant details</h2>
      <p className="muted">These appear on your bills. GSTIN and FSSAI are optional now and can be added later.</p>
      {error && <div role="alert" className="alert">{error}</div>}
      {saved && <div role="status" className="banner info">Saved.</div>}
      <form className="stack" onSubmit={save} key={o.version}>
        {FIELDS.map(([k, l, ph]) => <label key={k}>{l}<input name={k} defaultValue={(o[k] as string | undefined) ?? ''} placeholder={ph} disabled={!canEdit} /></label>)}
        {canEdit && <button className="btn primary" disabled={busy}>{busy ? 'Saving…' : 'Save'}</button>}
      </form>
    </section>)
}
