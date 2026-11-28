import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import PlatformConsole from './PlatformConsole'

afterEach(() => vi.restoreAllMocks())
describe('PlatformConsole', () => {
  it('lists waiting payments and confirms one only after the admin agrees', async () => {
    const claim = { id: 'c1', status: 'PENDING', utr: '412345678901', createdAt: '2026-11-28T05:00:00Z', restaurant: 'Spice Hub', invoiceNumber: 'GL-INV-000001', amount: '500.00', cycle: 'MONTHLY' }
    let confirmed = false
    const spy = vi.spyOn(globalThis, 'fetch').mockImplementation(async (url) => {
      if (String(url).endsWith('/confirm')) { confirmed = true; return new Response('', { status: 200 }) }
      return new Response(JSON.stringify(confirmed ? [] : [claim]), { status: 200 })
    })
    vi.spyOn(window, 'confirm').mockReturnValueOnce(false).mockReturnValueOnce(true)
    render(<PlatformConsole onLogout={() => {}} />)
    expect(await screen.findByText('Spice Hub')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Confirm' }))   // admin says no
    expect(confirmed).toBe(false)
    await userEvent.click(screen.getByRole('button', { name: 'Confirm' }))   // admin says yes
    await waitFor(() => expect(confirmed).toBe(true))
    expect(await screen.findByText('No payments waiting.')).toBeInTheDocument()
    expect(spy).toHaveBeenCalled()
  })
})
