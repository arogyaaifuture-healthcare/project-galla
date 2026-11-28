import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import SubscriptionPage from './SubscriptionPage'

afterEach(() => vi.restoreAllMocks())
const base = { status: 'SUSPENDED', planName: 'Standard', cycle: 'MONTHLY', trialEndsAt: null, periodEnd: null, daysLeft: 0, pricingSet: true, priceMonthly: '500.00', priceYearly: '5000.00', accessMode: 'LOCKED', upiConfigured: true, openInvoice: null, pendingClaim: null }
const inv = { id: 'i1', number: 'GL-INV-000001', amount: '500.00', currency: 'INR', cycle: 'MONTHLY', periodStart: '2026-12-01T00:00:00Z', periodEnd: '2027-01-01T00:00:00Z', status: 'DUE', upiUri: 'upi://pay?pa=galla%40okbank&pn=Galla&am=500.00&cu=INR&tn=GL-INV-000001' }
const ok = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status })

describe('SubscriptionPage', () => {
  it('shows the QR and the amount once an invoice exists, then accepts the UTR', async () => {
    const calls: string[] = []
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (url, init) => {
      const u = String(url); calls.push((init?.method ?? 'GET') + ' ' + u)
      if (u.endsWith('/subscription/invoices/i1/claim')) return ok({ id: 'c1', utr: '412345678901', status: 'PENDING' }, 201)
      return ok({ ...base, openInvoice: inv })
    })
    render(<SubscriptionPage isOwner />)
    expect(await screen.findByText('GL-INV-000001')).toBeInTheDocument()
    expect(await screen.findByAltText('UPI payment QR code')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Open in UPI app' })).toHaveAttribute('href', inv.upiUri)
    await userEvent.type(screen.getByLabelText(/UTR/), '412345678901')
    await userEvent.click(screen.getByRole('button', { name: 'I have paid' }))
    await waitFor(() => expect(calls.some((c) => c.startsWith('POST') && c.endsWith('/claim'))).toBe(true))
  })
  it('tells staff that only the owner can pay', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(ok(base))
    render(<SubscriptionPage isOwner={false} />)
    expect(await screen.findByText(/Only the restaurant owner can pay/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Pay now' })).toBeNull()
  })
  it('explains when pricing is not set instead of showing a blank page', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(ok({ ...base, pricingSet: false }))
    render(<SubscriptionPage isOwner />)
    expect(await screen.findByText(/Pricing is not available yet/)).toBeInTheDocument()
  })
  it('shows an error with retry when the server fails', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(ok({ code: 'INTERNAL', message: 'Something went wrong. Please try again.', details: [] }, 500))
    render(<SubscriptionPage isOwner />)
    expect(await screen.findByRole('alert')).toHaveTextContent('Something went wrong')
    expect(screen.getByRole('button', { name: 'Retry' })).toBeInTheDocument()
  })
})
