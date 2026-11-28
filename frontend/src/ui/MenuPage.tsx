import { useCallback, useEffect, useState } from 'react'
import { api, ApiError, type Session } from '../lib/api'
type Outlet = { id: string; name: string }
type Category = { id: string; name: string; active: boolean }
type Item = { id: string; categoryId: string; name: string; basePrice: string; foodType: string; available: boolean; version: number }
type State = { kind: 'loading' } | { kind: 'error'; message: string } | { kind: 'ready'; outlet: Outlet; cats: Category[]; items: Item[] }

export default function MenuPage({ session, onLogout }: { session: Session; onLogout: () => void }) {
  const [st, setSt] = useState<State>({ kind: 'loading' })
  const [msg, setMsg] = useState<string | null>(null)
  const canEdit = session.user.role === 'OWNER' || session.user.role === 'MANAGER'
  const load = useCallback(async () => {
    setSt({ kind: 'loading' })
    try {
      const outlets = await api<Outlet[]>('/outlets')
      if (!outlets.length) throw new ApiError(404, 'NO_OUTLET', 'No outlet found for this restaurant.')
      const o = outlets[0]
      const [cats, items] = await Promise.all([api<Category[]>(`/menu/categories?outletId=${o.id}`), api<Item[]>(`/menu/items?outletId=${o.id}`)])
      setSt({ kind: 'ready', outlet: o, cats, items })
    } catch (e) { setSt({ kind: 'error', message: e instanceof ApiError ? e.message : 'Something went wrong.' }) }
  }, [])
  useEffect(() => { void load() }, [load])

  async function addCategory(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault(); if (st.kind !== 'ready') return
    const form = e.currentTarget; const name = String(new FormData(form).get('name') ?? '').trim(); if (!name) return
    try { await api('/menu/categories', { method: 'POST', body: JSON.stringify({ outletId: st.outlet.id, name }) }); form.reset(); setMsg(null); await load() }
    catch (err) { setMsg(err instanceof ApiError ? err.message : 'Could not add the category.') }
  }
  async function addItem(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault(); if (st.kind !== 'ready') return
    const form = e.currentTarget; const f = new FormData(form)
    try {
      await api('/menu/items', { method: 'POST', body: JSON.stringify({ outletId: st.outlet.id, categoryId: f.get('categoryId'), name: f.get('name'), basePrice: f.get('basePrice') }) })
      form.reset(); setMsg(null); await load()
    } catch (err) { setMsg(err instanceof ApiError ? (err.details[0]?.message ?? err.message) : 'Could not add the item.') }
  }

  return (
    <main className="app">
      <header className="bar"><strong>Galla</strong><span className="muted">{session.user.name} · {session.user.role.toLowerCase()}</span><button className="btn" onClick={onLogout}>Sign out</button></header>
      <h2>Menu</h2>
      {msg && <div role="alert" className="alert">{msg}</div>}
      {st.kind === 'loading' && <p role="status">Loading menu…</p>}
      {st.kind === 'error' && <div role="alert" className="alert">{st.message} <button className="btn" onClick={() => void load()}>Retry</button></div>}
      {st.kind === 'ready' && (<>
        {canEdit && (<div className="row">
          <form onSubmit={addCategory} className="inline"><input name="name" placeholder="New category" aria-label="Category name" required maxLength={80} /><button className="btn">Add category</button></form>
          {st.cats.length > 0 && (<form onSubmit={addItem} className="inline">
            <select name="categoryId" aria-label="Category" required>{st.cats.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
            <input name="name" placeholder="Item name" aria-label="Item name" required maxLength={120} />
            <input name="basePrice" placeholder="Price" aria-label="Price" inputMode="decimal" pattern="\d{1,10}(\.\d{1,2})?" required />
            <button className="btn primary">Add item</button></form>)}
        </div>)}
        {st.cats.length === 0 ? <p className="panel">No menu yet.{canEdit ? ' Add your first category above.' : ' Ask your manager to add items.'}</p>
          : st.cats.map((c) => (
            <section key={c.id} className="panel"><h3>{c.name}</h3>
              {st.items.filter((i) => i.categoryId === c.id).length === 0 ? <p className="muted">No items in this category.</p>
                : <ul className="items">{st.items.filter((i) => i.categoryId === c.id).map((i) => <li key={i.id}><span>{i.name}</span><span>₹{i.basePrice}</span></li>)}</ul>}
            </section>))}
      </>)}
    </main>)
}
