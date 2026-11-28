import { lazy, Suspense } from 'react'
import { canUse3D } from './lib/perf'
import { ErrorBoundary } from './ui/ErrorBoundary'
import Login from './ui/Login'
const Hero3D = lazy(() => import('./ui/Hero3D'))
export default function App() {
  const fancy = canUse3D()
  return (
    <ErrorBoundary>
      <main className="stage">
        <div className="scene">{fancy && <Suspense fallback={null}><Hero3D /></Suspense>}</div>
        <Login />
      </main>
    </ErrorBoundary>)
}
