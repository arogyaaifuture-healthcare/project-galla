import { useState } from 'react'
const ROLES = ['Owner', 'Manager', 'Cashier', 'Kitchen', 'Accountant', 'Rider'] as const
export default function Login() {
  const [role, setRole] = useState<(typeof ROLES)[number]>('Cashier')
  return (
    <form className="panel login" onSubmit={(e) => e.preventDefault()} aria-label="Sign in">
      <h1>Galla</h1><p className="muted">Restaurant billing that stays fast.</p>
      <label>Sign in as
        <select value={role} onChange={(e) => setRole(e.target.value as typeof role)}>
          {ROLES.map((r) => <option key={r}>{r}</option>)}
        </select></label>
      <label>Email or phone<input autoComplete="username" required /></label>
      <label>Password<input type="password" autoComplete="current-password" required /></label>
      <button className="btn primary" type="submit">Sign in</button>
      <small className="muted">API connection is added in Phase 1.</small>
    </form>)
}
