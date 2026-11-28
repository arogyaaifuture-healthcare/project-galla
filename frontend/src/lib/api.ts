export type User = { id: string; tenantId: string; name: string; email: string; role: string }
export type Session = { accessToken: string; expiresInSeconds: number; user: User }
export class ApiError extends Error {
  status: number
  code: string
  details: { field: string; message: string }[]
  constructor(status: number, code: string, message: string, details: { field: string; message: string }[] = []) {
    super(message); this.status = status; this.code = code; this.details = details
  }
}
let token: string | null = null
export const setToken = (t: string | null) => { token = t }
// The refresh cookie is HttpOnly, so the page cannot see it. A harmless hint says whether trying is worthwhile,
// which avoids a pointless 401 (and a console error) on every first visit.
const HINT = 'galla_has_session'
export const hasSessionHint = () => { try { return localStorage.getItem(HINT) === '1' } catch { return false } }
export const setSessionHint = (on: boolean) => { try { on ? localStorage.setItem(HINT, '1') : localStorage.removeItem(HINT) } catch { /* private mode */ } }
const BASE = import.meta.env.VITE_API_URL ?? ''

const send = (path: string, init: RequestInit) => fetch(BASE + '/api/v1' + path, {
  credentials: 'same-origin', ...init,
  headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...init.headers },
})

let refreshing: Promise<Session | null> | null = null
/** Trades the HttpOnly refresh cookie for a new access token. One call at a time: parallel 401s share it,
 *  because the server rotates the cookie and a second concurrent use would look like token theft. */
export function refreshSession(): Promise<Session | null> {
  if (!refreshing) {
    refreshing = fetch(BASE + '/api/v1/auth/refresh', { method: 'POST', credentials: 'same-origin' })
      .then(async (r) => { if (!r.ok) { setSessionHint(false); return null } const s = (await r.json()) as Session; token = s.accessToken; return s })
      .catch(() => null)
      .finally(() => { refreshing = null })
  }
  return refreshing
}
export async function logoutSession() { setSessionHint(false); try { await fetch(BASE + '/api/v1/auth/logout', { method: 'POST', credentials: 'same-origin' }) } catch { /* offline: cookie expires on its own */ } }

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  let res: Response
  try {
    res = await send(path, init)
    if (res.status === 401 && token && !path.startsWith('/auth/') && !path.startsWith('/platform/')) {
      const s = await refreshSession()
      if (s) res = await send(path, init)
      else window.dispatchEvent(new CustomEvent('galla:expired'))
    }
  } catch {
    throw new ApiError(0, 'NETWORK', 'Cannot reach the server. Check your internet and try again.')
  }
  if (res.status === 402) window.dispatchEvent(new CustomEvent('galla:inactive'))
  if (res.ok) { const text = await res.text(); return (text ? JSON.parse(text) : undefined) as T } // some endpoints answer 200 with no body
  let b: { code?: string; message?: string; details?: { field: string; message: string }[] } = {}
  try { b = await res.json() } catch { /* non-JSON error body */ }
  throw new ApiError(res.status, b.code ?? 'ERROR', b.message ?? 'Something went wrong. Please try again.', b.details ?? [])
}
