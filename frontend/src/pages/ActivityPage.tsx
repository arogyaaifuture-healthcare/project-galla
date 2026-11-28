import { useEffect, useState } from 'react'
import { api, ApiError } from '../lib/api'
import { when } from '../lib/format'
type Row = { id: number; at: string; actor: string; actorType: string; action: string; entityType: string }
const label = (a: string) => a.toLowerCase().replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase())
export default function ActivityPage() {
  const [rows, setRows] = useState<Row[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  useEffect(() => { api<Row[]>('/audit?limit=100').then(setRows).catch((e) => setError(e instanceof ApiError ? e.message : 'Could not load activity.')) }, [])
  if (error) return <div role="alert" className="alert">{error}</div>
  if (!rows) return <p role="status">Loading…</p>
  return (
    <section className="panel"><h2>Activity</h2>
      {rows.length === 0 ? <p className="muted">Nothing has happened yet.</p> : (
        <table className="tbl"><thead><tr><th>When</th><th>Who</th><th>What</th></tr></thead>
          <tbody>{rows.map((r) => <tr key={r.id}><td>{when(r.at)}</td><td>{r.actor || (r.actorType === 'SYSTEM' ? 'System' : '—')}</td><td>{label(r.action)}</td></tr>)}</tbody></table>)}
    </section>)
}
