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
const BASE = import.meta.env.VITE_API_URL ?? ''

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  let res: Response
  try {
    res = await fetch(BASE + '/api/v1' + path, {
      ...init,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...init.headers },
    })
  } catch {
    throw new ApiError(0, 'NETWORK', 'Cannot reach the server. Check your internet and try again.')
  }
  if (res.status === 402) window.dispatchEvent(new CustomEvent('galla:inactive'))
  if (res.ok) { const text = await res.text(); return (text ? JSON.parse(text) : undefined) as T } // some endpoints answer 200 with no body
  let b: { code?: string; message?: string; details?: { field: string; message: string }[] } = {}
  try { b = await res.json() } catch { /* non-JSON error body */ }
  throw new ApiError(res.status, b.code ?? 'ERROR', b.message ?? 'Something went wrong. Please try again.', b.details ?? [])
}
