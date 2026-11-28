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
  page.on('console', (m) => { if (m.type() === 'error' && !/status of (401|402|422)/.test(m.text())) errors.push(`${who}: ${m.text()}`) })
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

// 8b. a reload keeps the owner signed in (refresh cookie), staff can be added, and a disabled cashier loses access at once
await owner.reload(); await expectText(owner, 'Paneer Tikka'); step('reload restores the session from the refresh cookie')
await owner.getByRole('button', { name: 'Staff' }).click()
const cashierMail = `cashier${stamp}@e2e.test`
await owner.getByLabel('Name', { exact: true }).fill('Ravi'); await owner.getByLabel('Email').fill(cashierMail)
await owner.getByLabel('Role').selectOption('CASHIER'); await owner.getByLabel('Temporary password').fill('cashier-pass-12')
await owner.getByRole('button', { name: 'Add staff member' }).click(); await expectText(owner, cashierMail); step('owner adds a cashier')
const cashier = await (await browser.newContext({ viewport: { width: 1100, height: 800 } })).newPage(); watch(cashier, 'cashier')
await cashier.goto(BASE); await cashier.getByLabel('Sign in as').selectOption('CASHIER')
await cashier.getByLabel('Email').fill(cashierMail); await cashier.getByLabel('Password').fill('cashier-pass-12'); await cashier.getByRole('button', { name: 'Sign in', exact: true }).click()
await expectText(cashier, 'Paneer Tikka')
if (await cashier.getByRole('button', { name: 'Staff' }).count()) errors.push('cashier: can see the Staff tab'); step('cashier signs in and has no staff controls')
await owner.getByRole('row', { name: new RegExp(cashierMail) }).getByRole('button', { name: 'Disable' }).click(); await expectText(owner, 'Disabled')
await cashier.getByRole('button', { name: 'Settings' }).click()
await cashier.getByRole('button', { name: 'Sign in', exact: true }).waitFor({ timeout: 15000 }); step('disabled cashier is thrown out on the next click')

// 8c. restaurant details validate GSTIN and save
await owner.getByRole('button', { name: 'Settings' }).click()
await owner.getByLabel('GSTIN').fill('NOT-A-GSTIN'); await owner.getByRole('button', { name: 'Save', exact: true }).click(); await expectText(owner, 'GSTIN must be 15 characters')
await owner.getByLabel('GSTIN').fill('27ABCDE1234F1Z5'); await owner.getByLabel('City').fill('Pune'); await owner.getByRole('button', { name: 'Save', exact: true }).click(); await expectText(owner, 'Saved.'); step('restaurant details validate and save')

// 8d. invoices, cancel and resume
await owner.getByRole('button', { name: 'Subscription' }).click()
await owner.getByRole('button', { name: 'View' }).click(); await expectText(owner, 'Invoice GL-INV-'); await owner.getByRole('button', { name: 'Close' }).click(); step('paid invoice is listed and can be opened')
owner.once('dialog', (d) => d.accept())
await owner.getByRole('button', { name: 'Cancel plan' }).click(); await owner.getByRole('button', { name: 'Keep my plan' }).click()
await owner.getByRole('button', { name: 'Cancel plan' }).waitFor(); step('cancel and resume work')

// 8e. platform overview, extend a trial, suspend and reactivate
await admin.getByRole('button', { name: 'Overview' }).click(); await expectText(admin, 'collected this month'); step('platform overview loads')
await admin.getByRole('button', { name: 'Restaurants' }).click()
const row = admin.getByRole('row', { name: /Spice Hub/ }).first()
const answers = ['testing the suspend flow']; admin.removeAllListeners('dialog'); admin.on('dialog', (d) => d.type() === 'prompt' ? d.accept(answers[0]) : d.accept())
await row.getByRole('button', { name: 'Suspend' }).click(); await expectText(admin, 'Suspended')
await owner.reload(); await owner.getByRole('button', { name: 'Sign in', exact: true }).waitFor({ timeout: 15000 }); step('suspended restaurant is signed out and cannot restore')
await admin.getByRole('row', { name: /Spice Hub/ }).first().getByRole('button', { name: 'Reactivate' }).click(); await admin.getByRole('row', { name: /Spice Hub/ }).first().getByRole('button', { name: 'Suspend' }).waitFor(); step('reactivation works')

// 9. phone-size layout has no sideways scroll
await owner.setViewportSize({ width: 390, height: 800 })
const overflow = await owner.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)
if (overflow) errors.push('restaurant: horizontal scroll on a 390px screen')
await owner.screenshot({ path: 'shots/4-mobile.png' }); step('phone layout fits')

await browser.close()
if (errors.length) { console.error('BROWSER ERRORS:\n' + errors.join('\n')); process.exit(1) }
console.log('E2E passed with zero browser errors')
