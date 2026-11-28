import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import Login from './Login'

afterEach(() => vi.restoreAllMocks())
const fill = async (email = 'a@b.io', pw = 'pw-pw-pw-pw-1') => {
  await userEvent.type(screen.getByLabelText('Email'), email); await userEvent.type(screen.getByLabelText('Password'), pw)
}
describe('Login', () => {
  it('shows the server message when credentials are wrong', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ code: 'INVALID_CREDENTIALS', message: 'Email or password is incorrect', details: [] }), { status: 401 }))
    render(<Login onSession={() => {}} />); await fill()
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Email or password is incorrect')
  })
  it('shows a friendly message when the server is unreachable', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new TypeError('failed'))
    render(<Login onSession={() => {}} />); await fill()
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Cannot reach the server')
  })
  it('sends the chosen role and hands the session up on success', async () => {
    const spy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ accessToken: 't', expiresInSeconds: 900, user: { id: '1', tenantId: '2', name: 'N', email: 'a@b.io', role: 'CASHIER' } }), { status: 200 }))
    const onSession = vi.fn(); render(<Login onSession={onSession} />); await fill()
    await userEvent.selectOptions(screen.getByLabelText('Sign in as'), 'CASHIER')
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    await waitFor(() => expect(onSession).toHaveBeenCalled())
    expect(JSON.parse(String((spy.mock.calls[0][1] as RequestInit).body)).role).toBe('CASHIER')
  })
  it('shows field errors from validation', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ code: 'VALIDATION_FAILED', message: 'Please correct the highlighted fields', details: [{ field: 'password', message: 'Password must be 10 to 100 characters' }] }), { status: 422 }))
    render(<Login onSession={() => {}} />)
    await userEvent.click(screen.getByRole('button', { name: /create an account/i }))
    await userEvent.type(screen.getByLabelText('Restaurant name'), 'R'); await userEvent.type(screen.getByLabelText('Your name'), 'O'); await fill('a@b.io', 'longenough-1')
    await userEvent.click(screen.getByRole('button', { name: 'Create account' }))
    expect(await screen.findByText('Password must be 10 to 100 characters')).toBeInTheDocument()
  })
})
