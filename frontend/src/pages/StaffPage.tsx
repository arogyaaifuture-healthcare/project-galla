import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { api, ApiError } from '../lib/api'
import { ROLES } from '../ui/Login'
import { when } from '../lib/format'
type Member = { id: string; name: string; email: string; phone?: string; role: string; status: string; lastLoginAt?: string }
const label = (r: string) => r.charAt(0) + r.slice(1).toLowerCase()
const msg = (e: unknown) => (e instanceof ApiError ? e.message : 'Something went wrong. Please try again.')

export default function StaffPage({ myId, isOwner }: { myId: string; isOwner: boolean }) {
  const [rows, setRows] = useState<Member[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [role, setRole] = useState('CASHIER')
  const roles = isOwner ? ROLES : ROLES.filter((r) => r !== 'OWNER')
  const load = useCallback(() => api<Member[]>('/users').then(setRows).catch((e) => setError(msg(e))), [])
  useEffect(() => { load() }, [load])

  async function add(e: FormEvent<HTMLFormElement>) {
    e.preventDefault(); setError(null); setBusy(true)
    const f = new FormData(e.currentTarget); const form = e.currentTarget
    try {
      await api('/users', { method: 'POST', body: JSON.stringify({ name: f.get('name'), email: f.get('email'), phone: f.get('phone') || undefined, role, password: f.get('password') }) })
      form.reset(); await load()
    } catch (err) { setError(err instanceof ApiError && err.details.length ? err.details.map((d) => d.message).join(' ') : msg(err)) } finally { setBusy(false) }
  }
  async function toggle(m: Member) {
    setError(null)
    try { await api('/users/' + m.id, { method: 'PATCH', body: JSON.stringify({ active: m.status !== 'ACTIVE' }) }); await load() } catch (err) { setError(msg(err)) }
  }
  async function reset(m: Member) {
    const password = window.prompt('New password for ' + m.name + ' (at least 10 characters)')
    if (!password) return
    setError(null)
    try { await api('/users/' + m.id + '/reset-password', { method: 'POST', body: JSON.stringify({ password }) }); window.alert('Password changed. ' + m.name + ' has been signed out everywhere.') } catch (err) { setError(msg(err)) }
  }

  return (
    <section className="panel stack"><h2>Staff</h2>
      {error && <div role="alert" className="alert">{error}</div>}
      <form className="stack" onSubmit={add} aria-label="Add staff member">
        <h3>Add a staff member</h3>
        <label>Name<input name="name" required maxLength={120} /></label>
        <label>Email<input name="email" type="email" required /></label>
        <label>Phone (optional)<input name="phone" inputMode="tel" /></label>
        <label>Role<select value={role} onChange={(e) => setRole(e.target.value)}>{roles.map((r) => <option key={r} value={r}>{label(r)}</option>)}</select></label>
        <label>Temporary password<input name="password" type="password" required minLength={10} autoComplete="new-password" /></label>
        <button className="btn primary" disabled={busy}>{busy ? 'Adding…' : 'Add staff member'}</button>
      </form>
      {!rows ? <p role="status">Loading…</p> : (
        <table className="tbl"><thead><tr><th>Name</th><th>Role</th><th>Last sign-in</th><th>Status</th><th /></tr></thead>
          <tbody>{rows.map((m) => (
            <tr key={m.id}><td>{m.name}<div className="muted">{m.email}</div></td><td>{label(m.role)}</td><td>{m.lastLoginAt ? when(m.lastLoginAt) : 'Never'}</td><td>{m.status === 'ACTIVE' ? 'Active' : 'Disabled'}</td>
              <td>{m.id !== myId && <>
                {(isOwner || m.role !== 'OWNER') && <button className="btn" onClick={() => toggle(m)}>{m.status === 'ACTIVE' ? 'Disable' : 'Enable'}</button>}
                {isOwner && <button className="btn" onClick={() => reset(m)}>Reset password</button>}</>}</td></tr>))}</tbody></table>)}
    </section>)
}
