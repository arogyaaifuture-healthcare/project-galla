import { useState, type FormEvent } from 'react'
import { api, ApiError } from '../lib/api'
export default function PlatformLogin({ onToken, onBack }: { onToken: (token: string) => void; onBack: () => void }) {
  const [error, setError] = useState<string | null>(null); const [busy, setBusy] = useState(false)
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault(); const f = new FormData(e.currentTarget); setBusy(true); setError(null)
    try { const r = await api<{ accessToken: string }>('/platform/auth/login', { method: 'POST', body: JSON.stringify({ email: f.get('email'), password: f.get('password') }) }); onToken(r.accessToken) }
    catch (err) { setError(err instanceof ApiError ? err.message : 'Something went wrong.') } finally { setBusy(false) }
  }
  return (
    <form className="panel login" onSubmit={submit} aria-label="Platform sign in" noValidate>
      <h1>Platform</h1><p className="muted">Galla owner sign-in</p>
      {error && <div role="alert" className="alert">{error}</div>}
      <label>Email<input name="email" type="email" autoComplete="username" required /></label>
      <label>Password<input name="password" type="password" autoComplete="current-password" required /></label>
      <button className="btn primary" disabled={busy}>{busy ? 'Please wait…' : 'Sign in'}</button>
      <button type="button" className="btn" onClick={onBack}>Back to restaurant sign in</button>
    </form>)
}
