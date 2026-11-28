import { lazy, Suspense, useEffect, useState } from 'react'
import { canUse3D } from './lib/perf'
import { api, setToken, type Session } from './lib/api'
import { ErrorBoundary } from './ui/ErrorBoundary'
import Login from './ui/Login'
import PlatformLogin from './ui/PlatformLogin'
import MenuPage from './pages/MenuPage'
import SubscriptionPage, { type Sub } from './pages/SubscriptionPage'
import ActivityPage from './pages/ActivityPage'
import PlatformConsole from './pages/PlatformConsole'
const Hero3D = lazy(() => import('./ui/Hero3D'))
type Page = 'menu' | 'subscription' | 'activity'

function Banner({ sub, goPay }: { sub: Sub | null; goPay: () => void }) {
  if (!sub) return null
  if (sub.status === 'TRIALING') return <div role="status" className={'banner ' + (sub.daysLeft <= 7 ? 'warn' : 'info')}>Free trial: {sub.daysLeft} day{sub.daysLeft === 1 ? '' : 's'} left <button className="link" onClick={goPay}>Choose a plan</button></div>
  if (sub.status === 'PAST_DUE') return <div role="alert" className="banner bad">Payment overdue — your access will stop soon. <button className="link" onClick={goPay}>Pay now</button></div>
  if (sub.status === 'ACTIVE' && sub.daysLeft <= 7) return <div role="status" className="banner warn">Your plan renews in {sub.daysLeft} day{sub.daysLeft === 1 ? '' : 's'} <button className="link" onClick={goPay}>Renew</button></div>
  return null
}

function RestaurantApp({ session, onLogout }: { session: Session; onLogout: () => void }) {
  const boss = session.user.role === 'OWNER' || session.user.role === 'MANAGER'
  const [page, setPage] = useState<Page>('menu')
  const [locked, setLocked] = useState(false)
  const [sub, setSub] = useState<Sub | null>(null)
  useEffect(() => { const f = () => setLocked(true); window.addEventListener('galla:inactive', f); return () => window.removeEventListener('galla:inactive', f) }, [])
  useEffect(() => { if (boss) api<Sub>('/subscription').then(setSub).catch(() => setSub(null)) }, [boss, page])

  return (
    <main className="app">
      <header className="bar"><strong>Galla</strong><span className="muted">{session.user.name} · {session.user.role.toLowerCase()}</span><button className="btn" onClick={onLogout}>Sign out</button></header>
      {locked ? (
        <section className="panel stack" role="alert"><h2>Subscription ended</h2>
          <p>Your free trial or subscription has ended. {session.user.role === 'OWNER' ? 'Pay to continue.' : 'Please ask the restaurant owner to pay.'}</p>
          {session.user.role === 'OWNER' && <SubscriptionPage isOwner />}</section>
      ) : (<>
        <Banner sub={sub} goPay={() => setPage('subscription')} />
        <nav className="tabs" aria-label="Sections">
          <button className={page === 'menu' ? 'on' : ''} onClick={() => setPage('menu')}>Menu</button>
          {boss && <button className={page === 'subscription' ? 'on' : ''} onClick={() => setPage('subscription')}>Subscription</button>}
          {boss && <button className={page === 'activity' ? 'on' : ''} onClick={() => setPage('activity')}>Activity</button>}
        </nav>
        {page === 'menu' && <MenuPage session={session} />}
        {page === 'subscription' && boss && <SubscriptionPage isOwner={session.user.role === 'OWNER'} />}
        {page === 'activity' && boss && <ActivityPage />}
      </>)}
    </main>)
}

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [platform, setPlatform] = useState<'login' | 'in' | null>(null)
  const fancy = canUse3D()
  const onSession = (s: Session) => { setToken(s.accessToken); setSession(s) }
  const logout = () => { setToken(null); setSession(null); setPlatform(null) }
  return (
    <ErrorBoundary>
      {platform === 'in' ? <PlatformConsole onLogout={logout} />
        : session ? <RestaurantApp session={session} onLogout={logout} />
        : (<main className="stage">
            <div className="scene">{fancy && <Suspense fallback={null}><Hero3D /></Suspense>}</div>
            {platform === 'login' ? <PlatformLogin onToken={(t) => { setToken(t); setPlatform('in') }} onBack={() => setPlatform(null)} />
              : <Login onSession={onSession} onPlatform={() => setPlatform('login')} />}
          </main>)}
    </ErrorBoundary>)
}
