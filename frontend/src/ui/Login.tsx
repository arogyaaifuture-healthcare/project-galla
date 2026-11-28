import { useState, type FormEvent } from 'react'
import { api, ApiError, type Session } from '../lib/api'
export const ROLES = ['OWNER', 'MANAGER', 'CASHIER', 'CAPTAIN', 'KITCHEN', 'RIDER', 'INVENTORY', 'ACCOUNTANT'] as const
const label = (r: string) => r.charAt(0) + r.slice(1).toLowerCase()

export default function Login({ onSession, onPlatform }: { onSession: (s: Session) => void; onPlatform?: () => void }) {
  const [mode, setMode] = useState<'login' | 'register'>('login')
  const [role, setRole] = useState<(typeof ROLES)[number]>('OWNER')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [fields, setFields] = useState<Record<string, string>>({})

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const f = new FormData(e.currentTarget)
    setBusy(true); setError(null); setFields({})
    try {
      const s = mode === 'login'
        ? await api<Session>('/auth/login', { method: 'POST', body: JSON.stringify({ email: f.get('email'), password: f.get('password'), role }) })
        : await api<Session>('/auth/register', { method: 'POST', body: JSON.stringify({ restaurantName: f.get('restaurantName'), ownerName: f.get('ownerName'), email: f.get('email'), password: f.get('password') }) })
      onSession(s)
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message)
        setFields(Object.fromEntries(err.details.map((d) => [d.field, d.message])))
      } else setError('Something went wrong. Please try again.')
    } finally { setBusy(false) }
  }

  return (
    <form className="panel login" onSubmit={submit} aria-label={mode === 'login' ? 'Sign in' : 'Create account'} noValidate>
      <h1>Galla</h1>
      <p className="muted">{mode === 'login' ? 'Restaurant billing that stays fast.' : 'Start your free trial. No card needed.'}</p>
      {error && <div role="alert" className="alert">{error}</div>}
      {mode === 'login' && (
        <label>Sign in as
          <select value={role} onChange={(e) => setRole(e.target.value as typeof role)}>
            {ROLES.map((r) => <option key={r} value={r}>{label(r)}</option>)}
          </select></label>)}
      {mode === 'register' && (<>
        <label>Restaurant name<input name="restaurantName" required maxLength={120} /><span className="field-error">{fields.restaurantName}</span></label>
        <label>Your name<input name="ownerName" required maxLength={120} /><span className="field-error">{fields.ownerName}</span></label></>)}
      <label>Email<input name="email" type="email" autoComplete="username" required /><span className="field-error">{fields.email}</span></label>
      <label>Password<input name="password" type="password" autoComplete={mode === 'login' ? 'current-password' : 'new-password'} required minLength={mode === 'register' ? 10 : undefined} />
        <span className="field-error">{fields.password}</span></label>
      <button className="btn primary" type="submit" disabled={busy}>{busy ? 'Please wait…' : mode === 'login' ? 'Sign in' : 'Create account'}</button>
      <button type="button" className="btn" onClick={() => { setMode(mode === 'login' ? 'register' : 'login'); setError(null); setFields({}) }}>
        {mode === 'login' ? 'New restaurant? Create an account' : 'Have an account? Sign in'}</button>
      {onPlatform && <button type="button" className="link" onClick={onPlatform}>Galla owner? Platform sign-in</button>}
    </form>)
}
