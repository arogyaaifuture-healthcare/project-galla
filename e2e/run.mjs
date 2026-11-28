// End-to-end check of the real stack: browser -> frontend -> API -> PostgreSQL.
import { chromium } from 'playwright'
import { execFileSync } from 'node:child_process'
import { mkdirSync } from 'node:fs'
const BASE = process.env.E2E_BASE ?? 'http://localhost:4173'
const stamp = Date.now(); const email = `owner${stamp}@e2e.test`; const PW = 'correct-horse-battery-1'
const sql = (q) => execFileSync('psql', [process.env.E2E_DB_URL, '-Atc', q], { encoding: 'utf8' })
mkdirSync('shots', { recursive: true })
const browser = await chromium.launch()
const errors = []
const watch = (page, who) => {
  page.on('pageerror', (e) => errors.push(`${who}: ${e}`))
  page.on('console', (m) => { if (m.type() === 'error' && !/status of 402/.test(m.text())) errors.push(`${who}: ${m.text()}`) })
}
const step = (n) => console.log('✔', n)
const expectText = async (page, text, t = 15000) => page.getByText(text, { exact: false }).first().waitFor({ timeout: t })

const owner = await browser.newPage({ viewport: { width: 1100, height: 800 } }); watch(owner, 'restaurant')
const admin = await (await browser.newContext({ viewport: { width: 1100, height: 800 } })).newPage(); watch(admin, 'platform')

// 1. register -> trial
await owner.goto(BASE)
await owner.getByRole('button', { name: /Create an account/ }).click()
await owner.getByLabel('Restaurant name').fill('Spice Hub'); await owner.getByLabel('Your name').fill('Asha')
await owner.getByLabel('Email').fill(email); await owner.getByLabel('Password').fill(PW)
await owner.getByRole('button', { name: 'Create account' }).click()
await expectText(owner, 'Free trial: 30 days left'); step('register starts a 30-day trial')

// 2. menu
await owner.getByLabel('Category name').fill('Starters'); await owner.getByRole('button', { name: 'Add category' }).click()
await owner.getByRole('heading', { name: 'Starters' }).waitFor()
await owner.getByLabel('Item name').fill('Paneer Tikka'); await owner.getByLabel('Price').fill('120.50'); await owner.getByRole('button', { name: 'Add item' }).click()
await expectText(owner, '₹120.50'); await owner.screenshot({ path: 'shots/1-menu.png' }); step('menu category and item added')

// 3. activity log shows what happened
await owner.getByRole('button', { name: 'Activity' }).click(); await expectText(owner, 'Menu item created'); step('activity log records actions')

// 4. super admin sets UPI id and price
await admin.goto(BASE); await admin.getByRole('button', { name: /Platform sign-in/ }).click()
await admin.getByLabel('Email').fill('root@galla.test'); await admin.getByLabel('Password').fill('super-admin-pass-1'); await admin.getByRole('button', { name: 'Sign in', exact: true }).click()
await admin.getByRole('button', { name: 'Settings' }).click()
await admin.getByLabel(/Your UPI ID/).fill('galla@okbank'); await admin.getByLabel(/Name shown in the UPI app/).fill('Galla Tech'); await admin.getByRole('button', { name: 'Save' }).click(); await expectText(admin, 'Saved.')
await admin.getByRole('button', { name: 'Plans' }).click()
const plan = admin.locator('form').first(); await plan.getByLabel(/Monthly/).fill('500'); await plan.getByLabel(/Yearly/).fill('5000'); await plan.getByRole('button', { name: 'Save' }).click(); await expectText(admin, 'Standard saved.')
step('super admin sets UPI id and prices')

// 5. trial ends -> restaurant is locked until it pays
sql(`update subscriptions set trial_ends_at = now() - interval '10 days' where tenant_id = (select tenant_id from users where email='${email}')`)
await owner.getByRole('button', { name: 'Sign out' }).click()
await owner.getByLabel('Email').fill(email); await owner.getByLabel('Password').fill(PW); await owner.getByRole('button', { name: 'Sign in', exact: true }).click()
await expectText(owner, 'Subscription ended'); step('after the trial the restaurant is locked')

// 6. restaurant pays by UPI QR
await owner.getByRole('button', { name: 'Pay now' }).click()
await owner.getByAltText('UPI payment QR code').waitFor(); await expectText(owner, '₹500.00')
await owner.screenshot({ path: 'shots/2-pay.png' })
await owner.getByLabel(/UTR/).fill('412345678901'); await owner.getByRole('button', { name: 'I have paid' }).click(); await expectText(owner, 'received'); step('restaurant sees the QR and submits the UTR')

// 7. super admin confirms
admin.on('dialog', (d) => d.accept())
await admin.getByRole('button', { name: 'Settings' }).click(); await admin.getByRole('button', { name: 'Payments' }).click()
await expectText(admin, 'Spice Hub'); await admin.screenshot({ path: 'shots/3-admin.png' })
await admin.getByRole('button', { name: 'Confirm' }).click(); await expectText(admin, 'No payments waiting.'); step('super admin confirms the payment')

// 8. access is back
await owner.getByRole('button', { name: 'Sign out' }).click()
await owner.getByLabel('Email').fill(email); await owner.getByLabel('Password').fill(PW); await owner.getByRole('button', { name: 'Sign in', exact: true }).click()
await expectText(owner, 'Paneer Tikka'); step('access restored after payment')

// 9. phone-size layout has no sideways scroll
await owner.setViewportSize({ width: 390, height: 800 })
const overflow = await owner.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)
if (overflow) errors.push('restaurant: horizontal scroll on a 390px screen')
await owner.screenshot({ path: 'shots/4-mobile.png' }); step('phone layout fits')

await browser.close()
if (errors.length) { console.error('BROWSER ERRORS:\n' + errors.join('\n')); process.exit(1) }
console.log('E2E passed with zero browser errors')
