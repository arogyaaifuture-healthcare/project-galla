import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import StaffPage from './StaffPage'
import OutletPage from './OutletPage'

afterEach(() => vi.restoreAllMocks())
const ok = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status })
const me = { id: 'u1', name: 'Asha', email: 'a@x.io', role: 'OWNER', status: 'ACTIVE' }
const cashier = { id: 'u2', name: 'Ravi', email: 'r@x.io', role: 'CASHIER', status: 'ACTIVE' }

describe('StaffPage', () => {
  it('lists staff, hides actions on yourself, and disables someone', async () => {
    const calls: string[] = []
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (url, init) => { calls.push((init?.method ?? 'GET') + ' ' + String(url)); return ok(init?.method === 'PATCH' ? { ...cashier, status: 'DISABLED' } : [me, cashier]) })
    render(<StaffPage myId="u1" isOwner />)
    expect(await screen.findByText('Ravi')).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Disable' })).toHaveLength(1)
    await userEvent.click(screen.getByRole('button', { name: 'Disable' }))
    await waitFor(() => expect(calls.some((c) => c.startsWith('PATCH') && c.endsWith('/users/u2'))).toBe(true))
  })
  it('does not offer the Owner role to a manager', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(ok([me]))
    render(<StaffPage myId="u9" isOwner={false} />)
    await screen.findByText('Asha')
    expect(screen.queryByRole('option', { name: 'Owner' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Reset password' })).toBeNull()
  })
  it('shows the server reason when the plan limit is hit', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (_u, init) => init?.method === 'POST' ? ok({ code: 'PLAN_LIMIT_USERS', message: 'Your plan allows 2 users.', details: [] }, 409) : ok([me]))
    render(<StaffPage myId="u1" isOwner />)
    await screen.findByText('Asha')
    await userEvent.type(screen.getByLabelText('Name'), 'Sam'); await userEvent.type(screen.getByLabelText('Email'), 's@x.io'); await userEvent.type(screen.getByLabelText('Temporary password'), 'long-enough-pass')
    await userEvent.click(screen.getByRole('button', { name: 'Add staff member' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Your plan allows 2 users.')
  })
})

describe('OutletPage', () => {
  const outlet = { id: 'o1', name: 'Spice Hub', version: 3 }
  it('sends the version and shows validation messages', async () => {
    let body: Record<string, unknown> = {}
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (url, init) => {
      if (init?.method === 'PATCH') { body = JSON.parse(String(init.body)); return ok({ code: 'VALIDATION', message: 'Check the highlighted fields.', details: [{ field: 'gstin', message: 'GSTIN must be 15 characters like 27ABCDE1234F1Z5' }] }, 422) }
      return ok(String(url).endsWith('/outlets') ? [{ id: 'o1' }] : outlet)
    })
    render(<OutletPage canEdit />)
    await userEvent.type(await screen.findByLabelText('GSTIN'), 'BAD')
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('GSTIN must be 15 characters')
    expect(body.version).toBe(3)
  })
  it('is read-only for staff who cannot edit', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (url) => ok(String(url).endsWith('/outlets') ? [{ id: 'o1' }] : outlet))
    render(<OutletPage canEdit={false} />)
    expect(await screen.findByLabelText('GSTIN')).toBeDisabled()
    expect(screen.queryByRole('button', { name: 'Save' })).toBeNull()
  })
})
