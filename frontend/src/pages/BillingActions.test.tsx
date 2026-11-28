import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import SubscriptionPage from './SubscriptionPage'
import PlatformConsole from './PlatformConsole'

afterEach(() => vi.restoreAllMocks())
const ok = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status })
const active = { status: 'ACTIVE', planName: 'Standard', cycle: 'MONTHLY', trialEndsAt: null, periodEnd: '2027-01-01T00:00:00Z', daysLeft: 30, pricingSet: true, priceMonthly: '500.00', priceYearly: '5000.00', accessMode: 'LOCKED', upiConfigured: true, openInvoice: null, pendingClaim: null, cancelAtPeriodEnd: false }
const detail = { id: 'i1', number: 'GL-INV-000001', planName: 'Standard', cycle: 'MONTHLY', periodStart: '2026-12-01T00:00:00Z', periodEnd: '2027-01-01T00:00:00Z', amountBeforeTax: '500.00', taxLabel: 'GST', taxPercent: '18.00', taxAmount: '90.00', total: '590.00', currency: 'INR', status: 'PAID' }

describe('subscription: invoices and cancel', () => {
  it('lists invoices and shows the printable invoice with tax', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (u) => ok(String(u).endsWith('/invoices') ? [detail] : active))
    render(<SubscriptionPage isOwner />)
    await userEvent.click(await screen.findByRole('button', { name: 'View' }))
    const inv = screen.getByRole('article', { name: 'Invoice GL-INV-000001' })
    expect(inv).toHaveTextContent('GST (18.00%)'); expect(inv).toHaveTextContent('590.00')
    expect(screen.getByRole('button', { name: 'Print' })).toBeInTheDocument()
  })
  it('cancels after confirmation and offers to keep the plan afterwards', async () => {
    const calls: string[] = []; let cancelled = false
    vi.spyOn(window, 'confirm').mockReturnValue(true)
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (u, init) => {
      const url = String(u); calls.push((init?.method ?? 'GET') + ' ' + url)
      if (url.endsWith('/cancel')) { cancelled = true; return new Response(null, { status: 200 }) }
      return ok(url.endsWith('/invoices') ? [] : { ...active, cancelAtPeriodEnd: cancelled })
    })
    render(<SubscriptionPage isOwner />)
    await userEvent.click(await screen.findByRole('button', { name: 'Cancel plan' }))
    expect(await screen.findByRole('button', { name: 'Keep my plan' })).toBeInTheDocument()
    expect(calls.some((c) => c.startsWith('POST') && c.endsWith('/subscription/cancel'))).toBe(true)
  })
  it('does not offer cancel to managers', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (u) => ok(String(u).endsWith('/invoices') ? [] : active))
    render(<SubscriptionPage isOwner={false} />)
    await screen.findByText(/Only the restaurant owner can pay/)
    expect(screen.queryByRole('button', { name: 'Cancel plan' })).toBeNull()
  })
})

describe('platform: overview and restaurant actions', () => {
  it('shows the overview numbers', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (u) => ok(String(u).endsWith('/dashboard') ? { restaurantsByStatus: { TRIALING: 3, ACTIVE: 2 }, suspendedByAdmin: 1, pendingPayments: 4, collectedThisMonth: '1500.00' } : []))
    render(<PlatformConsole onLogout={() => {}} />)
    await userEvent.click(screen.getByRole('button', { name: 'Overview' }))
    expect(await screen.findByText('On free trial')).toBeInTheDocument()
    expect(screen.getByText(/4/)).toBeInTheDocument()
  })
  it('extends a trial with a reason and a number of days', async () => {
    const posted: { url: string; body: unknown }[] = []
    vi.spyOn(window, 'prompt').mockReturnValueOnce('onboarding delay').mockReturnValueOnce('7')
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (u, init) => {
      if (init?.method === 'POST') { posted.push({ url: String(u), body: JSON.parse(String(init.body)) }); return ok({ trialEndsAt: 'x' }) }
      return ok([{ tenantId: 't1', tenantStatus: 'ACTIVE', name: 'Spice Hub', email: 'a@x.io', plan: 'Standard', effectiveStatus: 'TRIALING', trialEndsAt: '2026-12-20T00:00:00Z', periodEnd: null }])
    })
    render(<PlatformConsole onLogout={() => {}} />)
    await userEvent.click(screen.getByRole('button', { name: 'Restaurants' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Extend trial' }))
    await waitFor(() => expect(posted).toHaveLength(1))
    expect(posted[0].url).toContain('/platform/tenants/t1/extend-trial'); expect(posted[0].body).toEqual({ reason: 'onboarding delay', days: 7 })
  })
})
