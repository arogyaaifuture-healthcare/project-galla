import { lazy, Suspense, useState } from 'react'
import { canUse3D } from './lib/perf'
import { setToken, type Session } from './lib/api'
import { ErrorBoundary } from './ui/ErrorBoundary'
import Login from './ui/Login'
import MenuPage from './ui/MenuPage'
const Hero3D = lazy(() => import('./ui/Hero3D'))
export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const fancy = canUse3D()
  const onSession = (s: Session) => { setToken(s.accessToken); setSession(s) }
  const logout = () => { setToken(null); setSession(null) }
  return (
    <ErrorBoundary>
      {session ? <MenuPage session={session} onLogout={logout} /> : (
        <main className="stage">
          <div className="scene">{fancy && <Suspense fallback={null}><Hero3D /></Suspense>}</div>
          <Login onSession={onSession} />
        </main>)}
    </ErrorBoundary>)
}
