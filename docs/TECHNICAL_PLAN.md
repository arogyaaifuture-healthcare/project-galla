# Galla — Technical Plan (v1.4)

> **How to read this file:** PART I (Sections 0–17, appendices) = the billing core. PART II (Sections 18–30) = platform/SaaS (super admin, plans, trial, subscriptions), support & feedback, delivery charges & partner orders, own-UPI/QR accounts, login/role rules, **WhatsApp bill delivery (Section 23)** **offline mode (24)**, **everyday billing features (25)**, **inventory, recipes & purchasing (26)**, **online-order aggregators & payment auto-confirmation (27)**, **compliance, registers, exports, languages & data management (28)** the requirement-by-requirement verification (29) and the **final audit addendum — reports, loyalty, payment modes, reservations, tokens, out-of-scope list (30)**. Part II overrides Part I where they differ (differences are called out inline). Executable reference code is in `reference/`, verified SQL in `migrations/`.
>
> **New in v1.4 (final audit):** reports catalogue with tested SQL and a reconciliation gate, loyalty points, payment-mode labels, table reservations, token numbers + ready display, and one explicit list of what is deliberately not built (Section 30, V017). The v1.3 notes follow.
>
> **New in v1.3 (gap-filling release):** offline mode with per-terminal bill series and a tested JavaScript calculator (Section 24, V012) · combos, coupons, happy-hour pricing, packaging charge, open items, complimentary bills, tips, cashier shifts, credit sales/dues, credit notes, kitchen display, barcode, customer display, central menu (Section 25, V013) · inventory, recipes, purchasing, stock counts, wastage, transfers (Section 26, V014) · aggregator orders and gateway auto-confirmation (Section 27, V015) · GST/FSSAI fields, registers, Tally/CSV exports, Hindi, data export and retention (Section 28, V015) · cross-stream links (V016). **Everything that depends on outside parties (Meta, aggregators, payment gateways, tax law, real printers/browsers) is marked "not verified" — see Sections 17 and 29.2.**
>
> Restaurant billing web application: orders → KOT → bill → payment → print, plus delivery tracking on a map, notifications, and end-of-day reports.
> Product name: **Galla** (code name `galla`, Java package `com.galla`). *Domain availability and trademark clearance for "Galla" are NOT verified — see Open Decisions 17.20–17.21.* The name lives in ONE config place (`app.brand.name`, `VITE_BRAND_NAME`) so it can be changed later without code edits.

---

## 0. INSTRUCTIONS FOR THE AI AGENT / DEVELOPER READING THIS

Read this whole document before writing code. Follow these rules strictly:

1. **Do not invent features, tables, endpoints or rules** that are not in this document. If something is missing or ambiguous, write the question to `docs/OPEN_QUESTIONS.md` and continue with the most conservative option.
2. **Build in the phase order of Section 16.** Do not start a phase until the previous phase's acceptance criteria pass.
3. **Money is never a floating-point number.** Backend: `BigDecimal` + `NUMERIC(12,2)`. Frontend: `decimal.js`. API transports money and quantity as **strings** (e.g. `"330.76"`).
4. **All billing math lives in exactly one place**: `billing/domain/BillCalculator` on the backend. The frontend only *displays* values returned by the server. It may show a *preview* by calling `POST /bills/preview`, never by re-implementing the formulas.
5. **Every rule in Section 5 has test vectors.** Implement the vectors as unit tests FIRST (test-driven), then the code.
6. **No feature is "done"** until: code + unit tests + integration tests + OpenAPI updated + UI states (loading / empty / error) done + acceptance criteria met.
7. **Never hard-code** tax rates, tax names, currency, provider names, URLs, or secrets. They come from the database or environment variables.
8. Every table has `tenant_id`. Every query is tenant-scoped. A cross-tenant access attempt must return **404**, and there must be a test for it.
9. Keep the code boring and explicit. Prefer plain Java records, plain SQL migrations, and small classes over clever abstractions.

---

## 1. PRODUCT SCOPE

### 1.1 In scope (this plan)
| # | Capability | Phase |
|---|---|---|
| 1 | Login, roles, outlets, users | 1 |
| 2 | Menu (categories, items, variants, modifiers), taxes (configurable) | 1 |
| 3 | Dining areas & tables, floor view | 1 |
| 4 | Orders (dine-in, takeaway, delivery), KOT generation | 1 |
| 5 | Bill generation: discounts, service charge, tax, round-off, split by item, equal split via multiple payments | 1 |
| 6 | Payments: cash & card (manual entry) in Phase 1; UPI QR in Phase 2 | 1–2 |
| 7 | Printing: bill + KOT (browser print and print agent for thermal printers) | 2 |
| 8 | Reports, day close, **end-of-day email** | 2 |
| 9 | Delivery: rider assignment, **live map tracking**, **notifications** | 3 |
| 10 | AI-written daily summary (numbers computed by code, text by LLM) | 4 |
| 11 | Hardening, Docker, Kubernetes, observability | 4 |
| 12 | Platform layer: super admin, restaurant onboarding, plans & per-role user limits, 30-day trial, monthly/yearly subscriptions, activate/deactivate | 1S |
| 13 | Support tickets and feedback | 1S |
| 14 | Delivery charges by distance, partner orders, partner riders | 3 |
| 15 | Restaurant's own UPI ID / uploaded QR (payment accounts) | 2 |
| 16 | **WhatsApp bill delivery** (PDF to the customer's WhatsApp via the restaurant's own WhatsApp Business number, status tracking, consent, manual-share fallback, public bill page) — Section 23 | 2W |
| 17 | **Offline mode**: terminals keep billing without internet (local queue, own bill series per terminal, sync with conflict flags, offline print via local agent) — Section 24 | 2O |
| 18 | **Loyalty points** (earn/redeem as a tender, expiry, refunds reverse), **payment-mode labels**, **table reservations**, **token numbers + ready display**, **full reports catalogue** — Section 30. Marketing campaigns/CRM blasts are not built (30.8) | 5 |
| 19 | **Everyday billing**: combos, coupons, time-based prices, packaging charge, open items, complimentary (NC) bills, tips, cashier shifts & cash drawer, customer credit (dues), refunds with credit notes, kitchen display, barcode, customer display, central menu — Section 25 | 1B |
| 20 | **Inventory, recipes & purchasing**: stock items and units, recipes with costing, consumption on every paid bill, purchase orders/GRN/vendor payables, wastage, stock counts, transfers, reports, EOD stock block — Section 26 | 5I |
| 21 | **Online order aggregators**: provider-agnostic adapter, idempotent inbox, item mapping, auto-accept rules, SLA, kitchen flow, reconciliation (Section 27.A). Gated on partner/middleware access (**not verified**) | 6 |
| 22 | **Payment-gateway auto-confirmation (Mode B)**: locked-amount intents, signed idempotent webhooks, late/mismatch/duplicate handling, settlement import (Section 27.B) | 4 |
| 23 | **Compliance fields & registers**: GSTIN/FSSAI/HSN fields, document title, bill snapshot, sales/HSN/tax/payment-mode registers, generic accounting CSVs, Tally XML (best effort) (Section 28.A–B) | 2 / 2R |
| 24 | **Languages**: en + hi UI, per-outlet bill language, Indian digit grouping, raster Devanagari printing (28.C) | 2 / 2R |
| 25 | **Data management**: tenant data export, customer data requests, retention job, audit viewer, backup runbook, weekly e-mail (28.D) | 4 |

### 1.2 Explicitly OUT of scope for v1
Promotional/marketing WhatsApp messages; a shared Galla-owned WhatsApp number sending for all restaurants; checking whether a number is on WhatsApp by any unofficial method (Section 23.1). Payroll, marketing campaigns and bulk promotions (loyalty points and reservations **are** built — Section 30), multi-currency, kiosk/self-ordering. Customer-facing ordering apps/websites remain out of scope; **receiving** aggregator orders is Section 27.A (Phase 6). Inventory expiry/batch tracking, FIFO costing, landed-cost allocation, vendor e-invoicing, input-tax-credit handling, payment gateway for vendor payments, recipes nested deeper than one level (Section 26). LAN-only sync between terminals without internet (on-premise relay); offline manager-PIN approvals; offline day close. Stacked coupons, gift cards, label printing, automatic card/UPI refunds through a payment provider, KDS hardware integration, remote customer displays. E-invoicing (IRN/QR) and GST return filing; checksum/online validation of GSTIN; automatic refunds through a gateway; reading the restaurant's bank account; rider payout/commission; aggregator-side menu management beyond optional push; customer self-service privacy portal.

### 1.3 Roles
Restaurant roles: `OWNER` (shown in the UI as "Restaurant Admin"), `MANAGER`, `CASHIER`, `CAPTAIN`, `KITCHEN`, `RIDER`, `INVENTORY` (menu read/availability plus the inventory module, Sections 18.1 and 26). Platform roles (separate table): `SUPER_ADMIN`, `SUPPORT`. Permission matrix: Appendix A and A2.

### 1.4 Glossary
- **KOT** – Kitchen Order Ticket: what the kitchen prints/sees. No prices.
- **Bill** – the customer-facing tax document with prices.
- **Business date** – the trading day an order belongs to (may differ from calendar date after midnight; Section 5.9).
- **Series** – bill number sequence name (default `B`).
- **Tenant** – a restaurant business; **Outlet** – one physical location of a tenant.

---

## 2. TECHNOLOGY STACK

> Pin exact versions in `pom.xml` / `package.json` at project start, using the latest *stable* releases compatible with each other. Do not use snapshots or milestones.

### 2.1 Backend
| Concern | Choice |
|---|---|
| Language / JVM | Java 21 (LTS) |
| Framework | Spring Boot 3.5.x (latest stable patch at start) |
| Build | Maven (wrapper committed) |
| Web | Spring Web (MVC, not WebFlux) |
| Security | Spring Security + JWT (Nimbus), BCrypt (strength 12) |
| Persistence | Spring Data JPA (Hibernate) + PostgreSQL 16 |
| Migrations | Flyway (SQL only; never `ddl-auto` other than `validate`) |
| Cache / pub-sub / rate-limit store | Redis 7 |
| Validation | Jakarta Bean Validation |
| API docs | springdoc-openapi (OpenAPI 3) — source of truth for the TS client |
| Mapping | Hand-written mappers or MapStruct (no Lombok) |
| Email | Spring Mail (SMTP) |
| AI | Spring AI (use the release train compatible with the chosen Boot version) |
| Rate limiting | Bucket4j (Redis-backed) |
| QR image decoding | ZXing (core + javase) |
| Phone parsing/validation (E.164, mobile vs landline) | Google libphonenumber |
| Bill PDF rendering (for WhatsApp/public page) | an HTML-to-PDF library (e.g. OpenHTMLtoPDF) fed by the same `PrintDocument` HTML |
| WhatsApp Cloud API client | Spring `RestClient` against the Meta Graph API (base URL configurable for tests) |
| 2FA (platform users) | TOTP via a vetted library (RFC 6238) |
| File storage (QR images) | S3-compatible object storage; local volume in dev (`StorageService`) |
| Observability | Spring Actuator + Micrometer + Prometheus registry, JSON logs |
| CSV parsing (import) and CSV export | Apache Commons CSV (already used for the menu import; reuse for exports, Section 28.B) |
| Property-based tests | jqwik (Java) — ports of P1–P8 (Section 26) |
| Tests | JUnit 5, AssertJ, Mockito, Testcontainers (Postgres, Redis), jqwik (property tests), ArchUnit, GreenMail (SMTP) |
| Offline store (terminal/frontend) | Dexie (IndexedDB wrapper) |
| Service worker / PWA (terminal/frontend) | vite-plugin-pwa with Workbox (app shell precache; update only when the sync queue is empty) |
| Decimal maths on the terminal | decimal.js 10.4.3 (pinned; precision 28, explicit HALF_UP) |
| Local PIN hashing | WebCrypto PBKDF2-HMAC-SHA256 |
| Aggregator/gateway adapters | `OrderChannelAdapter` / `UpiPaymentProvider` implementations; Spring `RestClient` with timeouts; AES-GCM (JCA) for stored credentials |
| XLSX export | Apache POI (`poi-ooxml`, SXSSF streaming) — version pinned at implementation |
| ZIP | `java.util.zip` |
| Devanagari raster printing | a text-shaping library with HarfBuzz-class shaping (e.g. via Java2D with `GlyphVector` + bundled Noto Sans Devanagari, or a HarfBuzz binding) — choice and licence **not verified** |

### 2.2 Frontend
| Concern | Choice |
|---|---|
| Language | TypeScript (`strict: true`, `noUncheckedIndexedAccess: true`) |
| UI | React (latest stable) + Vite |
| Routing | React Router |
| Server state | TanStack Query |
| Client state | Zustand (only for UI state: cart draft, sidebar, theme) |
| Forms | react-hook-form + zod |
| Styling | Tailwind CSS with the design tokens of Section 12 |
| Primitives | Radix UI (via shadcn/ui pattern) |
| Money | decimal.js |
| Dates | date-fns + date-fns-tz |
| Maps | MapLibre GL JS (tile style URL from env; provider chosen later) |
| Live updates | Server-Sent Events (EventSource) |
| PWA & offline | vite-plugin-pwa (Workbox) + Dexie; installable; app shell and data snapshot cached; offline command queue (Section 24) |
| API client | Generated from OpenAPI with `openapi-typescript` + `openapi-fetch` |
| i18n (frontend) | `i18next` + `react-i18next`, `i18next-icu` |
| Frontend fonts | Noto Sans, Noto Sans Devanagari (self-hosted subsets) |
| Tests | Vitest, React Testing Library, MSW, Playwright |

### 2.3 Print agent (Phase 2)
Small cross-platform desktop helper installed at the restaurant counter that receives print jobs and writes ESC/POS bytes to LAN/USB thermal printers. Implement in Java 21 (single runnable JAR + jpackage installers) to stay in the same ecosystem. Details: Section 8. Phase 2O adds a loopback listener (127.0.0.1) with a pairing token so a browser can print without the internet — Section 24.8.

### 2.4 Repository layout (monorepo)
```
galla/
├─ backend/                      # Spring Boot app
│  ├─ src/main/java/com/galla/
│  │   ├─ GallaApplication.java
│  │   ├─ shared/                # money, ids, errors, time, security utils
│  │   ├─ identity/              # auth, users, roles, tokens, PIN override
│  │   ├─ tenancy/               # tenants, outlets, settings
│  │   ├─ catalog/               # categories, items, variants, modifiers, taxes
│  │   ├─ floor/                 # dining areas, tables
│  │   ├─ ordering/              # orders, order items, KOTs
│  │   ├─ pricing/               # price rules, combos, coupons (Section 25)
│  │   ├─ shifts/                # cashier shifts, cash drawer (Section 25)
│  │   ├─ credit/                # customer ledger, dues (Section 25)
│  │   ├─ creditnote/            # refunds / credit notes (Section 25)
│  │   ├─ kitchen/               # kitchen display, KDS (Section 25)
│  │   ├─ menu/central/          # central menu publishing (Section 25)
│  │   ├─ sync/                  # devices, sync push/pull, gaps, conflicts (Section 24)
│  │   ├─ billing/               # bills, calculator, numbering, discounts
│  │   ├─ payments/              # payments, UPI QR, webhooks
│  │   ├─ printing/              # print docs, renderers, print jobs, agents
│  │   ├─ customers/             # customers, addresses
│  │   ├─ delivery/              # deliveries, riders, tracking, geofence
│  │   ├─ notifications/         # outbox, channels, templates
│  │   ├─ whatsapp/              # accounts, consent, templates, sender, webhook, public bill links (Section 23)
│  │   ├─ platform/              # platform users, tenants onboarding, plans, settings, dashboard
│  │   ├─ subscription/          # subscriptions, invoices, plan limits, lifecycle jobs
│  │   ├─ support/               # feedback, tickets
│  │   ├─ inventory/             # units, items, ledger, costing, recipes, consumption, purchasing, counts, transfers, reports (Section 26)
│  │   ├─ integrations/          # OrderChannelAdapter, inbox, mappings, sync jobs, partner reconciliation (27.A)
│  │   ├─ gateway/               # payment intents, event resolver, settlements (27.B)
│  │   ├─ compliance/            # legal profile, tax-profile pairs, registers, accounting & Tally exports (28.A–B)
│  │   ├─ i18n/                  # bill language, item translations, raster bill renderer (28.C)
│  │   ├─ dataops/               # tenant export, data requests, retention job, scheduled reports (28.D)
│  │   ├─ reporting/             # reports, day close, EOD email, AI summary
│  │   └─ audit/                 # audit log
│  ├─ src/main/resources/db/migration/   # V001__*.sql ...
│  └─ src/test/java/...
├─ frontend/                     # React app
│  └─ src/{app,components,features,hooks,lib,pages,styles,api}/   # lib/offline/ (Dexie stores, outbox, sync worker); lib/billing/billCalculator.ts (offline-only port; golden-vector tested)
│                                  # Section 25: src/features/{coupons,priceRules,shifts,dues,refunds,kds,centralMenu,billingSettings}/, src/lib/display/channel.ts, src/lib/scan/useBarcodeScan.ts (scan detection: own 40-line hook, no library; BroadcastChannel for the customer display; Web Audio for KDS chimes)
│                                  # Streams D (Sections 27–28): src/locales/{en,hi}/, src/features/{integrations,gateway,compliance,dataops}/, src/lib/inrGroup.ts
├─ print-agent/                  # Java print agent
├─ reference/                    # executable specs (Python): bill_calculator, delivery_charge, subscription, whatsapp + tests; offline: golden_bill_vectors.json, gen_golden.py, billCalculator.mjs, deviceRules.mjs, test_golden.mjs, sync_rules.py, test_sync_rules.py, package.json; everyday billing: combo.py, coupon.py, pricing_rules.py, nc.py, kds.py, shift.py, credit.py, credit_note.py, conftest.py, test_bx.py; inventory: inventory.py, test_in.py; aggregators/gateway/compliance: external_order.py, payment_intent.py, registers.py, tally_export.py, test_external_order.py, test_payment_intent.py, test_registers.py, test_tally_i18n.py
├─ migrations/                   # V001..V017 (verified on PostgreSQL 16; each stream added its own numbers); V015 = integrations, gateway intents/settlements, compliance fields, exports, languages, data management; V016 adds the cross-stream foreign keys; V017 adds loyalty, payment-mode labels, reservations and token labels (Section 30)
├─ deploy/
│  ├─ docker/ (Dockerfiles, nginx.conf)
│  ├─ docker-compose.yml
│  └─ k8s/ (manifests)
├─ docs/ (OPEN_QUESTIONS.md, ADRs, runbooks)
└─ .github/workflows/ (CI)
```

---

## 3. ARCHITECTURE

### 3.1 Style: modular monolith (deliberate)
One deployable Spring Boot service with strict module boundaries. Reasons: billing needs strong transactional consistency (order + bill + payment + counters in one DB transaction); microservices would add distributed-transaction bugs without benefit at this stage. Modules communicate only via (a) public service interfaces in `<module>/api` packages, or (b) domain events. They can be extracted into services later (the outbox + events already isolate notifications and reporting).

### 3.2 Layering rules (enforced by ArchUnit tests)
- `web` (controllers, DTOs) → `service` → `domain`/`repository`.
- Controllers contain no business logic and never touch repositories.
- A module may not import another module's `repository` or `domain` packages — only its `api` package.
- No cyclic dependencies between modules.
- DTOs are Java `record`s; entities never leave the service layer.

### 3.3 Cross-cutting design
- **Tenancy**: `tenant_id` from the JWT is placed in a request-scoped `TenantContext`. Every repository method takes `tenantId` (or `outletId` validated against tenant). A Hibernate `@Filter` on `tenant_id` is a safety net, not the primary mechanism.
- **Two token types**: `typ=TENANT` (restaurant users) and `typ=PLATFORM` (platform users), signed with different secrets; each side's filters reject the other (Section 18.1). Platform staff reach tenant data only through a read-only `SUPPORT_VIEW` token (18.7).
- **Outlet scope**: users are assigned outlets (`user_outlets`). Header `X-Outlet-Id` selects the active outlet; backend verifies the user may access it.
- **IDs**: UUIDv4, **client-generated allowed** for orders/KOTs/bills/payments (required for offline mode, Section 24; sync commands are idempotent by `command_id`). Server validates uniqueness.
- **Idempotency**: `Idempotency-Key` header is **required** on `POST` for KOT, bill generation, payment creation, and day close. Store `(key, user, endpoint, request_hash) → response` for 24 h. Same key + same hash → replay stored response. Same key + different hash → `422 IDEMPOTENCY_KEY_REUSED`. `POST /sync/push` is idempotent per command (`sync_commands.UNIQUE (tenant_id, command_id)`) and does not use the `Idempotency-Key` header.
- **Offline calculation:** the server's `BillCalculator` is the only authority for online issue; a registered terminal may calculate **only while offline** with the ported calculator that passes the same golden vectors (Section 24.5).
- **Optimistic locking**: aggregate roots carry `version`. Updates send `version`; mismatch → `409 VERSION_CONFLICT`.
- **Pessimistic locking** only for counters (bill/order/KOT numbers) using `SELECT … FOR UPDATE`.
- **Time**: all timestamps stored as UTC `timestamptz`. Display in outlet timezone. API uses ISO-8601.
- **Transactional outbox**: anything that sends email/WhatsApp/SMS/push inserts a row into `notification_outbox` inside the business transaction; a scheduled worker sends it (Section 10). Never call external services inside a business transaction.
- **Audit**: every state-changing action on bills, payments, voids, discounts, price edits, user/role changes writes `audit_logs` (who, what, before, after).
- **Error model**: RFC 7807 `application/problem+json` with fields `type, title, status, code, detail, traceId, fieldErrors[]`. Error codes: Appendix B.
- **Inventory arithmetic:** quantities are NUMERIC(14,4) in the item's base unit, unit costs NUMERIC(16,6), values NUMERIC(14,2), HALF_UP, one rounding per step defined in Section 26.4/26.6; costing is moving weighted average.
- **Config**: `application.yml` + env overrides. No secrets in the repo. Profiles: `dev`, `test`, `prod`.
- **Provider isolation:** nothing outside `integrations/` and `gateway/` knows a provider's name; adapters are selected by the `provider` code; every provider call has a timeout and runs through a job or the webhook handler, never inside a billing transaction.
- **Facts first:** inbound provider data (`external_orders`, `payment_webhook_events`) is stored before it is acted on; stored events are immutable and replays are no-ops.

---

## 4. DATABASE DESIGN (PostgreSQL 16)

### 4.1 Conventions
- Table/column names `snake_case`, plural table names.
- PK: `id uuid PRIMARY KEY` (default `gen_random_uuid()`).
- Every business table: `tenant_id uuid NOT NULL REFERENCES tenants(id)`, `created_at timestamptz NOT NULL DEFAULT now()`, `updated_at timestamptz NOT NULL DEFAULT now()`. Aggregate roots also have `version bigint NOT NULL DEFAULT 0`.
- Enums are `text` + `CHECK` constraints (easier migrations than PG enum types).
- Money `numeric(12,2)`; quantity `numeric(10,3)`; percentage `numeric(5,2)`.
- Snapshots: order lines and bill lines copy name/price/tax at creation so later menu edits never change history.
- Soft delete via `active boolean`/`status` where noted; **bills, payments, audit logs are never deleted** (the sole exception is the retention job for audit logs and provider payloads, Section 28.D.3).
- Append-only tables (`external_status_events`, `audit_logs`) are protected by triggers; the nightly retention job is the only deleter and sets `galla.retention_job = 'on'` for its transaction.
- Each migration file is immutable once merged. New change → new `V###__description.sql`.
- **Migration V012 (offline mode, Section 24.12)** adds the tables `devices`, `sync_commands`, `bill_number_gaps`, `sync_conflicts`; columns on `orders`, `kots`, `bills`, `payments` (`origin_device_id`, `offline_created`, `client_created_at`, `synced_at`; orders also `device_order_no`, `needs_attention`, `attention_reason`; kots also `device_kot_no`) and on `outlets` (`offline_enabled`, `offline_max_hours`).

### 4.2 Migration V001 — tenancy & identity
```sql
CREATE TABLE tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE tax_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  name text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);

CREATE TABLE tax_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  tax_profile_id uuid NOT NULL REFERENCES tax_profiles(id) ON DELETE CASCADE,
  name text NOT NULL,                       -- e.g. "CGST", "SGST", "VAT" (configured by user)
  rate_percent numeric(5,2) NOT NULL CHECK (rate_percent >= 0 AND rate_percent <= 100),
  sort_order int NOT NULL DEFAULT 0
);

CREATE TABLE outlets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  code text NOT NULL,
  name text NOT NULL,
  address_line1 text, address_line2 text, city text, state text, postal_code text,
  country_code char(2) NOT NULL,
  phone text, email text,
  timezone text NOT NULL,                   -- IANA name, validated against java.time.ZoneId
  currency_code char(3) NOT NULL,
  currency_symbol text NOT NULL,            -- printed on bills, e.g. "Rs" (thermal printers often lack the rupee glyph)
  tax_registration_label text, tax_registration_no text,   -- label configurable, e.g. "GSTIN"
  license_label text, license_no text,                     -- e.g. "FSSAI"
  bill_header text, bill_footer text, logo_url text,
  prices_include_tax boolean NOT NULL,
  service_charge_percent numeric(5,2) NOT NULL DEFAULT 0 CHECK (service_charge_percent BETWEEN 0 AND 100),
  service_charge_tax_profile_id uuid REFERENCES tax_profiles(id),
  round_off_mode text NOT NULL DEFAULT 'NEAREST_1' CHECK (round_off_mode IN ('NONE','NEAREST_1')),
  fiscal_year_start_month smallint NOT NULL CHECK (fiscal_year_start_month BETWEEN 1 AND 12),
  day_start_hour smallint NOT NULL DEFAULT 4 CHECK (day_start_hour BETWEEN 0 AND 23),
  upi_vpa text, upi_payee_name text,
  eod_email_enabled boolean NOT NULL DEFAULT false,
  eod_email_time time,                      -- local time to send EOD email if not manually closed
  eod_email_recipients text[] NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (tenant_id, code)
);

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  email text NOT NULL,
  password_hash text NOT NULL,
  full_name text NOT NULL,
  phone text,
  role text NOT NULL CHECK (role IN ('OWNER','MANAGER','CASHIER','CAPTAIN','KITCHEN','RIDER')),
  pin_hash text,                            -- 4-6 digit manager override PIN (BCrypt); only OWNER/MANAGER
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DISABLED')),
  failed_login_attempts int NOT NULL DEFAULT 0,
  locked_until timestamptz,
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX ux_users_email ON users (lower(email));

CREATE TABLE user_outlets (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, outlet_id)
);

CREATE TABLE refresh_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  family_id uuid NOT NULL,                  -- rotation family; reuse of a revoked token revokes the whole family
  token_hash text NOT NULL UNIQUE,          -- SHA-256 of the opaque token
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  replaced_by uuid,
  user_agent text, ip text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_refresh_tokens_user ON refresh_tokens(user_id);
```

### 4.3 Migration V002 — catalog, floor, printers
```sql
CREATE TABLE kitchen_stations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  name text NOT NULL,                       -- e.g. "Main Kitchen", "Bar", "Tandoor"
  active boolean NOT NULL DEFAULT true,
  UNIQUE (outlet_id, name)
);

CREATE TABLE menu_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  name text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, name)
);

CREATE TABLE menu_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  category_id uuid NOT NULL REFERENCES menu_categories(id),
  name text NOT NULL,
  short_code text,                          -- fast keyboard search, unique per outlet when present
  description text,
  base_price numeric(12,2) NOT NULL CHECK (base_price >= 0),
  tax_profile_id uuid REFERENCES tax_profiles(id),   -- NULL = no tax
  food_type text NOT NULL DEFAULT 'NA' CHECK (food_type IN ('VEG','NON_VEG','EGG','NA')),
  station_id uuid REFERENCES kitchen_stations(id),
  hsn_sac_code text,
  available boolean NOT NULL DEFAULT true,  -- temporarily out of stock toggle
  active boolean NOT NULL DEFAULT true,     -- soft delete
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX ux_menu_items_short_code ON menu_items(outlet_id, lower(short_code)) WHERE short_code IS NOT NULL AND active;
CREATE INDEX ix_menu_items_outlet_cat ON menu_items(outlet_id, category_id) WHERE active;

CREATE TABLE item_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  menu_item_id uuid NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  name text NOT NULL,                       -- "Half", "Full"
  price numeric(12,2) NOT NULL CHECK (price >= 0),
  sort_order int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE modifier_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  name text NOT NULL,
  min_select int NOT NULL DEFAULT 0 CHECK (min_select >= 0),
  max_select int NOT NULL DEFAULT 1 CHECK (max_select >= 1),
  CHECK (min_select <= max_select),
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE modifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  group_id uuid NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
  name text NOT NULL,
  price numeric(12,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  sort_order int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE item_modifier_groups (
  menu_item_id uuid NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  group_id uuid NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (menu_item_id, group_id)
);

CREATE TABLE dining_areas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  name text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  UNIQUE (outlet_id, name)
);

CREATE TABLE dining_tables (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  area_id uuid NOT NULL REFERENCES dining_areas(id),
  name text NOT NULL,                       -- "T1"
  capacity int NOT NULL DEFAULT 4 CHECK (capacity > 0),
  sort_order int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  UNIQUE (outlet_id, name)
);

CREATE TABLE print_agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  name text NOT NULL,
  token_hash text NOT NULL UNIQUE,          -- SHA-256 of the agent token (shown once at creation)
  last_seen_at timestamptz,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE printers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  name text NOT NULL,
  purpose text NOT NULL CHECK (purpose IN ('BILL','KOT')),
  paper_width_mm smallint NOT NULL CHECK (paper_width_mm IN (58,80)),
  connection text NOT NULL CHECK (connection IN ('BROWSER','AGENT')),
  agent_id uuid REFERENCES print_agents(id),
  device_address text,                      -- agent-side: "tcp://192.168.1.50:9100" or "usb:<name>"
  station_id uuid REFERENCES kitchen_stations(id),   -- for KOT printers
  code_page text NOT NULL DEFAULT 'CP437',
  active boolean NOT NULL DEFAULT true
);
```

### 4.4 Migration V003 — customers, orders, KOTs, counters
```sql
CREATE TABLE customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  name text NOT NULL,
  phone text NOT NULL,
  email text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, phone)
);

CREATE TABLE customer_addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  label text NOT NULL DEFAULT 'Home',
  line1 text NOT NULL, line2 text, landmark text, city text, postal_code text,
  latitude numeric(9,6) CHECK (latitude BETWEEN -90 AND 90),
  longitude numeric(9,6) CHECK (longitude BETWEEN -180 AND 180)
);

-- Atomic counters (one row per outlet/scope). Increment with a single statement:
--   INSERT ... ON CONFLICT (...) DO UPDATE SET last_no = counters.last_no + 1 RETURNING last_no;
CREATE TABLE order_counters (
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  business_date date NOT NULL,
  last_no int NOT NULL,
  PRIMARY KEY (outlet_id, business_date)
);
CREATE TABLE kot_counters (
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  business_date date NOT NULL,
  last_no int NOT NULL,
  PRIMARY KEY (outlet_id, business_date)
);
CREATE TABLE bill_counters (
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  series text NOT NULL,
  fiscal_year text NOT NULL,
  last_no int NOT NULL,
  PRIMARY KEY (outlet_id, series, fiscal_year)
);

CREATE TABLE orders (
  id uuid PRIMARY KEY,                       -- client-generated allowed
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  order_no int NOT NULL,                     -- per outlet per business_date
  business_date date NOT NULL,
  order_type text NOT NULL CHECK (order_type IN ('DINE_IN','TAKEAWAY','DELIVERY')),
  table_id uuid REFERENCES dining_tables(id),
  customer_id uuid REFERENCES customers(id),
  guest_count int CHECK (guest_count IS NULL OR guest_count > 0),
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','BILLED','PAID','CANCELLED')),
  notes text,
  cancel_reason text,
  opened_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (outlet_id, business_date, order_no),
  CHECK (order_type <> 'DINE_IN' OR table_id IS NOT NULL)
);
CREATE INDEX ix_orders_outlet_status ON orders(outlet_id, status);
CREATE INDEX ix_orders_table_active ON orders(table_id) WHERE status IN ('OPEN','BILLED');

CREATE TABLE kots (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  order_id uuid NOT NULL REFERENCES orders(id),
  kot_no int NOT NULL,                       -- per outlet per business_date
  business_date date NOT NULL,
  station_id uuid REFERENCES kitchen_stations(id),
  status text NOT NULL DEFAULT 'SENT' CHECK (status IN ('SENT','CANCELLED')),
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, business_date, kot_no)
);

CREATE TABLE order_items (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  menu_item_id uuid NOT NULL REFERENCES menu_items(id),
  variant_id uuid REFERENCES item_variants(id),
  name_snapshot text NOT NULL,               -- includes variant name, e.g. "Paneer Tikka (Half)"
  unit_price numeric(12,2) NOT NULL CHECK (unit_price >= 0),   -- base/variant price + modifiers, per unit
  quantity numeric(10,3) NOT NULL CHECK (quantity > 0),
  tax_profile_id uuid REFERENCES tax_profiles(id),
  station_id uuid REFERENCES kitchen_stations(id),
  notes text,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','CANCELLED')),
  cancel_reason text,
  kot_id uuid REFERENCES kots(id),           -- NULL = draft line not yet sent to kitchen
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_order_items_order ON order_items(order_id);

CREATE TABLE order_item_modifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_item_id uuid NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
  modifier_id uuid REFERENCES modifiers(id),
  name_snapshot text NOT NULL,
  price numeric(12,2) NOT NULL DEFAULT 0
);
```

### 4.5 Migration V004 — billing & payments
```sql
CREATE TABLE bills (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  order_id uuid NOT NULL REFERENCES orders(id),
  series text NOT NULL DEFAULT 'B',
  fiscal_year text NOT NULL,                 -- "2026-27" or "2026"
  bill_seq int NOT NULL,
  bill_number text NOT NULL,                 -- "B-2026-27-000123"
  status text NOT NULL DEFAULT 'GENERATED' CHECK (status IN ('GENERATED','PAID','VOID')),
  prices_include_tax boolean NOT NULL,       -- snapshot of outlet setting
  currency_code char(3) NOT NULL,
  subtotal numeric(12,2) NOT NULL,           -- sum of ITEM line_gross
  discount_type text CHECK (discount_type IN ('PERCENT','AMOUNT')),
  discount_value numeric(12,2),              -- percent or amount as entered
  discount_total numeric(12,2) NOT NULL DEFAULT 0,
  discount_reason text,
  service_charge_total numeric(12,2) NOT NULL DEFAULT 0,   -- line_total of SERVICE_CHARGE line
  tax_total numeric(12,2) NOT NULL,
  total_before_round_off numeric(12,2) NOT NULL,
  round_off numeric(12,2) NOT NULL DEFAULT 0,
  grand_total numeric(12,2) NOT NULL,
  amount_paid numeric(12,2) NOT NULL DEFAULT 0,
  customer_name text, customer_phone text,   -- snapshot
  generated_by uuid NOT NULL REFERENCES users(id),
  generated_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  voided_by uuid REFERENCES users(id),
  voided_at timestamptz,
  void_reason text,
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (outlet_id, series, fiscal_year, bill_seq),
  UNIQUE (outlet_id, bill_number),
  CHECK (grand_total >= 0)
);
CREATE INDEX ix_bills_outlet_date ON bills(outlet_id, generated_at);
CREATE INDEX ix_bills_order ON bills(order_id);

CREATE TABLE bill_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  bill_id uuid NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
  line_no int NOT NULL,
  line_type text NOT NULL CHECK (line_type IN ('ITEM','SERVICE_CHARGE')),
  order_item_id uuid REFERENCES order_items(id),
  name text NOT NULL,
  quantity numeric(10,3) NOT NULL,
  unit_price numeric(12,2) NOT NULL,
  line_gross numeric(12,2) NOT NULL,         -- qty * unit_price (rounded HALF_UP to 2dp)
  discount_amount numeric(12,2) NOT NULL DEFAULT 0,
  taxable_amount numeric(12,2) NOT NULL,
  tax_amount numeric(12,2) NOT NULL,
  line_total numeric(12,2) NOT NULL,
  active boolean NOT NULL DEFAULT true,      -- false when parent bill is voided
  UNIQUE (bill_id, line_no)
);
-- an order item can be on at most ONE non-void bill:
CREATE UNIQUE INDEX ux_bill_lines_order_item_active ON bill_lines(order_item_id) WHERE active AND order_item_id IS NOT NULL;

CREATE TABLE bill_line_taxes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_line_id uuid NOT NULL REFERENCES bill_lines(id) ON DELETE CASCADE,
  component_name text NOT NULL,              -- snapshot
  rate_percent numeric(5,2) NOT NULL,        -- snapshot
  taxable_amount numeric(12,2) NOT NULL,
  tax_amount numeric(12,2) NOT NULL
);

CREATE TABLE payments (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  bill_id uuid NOT NULL REFERENCES bills(id),
  method text NOT NULL CHECK (method IN ('CASH','CARD','UPI','OTHER')),
  amount numeric(12,2) NOT NULL CHECK (amount > 0),         -- amount APPLIED to the bill
  tendered_amount numeric(12,2),             -- cash handed over
  change_amount numeric(12,2),               -- cash returned
  status text NOT NULL CHECK (status IN ('PENDING','SUCCESS','FAILED','REFUNDED','EXPIRED')),
  confirmation text NOT NULL DEFAULT 'MANUAL' CHECK (confirmation IN ('MANUAL','PROVIDER')),
  reference text,                            -- card slip no / UPI txn id typed by cashier
  provider text, provider_txn_id text,
  qr_payload text, expires_at timestamptz,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  confirmed_by uuid REFERENCES users(id)
);
CREATE INDEX ix_payments_bill ON payments(bill_id);
CREATE UNIQUE INDEX ux_payments_provider_txn ON payments(provider, provider_txn_id) WHERE provider_txn_id IS NOT NULL;

CREATE TABLE payment_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  event_id text NOT NULL,
  payload jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  UNIQUE (provider, event_id)                -- dedupes provider retries
);

CREATE TABLE idempotency_keys (
  key text NOT NULL,
  user_id uuid NOT NULL,
  endpoint text NOT NULL,
  request_hash text NOT NULL,
  response_status int NOT NULL,
  response_body jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (key, user_id, endpoint)
);
```

### 4.6 Migration V005 — printing, delivery, notifications, reporting, audit
```sql
CREATE TABLE print_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  printer_id uuid NOT NULL REFERENCES printers(id),
  doc_type text NOT NULL CHECK (doc_type IN ('BILL','KOT','TEST')),
  ref_id uuid,                               -- bill id or kot id
  payload bytea NOT NULL,                    -- ESC/POS bytes
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','CLAIMED','PRINTED','FAILED')),
  attempts int NOT NULL DEFAULT 0,
  last_error text,
  claimed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  printed_at timestamptz
);
CREATE INDEX ix_print_jobs_pending ON print_jobs(printer_id, created_at) WHERE status IN ('PENDING','CLAIMED');

CREATE TABLE riders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  user_id uuid REFERENCES users(id),         -- rider logs into the rider web page with a RIDER user
  name text NOT NULL,
  phone text NOT NULL,
  vehicle text,
  status text NOT NULL DEFAULT 'OFFLINE' CHECK (status IN ('AVAILABLE','BUSY','OFFLINE')),
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  order_id uuid NOT NULL UNIQUE REFERENCES orders(id),
  customer_name text NOT NULL, customer_phone text NOT NULL,
  address_text text NOT NULL,
  dest_lat numeric(9,6), dest_lng numeric(9,6),
  rider_id uuid REFERENCES riders(id),
  status text NOT NULL DEFAULT 'PLACED' CHECK (status IN ('PLACED','PREPARING','READY','ASSIGNED','PICKED_UP','DELIVERED','CANCELLED','FAILED')),
  tracking_token text NOT NULL UNIQUE,       -- 32+ random url-safe chars; used in public tracking link
  eta_minutes int,
  arriving_notified boolean NOT NULL DEFAULT false,
  failed_reason text,
  assigned_at timestamptz, picked_up_at timestamptz, delivered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);
CREATE INDEX ix_deliveries_outlet_status ON deliveries(outlet_id, status);

CREATE TABLE delivery_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  from_status text, to_status text NOT NULL,
  changed_by uuid REFERENCES users(id),
  note text,
  changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE rider_locations (
  id bigserial PRIMARY KEY,
  delivery_id uuid NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  rider_id uuid NOT NULL REFERENCES riders(id),
  latitude numeric(9,6) NOT NULL, longitude numeric(9,6) NOT NULL,
  accuracy_m numeric(8,2), speed_mps numeric(8,2), heading_deg numeric(5,2),
  recorded_at timestamptz NOT NULL,          -- device time (validated: not in future, not older than 2 min)
  received_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_rider_locations_delivery ON rider_locations(delivery_id, recorded_at DESC);
-- retention job deletes rows older than 30 days

CREATE TABLE notification_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  channel text NOT NULL CHECK (channel IN ('EMAIL','WHATSAPP','SMS','PUSH')),
  recipient text NOT NULL,
  template_code text NOT NULL,
  payload jsonb NOT NULL,                    -- template variables (already rendered values)
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','SENDING','SENT','FAILED')),
  attempts int NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_error text,
  dedupe_key text UNIQUE,                    -- e.g. "eod:<outlet>:<date>" or "delivery:<id>:PICKED_UP"
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz
);
CREATE INDEX ix_outbox_due ON notification_outbox(next_attempt_at) WHERE status IN ('PENDING','SENDING');

CREATE TABLE notification_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id),     -- NULL = system default
  code text NOT NULL,
  channel text NOT NULL,
  locale text NOT NULL DEFAULT 'en',
  subject text,
  body text NOT NULL,                        -- {{variable}} placeholders
  UNIQUE (tenant_id, code, channel, locale)
);

CREATE TABLE push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  endpoint text NOT NULL UNIQUE, p256dh text NOT NULL, auth text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE day_closings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  business_date date NOT NULL,
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','CLOSED')),
  opening_cash numeric(12,2) NOT NULL DEFAULT 0,
  expected_cash numeric(12,2),
  counted_cash numeric(12,2),
  cash_variance numeric(12,2),
  summary jsonb,                             -- computed numbers snapshot (Section 10.3)
  ai_summary text,
  closed_by uuid REFERENCES users(id),
  closed_at timestamptz,
  email_queued_at timestamptz,
  UNIQUE (outlet_id, business_date)
);

CREATE TABLE audit_logs (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL,
  outlet_id uuid,
  user_id uuid,
  action text NOT NULL,                      -- e.g. BILL_VOIDED, DISCOUNT_APPLIED, ITEM_CANCELLED
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  before_data jsonb, after_data jsonb,
  reason text,
  ip text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_audit_entity ON audit_logs(tenant_id, entity_type, entity_id);
```

### 4.7 Seed (dev profile only)
One tenant, one outlet, users `owner@demo.test` / `manager@demo.test` / `cashier@demo.test` / `captain@demo.test` / `rider@demo.test` (password in README, **never in prod**), 2 areas, 10 tables, a tax profile with two components, 4 categories, 25 items.

### 4.8 Migration V013 overview (Section 25, everyday billing)
V013 adds 14 new tables: `reason_codes`, `outlet_role_permissions`, `combo_components`, `price_rules`, `cashier_shifts`, `cash_movements`, `customer_ledger`, `coupons`, `coupon_redemptions`, `credit_notes`, `credit_note_lines`, `credit_note_line_taxes`, `outlet_menu_versions`, `menu_publish_runs` (77 tables in total after V001–V011 + V013 alone; the final count over V001–V016 is in Section 29). Columns are added to `outlets`, `printers`, `kitchen_stations`, `menu_items`, `menu_categories`, `modifier_groups`, `order_items` (+ `menu_item_id` now nullable), `customers`, `bills`, `bill_lines` (CHECK widened), `payments` (method CHECK widened). New unique-by-code: `ux_coupons_code (tenant_id, lower(code))`. Full SQL: Section 25.20.
Interface notes: **Inventory (Section 26):** read `combo_components` (consumption per component), `credit_note_lines.restock`, open items (no recipe). **Offline (Section 24):** `order_items` new columns travel in sync commands; `payments.shift_id` is NULL for payments created offline unless the terminal had a local shift (decision for the merger — see Section 29.3). **V016:** add FKs `cashier_shifts.device_id → devices(id)`.

### 4.9 Migration V014 overview (Section 26, inventory)
V014 adds 28 tables: `inventory_units`, `stock_categories`, `vendors`, `stock_items`, `inventory_settings`, `inventory_counters`, `stock_levels`, `stock_consumptions`, `stock_consumption_skips`, `stock_movements`, `stock_snapshots`, `recipes`, `recipe_lines`, `purchase_orders`, `purchase_order_lines`, `goods_receipts`, `goods_receipt_lines`, `purchase_returns`, `purchase_return_lines`, `vendor_payments`, `vendor_payment_allocations`, `stock_adjustments`, `stock_counts`, `stock_count_lines`, `stock_transfers`, `stock_transfer_lines`, `production_runs`, `inventory_import_jobs`. Requires the extension `btree_gist`. Plain uuid soft references (FKs added in V016): none required by V014 other than existing tables; credit-note and combo links are carried by `ref_id` on movements. `inventory_units` is seeded by V014 itself. Full SQL and the verification record: Section 26.

---

## 5. DOMAIN RULES (the heart of the system)

### 5.1 Order lifecycle
```
OPEN ──generate bill (all active items billed)──▶ BILLED ──all bills PAID──▶ PAID (terminal)
 │                                                  │
 │                                                  └─ void bill ─▶ back to OPEN
 └─ cancel (reason; manager PIN if any KOT sent) ─▶ CANCELLED (terminal)
```
`recomputeOrderStatus(order)` runs inside the same transaction after any bill/payment/void/cancel-item change:
- `CANCELLED` stays `CANCELLED`.
- Let `A` = active order items (status ACTIVE). If `A` is empty → remains `OPEN`.
- If every item in `A` is on an active (non-void) bill: all those bills `PAID` → `PAID`; else → `BILLED`.
- Otherwise → `OPEN`.
- Adding items to an order that has any active bill is allowed only for items **not yet billed**; the order goes back to `OPEN`. Existing bills are never modified.

### 5.2 Order items & KOT
- Draft lines (`kot_id IS NULL`) are freely editable (qty, notes, modifiers, delete).
- `POST /orders/{id}/kots` takes **all draft lines**, groups them by `station_id`, creates one KOT per station, assigns `kot_no`, sets `kot_id`, and enqueues KOT print jobs. Atomic.
- After KOT: lines are immutable except **cancel** (`status=CANCELLED`, reason required, **manager PIN override required**; allowed only if the line is not on an active bill). To order more of the same item → add a new line.
- Unit price snapshot = (variant price or `base_price`) + sum(selected modifier prices). Validate modifier selections against `min_select`/`max_select`.
- `quantity` allows decimals (3 dp) for weight-based items; UI default step is 1.
- Order lines may be **open items** (`menu_item_id` NULL), **combo header/component** lines, and carry a **price snapshot** (`price_source`, `list_unit_price`, `price_rule_id`) and a **kitchen status** (`NEW/PREPARING/READY/SERVED`) once on a KOT (25.3, 25.5, 25.7, 25.13).

### 5.3 Bill calculation — `BillCalculator` (pure function, no I/O)
**Inputs added by Section 25:** combo component lines (qty 1, `unit_price = fixed_line_amount`; the combo header is not billed), open items, price-rule snapshot prices.

**Input:** list of billable lines `(sortKey, orderItemId, name, quantity, unitPrice, taxComponents[])`, outlet settings `(pricesIncludeTax, serviceChargePercent, serviceChargeTaxComponents[], roundOffMode)`, discount `(type PERCENT|AMOUNT, value)` or none, and optionally a **delivery charge** `(amount, taxComponents[])` (Section 20), optionally `extra_charges[]` (Section 25.6). **Tips are never an input** (25.9). NC tax-on-list-price is computed by a separate function (25.8).
**Output:** bill header totals + bill lines + per-line tax rows.

All rounding: `RoundingMode.HALF_UP`, scale 2, applied **exactly where stated** and nowhere else. Intermediate values keep full `BigDecimal` precision.

**Step 0 – canonical order.** Sort the input lines ascending by `sortKey` (a unique string per line; the app sets it to the zero-padded `created_at` epoch-microseconds + the order item id; the reference code calls it `id`) and assign `line_no` in that order. Every tie-break below uses this order, which is what makes the result independent of how the caller happened to order the list. *(An earlier draft of this plan claimed order independence without this step; the property test proved that claim false, so the step was added.)*

**Step 1 – line gross.** `line_gross = round2(quantity × unit_price)`.

**Step 2 – subtotal.** `subtotal = Σ line_gross` over ITEM lines.

**Step 3 – discount total.**
- `PERCENT`: `discount_total = round2(subtotal × value / 100)`; `value` must be in `(0, 100]`.
- `AMOUNT`: `discount_total = value`; must satisfy `0 < value ≤ subtotal` else error `DISCOUNT_EXCEEDS_SUBTOTAL`.
- No discount → `0`.
- The discount is **one** of: manual, coupon (flat amount, `PERCENT` capped by `max_discount` and by the subtotal **before** Step 4), or NC (100 %). They are mutually exclusive in v1.

**Step 4 – discount allocation (largest remainder, in cents).** For each ITEM line `i`: `exact_i = discount_total × line_gross_i / subtotal`. `floor_i` = `exact_i` rounded DOWN to cents. Let `R = discount_total − Σ floor_i` (in cents, `0 ≤ R < n`). Give +1 cent to the `R` lines with the largest fractional remainder (ties → lower canonical position first). Result `discount_i`; invariant `Σ discount_i = discount_total`. If `subtotal = 0` → all zeros.

**Step 5 – service charge line (optional).** If `service_charge_percent > 0`: `base = subtotal − discount_total`; `sc = round2(base × percent / 100)`. If `sc > 0`, add a synthetic line `SERVICE_CHARGE` with `quantity=1, unit_price=sc, line_gross=sc, discount=0`, taxed with the outlet's service-charge tax profile (none → untaxed).

**Step 5b – delivery charge line (optional, Section 20).** If a delivery charge `> 0` applies to this bill, add a synthetic line `DELIVERY_CHARGE` with `quantity=1, unit_price=gross=charge, discount=0`. It is **not discounted**, **not part of the service-charge base**, and is taxed in Step 6 with the outlet's delivery tax profile (none → untaxed). Packaging (Section 25.6): add synthetic lines `DELIVERY_CHARGE` and/or `PACKAGING_CHARGE` in this order; neither is discounted nor in the service-charge base; each is taxed with its own profile. Lines are appended in the order ITEM…, SERVICE_CHARGE, DELIVERY_CHARGE, PACKAGING_CHARGE.

**Step 6 – per-line tax.** `net_i = line_gross_i − discount_i`. Let `components` be the line's tax components `(name, rate)`; `totalRate = Σ rate`.
- **Exclusive pricing** (`prices_include_tax = false`): `taxable_i = net_i`. For each component: `tax_ic = round2(taxable_i × rate_c / 100)`. `tax_i = Σ_c tax_ic`. `line_total_i = taxable_i + tax_i`.
- **Inclusive pricing** (`true`): `line_total_i = net_i`. If `totalRate = 0`: `taxable_i = net_i`, `tax_i = 0`. Else `taxable_i = round2(net_i × 100 / (100 + totalRate))`, `tax_i = net_i − taxable_i`. Split `tax_i` across components proportionally to rate in cents using the same largest-remainder method (ties → earlier `sort_order`) so `Σ_c tax_ic = tax_i` exactly.
- No tax profile → `taxable_i = net_i`, `tax_i = 0`, no tax rows.

**Step 7 – totals.** `tax_total = Σ tax_i`; `total_before_round_off = Σ line_total_i` (ITEM + SERVICE_CHARGE + DELIVERY_CHARGE + PACKAGING_CHARGE lines).
- `round_off_mode = NONE`: `round_off = 0`.
- `NEAREST_1`: `grand_total = (total_before_round_off).setScale(0, HALF_UP)`; `round_off = grand_total − total_before_round_off` (can be negative).
- `grand_total ≥ 0` always.

**Invariants (property-tested with jqwik, 10 000 random cases each; the same 7 invariants were already run on the Python reference with 10 000 random cases each and pass):**
1. `Σ discount_i = discount_total`.
2. `Σ line_total_i = total_before_round_off`.
3. `grand_total = total_before_round_off + round_off`.
4. Every `line_total_i = taxable_i + tax_i` (exclusive) or `= net_i` (inclusive); every amount `≥ 0`.
5. `Σ tax_ic (all components, all lines) = tax_total`.
6. Calculating twice with the same input gives identical output (pure/deterministic).
7. Order of input lines does not change any total (relies on Step 0).

### 5.4 Test vectors (must pass exactly)
Tax profile "T5" used below = components `CGST 2.50` + `SGST 2.50` (example values for tests only; real rates are user-configured).

**V1 – exclusive, percent discount, round-off**
Lines: A `2 × 100.00`, B `1 × 150.00`, both T5. Discount `PERCENT 10`. `prices_include_tax=false`, `NEAREST_1`.
- `subtotal = 350.00`, `discount_total = 35.00` → `discount_A = 20.00`, `discount_B = 15.00`
- taxable A `180.00`, B `135.00`
- A tax: CGST `4.50`, SGST `4.50` (line tax `9.00`); B tax: `135.00×2.5% = 3.375 → 3.38` each (line tax `6.76`)
- `tax_total = 15.76`; `total_before_round_off = 315.00 + 15.76 = 330.76`
- `grand_total = 331.00`, `round_off = +0.24`

**V2 – inclusive**
Line: `1 × 100.00`, T5, no discount, `prices_include_tax=true`, `NEAREST_1`.
- `taxable = round2(100×100/105) = 95.24`, `tax = 4.76` → CGST `2.38`, SGST `2.38`
- `line_total = 100.00`, `grand_total = 100.00`, `round_off = 0.00`

**V3 – allocation ties**
Three ITEM lines each `10.00` gross, no tax. Discount `AMOUNT 10.00`.
- exact each `3.3333…`, floors `3.33 ×3 = 9.99`, `R = 1 cent` → line1 `3.34`, line2 `3.33`, line3 `3.33`.

**V4 – invalid discount**
Subtotal `50.00`, discount `AMOUNT 50.01` → error `DISCOUNT_EXCEEDS_SUBTOTAL`. Percent `0` or `100.01` → `VALIDATION_ERROR`.

**V5 – service charge with tax**
Outlet service charge `10%` taxed with T5, exclusive. One untaxed line `1 × 200.00`, no discount.
- `sc = 20.00`; SC line tax CGST `0.50`, SGST `0.50`
- `total_before_round_off = 200.00 + 21.00 = 221.00`, `grand_total = 221.00`

**V6 – percent rounding**
Subtotal `99.99`, `PERCENT 15` → `99.99×0.15 = 14.9985 → discount_total = 15.00`.

**V7 – round-off boundaries (`NEAREST_1`)**
`100.50 → 101.00 (round_off +0.50)`; `100.49 → 100.00 (−0.49)`; `100.00 → 100.00 (0.00)`.

**V8 – no tax profile**
Line `3 × 33.33` → `line_gross = 99.99`; taxable `99.99`, tax `0.00`.

**V9 – round-off NONE**
Same as V1 with `NONE` → `grand_total = 330.76`, `round_off = 0.00`.

**V10 – delivery charge, exclusive, with discount and service charge**
Item `1 × 200.00` (untaxed), discount `PERCENT 10`, service charge `10%` (untaxed), delivery charge `40.00` taxed with T5, exclusive.
- `discount_total = 20.00`; service charge = 10 % of `180.00` = `18.00` (the delivery charge is **not** in its base); delivery tax = CGST `1.00` + SGST `1.00`
- `total_before_round_off = 180.00 + 18.00 + 42.00 = 240.00`; `grand_total = 240.00`; line order ITEM, SERVICE_CHARGE, DELIVERY_CHARGE.

**V11 – delivery charge, inclusive**
Item `1 × 100.00` (untaxed), delivery charge `52.50` taxed with T5, `prices_include_tax=true`, `NEAREST_1`.
- delivery `taxable = 50.00`, `tax = 2.50`, `line_total = 52.50`; `total_before_round_off = 152.50`; `grand_total = 153.00` (half rounds up), `round_off = +0.50`.

> Reference implementation of these rules: `reference/bill_calculator.py`; tests: `reference/test_vectors.py` (V1–V11) and `reference/test_props.py` (invariants, 10 000 random cases each).

### 5.5 Bill numbering
- `fiscal_year` label: if `fiscal_year_start_month = 1` → `"2026"`. Otherwise, with start month `m`: FY start year = (outlet-local date's year if month ≥ m else year − 1); label = `"{startYear}-{(startYear+1) mod 100, 2 digits}"` e.g. `"2026-27"`.
- `bill_seq` = atomic counter per `(outlet, series, fiscal_year)`:
  `INSERT INTO bill_counters(outlet_id,series,fiscal_year,last_no) VALUES (?,?,?,1) ON CONFLICT (outlet_id,series,fiscal_year) DO UPDATE SET last_no = bill_counters.last_no + 1 RETURNING last_no;`
- `bill_number = series + "-" + fiscal_year + "-" + lpad(bill_seq, 6, '0')` → `B-2026-27-000123`.
- Assigned **inside the bill-generation transaction**. If the transaction rolls back the counter increment rolls back too (gapless). Voided bills keep their number forever; numbers are never reused.
- Required concurrency test: 100 parallel generations on one outlet → 100 distinct, consecutive numbers, no duplicates, no gaps.
- **Registered terminals (Section 24.4):** a registered terminal issues bills in its own series (e.g. `A`) from a local counter; the server validates contiguity at sync (`bill_counters.last_no` = highest sequence seen; missing numbers → `bill_number_gaps`). Gapless-by-transaction applies to the server-allocated default series `B` only.
- **Credit notes** use `bill_counters` with `series = 'CN'` and the same atomic upsert, inside the credit-note transaction (Section 25.12): `CN-2026-27-000001`. Whether a separate series is acceptable is not verified (Decision 30).

### 5.6 Business date & other counters
`business_date = (now in outlet timezone − day_start_hour hours).toLocalDate()`. Example: `day_start_hour=4`, local time 01:30 on 23 Nov → business date 22 Nov. `order_no` and `kot_no` use per-`(outlet, business_date)` counters with the same atomic upsert. Offline orders/KOTs carry `device_order_no` / `device_kot_no` (unique per device and business date); `order_no`/`kot_no` are assigned at sync.

### 5.7 Split bills
- **By items:** `POST /orders/{id}/bills` with `orderItemIds[]` (subset of unbilled active items). Each call creates one bill. Discount applies per bill.
- A flat packaging charge is charged once per order: the first generated bill carries it (partial unique index); if that bill is voided the next one does (25.6).
- **Equal split:** one bill, multiple `payments` rows (UI helper divides the grand total by N; the last payer gets the remainder cents).
- DB guarantee: an order item can be on at most one active bill (`ux_bill_lines_order_item_active`).

### 5.8 Void rules
- Bill `GENERATED` (no successful payment): MANAGER+ may void with `reason` (required, ≥ 5 chars) → bill `VOID`, lines `active=false`, order recomputed (back to `OPEN`), audit log.
- Bill `PAID`: OWNER only, reason required — for **mistakes** (whole sale cancelled); every `SUCCESS` payment becomes `REFUNDED` (the cashier records the refund physically); the coupon redemption is released (trigger); audit log. (Automated gateway refunds are out of scope for v1.) **A PAID bill that already has a credit note cannot be voided** (`BILL_HAS_CREDIT_NOTES`). For a return after the sale use a **credit note** (Section 25.12): part or all of the bill, by line and quantity, tax reversed from the original, refund method cash/original/ON_ACCOUNT, manager PIN + reason.
- A voided bill cannot be un-voided; generate a new bill instead.
- **Inventory (Section 26):** after a bill is voided (or a credit note issued) the inventory module posts proportional `SALE_REVERSAL` movements (26.7). Interface: the billing service raises `BillVoided(billId)` and `CreditNoteIssued(creditNoteId, billLineId, fraction)` after commit of the document; no FK from inventory to credit-note tables (added in V016).

### 5.9 Payments
- Allowed only on `GENERATED` bills. `amount ≤ remaining = grand_total − Σ SUCCESS`. For `CASH`: `tendered_amount ≥ amount`, `change = tendered − amount`. Non-cash cannot exceed remaining.
- When `Σ SUCCESS = grand_total` (compare with `compareTo`, never `equals`) → bill `PAID`, `paid_at` set, order recomputed, all inside one transaction with a row lock on the bill (`SELECT … FOR UPDATE`).
- `UPI` payments record which **payment account** (Section 21) was used (`payments.payment_account_id`).
- `UPI` with `confirmation=MANUAL`: payment is created as `PENDING`; cashier presses **"Payment received"** to move it to `SUCCESS` (records `confirmed_by`). `confirmation=PROVIDER`: set to `SUCCESS` only by a verified webhook (Section 9).
- `PENDING` UPI payments older than `expires_at` become `EXPIRED` (scheduled job, every minute).
- `method` also allows **`ON_ACCOUNT`** (needs `customer_id`; no tip, no tendered cash; blocked above the customer's credit limit unless a manager overrides; creates a `CHARGE` ledger row — 25.11). `tip_amount` (+ optional `tip_staff_id`) is stored on the payment, is **not** part of `amount`, the bill total or `remaining`, carries no tax and no round-off (25.9). With `outlets.shifts_required` a payment needs an open shift (`shift_id`); a cash payment lands in the shift's drawer (25.10). Cash and the `amount ≤ remaining` rules are unchanged.
- **Gateway intents (Section 27.B):** a `payment_intents` row locks the amount to the bill's remaining balance; only an exact-amount provider SUCCESS received in time and on a still-payable bill is applied (once). Pressing **Payment received** on a bill with a live intent first expires that intent (superseded). A provider success that arrives after the bill was paid or voided is flagged `DUPLICATE_PAYMENT` / `BILL_NOT_PAYABLE` and never applied; late, mismatched and duplicate payments need a Manager (S38). Refunds are manual in v1.

### 5.10 Table status (derived, never stored)
For a table: `FREE` (no order in `OPEN`/`BILLED`), `OCCUPIED` (has an `OPEN` order), `BILL_PENDING` (only `BILLED` orders). Floor-view query returns this status plus running total and elapsed minutes. If two active orders exist on one table (possible after offline sync, 24.6) the floor view shows 'needs attention'; the database does not forbid it.

### 5.11 Table transfer / merge
- **Transfer:** move an `OPEN` order to a `FREE` table. Audit logged.
- **Merge:** move all active items of source order into target order (both `OPEN`, same outlet, neither has an active bill); source order → `CANCELLED` with `cancel_reason='MERGED_INTO:<orderNo>'`. KOT history stays attached to its original order.

### 5.12 Migration V006 — outlet notification settings (used by Section 11)
```sql
CREATE TABLE outlet_notification_settings (
  outlet_id uuid PRIMARY KEY REFERENCES outlets(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  customer_channel_priority text[] NOT NULL DEFAULT '{WHATSAPP,SMS,EMAIL}',  -- first usable channel wins
  notify_on_placed boolean NOT NULL DEFAULT true,
  notify_on_picked_up boolean NOT NULL DEFAULT true,
  notify_on_arriving boolean NOT NULL DEFAULT true,
  notify_on_delivered boolean NOT NULL DEFAULT true,
  arriving_radius_m int NOT NULL DEFAULT 150 CHECK (arriving_radius_m BETWEEN 50 AND 1000),
  avg_speed_kmph int NOT NULL DEFAULT 20 CHECK (avg_speed_kmph BETWEEN 5 AND 80)
);
```

---

## 6. REST API

Base path `/api/v1`. JSON only. Auth: `Authorization: Bearer <accessToken>`. Active outlet: header `X-Outlet-Id: <uuid>` (required on every outlet-scoped endpoint). Money/quantity are **strings**. Timestamps ISO-8601 UTC.

### 6.1 Conventions
- **Pagination:** `?page=0&size=20&sort=createdAt,desc` → `{ "content": [...], "page": 0, "size": 20, "totalElements": 134, "totalPages": 7 }`. Max `size=100`.
- **Errors:** `application/problem+json`:
  ```json
  { "type":"about:blank","title":"Validation failed","status":422,"code":"VALIDATION_ERROR",
    "detail":"One or more fields are invalid","traceId":"9f3c…",
    "fieldErrors":[{"field":"discount.value","message":"must be > 0"}] }
  ```
- **Idempotency-Key** header required on: `POST /orders/{id}/kots`, `POST /orders/{id}/bills`, `POST /bills/{id}/payments`, `POST /day-closing/close`.
- **Optimistic lock:** body field `version`; mismatch → `409 VERSION_CONFLICT`.
- **Manager override:** header `X-Override-Token` (from `POST /auth/override`) on actions marked 🔑. Missing/expired → `403 OVERRIDE_REQUIRED`.
- **Rate limits:** `/auth/login` 10/min/IP and 5 failures/account → 15 min lock; `/public/**` 60/min/IP; rider location 1 request/3 s/rider.

### 6.2 Endpoint catalogue
> Part II endpoints: platform/tenants/plans/invoices (18.9), support & feedback (19.5), delivery settings/charges (20.6), payment accounts (21.5), WhatsApp & public bill links (23.10). New error codes: Appendix B.
Roles: O=Owner, M=Manager, C=Cashier, K=Captain, T=Kitchen, R=Rider.

**Auth & users**
| Method | Path | Roles | Notes |
|---|---|---|---|
| POST | `/auth/login` | public | `{email,password}` → `{accessToken,expiresIn,user,outlets[]}`; sets httpOnly refresh cookie |
| POST | `/auth/refresh` | cookie | requires header `X-Requested-With: Galla`; rotates refresh token |
| POST | `/auth/logout` | any | revokes refresh family |
| GET | `/auth/me` | any | current user + permissions |
| POST | `/auth/override` | any | `{pin}` → `{overrideToken,expiresIn:120}`; PIN must belong to an active OWNER/MANAGER with access to the outlet; token is single-use |
| GET/POST | `/users` | O,M | list/create (M cannot create OWNER) |
| PUT | `/users/{id}` | O,M | profile, role, status |
| POST | `/users/{id}/reset-password` | O,M | sets temp password, forces change |
| PUT | `/users/{id}/outlets` | O | assign outlets |
| PUT | `/users/me/password` | any | change own password |
| PUT | `/users/me/pin` | O,M | set override PIN |

**Outlet & settings**
| Method | Path | Roles |
|---|---|---|
| GET | `/outlets` | any (only assigned) |
| POST | `/outlets` | O |
| GET/PUT | `/outlets/{id}` | O (PUT), M (GET) |
| GET/PUT | `/outlets/{id}/notification-settings` | O,M |
| GET/POST/PUT | `/tax-profiles`, `/tax-profiles/{id}` | O,M (read: all) |

**Catalog**
| Method | Path | Roles |
|---|---|---|
| GET | `/catalog/pos` | O,M,C,K — whole active menu in one payload with `ETag`; supports `If-None-Match` → 304 |
| GET/POST/PUT/DELETE | `/categories[/{id}]` | O,M |
| GET/POST/PUT/DELETE | `/items[/{id}]` (DELETE = soft) | O,M |
| PATCH | `/items/{id}/availability` `{available}` | O,M,C |
| POST | `/items/import` (CSV) | O,M |
| GET/POST/PUT/DELETE | `/modifier-groups[/{id}]` | O,M |
| GET/POST/PUT/DELETE | `/kitchen-stations[/{id}]` | O,M |

**Floor**
| Method | Path | Roles |
|---|---|---|
| GET | `/floor` | O,M,C,K — areas with tables + derived status, running total, minutes open |
| CRUD | `/dining-areas`, `/dining-tables` | O,M |

**Customers**
| Method | Path | Roles |
|---|---|---|
| GET | `/customers?phone=&q=` | O,M,C,K |
| POST/PUT | `/customers[/{id}]` | O,M,C,K |
| POST/PUT/DELETE | `/customers/{id}/addresses[/{aid}]` | O,M,C,K |

**Orders & KOT**
| Method | Path | Roles | Notes |
|---|---|---|---|
| POST | `/orders` | O,M,C,K | create (client may supply `id`) `{orderType, tableId?, customerId?, guestCount?}`; DINE_IN requires table without an active order, else `409 TABLE_OCCUPIED` |
| GET | `/orders` | O,M,C,K | filters `status,type,businessDate,tableId` |
| GET | `/orders/{id}` | O,M,C,K | order + items + bills + kots |
| PUT | `/orders/{id}` | O,M,C,K | guestCount, notes, customer; with `version` |
| POST | `/orders/{id}/items` | O,M,C,K | add draft item `{menuItemId, variantId?, modifierIds[], quantity, notes?}` |
| PUT | `/orders/{id}/items/{itemId}` | O,M,C,K | only drafts |
| DELETE | `/orders/{id}/items/{itemId}` | O,M,C,K | only drafts |
| POST | `/orders/{id}/items/{itemId}/cancel` | 🔑 | `{reason}`; after KOT |
| POST | `/orders/{id}/kots` | O,M,C,K | Idempotency-Key; returns KOT(s); enqueues print jobs |
| POST | `/orders/{id}/transfer` | O,M,C | `{toTableId}` |
| POST | `/orders/{id}/merge` | O,M | `{intoOrderId}` |
| POST | `/orders/{id}/cancel` | O,M (🔑 for C if KOT sent) | `{reason}` |
| GET | `/kots/{id}` | O,M,C,K,T | |
| GET | `/kitchen/orders` + SSE | T | active KOT items grouped by station for the kitchen screen (Phase 2, simple list view) |

**Billing**
| Method | Path | Roles | Notes |
|---|---|---|---|
| POST | `/bills/preview` | O,M,C | `{orderId, orderItemIds?, discount?}` → computed bill, nothing persisted |
| POST | `/orders/{id}/bills` | O,M,C | Idempotency-Key; `{orderItemIds? (default: all unbilled active), discount?{type,value,reason}, customerName?, customerPhone?}`; discount > configured limit needs 🔑 |
| GET | `/bills/{id}` | O,M,C | |
| GET | `/bills` | O,M,C | filters `status,from,to,billNumber,q` |
| POST | `/bills/{id}/void` | M (GENERATED), O (PAID) | `{reason}` |

**Payments**
| Method | Path | Roles | Notes |
|---|---|---|---|
| POST | `/bills/{id}/payments` | O,M,C | Idempotency-Key; `{method, amount, tenderedAmount?, reference?}` |
| POST | `/bills/{id}/upi-qr` | O,M,C | creates PENDING UPI payment, returns `{paymentId, qrPayload, expiresAt, confirmation}` |
| POST | `/payments/{id}/confirm` | O,M,C | manual UPI/card confirmation |
| POST | `/payments/{id}/cancel` | O,M,C | only PENDING |
| GET | `/bills/{id}/payments` | O,M,C | |
| POST | `/webhooks/payments/{provider}` | public, signature-verified | Section 9 |

**Printing**
| Method | Path | Roles |
|---|---|---|
| CRUD | `/printers` | O,M |
| POST | `/printers/{id}/test` | O,M |
| POST | `/bills/{id}/print`, `/kots/{id}/print` | O,M,C,K — `{printerId?}` creates job (or returns HTML URL for BROWSER printers) |
| GET | `/bills/{id}/print-doc?format=html|json&width=58|80` | O,M,C |
| POST | `/print-agents` (token shown once) | O,M |
| GET | `/agent/jobs/stream` (SSE) | agent token |
| POST | `/agent/jobs/{id}/ack` `{status:PRINTED|FAILED, error?}` | agent token |
| POST | `/agent/heartbeat` | agent token |

**Delivery**
| Method | Path | Roles |
|---|---|---|
| POST | `/orders/{id}/delivery` | O,M,C — creates delivery for an order of type DELIVERY `{addressText, destLat?, destLng?, customerName, customerPhone}` |
| GET | `/deliveries?status=` | O,M,C |
| GET | `/deliveries/{id}` | O,M,C |
| POST | `/deliveries/{id}/status` `{to, note?}` | O,M,C (per Section 11.1) |
| POST | `/deliveries/{id}/assign` `{riderId}` | O,M,C |
| CRUD | `/riders` | O,M |
| GET | `/deliveries/stream` (SSE) | O,M,C |
| GET | `/rider/me/deliveries` | R |
| POST | `/rider/deliveries/{id}/status` `{to, note?}` | R (only PICKED_UP, DELIVERED, FAILED) |
| POST | `/rider/location` `{deliveryId, points:[{lat,lng,accuracy,speed,heading,recordedAt}]}` | R |
| PUT | `/rider/me/availability` `{status:AVAILABLE|OFFLINE}` | R |
| GET | `/public/track/{token}` | public |
| GET | `/public/track/{token}/stream` (SSE) | public |

**Reports & day close**
| Method | Path | Roles |
|---|---|---|
| GET | `/reports/daily-sales?date=` | O,M |
| GET | `/reports/item-sales?from=&to=` | O,M |
| GET | `/reports/payment-modes?from=&to=` | O,M |
| GET | `/reports/discounts?from=&to=` | O,M |
| GET | `/reports/voids?from=&to=` | O,M |
| GET | `/reports/hourly?date=` | O,M |
| GET | `/reports/*/export?format=csv` | O,M |
| GET | `/day-closing/current` | O,M,C — status for current business date + readiness checks |
| POST | `/day-closing/close` `{countedCash, openingCash?}` | O,M — Idempotency-Key; blocks if any order is `OPEN`/`BILLED` unless `force=true` (O only); fails with `OPEN_SHIFTS_EXIST` while any shift of the outlet is OPEN (DB trigger, Section 25.10) |
| POST | `/day-closing/{id}/resend-email` | O,M |
| POST | `/day-closing/{id}/reopen` `{reason}` | O — see Section 11.7 |

**Misc**
| Method | Path | Roles |
|---|---|---|
| GET | `/audit-logs?entityType=&entityId=&from=&to=` | O,M |
| POST | `/push/subscribe` | any |
| GET | `/notifications/outbox?status=` | O,M |
| GET | `/actuator/health/liveness`, `/readiness` | public (no details) |

### 6.3 Key payloads
**POST `/orders/{id}/items`**
```json
{ "menuItemId":"…", "variantId":null, "modifierIds":["…"], "quantity":"2", "notes":"less spicy" }
```
**Bill response** (shape for V1 of Section 5.4)
```json
{
  "id":"…","billNumber":"B-2026-27-000123","status":"GENERATED","orderId":"…",
  "pricesIncludeTax":false,"currencyCode":"INR",
  "subtotal":"350.00","discountType":"PERCENT","discountValue":"10.00","discountTotal":"35.00",
  "serviceChargeTotal":"0.00","taxTotal":"15.76","totalBeforeRoundOff":"330.76",
  "roundOff":"0.24","grandTotal":"331.00","amountPaid":"0.00","balanceDue":"331.00",
  "lines":[
    {"lineNo":1,"type":"ITEM","name":"Paneer Tikka","quantity":"2","unitPrice":"100.00",
     "lineGross":"200.00","discountAmount":"20.00","taxableAmount":"180.00","taxAmount":"9.00","lineTotal":"189.00",
     "taxes":[{"name":"CGST","ratePercent":"2.50","taxAmount":"4.50"},{"name":"SGST","ratePercent":"2.50","taxAmount":"4.50"}]}
  ],
  "taxSummary":[{"name":"CGST","ratePercent":"2.50","taxableAmount":"315.00","taxAmount":"7.88"}],
  "version":0,"generatedAt":"2026-11-22T15:44:00Z"
}
```
> Note: `taxSummary` is derived by summing `bill_line_taxes` grouped by `(component_name, rate_percent)`; it must equal `taxTotal` when summed over components.

---

## 7. REAL-TIME (SSE)

- Server→client only; client actions are normal `POST`s. Staff streams use `@microsoft/fetch-event-source` (supports `Authorization` header). The public tracking stream uses native `EventSource`.
- Streams: `GET /deliveries/stream` (outlet events), `GET /agent/jobs/stream`, `GET /public/track/{token}/stream`.
- Event envelope: `event: <type>` + `data: {"id":"…","version":N, …}`. Types: `order.updated`, `table.changed`, `bill.paid`, `delivery.status`, `delivery.location`, `print.job`, `kitchen.item.status`.
- `kitchen.item.status` `{orderItemId, kotId, orderId, from, to, at}` (Section 25.13).
- **Frontend rule:** for everything except `delivery.location` and `print.job`, the event only says *"entity X changed"*; the client invalidates the matching TanStack Query key and refetches. This keeps one source of truth and avoids stale-state bugs.
- Fan-out across backend instances via Redis pub/sub channels `outlet:{outletId}:events` and `delivery:{id}:loc`.
- Heartbeat comment `: ping` every 25 s; server closes idle streams after 2 h; client auto-reconnects with backoff 1 s → 30 s and refetches all visible queries on reconnect.

---

## 8. PRINTING

### 8.1 Pipeline
`Bill/KOT → PrintDocument (structured JSON) → renderer → (HTML for browser) | (ESC/POS bytes for agent)`. The same `PrintDocument` feeds both renderers so layouts never diverge.

### 8.2 Bill layout (80 mm = 48 columns, Font A; 58 mm = 32 columns — same blocks, narrower columns)
```
            {OUTLET NAME}
         {address line 1, line 2}
              Ph: {phone}
        {tax_registration_label}: {tax_registration_no}
        {license_label}: {license_no}
------------------------------------------------
Bill: B-2026-27-000123       Date: 22/11/2026
Table: T4 (Dine-in)          Time: 21:14
Cashier: Asha                Guests: 3
------------------------------------------------
Item                      Qty    Rate     Amount
------------------------------------------------
Paneer Tikka                2  100.00     200.00
Butter Naan                 4   40.00     160.00
------------------------------------------------
Subtotal                                  360.00
Discount (10%)                            -36.00
CGST 2.50%                                  8.10
SGST 2.50%                                  8.10
Round off                                  -0.20
------------------------------------------------
GRAND TOTAL                            Rs 340.00
------------------------------------------------
Paid: UPI                                 340.00
              {bill_footer}
              [QR: payment / feedback link]
```
Extra bill blocks (25.19): combo header with indented components; `Packaging charge` line after the delivery charge; `Coupon CODE −x.xx` replaces `Discount`; `NC — Complimentary` banner + reason, no QR; `Tip (not part of bill)` after GRAND TOTAL; `Paid: On account — {customer}`.

Rules: labels with empty values are omitted; long names wrap at column width (word boundary, continuation lines indented 2); numbers right-aligned; currency symbol from `outlet.currency_symbol` (never assume `₹` — many thermal printers lack the glyph); `GRAND TOTAL` printed double-height bold; paper cut after footer.

**Header amendment (Section 28.A, 28.C):** Header (each line printed only when the field is set): **document title** (Section 28.A.1) · trade/legal name · address · **GSTIN** · **FSSAI Lic. No.** · phone. Item lines show the **HSN/SAC** code when the outlet has `print_hsn`. All of these come from the **bill snapshot** (`bills.seller_*`, 28.A.4), not from the outlet's current values. Text is in the **outlet bill language** (28.C); Hindi bills are rendered as a raster image (28.C.3). This replaces the header block of the sample above where they differ.

### 8.3 KOT layout (no prices)
```
KOT #14        Station: Tandoor
Table: T4      Order #37   21:12
------------------------------------------------
2 x Paneer Tikka
    + Extra spicy
    NOTE: no onion
4 x Butter Naan
------------------------------------------------
Captain: Ravi
```
Reprints are stamped `** DUPLICATE **`. KOT: combo heading with indented component lines; `OPEN ITEM` tag.

Partner orders (Section 27.A.5): the KOT shows a header chip `PARTNER · {name} · #{externalOrderId}`; a provider-cancelled order prints a 'CANCELLED — do not prepare' slip.

### 8.4 ESC/POS encoder (backend, `printing/escpos`)
Minimal command set only: initialize `ESC @`; align `ESC a n`; bold `ESC E n`; size `GS ! n`; feed `ESC d n`; partial cut `GS V 66 n`; QR code `GS ( k` sequence; code page select `ESC t n`. Text is encoded with the printer's `code_page` (default CP437); unsupported characters are replaced with `?` (never throw). Unit-test the encoder against golden byte files.
A raster path (`GS v 0`) is used for languages the printer's code pages cannot render; capability flag per printer profile (`raster_supported`) — **not tested on hardware**.

### 8.5 Browser printing (fallback / default for MVP)
`GET /bills/{id}/print-doc?format=html&width=80` returns a standalone HTML page with `@page { size: 80mm auto; margin: 0 }`, monospace font, black-on-white. The frontend loads it in a hidden `<iframe>` and calls `iframe.contentWindow.print()`. Documented limitation: browsers show a print dialog unless kiosk-printing mode is enabled (`--kiosk-printing` flag in Chrome) — this is why the print agent exists.

### 8.6 Print agent protocol
1. Owner/Manager creates an agent in Settings → shows a one-time token.
2. Agent starts with `--server https://… --token …`, connects to `GET /agent/jobs/stream`.
3. Server pushes `event: print.job` `{id, deviceAddress, codePage, payloadBase64}` for that agent's printers. Job → `CLAIMED`.
4. Agent writes bytes to `tcp://host:9100` (raw socket) or USB device, then `POST /agent/jobs/{id}/ack {status:"PRINTED"}` (or `FAILED` + error).
5. If no ack within 30 s the job returns to `PENDING` (`attempts+1`); after 3 attempts → `FAILED`; the UI shows a red "Print failed — Retry" toast with a retry button. Acks are idempotent.
6. Agent heartbeat every 15 s updates `last_seen_at`; Settings shows agent Online/Offline.
7. **Loopback mode (Phase 2O):** the agent also accepts `POST http://127.0.0.1:<port>/print` from the browser with the pairing token; body = `PrintDocument` JSON; same ESC/POS encoder, same retries; works without the internet (Section 24.8).

### 8.7 Credit note layout
Outlet header, `CREDIT NOTE`, `CN-2026-27-000001`, date/time, `Against bill: B-… dated …`, lines (name, qty returned, taxable, tax), tax summary per component, round-off, `REFUND TOTAL`, refund method + reference, reason, `Approved by`, `DUPLICATE` on reprints. Same 48/32 column rules as 8.2.

---

## 9. PAYMENTS & UPI QR

### 9.1 Provider abstraction
```java
public interface UpiPaymentProvider {
  String code();                                        // "manual", later e.g. a gateway code
  UpiQr createQr(UpiQrRequest r);                       // billId, amount, currency, reference, expiresAt
  WebhookResult verifyAndParse(String rawBody, Map<String,String> headers);   // throws on bad signature
}
```
Provider choice is **not decided** (see Open Decision 51); the gateways seen in research (e.g. PhonePe, Razorpay, PayU) all expose a "dynamic QR + callback" pattern that fits this interface. Implementations are added without changing billing code.

### 9.2 Mode A — `manual` provider (built first, no gateway needed)
> **Part II change:** the UPI ID no longer lives on the outlet. Migration V010 moves `outlets.upi_vpa/upi_payee_name` into `outlet_payment_accounts`, and restaurants may hold several accounts or upload their own QR (Section 21). `{account}` below is the selected payment account.
- Server builds the standard UPI deep link and returns it as `qrPayload`:
  `upi://pay?pa={account.vpa}&pn={urlEncode(account.payee_name)}&am={amount with 2 decimals}&cu={currency}&tn={bill_number}`
- Frontend renders it as a QR code (`qrcode` library) in the payment dialog. The amount is locked in the link.
- The system cannot know the customer paid. The cashier must press **"Payment received"**; the dialog says so explicitly. Confirming user and time are stored (`confirmed_by`, `confirmed_at`) for audit.

### 9.3 Mode B — provider with callback (Phase 4): **see Section 27.B**
The `UpiPaymentProvider` interface (9.1) stays the adapter contract; webhook route `POST /webhooks/payments/{provider}`; amount locked, one live intent per bill, derived intent state, late/mismatch/duplicate handling, settlements import. Provider choice is Open Decision 51.

### 9.4 Discounts before QR
The QR amount always equals the **remaining balance of the generated bill**. To discount, void and regenerate the bill (or apply the discount at bill generation). Never change an amount under an existing QR.

---

## 10. NOTIFICATIONS & END-OF-DAY

### 10.1 Outbox worker
- `@Scheduled(fixedDelay=5000)`: `SELECT … FROM notification_outbox WHERE status='PENDING' AND next_attempt_at <= now() ORDER BY created_at LIMIT 20 FOR UPDATE SKIP LOCKED` → mark `SENDING` → send via channel → `SENT` or retry.
- Retry backoff: 1 min, 5 min, 30 min, 2 h, 12 h; after the 5th failure → `FAILED` (visible in admin screen, can be retried manually).
- `SENDING` rows older than 5 min are reset to `PENDING` (worker crashed).
- `dedupe_key` unique → inserting the same logical notification twice is a no-op.
- Channels implement `NotificationChannel { Channel type(); SendResult send(OutboxMessage m); }`. `EMAIL` uses SMTP. `WHATSAPP` is implemented by the `whatsapp` module (Section 23: consent + approved template + status webhook); `SMS` ships as a stub that marks the row `FAILED` with `PROVIDER_NOT_CONFIGURED` (never silently drop); a WhatsApp send without a connected account or approved template also ends as `FAILED` with `WHATSAPP_NOT_CONFIGURED`/`WHATSAPP_TEMPLATE_NOT_APPROVED`. `PUSH` uses Web Push (VAPID keys from env) and is optional.

### 10.2 Templates
Stored in `notification_templates` with `{{variable}}` placeholders; rendered with a safe, logic-less engine (no code execution; HTML-escape values in email). System defaults seeded: `EOD_SUMMARY`, `DELIVERY_PLACED`, `DELIVERY_PICKED_UP`, `DELIVERY_ARRIVING`, `DELIVERY_DELIVERED`, `DELIVERY_FAILED_STAFF`. Stream D adds template keys `weekly_summary`, `monthly_summary`, `ops_online_order_expired`, `ops_payment_attention` (English text defaults; Hindi after review).

### 10.3 End-of-day summary (computed by SQL, never by the LLM)
`day_closings.summary` JSON:
```json
{ "businessDate":"2026-11-22","outlet":{"id":"…","name":"…"},
  "bills":{"count":142,"voidedCount":2,"voidedAmount":"1240.00"},
  "sales":{"subtotal":"61200.00","discounts":"2310.00","serviceCharge":"0.00","tax":"2989.50","roundOff":"-1.20","grandTotal":"61878.30"},
  "byPaymentMethod":[{"method":"CASH","amount":"22100.00"},{"method":"UPI","amount":"31000.30"},{"method":"CARD","amount":"8778.00"}],
  "byOrderType":[{"type":"DINE_IN","bills":98,"amount":"44000.00"}],
  "topItems":[{"name":"Butter Naan","qty":"310","amount":"12400.00"}],
  "cash":{"opening":"2000.00","expected":"24100.00","counted":"24050.00","variance":"-50.00"},
  "nc":{"bills":2,"listValue":"640.00","taxLiability":"32.00","byReason":[{"code":"STAFF_MEAL","bills":2}]},
  "coupons":{"redeemed":9,"discount":"1240.00","byCode":[{"code":"WELCOME10","uses":9,"discount":"1240.00"}]},
  "packaging":"310.00",
  "tips":{"total":"540.00","cash":"300.00","other":"240.00"},
  "creditSales":{"charged":"2100.00","settled":"800.00","outstanding":"15400.00"},
  "shifts":[{"cashier":"Asha","opening":"2000.00","expected":"24100.00","counted":"24050.00","variance":"-50.00"}],
  "refunds":{"count":3,"amount":"620.00","byMethod":[{"method":"CASH","amount":"400.00"}]},
  "openItems":{"count":4,"amount":"900.00"},
  "warnings":["2 orders still OPEN at close","Discounts are 3.8% of subtotal"],
  "delivery":{"delivered":21,"failed":1,"avgMinutes":34},
  "manualUpiConfirmations":[{"cashier":"Asha","count":18,"amount":"9400.00"}],
  "deliveryCharges":"840.00",
  "inventory":{"opening_value":"84210.50","purchases_value":"18400.00","consumption_value":"15320.75","wastage_value":"640.00","adjustments_value":"-120.00","other_movements_value":"0.00","closing_value":"86529.75","low_stock_count":6,"no_recipe_items_count":3,"price_alert_count":2,"sales_coverage_percent":"96.40"} }
```
(`inventory` is the object of Section 26.10 and is `null` when the outlet has not started inventory (feature flag `inventory` off or no opening stock). Invariant: closing = opening + purchases − consumption − wastage + adjustments + other (Section 26.10).) Section 25 adds the keys `nc`, `coupons`, `packaging`, `tips`, `creditSales`, `shifts`, `refunds`, `openItems`; the `cash` object stays only for outlets without shifts (with shifts, per-shift figures are in `shifts`). The email layout gets matching sections; all numbers are computed by code (the AI guard of 10.5 is unchanged).

If any payment intent needs attention (27.B.6) or any online order expired unaccepted (27.A.1) that day, the e-mail lists the count and the S38/S36 link. The optional weekly/monthly summary is Section 28.D.6.

### 10.4 When the EOD email is sent
1. **On day close** (`POST /day-closing/close`): compute summary → store → enqueue email to `outlet.eod_email_recipients` with `dedupe_key = "eod:<outletId>:<date>"`, in the same transaction.
2. **Safety net:** a scheduled job runs every 5 min; for outlets with `eod_email_enabled` and local time ≥ `eod_email_time` whose day is still `OPEN`, it enqueues a **PROVISIONAL** summary (subject prefixed "Provisional") with dedupe key `eod-prov:<outletId>:<date>`. It does not close the day.
3. Email = HTML + plain-text alternative: headline totals, payment-method table, top items, cash reconciliation, warnings, and (if available) the AI paragraph labelled "AI-generated summary". When `inventory` is not null the e-mail gets a **Stock** block under Sales: valuation walk (opening → closing), consumption vs purchases, and one line each for low-stock items, items without recipe and purchase-price alerts, with links to the reports. Omitted when `inventory` is null. Day close also writes `stock_snapshots` (on-hand and average cost per item for the date).
If a bill reaches the server after its business date was closed (`LATE_FOR_CLOSED_DAY`), a 'late bills added' notice is queued with dedupe key `eod:<outlet>:<date>:late:<n>`; the full summary is not re-sent. Day close (S12) warns about terminals with unsynced items and open bill-number gaps (Section 24.11).

### 10.5 AI summary (Phase 4, optional per outlet)
- Spring AI `ChatClient`; model/provider selected only through `spring.ai.*` config; timeout 15 s; temperature 0.2.
- **Input:** the summary JSON + the previous 7 days' `grandTotal` series (all computed by code). No customer names/phones are ever sent.
- **System prompt rules:** ≤ 120 words; plain English; use ONLY numbers present in the input; do not calculate; flag unusual items as "worth checking", never as accusations; no advice about staff.
- **Guard:** extract every number from the output; if any number is not present in the input (after normalising formatting) → discard the AI text and send the email without it. Any exception/timeout → send without it. The numeric tables are always generated by code.

---

## 11. DELIVERY & MAP TRACKING

### 11.1 Delivery state machine (enforced in `DeliveryService`; illegal transition → `409 ILLEGAL_TRANSITION`)
| From | Allowed next | Who |
|---|---|---|
| PLACED | PREPARING, CANCELLED | O,M,C |
| PREPARING | READY, CANCELLED | O,M,C |
| READY | ASSIGNED, CANCELLED | O,M,C |
| ASSIGNED | PICKED_UP, READY (unassign), CANCELLED | PICKED_UP: R or staff; others staff |
| PICKED_UP | DELIVERED, FAILED | R or staff |
| DELIVERED / CANCELLED / FAILED | — (terminal) | — |

Every transition writes `delivery_status_history` and publishes `delivery.status`. `FAILED` and `CANCELLED` require a `note`.
- Assign: rider must be `AVAILABLE`; becomes `BUSY`. On DELIVERED/FAILED/CANCELLED/unassign → `AVAILABLE`. One active delivery per rider in v1.
- Delivery is created from an order of type `DELIVERY`; the order's bill/payment flow is the normal one (e.g. cash on delivery is a CASH payment recorded when the rider/cashier confirms).
- Partner orders from aggregators (Section 27.A) have no rider tracking (as 20.3); the `DELIVERY` order type for them carries the delivery address from the payload if the provider sends it (**not verified**).

### 11.2 Tracking link
`tracking_token` = 32 random bytes (SecureRandom), base64url. Link: `{PUBLIC_BASE_URL}/track/{token}`. Public API returns only: status + timeline, outlet name/phone, rider **first name**, destination marker, latest rider point (only while `PICKED_UP`), ETA. No customer phone, no internal IDs. After `DELIVERED/CANCELLED/FAILED` + 2 h → `410 Gone`.

### 11.3 Rider location ingestion (`POST /rider/location`)
- Rider must be the one assigned to `deliveryId`, status `ASSIGNED` or `PICKED_UP`, else `403`.
- Accept ≤ 10 points per request. Drop points with invalid ranges, `accuracy > 200 m`, `recordedAt` older than 120 s or more than 30 s in the future.
- Persist at most one point per 5 s per delivery (downsample); publish the latest to Redis → SSE `delivery.location`.
- **Geofence:** when status is `PICKED_UP`, `arriving_notified = false` and haversine distance to destination ≤ `arriving_radius_m` → set flag and enqueue `DELIVERY_ARRIVING` (dedupe key `delivery:<id>:ARRIVING`).
- **ETA:** `RoutingProvider` interface; default `HaversineRoutingProvider` = straight-line distance ÷ `avg_speed_kmph`, recomputed at most every 30 s and stored in `eta_minutes`. A road-routing provider can be plugged in later.
- Retention job deletes `rider_locations` older than 30 days.

### 11.4 Notification triggers
| Event | Recipient | Template | Dedupe key |
|---|---|---|---|
| Delivery created (if enabled) | customer | DELIVERY_PLACED | `delivery:<id>:PLACED` |
| → PICKED_UP | customer (includes tracking link) | DELIVERY_PICKED_UP | `delivery:<id>:PICKED_UP` |
| Within radius | customer | DELIVERY_ARRIVING | `delivery:<id>:ARRIVING` |
| → DELIVERED | customer | DELIVERY_DELIVERED | `delivery:<id>:DELIVERED` |
| → FAILED | managers (push/email) | DELIVERY_FAILED_STAFF | `delivery:<id>:FAILED` |
Customer channel = first usable channel in `customer_channel_priority` (usable = has contact + provider configured). **WhatsApp is usable only when the outlet's WhatsApp account is `CONNECTED`, the delivery template is `APPROVED`, and the customer's newest `DELIVERY_UPDATES` consent is `OPTED_IN` (Section 23.5–23.6).**

### 11.5 Map UI
MapLibre GL JS; tile style URL from `VITE_MAP_STYLE_URL` (provider decided later; no key hard-coded). Markers: restaurant (🏪 icon, brand color), destination (pin, red), rider (scooter icon, rotates by `heading`, smooth 1 s animation between points). Breadcrumb polyline of the last 50 points (a *traced path*, not a routed path). Map auto-fits to rider + destination; "Recenter" button appears after the user pans. If tiles fail to load show an inline error with the delivery's text address so the page is still useful.

### 11.6 Rider web page — honest platform limits
Browser geolocation works only while the page is open and in the foreground (and on HTTPS). The page uses the Screen Wake Lock API where available and shows a persistent banner "Keep this screen open while delivering". Background tracking would need a native wrapper — noted for a later phase, not built now.

### 11.7 Migration V007 — cashier discount limit & day-close rules
```sql
ALTER TABLE outlets ADD COLUMN cashier_discount_limit_percent numeric(5,2) NOT NULL DEFAULT 0
  CHECK (cashier_discount_limit_percent BETWEEN 0 AND 100);
```
- A CASHIER may apply a discount without override only if the effective percent (`discount_total / subtotal × 100` for AMOUNT type) is ≤ this limit. Above it → `403 OVERRIDE_REQUIRED`. MANAGER/OWNER: no limit. Every discount writes an audit log with the reason (reason required for any discount).
- **Day close:** after a business date is `CLOSED`, creating an order or bill for that date returns `409 DAY_CLOSED`. OWNER may reopen with `POST /day-closing/{id}/reopen {reason}` (audit logged); reopening re-enables billing and the next close recomputes the summary (the EOD email dedupe key includes a `reopenCount` suffix so the corrected summary is sent).

---

## 12. FRONTEND DESIGN & UX SPECIFICATION

### 12.1 Design tokens (define as CSS variables in `styles/tokens.css`, exposed to Tailwind)
**Light theme**
| Token | Value | Use |
|---|---|---|
| `--primary` | `#C2410C` | primary buttons, active nav (white text on it passes AA) |
| `--primary-hover` | `#9A3412` | hover/pressed |
| `--primary-accent` | `#EA580C` | icons, focus ring, highlights (not for small text) |
| `--primary-soft` | `#FFEDD5` | selected rows, soft badges |
| `--bg` | `#F8F9FA` | app background |
| `--surface` | `#FFFFFF` | cards, modals |
| `--surface-2` | `#F1F3F5` | table headers, inputs hover |
| `--border` | `#DEE2E6` | decorative borders, dividers (not for identifying controls) |
| `--border-strong` | `#7A828B` | borders of inputs, selects, checkboxes, cards that are controls (≥ 3:1) |
| `--platform` / `--platform-soft` | `#4338CA` / `#E0E7FF` | platform console accent (white text on `--platform` = 7.9:1) |
| `--text` | `#212529` | body |
| `--text-muted` | `#5F6672` | secondary text (AA on bg, surface and surface-2) |
| `--text-disabled` | `#ADB5BD` | disabled |
| `--success` / `--success-text` / `--success-soft` | `#2F9E44` / `#1E7A34` / `#EBFBEE` | fills & icons / text / backgrounds |
| `--warning` / `--warning-text` / `--warning-soft` | `#F59F00` / `#A15C00` / `#FFF9DB` | |
| `--danger` / `--danger-text` / `--danger-soft` | `#E03131` / `#C92A2A` / `#FFF5F5` | |
| `--info` / `--info-text` / `--info-soft` | `#1C7ED6` / `#1864AB` / `#E7F5FF` | |
| `--veg` `--nonveg` `--egg` | `#2F9E44` `#E03131` `#F59F00` | food-type markers (square with dot) |

**Dark theme** (`[data-theme="dark"]`, follows `prefers-color-scheme` by default, user can override): `--bg #0B1220`, `--surface #111827`, `--surface-2 #1F2937`, `--border #374151` (decorative), `--border-strong #7B8494` (controls), `--platform-text #A5B4FC`, `--text #F3F4F6`, `--text-muted #9CA3AF`, `--primary #F97316` with button text `#111827`, `--primary-hover #FB923C`, soft backgrounds use 16 % opacity of the base color.

Rules: status text always uses the `*-text` variant; fills/icons use the base color. **Color is never the only signal** — every status has an icon or text label too. Automated axe checks must pass AA contrast in both themes. **Verified:** every text/background pair and control border in this table passes (`reference/contrast.py`, 26 pairs; the original `#6B7280` muted text and `#DEE2E6`/`#374151` control borders failed and were replaced).

**Typography:** Inter (variable, self-hosted; fallback `system-ui, sans-serif`). Money and numbers: `font-variant-numeric: tabular-nums`, right-aligned. Bill preview: `ui-monospace`.
| Style | Size/line-height | Weight |
|---|---|---|
| xs | 12/16 | 400 |
| sm | 14/20 | 400/500 |
| base | 16/24 | 400/500 |
| lg | 18/28 | 600 |
| xl | 20/28 | 600 |
| 2xl | 24/32 | 700 |
| 3xl (balance due) | 30/36 | 700 |

**Spacing** 4 px scale (4, 8, 12, 16, 24, 32, 48). **Radius**: 6 inputs/buttons, 8 cards, 12 modals, 999 badges. **Shadows**: sm `0 1px 2px rgba(16,24,40,.06)`, md `0 4px 12px rgba(16,24,40,.10)`, lg `0 12px 32px rgba(16,24,40,.16)`. **Breakpoints**: sm 640, md 768, lg 1024, xl 1280. The POS/billing screens are designed for tablet landscape (≥ 1024 × 768) and desktop; minimum supported width 768 px for staff screens; rider and public tracking pages are mobile-first (≥ 360 px).
**Motion:** 150 ms ease-out for hover/press; modals 200 ms fade + scale from 0.98; everything disabled under `prefers-reduced-motion`.

### 12.2 Component behavior (build once in `components/ui`, reuse everywhere)
- **Button** variants: primary, secondary (outline), ghost, danger. Sizes: sm 32 px, md 40 px, lg 48 px (POS primary actions use lg; touch targets ≥ 44 px). Loading state shows a spinner and keeps width; the button is disabled while loading (prevents double submit). Disabled: 50 % opacity, `cursor-not-allowed`, `aria-disabled`.
- **Input / Select / Textarea:** 1 px `--border-strong` border, label above, helper text below; error text below in `--danger-text` with an icon; validation on blur and on submit; focus ring 2 px `--primary-accent` with 2 px offset. Numeric inputs use `inputmode="decimal"` and reject non-numeric characters.
- **Modal:** centered, sizes sm 400 / md 520 / lg 720; focus trapped; initial focus on first field; `Esc` closes unless the form is dirty (then "Discard changes?" confirm); overlay click closes only non-form dialogs; focus returns to the trigger; under 640 px becomes a full-screen sheet.
- **Drawer:** right side, 420 px (full width on mobile) for detail views (bill details, item editor).
- **ConfirmDialog:** destructive actions use a danger button with a specific verb ("Void bill", not "OK"). Where the API requires a reason, a required textarea (min 5 chars) is part of the dialog.
- **ManagerPinDialog:** 4–6 digit masked input, numeric keypad on touch, calls `POST /auth/override`; on success retries the original action with `X-Override-Token`; wrong PIN shows "Incorrect PIN" and clears the field; 5 wrong attempts → dialog locks for 30 s.
- **Toast:** top-right (top-center on mobile), max 3 stacked; success 4 s, info 5 s, error 8 s (pauses on hover) with optional action button ("Retry"); `aria-live="polite"` (errors `assertive`).
- **Badge:** status chips — soft background + `*-text` color + icon.
- **Table (data grid):** sticky header, sortable columns, zebra off, row hover `--surface-2`, empty/loading/error states built in, pagination footer, keyboard navigable rows.
- **Skeleton:** loading placeholders match final layout; never show a blank page or a lone spinner for > 300 ms.
- **EmptyState:** icon + one sentence + primary action. **ErrorState:** message + "Retry" + "Copy error ID" (the `traceId`).
- **Banner (persistent):** working offline / locked, GPS denied, day closed, print agent offline.

### 12.3 App structure & routes
> Part II adds the platform console, subscription, payment-account, delivery-charge and help routes — see Sections 18.10 and 22.5. Section 23 adds `/settings/whatsapp` (screen S15, Owner) and the public bill page `/b/:token` (screen S14, no login). Section 24 adds `/settings/devices` (S16) and `/sync/issues` (S17). Section 25 adds `/settings/coupons`, `/settings/price-rules`, `/settings/billing`, `/settings/central-menu`, `/shifts`, `/dues`, `/customers/:id/dues`, `/expo`, `/display` and makes `/kitchen` interactive (S18–S26).
```
/login                 /select-outlet        /change-password
/tables                (floor view)
/orders                (list)                /orders/:orderId   (POS order screen)
/bills                 (list + drawer)
/delivery              (board + map)
/kitchen               (interactive kitchen display, S24; Section 25.13)
/reports/daily  /reports/items  /reports/payments  /reports/discounts  /reports/voids
/day-close
/menu                  (categories + items)
/settings/outlet  /settings/taxes  /settings/tables  /settings/printers
/settings/users   /settings/riders /settings/notifications
/settings/devices  /sync/issues
/settings/coupons  /settings/price-rules  /settings/billing  /settings/central-menu
/settings/online-ordering (S35)  /online-orders (S36)  /online-orders/mapping (S37)  /payments/attention (S38)
/settings/compliance (S39: legal, registers, accounting, languages)  /settings/data (S40: export, requests, retention, audit, weekly e-mail)
/shifts  /dues  /customers/:id/dues  /expo
/display               (customer display: second window, no login beyond the POS session, read-only)
/rider                 (mobile page for RIDER role)
/track/:token          (public customer tracking page — no login)
/403  /404
```
Role landing after login: OWNER/MANAGER → `/reports/daily`; CASHIER/CAPTAIN → `/tables`; KITCHEN → `/kitchen`; RIDER → `/rider`. Routes are guarded by role; unauthorized → `/403`.

**App shell:** top bar 56 px: brand logo · outlet switcher (only if > 1 outlet) · business date + "Day open/closed" badge · connection indicator (green "Online" / red "Offline — actions disabled") · notification bell (failed prints, failed deliveries) · theme toggle · user menu (change password, set PIN, logout). Left nav: 72 px collapsed (icons + tooltips) / 240 px expanded; items filtered by role.

**Session handling:** access token in memory only (never localStorage); refresh via httpOnly cookie on app start and on 401 (single in-flight refresh; queue other requests). If refresh fails → "Session expired" modal with password re-entry that preserves current screen state; no data loss because order lines are saved on the server as they are added.

### 12.4 Screens

**S1 Login** — centered card 400 px: logo, **"Sign in as" selector (Platform admin · Restaurant admin · Staff — rules in Section 22.1)**, email, password (show/hide), "Sign in". Generic error "Email or password is incorrect". Locked: "Too many attempts. Try again in 15 minutes." Forced password change screen when `mustChangePassword`.

**S2 Tables (floor view)** — tabs per dining area; grid of table cards (min 128 × 96): name, status badge (icon + text), running total, minutes open, guest count.
| Status | Card style |
|---|---|
| FREE | surface bg, green border, check icon, "Free" |
| OCCUPIED | `--primary-soft` bg, orange border, utensils icon, total + minutes |
| BILL_PENDING | `--info-soft` bg, blue border, receipt icon, "Bill pending" + total |
Click FREE → small dialog "Guests (optional)" → creates order → opens `/orders/:id`. Click occupied → opens its order. Top-right buttons: **+ Takeaway**, **+ Delivery**. Legend at the bottom. Live-updates via SSE; no manual refresh needed (a refresh icon exists anyway).

**S3 Order screen (POS)**
```
┌ T4 · Order #37 · 3 guests ───────────────────── [Transfer] [Merge] [Cancel order] ┐
│ Categories │ [ 🔍 Search name or code…  ]        │ ORDER                         │
│ ▸ Starters │ ┌────────┐┌────────┐┌────────┐      │ ■ Paneer Tikka  2   200.00 🔒 │
│   Mains    │ │■ Paneer││■ Chilli││■ Spring│      │    + Extra spicy               │
│   Breads   │ │ Tikka  ││ Paneer ││ Rolls  │      │ ■ Butter Naan   4   160.00 🔒 │
│   Drinks   │ │ 100.00 ││ 140.00 ││  90.00 │      │ ─── not sent to kitchen ───   │
│            │ └────────┘└────────┘└────────┘      │ ■ Dal Fry   [−] 1 [+] 180 🗑 │
│            │ ┌────────┐ (unavailable = greyed)    │ Subtotal            540.00    │
│            │ │…       │                           │ [ Send KOT (F4) · 1 ] [ Bill (F8) ]
└────────────┴─────────────────────────────────────┴───────────────────────────────┘
```
Behavior:
1. Item card: food-type marker (square + dot), name, price. Unavailable items are greyed with an "Unavailable" label and are not clickable.
2. Tap item: if the item has variants or required modifier groups → **Customize** modal (radio/checkbox groups honoring min/max, quantity stepper, notes); else adds one draft line immediately. Tapping an item that already exists as a draft line with identical options and notes increments its quantity. Each add is an immediate `POST` (optimistic UI with rollback + toast on failure) — **the server order is the single source of truth; there is no local-only cart**.
3. Draft lines: stepper `− qty +`, delete icon. Sent lines: lock icon; "Cancel item" opens ManagerPinDialog + reason, then `POST …/cancel`.
4. Search: matches name or `short_code`, debounced 150 ms; `Enter` adds the first result when the query exactly equals a short code.
5. **Send KOT** (disabled when no drafts, shows draft count): one click → button loading → success toast "KOT #14 sent" → draft lines become sent. Network error → red toast "Couldn't send KOT — Retry"; the same `Idempotency-Key` is reused on retry so no duplicate KOT can be created.
6. **Bill** (disabled when no active lines): opens the bill dialog (S4). Totals area calls `POST /bills/preview` (debounced 300 ms) and shows the server numbers; skeleton while loading, inline error + Retry on failure. **The frontend never computes totals.**
7. Header actions: Transfer (table picker showing FREE tables only), Merge (picker of other OPEN orders), Cancel order (reason; PIN if KOT sent).

**S4 Bill & payment dialog (lg)**
- *Step 1 Review:* line table (name, qty, rate, amount), discount control (None / Percent / Amount + required reason; exceeding the cashier limit triggers ManagerPinDialog), customer name/phone (optional), totals from preview (subtotal, discount, service charge, per-component tax, round-off, **grand total** in 3xl). Buttons: **Generate bill** (creates bill, `Idempotency-Key`), Cancel.
- *Step 2 Pay* (after generation; the dialog shows bill number): large **Balance due**; tabs **Cash | UPI | Card | Other**.
  - Cash: "Amount received" input (+ "Exact" chip); change shown in large text (UI convenience only; server returns the authoritative `changeAmount`).
  - UPI: segmented control **Own QR (manual) | Gateway QR (automatic)** when a gateway is configured (27.B.10); QR (from `qrPayload`), amount, expiry countdown, button **Payment received** with helper text "Confirm only after your bank/UPI app shows the credit." (manual mode) — or "Waiting for payment…" spinner (provider mode).
  - Card: reference field (last 4 digits / slip no.), **Record card payment**.
  - Partial payments allowed: payments list with status badges; balance updates; **Add another payment**. "Split equally" helper divides by N people and pre-fills each amount (last one takes remainder cents).
- *Step 3 Done:* ✔ "Paid", buttons **Print bill**, **New order**/**Back to tables**; if "Auto-print on payment" setting is on, the bill prints automatically and a toast confirms.
- Closing the dialog before paying keeps the bill `GENERATED`; the table shows BILL_PENDING; reopening resumes at Step 2.
- Split by items: "Split bill" link in Step 1 → select items → creates one bill per group.

**S5 Orders list** — tabs: Open · Billed · Paid today · Cancelled; columns: #, type, table/customer, items, amount, status, opened by, time; search by order # or phone.

**S6 Bills list** — filters (status, date range, bill number); row click → drawer with lines, payments, **Reprint**, **Void** (role-gated; reason dialog), and an *Audit* tab.

**S7 Delivery board** (`/delivery`) — columns: PLACED · PREPARING · READY · ASSIGNED · PICKED_UP · DONE (today). Card: order #, customer, truncated address, rider, ETA, age timer (turns warning > 30 min, danger > 45 min — constants in one file). Card actions are buttons (accessible), not drag-and-drop: "Start preparing", "Mark ready", "Assign rider", "Cancel". *Assign rider* dialog lists `AVAILABLE` riders. Right pane: map with all active deliveries (rider markers + destination pins); selecting a card focuses the map. New delivery order: reuse S3 with a customer panel — phone lookup (found → pick saved address; not found → create), address text (required), optional map pin picker (click to set coordinates).

**S8 Kitchen view** (`/kitchen`, Phase 2; superseded by S24 from Phase 1B) — read-only columns of active KOT cards by station with item list + notes; card age color: < 10 min neutral, 10–20 warning, > 20 danger (constants). Auto-updates via SSE.

**S9 Rider page** (`/rider`, mobile-first) — header: name + toggle Available/Offline. Active delivery card: customer name, address, **Navigate** (`geo:lat,lng` link, falls back to showing the address text), **Call customer** (`tel:`), big buttons **Picked up** → **Delivered** and **Couldn't deliver** (reason list: Customer unreachable / Wrong address / Customer refused / Other + note). Location sharing starts automatically when a delivery is `ASSIGNED`/`PICKED_UP` (`watchPosition`, send every ~5 s, batch ≤ 10). Banners: GPS permission denied (with how-to), weak signal (accuracy > 200 m), offline, "Keep this screen open while delivering". Wake Lock requested where supported.

**S10 Public tracking page** (`/track/:token`, no login, mobile-first) — outlet name; status stepper (Order placed → Preparing → On the way → Delivered); map shown only while `PICKED_UP`; text "Arriving in about N min"; rider first name; **Call restaurant** button. States: invalid/expired token → friendly "This tracking link is no longer active"; delivered → success message; cancelled/failed → apology + restaurant phone.

**S11 Reports** — filter bar (date/range/outlet), KPI cards (bills, net sales, discounts, tax, grand total), tables, Recharts bar chart for hourly sales, **Export CSV**.

**S12 Day close wizard** — Step 1 readiness checks (open orders, pending UPI payments; open shifts with a 'Close shift' link — a manager may close a shift on the cashier's behalf with a count and a note; each with a link to fix). Step 2 cash: opening cash, counted cash, expected (server), variance (red if ≠ 0). Step 3 confirm → **Close day & email summary** → success with "Resend email". After close a persistent banner shows "Day closed"; billing is blocked (`DAY_CLOSED`).

**S13 Settings**
- *Outlet:* all outlet fields; **live bill preview** beside the form (renders the real `print-doc` HTML with sample data).
- *Taxes:* profiles with components (name + rate); inline validation (0–100).
- *Menu* (`/menu`): categories on the left (reorder with up/down buttons), items table on the right (search, availability toggle), item editor drawer (name, short code, price, tax profile, food type, station, variants, modifier groups); **CSV import**: upload → preview rows → per-row errors listed → confirm.
- *Tables & areas*, *Printers & agents* (add printer, **Test print**, agent online/offline badge, one-time token display with copy button), *Users & roles*, *Riders*.
- *Notifications:* customer channel priority (drag handle + up/down buttons), toggles for each delivery event, EOD email enable/time/recipients, **Send test email**.
- *Devices & offline:* tab → S16 (Section 24.11).

**S16 Devices & Sync** and **S17 Sync issues** — see Section 24.11.

**Section 25 screens (full text in 25.19):** S18 Coupons · S19 Price rules · S20 Combo editor (in the menu screen S13) · S21 Shifts & cash · S22 Customer dues · S23 Refund / credit note dialog · S24 Kitchen display (+ S24b Expo; replaces the read-only S8) · S25 Central menu · S26 Billing settings. S3/S4 additions: barcode scan, Open item, combo tile, price-rule chip, tip buttons, On account, NC, Customer display button. S8: superseded by S24.

**Section 26 screens (full text in 26.12):** S27 Stock list · S28 Stock item detail & ledger · S29 Recipe editor (live cost) · S30 Purchasing (PO, GRN, returns, vendors, payables) · S31 Wastage quick entry · S32 Stock count · S33 Transfers & production · S34 Inventory reports & alerts. Settings gets an *Inventory* page. Section 12.2 applies to all.

**Stream D screens:** S35 Online ordering settings · S36 Online orders inbox · S37 Mapping needed & reconciliation · S38 Payments needing attention & settlements · S39 Compliance & exports · S40 Data & privacy (specs in 27.A.12, 27.B.10, 28.B.6, 28.E.2).

### 12.5 Keyboard shortcuts (POS screens)
| Key | Action |
|---|---|
| `/` | Focus item search |
| `F2` | New takeaway order |
| `F4` | Send KOT |
| `F8` | Open bill dialog |
| `F9` | Focus payment amount |
| `Esc` | Close dialog / clear search |
| `B` / Space (KDS) | Bump selected ticket |
| `R` (KDS) | Recall |
| arrows (KDS) | Select ticket |
| scanner Enter (POS) | Barcode scan handling (Section 25.14) |
Shortcuts are listed in a "Keyboard shortcuts" help dialog (`?`). They are disabled while typing in a text field except `Esc`.

### 12.6 Cross-screen UI rules
- Every data view has **loading (skeleton), empty, error** states; every mutation has **pending, success, failure** feedback.
- Never trust the client for money: display server values only; use `decimal.js` for UI-only conveniences (change due, equal-split suggestion).
- Currency formatting via `Intl.NumberFormat` with the outlet's `currency_code`; dates in outlet timezone via `date-fns-tz`.
- All user-visible strings go through `t()`; languages `en` and `hi`; missing key → English, never blank; money and counts on screen use Indian grouping `1,00,000.00` via `inrGroup()`; the user's UI language and the outlet's bill language are separate settings (28.C).
- Accessibility target: WCAG 2.1 AA — visible focus rings, labels for all inputs, `aria-live` for toasts, dialog roles, 44 px touch targets, no color-only signals.
- **Offline:** registered terminals keep working without the internet (Section 24). Connection states: Online / Working offline (amber) / Syncing (blue) / Sync problem (amber) / Locked (red). Unsynced work is shown as a queue badge; sign-out is blocked while it is not empty. Online-only browsers (not registered) still show the red offline banner and disable mutating actions.
- Frontend folders: `src/features/<feature>/{api,components,hooks,pages}`; shared UI in `src/components/ui`; generated API types in `src/api/generated`; query keys in `src/api/queryKeys.ts`.

---

## 13. SECURITY

### 13.1 Authentication
- Login → access JWT (15 min, HS256, secret ≥ 32 random bytes from env) + opaque refresh token (7 days) in an `httpOnly; Secure; SameSite=Strict; Path=/api/v1/auth` cookie. Only the SHA-256 hash of the refresh token is stored.
- **Refresh rotation:** each refresh issues a new token and revokes the old one (`replaced_by`). Presenting an already-revoked token = theft signal → revoke the entire `family_id`.
- JWT claims: `sub` (user id), `tid` (tenant id), `role`, `outlets[]`, `iat`, `exp`, `jti`. The server re-checks the user is `ACTIVE` on refresh.
- Passwords: BCrypt strength 12; min 10 chars; no composition rules beyond a common-password blocklist; account lock after 5 failed logins (15 min).
- **Override PIN:** BCrypt-hashed; 5 wrong attempts → 30 s lock per user; override tokens are single-use, 120 s lifetime, bound to `(requesting user, outlet)`.
- Agent tokens and rider/public tokens: random ≥ 32 bytes, only hashes stored (except `tracking_token`, which is needed in the URL and is unguessable).

- **Platform users** are a separate table with their own login, refresh tokens and signing secret; 2FA (TOTP) is mandatory for platform users before production (Phase 4); platform logins have their own rate limit (5/min/IP).

### 13.2 Authorization
Role-based, enforced in the service layer with method security (`@PreAuthorize`) **and** tenant/outlet scoping in every query. Matrix in Appendix A. Test rule: for every endpoint, an automated test calls it as (a) an unauthenticated user → 401, (b) a role without permission → 403, (c) a user of another tenant → 404.

**Inventory data (Section 26):** cost and margin data is visible only to OWNER, MANAGER and INVENTORY. Vendor-invoice attachments: JPEG/PNG/PDF ≤ 5 MB, unguessable keys, signed URLs. The stock ledger is append-only (database trigger).

### 13.3 Hardening checklist
- Input validation on every DTO (size limits, ranges, enums); request body max 1 MB (CSV import 5 MB).
- SQL only through JPA/parameterized queries. No string-built SQL.
- XSS: React escaping only; **no `dangerouslySetInnerHTML`**; email/print templates HTML-escape variables. Strict CSP: `default-src 'self'; img-src 'self' data:; connect-src 'self' <map tile origin>; frame-ancestors 'none'`.
- Security headers via nginx/Spring: HSTS (prod), `X-Content-Type-Options`, `Referrer-Policy: same-origin`.
- CORS: only origins in `CORS_ALLOWED_ORIGINS`; no wildcards with credentials.
- CSRF: access token is sent in a header (not a cookie); the refresh endpoint requires `SameSite=Strict` cookie + `X-Requested-With` header.
- Rate limiting (Bucket4j/Redis) per Section 6.1. Webhook signature verification with constant-time comparison.
- Logs: structured JSON with `traceId`, `tenantId`, `userId`; **never** log passwords, tokens, PINs, full phone/email (mask to `98****21`).
- Secrets only via environment / K8s Secrets. `.env` files are git-ignored.
- Actuator: only `health/liveness` and `health/readiness` public (no details); the rest require OWNER or are disabled.
- Dependency scanning in CI (OWASP Dependency-Check, `npm audit`); Dependabot/Renovate weekly.
- Database backups (daily, 14-day retention, restore tested quarterly) — operations runbook in `docs/runbooks/backup.md`.
- Append-only tables (cash movements, customer ledger, credit notes + lines, coupon redemptions except ACTIVE→RELEASED) reject UPDATE/DELETE in the database. Manager PIN is required for NC, refunds by cashiers and credit-limit overrides; the approver is stored. Coupon validation is rate-limited (25.21).
- Offline terminals: device key (hashed server-side, revocable), pairing codes single-use/30 min, no manager PINs or secrets on terminals, loopback print endpoint token-protected (Sections 24.7–24.9, 24.14).
- **Provider/aggregator secrets and webhooks (Section 27–28):** provider/aggregator secrets are encrypted at rest, write-only through the API, never logged; public webhook routes verify signatures over the raw body with constant-time compare, enforce body-size and rate limits, and store nothing on a bad signature; exports exclude secrets and hashes, use signed time-limited URLs and neutralise CSV formula injection (28.E.3).

---

## 14. QUALITY STRATEGY ("minimum bugs" plan)

> No process can honestly *guarantee* zero bugs. This plan lowers risk by making money logic pure and heavily tested, making state transitions explicit, making retries safe (idempotency), and blocking merges that fail automated checks.

### 14.1 Test pyramid & gates
| Layer | Tooling | What must be covered |
|---|---|---|
| Unit | JUnit 5, AssertJ | `BillCalculator` (all vectors V1–V9 + invariants), numbering/fiscal-year, business-date, state machines, ESC/POS encoder (golden files), template rendering |
| Property-based | jqwik | Billing invariants (Section 5.3) over 10 000 random inputs, including inclusive/exclusive, odd quantities (3 dp), 0–100 % rates |
| Integration | Spring Boot Test + Testcontainers (Postgres 16, Redis) + GreenMail | Every repository query; every endpoint (happy path + validation + auth + tenant isolation); Flyway migrations from empty DB; outbox worker retry/backoff; webhook idempotency |
| Concurrency | Testcontainers | 100 parallel bill generations → unique, gapless numbers; two cashiers paying the same bill simultaneously → no overpayment; double-submit with the same Idempotency-Key → one bill |
| Architecture | ArchUnit | Layering and module-boundary rules (Section 3.2), no cycles |
| Contract | OpenAPI diff in CI | Fails the build on breaking API changes; TS client regenerated and compiled |
| Frontend unit/component | Vitest + Testing Library + MSW | Components, hooks, form validation, every state (loading/empty/error) |
| End-to-end | Playwright (Chromium + WebKit, tablet 1024×768 and phone 390×844 viewports) | Scenarios in 14.2; `@axe-core/playwright` accessibility checks on every page |
| Static analysis | SpotBugs, Checkstyle/Spotless, ESLint (strict), `tsc --noEmit` | Zero warnings policy |
| Security | Dependency scan, ZAP baseline scan against compose stack | No high/critical findings |

Everyday billing gates (Section 25): reference tests BX01–BX91 (`reference/test_bx.py`) pass as Java tests on the same vectors; V013's 231 DB cases pass; concurrency tests for coupons and refunds (25.23).

Inventory gate (Section 26): IN1–IN22 + P1–P8 pass in Java; V014's 217 DB cases pass; the no-divergence query returns zero rows; a fault-injection test proves a failing consumption never blocks a payment.

Stream D gates (Sections 27–28): the register reconciliation test (`reference/registers.py` property test) and the resolver property tests (`reference/payment_intent.py`) are release-blocking.

The golden-vector JSON is loaded by Java, Vitest and Node tests; a calculator change that alters any expected value fails all three.

**Coverage gates (CI fails below):** `billing` and `payments` modules ≥ 95 % line + branch; other backend modules ≥ 80 %; frontend ≥ 80 % for `features/` and `components/ui`.

### 14.2 Required E2E scenarios
1. Login (valid / invalid / locked), role landing pages, role-restricted routes → 403.
2. Dine-in: open table → add items → send KOT → add more → send second KOT → generate bill → pay cash with change → paid → print.
3. Takeaway with percent discount above cashier limit → PIN dialog → success; wrong PIN → error.
4. Cancel item after KOT requires PIN + reason; audit log entry exists.
5. Split bill by items → two bills, both paid → order PAID.
6. Equal split: three payments summing to total → PAID; fourth payment rejected.
7. Void unpaid bill (manager) → order reopens; void paid bill (owner only).
8. UPI manual: QR shown with correct amount; "Payment received" → PAID; expired QR → cannot confirm.
9. Table transfer and merge.
10. Delivery: create → prepare → ready → assign → rider page shows it → pick up → location points streamed → customer tracking page shows moving marker → arriving notification enqueued → delivered. Tracking link returns 410 after expiry.
11. Day close: blocked by open order; close with cash variance; EOD email received (GreenMail); reopen as owner.
12. Offline: network down → red banner, actions disabled; network back → recovers without reload.
13. Double-click on every "submit" button creates exactly one record.
14. Cross-tenant URL guessing returns 404 everywhere.
15. Super admin onboards a restaurant → temporary password shown once → Restaurant Admin logs in, is forced to change it, lands in a usable app.
16. Trial: 30-day countdown banner; reminder emails at T-7/3/1/0 (test clock); at trial end → PAST_DUE banner; after grace → read-only (new order → `402 SUBSCRIPTION_INACTIVE`, existing bill can still be paid and printed); extend trial → TRIALING again.
17. Invoice issued → super admin records payment (double submit with one Idempotency-Key = one payment) → subscription advances without gap; yearly vs monthly price shown; reactivation after suspension re-anchors.
18. Plan limits: Restaurant Admin cannot create a 3rd cashier on a plan with `CASHIER:2` (`PLAN_LIMIT_ROLE`) or exceed `max_users`; disabling a user frees a slot; downgrade blocked while over limits.
19. Disabling a user invalidates their live session within 1 s; deactivating a restaurant blocks all its logins; last Owner cannot be disabled.
20. Restaurant raises a ticket (diagnostics attached) → platform replies and adds an internal note → restaurant never sees the note → restaurant closes; feedback prompt appears once near trial end.
21. Delivery order beyond the radius → blocked; inside slab → correct charge on bill; free-above waives it; manager override with PIN + reason; split bill carries the charge once; partner order shows partner name and reference.
22. Restaurant Admin uploads a QR image → ID extracted and confirmed → cashier sees QR with the locked amount → presses Payment received; non-admin cannot add accounts; change e-mail is queued.
23. Role selector: wrong selection shows the mismatch message and logs out; choosing a higher role than the account has grants nothing.
24. Resilience: every route with the API returning 500 / timing out / offline shows a heading, skeleton or ErrorState — never an empty body — and no uncaught console error.
25. WhatsApp automatic send, status chips, resend, STOP opt-out (Section 23.14).
26. WhatsApp failure (number not on WhatsApp) → fallbacks → manual `wa.me` share → public bill page and expired-link page (Section 23.14).
27. No WhatsApp account / plan without `whatsapp_bills` → only manual share offered; API mode returns `402 FEATURE_NOT_IN_PLAN` (Section 23.14).
28. Offline service end to end (KOT, bill, cash, print, reconnect, no duplicates).
29. Two terminals, same table offline → TABLE_CONFLICT → merge.
30. Bill-number gaps: out-of-order arrival fills/splits gaps; storage loss → re-pair → STORAGE_LOST gap → Owner explains.
31. Offline session expiry → Locked + export; clock set back → locked; deactivated user's bill accepted + flagged.
32. Server/terminal total mismatch → accepted as issued + CALC_MISMATCH CRITICAL.
33. Offline blocked actions and reasons; queued WhatsApp bill sent after sync with consent; revoked terminal final sync; late bill for closed day.
51. Auto-accept happy path (Section 27.A.14).
52. Unmapped item.
53. SLA expiry, reject, provider cancel.
54. Gateway auto-confirmation including duplicate / late / mismatch (27.B.12).
55. Reconciliation (partner and settlements).
56. Legal fields and bill snapshot (28.E.5).
57. Registers reconcile.
58. Accounting exports and Tally.
59. Hindi UI and bill.
60. Data management.
(Full texts of 51–60: 27.A.14, 27.B.12 and 28.E.5; numbers 34–50 belong to Sections 25–26.)

### 14.3 Definition of Done (every task)
- [ ] Acceptance criteria met and demonstrated by an automated test.
- [ ] Unit + integration tests added; coverage gates green.
- [ ] OpenAPI updated; TS client regenerated.
- [ ] Loading / empty / error / disabled states implemented and tested.
- [ ] Audit log written for sensitive actions.
- [ ] Authorization tests (401/403/404-tenant) added.
- [ ] No TODO/FIXME without a linked entry in `docs/OPEN_QUESTIONS.md`.
- [ ] Lint, type-check, static analysis: zero warnings.
- [ ] Accessibility (axe) clean on new screens.
- [ ] Docs/README/ADR updated if a decision was made.

### 14.4 Performance targets (verified with a k6 script, single backend instance, 2 vCPU/2 GB)
| Operation | p95 target at 50 concurrent users |
|---|---|
| `GET /catalog/pos` (cached, ETag) | < 150 ms |
| Add order item | < 200 ms |
| Bill preview | < 250 ms |
| Generate bill | < 400 ms |
| Floor view | < 250 ms |
Database: indexes per Section 4; no N+1 queries (verified by a Hibernate statistics assertion in tests of list endpoints).

---

## 15. DEPLOYMENT & OPERATIONS

### 15.1 Containers
- **backend/Dockerfile:** multi-stage (Maven build on `maven:3-eclipse-temurin-21` → run on `eclipse-temurin:21-jre`), non-root user, `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=75`, healthcheck on `/actuator/health/readiness`.
- **frontend/Dockerfile:** build with Node LTS → serve with nginx (SPA fallback to `index.html`, gzip, long cache for hashed assets, `no-cache` for `index.html`, security headers).
- **deploy/docker-compose.yml:** `postgres:16`, `redis:7`, `mailpit` (dev SMTP catcher), `backend`, `frontend`. One command: `docker compose up --build`.

### 15.2 Configuration (environment variables)
| Variable | Purpose |
|---|---|
| `DB_URL`, `DB_USER`, `DB_PASSWORD` | PostgreSQL |
| `REDIS_HOST`, `REDIS_PORT` | Redis |
| `JWT_SECRET` | ≥ 32 bytes random |
| `JWT_ACCESS_TTL` (default `PT15M`), `REFRESH_TTL` (default `P7D`) | token lifetimes |
| `PUBLIC_BASE_URL` | used in tracking links and emails |
| `CORS_ALLOWED_ORIGINS` | comma-separated |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `MAIL_FROM` | email |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` | web push (optional) |
| `PAYMENT_WEBHOOK_SECRET_<PROVIDER>` | webhook signature secrets |
| `SPRING_AI_*` | LLM provider settings (chosen later) |
| `PLATFORM_JWT_SECRET` | signing secret for platform tokens (≠ `JWT_SECRET`) |
| `TOTP_ENCRYPTION_KEY` | encrypts platform users' TOTP secrets |
| `STORAGE_ENDPOINT`, `STORAGE_BUCKET`, `STORAGE_ACCESS_KEY`, `STORAGE_SECRET_KEY` | object storage for QR images |
| `WHATSAPP_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_TOKEN_ENCRYPTION_KEY`, `WHATSAPP_GRAPH_BASE_URL`, `WHATSAPP_API_VERSION` | WhatsApp (Section 23.13) |
| `SYNC_MAX_BATCH` (default 50) | max commands per `/sync/push` |
| `DEVICE_PAIRING_TTL` (default `PT30M`) | pairing-code lifetime |
| `OFFLINE_REVOKED_SYNC_DAYS` (default 7) | final-sync window for revoked terminals |
| `SYNC_SCHEMA_VERSION` | current command schema version (previous one also accepted) |
| `SYNC_CLOCK_SKEW_SECONDS` (default 900) | skew above this raises CLOCK_SKEW |
| `VITE_OFFLINE_DEFAULT_MAX_HOURS` | UI default shown before the outlet setting loads |
| `COUPON_VALIDATE_RATE_PER_MIN` (default 20) | coupon validations per user per minute |
| `KDS_RECALL_HISTORY` (default 10) | last bumped tickets that can be recalled |
| `BARCODE_SCAN_MAX_GAP_MS` (default 35) | keyboard-wedge burst gap (frontend config, not verified on real scanners) |
| `BARCODE_MIN_LENGTH` (default 4) | minimum scanned code length |
| `CREDIT_AGING_BUCKETS` (default `30,60,90`) | days |
| `INVENTORY_CONSUMPTION_RETRY_SECONDS` | default 300; retry of failed consumptions |
| `INVENTORY_LOW_STOCK_CRON` | default `0 7 * * *` outlet time; daily low-stock mail |
| `INVENTORY_ATTACHMENT_MAX_BYTES` | default 5242880 (matches the DB CHECK; do not raise without a migration) |
| `INTEGRATION_ENCRYPTION_KEY` | base64 32-byte key for aggregator credentials (AES-GCM); rotation = re-encrypt on write |
| `PAYMENT_PROVIDER_ENCRYPTION_KEY` | same, for gateway credentials |
| `WEBHOOK_MAX_BODY_BYTES` | default 262144 |
| `INTENT_DEFAULT_EXPIRY_MINUTES` | default 10 (placeholder; provider-specific limits come from its docs) |
| `EXPORT_STORAGE_BUCKET`, `EXPORT_LINK_TTL_MINUTES` | where export files live and download-link lifetime (default 15) |
| `RETENTION_JOB_CRON` | default `0 30 2 * * *` (outlet-independent, server time) |
| `FONT_DIR` | directory of bundled fonts for raster bills |
| `APP_BRAND_NAME` | brand name (default `Galla`) |
| `VITE_API_BASE_URL`, `VITE_MAP_STYLE_URL`, `VITE_BRAND_NAME` | frontend build-time |

Frontend `VITE_*`: none else (besides the offline default above). Print agent: `--loopback-port 9171`.

### 15.3 Kubernetes (`deploy/k8s`)
Namespace; `Deployment` backend (2 replicas, readiness `/actuator/health/readiness`, liveness `/actuator/health/liveness`, requests 500m CPU/768Mi, limits 1 CPU/1Gi) and frontend (2 replicas); `Service`s; `Ingress` with TLS (host-based; SSE needs proxy read timeout ≥ 3600 s and buffering off: `proxy_buffering off`); `ConfigMap` (non-secret config); `Secret` (credentials); `HorizontalPodAutoscaler` (CPU 70 %, 2–6 pods); `PodDisruptionBudget` (minAvailable 1). PostgreSQL and Redis: **managed services recommended**; the plan does not run databases as StatefulSets. Flyway runs at application start (it uses a DB lock so concurrent replicas are safe).
Because SSE streams are in-memory per pod, cross-pod delivery goes through Redis pub/sub (Section 7) — no sticky sessions needed.

### 15.4 CI pipeline (example: GitHub Actions; any CI works)
1. Backend: `mvn verify` (unit + integration with Testcontainers + coverage gates + SpotBugs + Checkstyle).
2. Frontend: `npm ci`, lint, `tsc`, Vitest with coverage gates, build.
3. Contract: start backend → export OpenAPI → diff vs. committed spec → regenerate TS client → compile.
4. E2E: `docker compose up -d` → Playwright suite (+ axe).
5. Security: dependency scans + ZAP baseline.
6. Build/push images on `main`; deploy to staging; manual approval for production.

### 15.5 Observability
Micrometer metrics → Prometheus: HTTP latency/error rate, outbox queue depth, failed notifications, print job failures, SSE connected clients, rider-location ingest rate, DB pool usage. Alerts: error rate > 2 %, outbox oldest pending > 10 min, print failures > 5 in 10 min, readiness failing. Logs: JSON with `traceId` propagated from the `X-Request-Id` header; the UI shows `traceId` in error states. Stream D adds metrics `inbox_received_total`, `inbox_expired_total`, `webhook_signature_invalid_total{kind}`, `payment_attention_open`, `export_jobs_failed_total`, `backup_age_hours`; alerts for backup age > 26 h and 10 consecutive webhook signature failures.

---

## 16. BUILD ORDER — PHASES, TASKS, ACCEPTANCE CRITERIA

Build order: 0 → 1 → 1B → 1S/2 → 2W/2O/… (Phase 1B = everyday billing, Section 25.25; it may start as soon as Phase 1 is accepted).

### Phase 0 — Foundation (≈ 1 week)
**Tasks:** monorepo scaffold; Maven + Vite projects; Docker Compose; Flyway V001–V017 (all verified SQL is in `migrations/`); `shared` module (Money utils, error model/RFC 7807, `TenantContext`, idempotency filter, audit service, time/business-date utils); Spring Security skeleton; OpenAPI export + TS client generation; design tokens + base UI components (Section 12.2) with component tests; CI pipeline with all gates; dev seed data.
**Accept when:** `docker compose up` brings the stack up; migrations apply to an empty DB; health endpoints green; CI runs and fails when coverage/lint thresholds are violated; ArchUnit tests exist and pass; a sample protected endpoint passes 401/403/404-tenant tests.

### Phase 1 — Core billing MVP (≈ 4–5 weeks)
**Tasks (in order):** identity (login, refresh rotation, logout, override PIN, users CRUD) → outlets & settings → tax profiles → catalog (categories, items, variants, modifiers, stations, CSV import, `/catalog/pos` with ETag) → floor (areas, tables, floor view) → ordering (create, items, KOT with counters, cancel item, transfer, merge, cancel) → **`BillCalculator` with all vectors and property tests first (plus `golden_bill_vectors.json` and the Java/TypeScript contract tests, so Phase 2O only adds the offline layer)**, then billing (preview, generate with numbering, split by items, void) → payments (cash, card manual, partial, equal split) → frontend screens S1, S2, S3, S4, S5, S6, S13 (outlet, taxes, menu, tables, users).
**Accept when:** E2E scenarios 1–7, 9, 13, 14 pass; all vectors V1–V11 pass; concurrency tests pass; coverage gates green; a cashier can complete a dine-in order from login to paid bill in ≤ 12 clicks; browser-print of the bill works.

### Phase 1B — Everyday billing (≈ 4–5 weeks; after Phase 1, before Phase 2)
**Tasks and acceptance:** text of Section 25.25. **Accept when:** BX01–BX91 pass as Java tests, V013's 231 cases pass, E2E 34–44 pass.

### Phase 1S — Platform, subscriptions, support (≈ 3 weeks; can run in parallel with Phase 2 by a second developer)
**Tasks:** platform auth (separate tokens) → plans → tenant onboarding → `PlanLimitService` + feature gates → subscription lifecycle + hourly job + `@RequiresActiveSubscription` (+ ArchUnit rule) → invoices and manual payment recording → trial/billing notifications → restaurant Subscription page and Users page with limits → platform console P0–P10 → feedback and tickets → support-view grants → user/restaurant deactivation with instant revocation → login role selector → global ErrorBoundary and resilience tests.
**Accept when:** E2E scenarios 15–20, 23, 24 pass; subscription vectors S1–S12 pass as Java tests; ArchUnit proves every mutating ordering/billing/delivery endpoint is guarded; a platform token is rejected on tenant endpoints and the reverse; internal ticket notes never appear in tenant responses.

### Phase 2 — Printing, UPI, reports, day close (≈ 3 weeks)
**Tasks:** `PrintDocument` + HTML renderer + ESC/POS encoder (golden tests) → printers/agents settings → print agent app + protocol → KOT auto-print per station → payment accounts (own UPI ID / QR upload, Section 21) + UPI manual QR (Mode A) → pending/expired handling → reports (daily, items, payments, discounts, voids, hourly, CSV) → day close wizard + `day_closings` + reopen → notification outbox + email channel + **EOD email** (on close + provisional safety net) → kitchen view S8. Stream D: legal & invoice fields, bill snapshot, HSN field, `inrGroup`, i18n framework with `en`/`hi` (28.A, 28.C.2).
**Accept when:** E2E scenarios 8, 11, 22 pass; golden ESC/POS files match; agent prints to a real or emulated (TCP listener) printer; failed print shows retry; EOD email arrives in the test SMTP inbox with correct numbers equal to the reports; email is sent exactly once per close (dedupe test).

### Phase 2R — Registers & exports (≈ 2 weeks; after Phase 2; credit-note and purchase registers wait for their modules)
**Tasks:** 28.B registers and accounting exports (generic CSVs, Tally XML best effort) and Hindi raster bills (28.C.3).
**Accept when:** IG-R/T/I tests pass; E2E 57–59 pass.

### Phase 2O — Offline mode (≈ 4 weeks; after Phase 2 printing; the riskiest phase — do not start before Phases 1 and 2 are accepted; full text Section 24.16)
**Tasks:** V012 → devices (pairing, series, revoke) → golden vectors in Java and TypeScript (`billCalculator.ts`) → Dexie stores, snapshot/pull → service worker (PWA, update-after-queue rule) → command outbox + `/sync/push` with idempotency, dependency wait, protocol-only rejections → bill-number gap service → conflict classification and S17 → heartbeat → offline session/lock/quick-PIN → loopback print mode in the agent → offline UI states and disabled-action tooltips → day-close readiness additions → emergency export → E2E 28–33 and `docs/OFFLINE_GO_LIVE.md`.
**Accept when:** golden vectors pass in JS, TS and Java; OF1–OF20 pass as Java tests; E2E 28–33 pass; no scenario loses or duplicates a bill; manual go-live checklist done on real hardware.

### Phase 2W — WhatsApp bills (≈ 2 weeks; after Phase 2 printing, because it reuses `PrintDocument`; can overlap Phase 3)
**Tasks:** V011 → phone normalisation + consent service (port `reference/whatsapp.py`) → public bill links + page S14 → manual wa.me share (Mode B) → WhatsApp account settings S15 (encrypt token, verify, create template) → webhook endpoint (signature, idempotent events) → PDF rendering → outbox sender with status merge, failure classification, retries → Bill dialog panel and Bills drawer resend → usage report → delivery-update templates (optional, after Phase 3) → `docs/WHATSAPP_GO_LIVE.md`.
**Accept when:** vectors W1–W12 pass as Java tests; E2E 25–27 pass against the fake Meta server; the token never appears in any response/log; webhook replay is idempotent; invalid signature is rejected; manual go-live checklist done with 3 real phones (one not on WhatsApp).

### Phase 3 — Delivery & map tracking (≈ 3 weeks)
**Tasks:** customers & addresses → delivery entity + state machine + history → delivery charges, partner orders and partner riders (Section 20) → riders + assignment → delivery board (S7) → rider page (S9) with location ingestion → SSE + Redis fan-out → public tracking page (S10) with MapLibre → geofence + ETA (Haversine) → delivery notifications (outbox triggers; WhatsApp/SMS stubs fail visibly; email works) → retention job.
**Accept when:** E2E scenarios 10 and 21 pass; delivery-charge vectors D1–D10 pass as Java tests; illegal transitions rejected with 409; rider can't post locations for other riders' deliveries (403); tracking link expiry works (410); arriving notification fires once; location ingest drops invalid points; map shows smooth marker movement.

### Phase 4 — AI summary, hardening, deployment (≈ 2 weeks)
**Tasks:** Spring AI daily summary with the number-guard (Section 10.5); provider-based UPI webhook flow (Mode B) for the chosen gateway; rate limits; security headers/CSP; k6 performance run vs. targets; Kubernetes manifests + staging deployment; runbooks (backup/restore, incident); accessibility pass; final regression of all E2E scenarios. Stream D: 27.B gateway Mode B (after Open Decision 51), 28.D data management (after Decisions 54–56 for numbers/wording).
**Accept when:** AI text is discarded when it contains a number not in the input (unit test with a fake model); performance targets met; ZAP baseline clean; staging deployment passes smoke tests; all Definition-of-Done items true for every task. Stream D acceptance: E2E 54, 60.

### Phase 5 — Final-audit features (Section 30.10) and later items
**Build (≈ 2 weeks, after launch):** V017 → reports RP1–RP9 and the reconciliation gate → payment-mode labels → loyalty → reservations → token numbers and ready display → E2E 61–66 (details and acceptance in 30.10).

**Later (not part of this plan's build):**
On-premise LAN relay for multi-terminal offline, marketing campaigns, road-routing ETA, native rider wrapper for background tracking, further UI languages beyond en/hi.

### Phase 5I — Inventory, recipes & purchasing (≈ 6–7 weeks; after Phase 4 and the billing-extras stream; behind feature flag `inventory`; full text Section 26.17)
**Tasks:** V014 → units, items, levels and the ledger service (with the P1 check in CI) → costing engine ported from `ref/inventory.py` → recipes (versions, live cost) → consumption on bill paid (savepoint, retry) and reversal on void/credit note → vendors, PO, GRN with attachment, duplicate guard → payables and aging → wastage, adjustments (PIN threshold) → counts, transfers, production → reports and alerts → EOD `inventory` and e-mail block → CSV import → S27–S34 → permission rows and audit.
**Accept when:** IN1–IN22 and P1–P8 pass as Java tests; the 217 database cases pass; the no-divergence query returns zero rows after the E2E run; E2E 45–50 pass; a bill is never blocked by any inventory failure (fault-injection test).

### Phase 6 — Aggregator integration (≈ 3–4 weeks per adapter; GATED on written partner/middleware access; full text Section 27.C)
**Tasks:** 27.A framework + fake adapter first; one real adapter after onboarding; pilot on one outlet.
**Accept when:** IG-A/DB/API/WK tests pass; E2E 51–53 and 55 pass.

---

## 17. OPEN DECISIONS (do not block build; record answers in `docs/OPEN_QUESTIONS.md`)
1. Tax/GST compliance — see 52.
2. UPI payment gateway (Mode B) — see 51.
3. SMS provider for customer notifications (WhatsApp is designed in Section 23; see 17.17–17.19).
4. Map tile provider and (optionally) road-routing provider.
5. LLM provider for the daily AI summary.
6. Hosting target and managed Postgres/Redis choice.
7. Pricing/licensing model for Galla itself.
8. Whether outlets need a customer-facing display or QR self-ordering (out of scope now).
9. Self-signup for the free trial (v1 is invite-only by the super admin).
10. Tax on Galla's own subscription invoices — see 53.
11. Automated recurring collection of subscription fees (gateway not researched; v1 records payments manually).
12. Plan names, prices, limits and trial length (entered by the super admin; sample values only in dev seed).
13. Data retention / deletion after a restaurant cancels — see 54.
14. Owner data export on request and format — see 55.
15. Whether platform support staff (SUPPORT) will exist at launch.
16. Meaning of "revenue/delivery partner": this plan assumes partner **orders** and partner **riders** (Section 20.3) — confirm. Online aggregators are Section 27.A; manual partner orders remain 20.3.
17. **WhatsApp cost model:** v1 assumes each restaurant pays Meta directly through its own WhatsApp Business account; Meta's current India rates and free-window rules are **not verified**. Alternative: Galla resells messages (needs a billing meter and a Meta partner relationship).
18. **WhatsApp route:** direct Meta Cloud API with a restaurant-pasted token (v1, simplest) vs. becoming a Meta Tech Provider with **Embedded Signup** (restaurants connect with a login flow) vs. a business solution provider (BSP). Embedded Signup requirements were not researched here.
19. **Legal/privacy:** consent wording, DPDP Act duties for storing phone numbers, retention of consent records and webhook payloads (30 days is my default for payloads) — **not verified; check with a lawyer**.
20. **Domain and trademark for "Galla":** domain availability was **not checked** (the research tools in this environment could not reach registrars). Check `galla.in`, `galla.com`, `galla.app` and variants (`getgalla.in`, `gallapos.in`, `usegalla.com`, `gallabill.com`, `galla.co.in`) at a registrar, and search the IP India trademark database (Classes 9 and 42) before committing.
21. **Name:** "Galla" (Hindi/Urdu for a shop's cash box) was chosen by the product owner for the Indian market. Caveat: "Galla" is also a dated exonym for the Oromo people that some consider offensive — this matters if the product goes global; the name lives in config (`app.brand.name`) so it can change. Other software in this space uses similar-looking names — check for conflicts before launch.
22. **Multiple bill series (one per terminal):** whether the legal invoicing rules allow several parallel series in one outlet is **not verified**. Fallback: number-block lease per terminal (Section 24.4 point 1). Check with a tax professional before production.
23. **Offline limit:** default 72 hours (1–720, per outlet). Decide whether high-security outlets should disable offline (`offline_enabled = false`).
24. **LAN relay for multi-terminal offline** (shared state without internet) — later phase; not designed in detail.
25. **Local data encryption** on terminals (IndexedDB is not encrypted; option: key derived from the quick-PIN) — decide before handling sensitive customer data offline.
26. **Safety skip after storage loss** (default 10) and how the Owner documents gaps for audits.
27. **Offline approval of discounts above the cashier limit** (e.g. pre-issued one-time manager codes) — not in v1; today such actions are blocked offline.
28. **Browser/OS support matrix** for offline: IndexedDB eviction rules, `navigator.storage.persist()` behaviour, service-worker update behaviour, loopback calls from an HTTPS page (mixed-content / private-network rules) — **not verified**; test on the real devices of the first customers.
29. **PIN hashing parameters** (PBKDF2 iteration count) — follow current OWASP guidance at build time.
30. **Credit-note numbering:** separate gapless series `CN` (as built) vs. continuing the bill series — legal requirement **not verified**; ask a tax professional before production.
31. **NC bills and tax:** `ZERO_TAX` vs `TAX_ON_LIST_PRICE` — which treatment applies is **not verified**; per-outlet setting, the accountant decides.
32. **Tips:** taxability and reporting are **not verified**; the software keeps tips out of the tax base and out of the bill total.
33. **Coupons offline:** blocked offline (global limits need the server). Alternative later: per-terminal coupon quotas.
34. **Card/UPI refunds through a provider's API:** not built; the cashier refunds physically and records the reference.
35. **Coupon stacking, gift cards:** not in v1 (loyalty points are built in Section 30) (`stackable` column reserved, constrained to false).
36. **Cash tips in the drawer:** expected cash includes cash tips and cash dues settlements (as built); an outlet that keeps tips outside the drawer would need a switch — decide with the first customers.
37. **KDS hardware and sound policy:** which tablet/browser is the kitchen screen; sound autoplay differs per browser — **not verified**; manual test.
38. **Credit-note round-off:** partial notes round **down** to a whole rupee and the final note returns the remainder (as built); alternative: always exact paise. Legal view **not verified**.
39. **Central menu:** price rules and tax-profile mapping by name (as built) vs. publishing rules too; per-outlet price override is by `overridden_fields`.
40. **Costing method:** moving weighted average only (no FIFO). Confirm with the owner's accountant that this is acceptable for the books; stock valuation here is operational, **not** statutory — not verified.
41. **Negative stock:** default `ALLOW` with warning. Decide per customer whether `BLOCK_MANUAL` should be the default.
42. **Wastage approval threshold** default 500.00 (outlet currency) and who may approve (Manager only, or any user with the PIN).
43. **Expiry/batch tracking** is not in v1 — decide whether a later phase needs batches (FIFO/FEFO) for dairy/meat.
44. **Vendor GST:** recorded as printed on the invoice only. Whether and how to support input-tax-credit reporting is **not verified** and needs a tax professional; the plan assumes none.
45. **Freight and other charges** are not added to item cost in v1 (landed cost) — decide with early customers.
46. **Variant recipes:** default "same as item × factor"; confirm that portion factors cover real menus (Half/Full).
47. **Stock count discipline:** count before opening or after closing (26.9 limitation); decide whether to add stock-freeze or per-movement re-baselining.
48. **Combos and credit notes interface:** consumption interface to the billing-extras section (flat expanded line list; `(billLineId, fraction, creditNoteId)`) must be agreed with that section before build.
49. **Low-stock channel:** e-mail through the outbox only in v1; whether WhatsApp/push alerts are wanted.
50. **Aggregator route:** direct partner API per aggregator vs a middleware company; which providers first; partner/approval requirements, fees, deadlines — **not verified**; blocks Phase 6 only.
51. **UPI gateway provider for Mode B** (or none) — replaces old Decision 2.
52. **CA review of the compliance checklist (28.A.6)** before the first live outlet; which document title each outlet uses — absorbs old Decision 1 (its text about mandatory fields, e-invoicing, rates and HSN is now items 1–7 of the checklist).
53. **Tax on Galla's own subscription invoices** — rate, label, format (**not verified**) — renames old Decision 10 (unchanged content; checklist item 12).
54. **Retention numbers** (audit 730 d, payload 30/90 d, export files 7 d, post-cancel download 90 d, deletion 365 d are proposals) — replaces old Decision 13: the mechanism is built (28.D.3), only numbers/lawyer sign-off remain.
55. **Owner data export format** — replaces old Decision 14: answered by design — ZIP of CSV + JSON manifest, Owner only (28.D.1); reopen only if a customer asks for another format.
56. **DPDP duties:** consent wording, notice, request deadlines, who is data fiduciary for restaurant customers; Rules notified 14 Nov 2025 with an 18-month phased period, duty detail **not verified** — extends old Decision 19.
57. **Tally:** test the XML export with a real Tally company/version and a Tally-using accountant; GST-related tags — **not verified**.
58. **Languages:** native-speaker review of Hindi; next languages; Devanagari raster tested on the actual printers; font licences.
59. **Backup targets:** RPO ≤ 15 min / RTO ≤ 4 h are proposals; can the chosen hosting meet them; monthly restore-test owner — ties to Decision 6 (hosting).

---

## APPENDIX A — Permission matrix
| Capability | O | M | C | K | T | R |
|---|---|---|---|---|---|---|
| Manage outlets, assign users to outlets | ✔ | | | | | |
| Manage users (M cannot create OWNER) | ✔ | ✔ | | | | |
| Manage menu / taxes / tables / printers / riders / settings | ✔ | ✔ | | | | |
| Create/edit orders, add items, send KOT | ✔ | ✔ | ✔ | ✔ | | |
| Cancel item after KOT | 🔑 | 🔑 | 🔑 | 🔑 | | |
| Transfer / merge tables | ✔ | ✔ | transfer | | | |
| Generate bill | ✔ | ✔ | ✔ | | | |
| Discount ≤ cashier limit | ✔ | ✔ | ✔ | | | |
| Discount > cashier limit | ✔ | ✔ | 🔑 | | | |
| Record payments | ✔ | ✔ | ✔ | | | |
| Void unpaid bill | ✔ | ✔ | | | | |
| Void paid bill | ✔ | | | | | |
| View reports / audit log | ✔ | ✔ | | | | |
| Close day | ✔ | ✔ | | | | |
| Reopen day | ✔ | | | | | |
| Print bill/KOT | ✔ | ✔ | ✔ | ✔ | | |
| Kitchen view | ✔ | ✔ | | | ✔ | |
| Manage deliveries (assign, status) | ✔ | ✔ | ✔ | | | |
| Rider page, post location, rider statuses | | | | | | ✔ |
(🔑 = allowed with a valid manager override token; for O/M the override is implicit.)

## APPENDIX A2 — Part II permission matrix
| Capability | SUPER_ADMIN | SUPPORT | O | M | C | K | T | R | INVENTORY |
|---|---|---|---|---|---|---|---|---|---|
| Onboard / deactivate restaurants, manage plans, platform settings | ✔ | | | | | | | | |
| Record subscription payments, issue/void invoices | ✔ | | | | | | | | |
| View restaurants (read-only), tickets, feedback | ✔ | ✔ | | | | | | | |
| Reply to tickets, add internal notes | ✔ | ✔ | | | | | | | |
| Read-only support view of a restaurant | ✔ | ✔ (grant needed) | | | | | | | |
| Create / disable restaurant users (within plan limits) | ✔ | | ✔ | ✔ (not Owners) | | | | | |
| Choose / change plan, cancel subscription, grant support access | | | ✔ | | | | | | |
| View subscription & invoices | | | ✔ | ✔ | | | | | |
| Add / change payment accounts | | | ✔ | | | | | | |
| Use a payment account at checkout | | | ✔ | ✔ | ✔ | | | | |
| Delivery-charge settings | | | ✔ | ✔ | | | | | |
| Delivery-charge override | | | 🔑 | 🔑 | 🔑 | | | | |
| Send feedback, raise tickets | | | ✔ | ✔ | ✔ | ✔ | ✔ | | ✔ |
| Read menu, toggle item availability (INVENTORY keeps this next to the inventory rows below) | | | ✔ | ✔ | toggle | | | | ✔ |
| Connect / disconnect WhatsApp account, create template | | | ✔ | | | | | | |
| View WhatsApp status and usage report | | | ✔ | ✔ | | | | | |
| Send / resend bill on WhatsApp, create share link, record consent | | | ✔ | ✔ | ✔ | | | | |
| Revoke bill share links | | | ✔ | ✔ | | | | | |
| Register / re-pair / revoke terminals, offline settings | | | ✔ | | | | | | |
| View terminals, sync conflicts and number gaps | | | ✔ | ✔ | | | | | |
| Resolve sync conflicts | | | ✔ | ✔ | | | | | |
| Explain bill-number gaps | | | ✔ | | | | | | |
| Retry rejected sync commands | | | ✔ | | | | | | |
| Work offline on a registered terminal (create orders/bills/payments offline) | | | ✔ | ✔ | ✔ | | orders & KOT only | | |
| Export unsynced data from a terminal | | | ✔ | ✔ | ✔ | | ✔ | | |
| Manage coupons, price rules, combos | | | ✔ | ✔ | | | | | |
| Apply a coupon to a bill | | | ✔ | ✔ | ✔ | | | | |
| Add an open item | | | ✔ | ✔ (default) | Owner can grant per role | | Owner can grant | | |
| Configure billing settings, reason codes, role permissions, credit limits | | | ✔ | | | | | | |
| Complimentary (NC) bill | | | ✔ | ✔ | with manager PIN | | | | |
| Record a tip with a payment | | | ✔ | ✔ | ✔ | | | | |
| Open / close own shift, pay-in / pay-out / drop | | | ✔ | ✔ | ✔ | | | | |
| View all shifts and variances; close a shift for someone else | | | ✔ | ✔ | | | | | |
| Open the cash drawer without a sale | | | ✔ | ✔ | ✔ | | | | |
| Accept ON_ACCOUNT payment (within limit) / settle dues | | | ✔ | ✔ | ✔ | | | | |
| Override a credit limit, ledger adjustment | | | ✔ | ✔ | | | | | |
| Issue refund / credit note | | | ✔ | ✔ | with manager PIN | | | | |
| Kitchen display: bump / recall | | | ✔ | ✔ | view | ✔ | | | |
| Set station SLA times | | | ✔ | ✔ | | | | | |
| Publish central menu, reset overrides | | | ✔ | | | | | | |
| NC / open-item / tip / coupon / refund / dues reports | | | ✔ | ✔ | | | | | |
| View stock items, levels, ledger, recipes, vendors, POs, GRNs (Section 26) | | | ✔ | ✔ | | | | | ✔ |
| Create/edit stock items, categories, vendors | | | ✔ | ✔ | | | | | ✔ |
| Create/edit/activate recipes | | | ✔ | ✔ | | | | | |
| Create/send POs, post GRNs, purchase returns | | | ✔ | ✔ | | | | | ✔ |
| Void a posted GRN, record/void vendor payments | | | ✔ | ✔ | | | | | |
| Wastage and adjustments (PIN above the threshold) | | | ✔ | ✔ | | | | | ✔ |
| Start/enter/submit a stock count | | | ✔ | ✔ | | | | | ✔ |
| Approve a stock count (not the submitter) | | | ✔ | ✔ | | | | | |
| Stock transfers, production runs | | | ✔ | ✔ | | | | | ✔ |
| Inventory reports (payables: O, M only) | | | ✔ | ✔ | | | | | ✔ |
| CSV import (items, opening stock, recipes) | | | ✔ | ✔ | | | | | |
| Inventory settings (policy, thresholds, recipients) | | | ✔ | | | | | | |
| See item cost / margin | | | ✔ | ✔ | | | | | ✔ |
| Connect / disconnect aggregator account, replace credentials, run test | | | ✔ | | | | | | |
| Change auto-accept, SLA, store open/close | | | ✔ | ✔ | | | | | |
| View online orders (list) | | | ✔ | ✔ | ✔ | read | | | |
| Accept / reject online order | | | ✔ | ✔ | ✔ | | | | |
| Mark online order preparing / ready / handed over | | | ✔ | ✔ | ✔ | ✔ | | | |
| View raw provider payload | | | ✔ | ✔ | | | | | |
| Manage item mappings, push menu / availability | | | ✔ | ✔ | | | | | |
| Enter commission / settlement amounts, partner payouts, view partner reconciliation | | | ✔ | ✔ | | | | | |
| Configure gateway provider and credentials | | | ✔ | | | | | | |
| Create / cancel a gateway QR at checkout | | | ✔ | ✔ | ✔ | | | | |
| View payments needing attention | | | ✔ | ✔ | | | | | |
| Resolve / apply a payment attention 🔑 | | | 🔑 | 🔑 | | | | | |
| Import provider settlement file, view settlements | | | ✔ | view | | | | | |
| Edit legal profile, document title, tax-profile pairs | | | ✔ | | | | | | |
| Edit item HSN/SAC and item translations | | | ✔ | ✔ | | | | | |
| Create register / accounting exports, Tally ledger mappings | | | ✔ | ✔ | | | | | |
| Download an export | | | ✔ | ✔ | | | | | |
| Tenant data export | | | ✔ | | | | | | |
| Create / handle customer data requests | | | ✔ | ✔ | | | | | |
| Change retention settings | | | ✔ | | | | | | |
| View / export audit log | | | ✔ | view | | | | | |
| Weekly / monthly summary e-mail settings | | | ✔ | ✔ | | | | | |
| Change own UI language | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Set outlet bill language | | | ✔ | | | | | | |
| View backup runs (platform) | ✔ | view | | | | | | | |

**Section 30 rights (Owner / Manager / Cashier / Accountant / Kitchen):** reports RP1, RP2, RP6, RP7, RP8 — O M A; RP3, RP4, RP5 — O M; loyalty settings and rates — O only; loyalty adjust — O M (PIN above threshold); redeem points and read balance — O M C; payment-mode labels — O M; reservations create/seat/cancel — O M C; token/ready — O M C K.

Feature flags (plan limits, Section 18.3): `online_orders`, `gateway_payments`, `exports`, `data_requests` (402 `FEATURE_NOT_IN_PLAN` when off).

## APPENDIX B — Error codes (HTTP status → `code`)
| Status | Code | Meaning |
|---|---|---|
| 400 | `BAD_REQUEST` | malformed JSON / missing header |
| 401 | `UNAUTHENTICATED`, `TOKEN_EXPIRED` | |
| 403 | `FORBIDDEN`, `OVERRIDE_REQUIRED`, `OUTLET_NOT_ALLOWED` | |
| 404 | `NOT_FOUND` | also used for cross-tenant access |
| 409 | `VERSION_CONFLICT`, `TABLE_OCCUPIED`, `ILLEGAL_TRANSITION`, `DAY_CLOSED`, `ORDER_NOT_EDITABLE`, `ITEM_ALREADY_BILLED`, `BILL_NOT_PAYABLE`, `RIDER_NOT_AVAILABLE` | |
| 410 | `TRACKING_LINK_EXPIRED` | |
| 422 | `VALIDATION_ERROR`, `DISCOUNT_EXCEEDS_SUBTOTAL`, `OVERPAYMENT`, `IDEMPOTENCY_KEY_REUSED`, `MODIFIER_SELECTION_INVALID`, `ITEM_UNAVAILABLE` | |
| 423 | `ACCOUNT_LOCKED` | |
| 429 | `RATE_LIMITED` | includes `Retry-After` |
| 502 | `PROVIDER_ERROR` | external provider failure |
| 500 | `INTERNAL_ERROR` | body contains `traceId`, no stack trace |
| 402 | `SUBSCRIPTION_INACTIVE`, `FEATURE_NOT_IN_PLAN` | Part II |
| 403 | `TENANT_DEACTIVATED`, `SUPPORT_VIEW_READ_ONLY` | Part II |
| 409 | `PLAN_LIMIT_USERS`, `PLAN_LIMIT_ROLE`, `PLAN_LIMIT_OUTLETS`, `PLAN_DOWNGRADE_BLOCKED`, `LAST_OWNER`, `OUT_OF_DELIVERY_RANGE` | Part II |
| 422 | `DELIVERY_DISTANCE_UNKNOWN`, `INVALID_QR_IMAGE`, `INVALID_UPI_ID` | Part II |
| 413 | `PAYLOAD_TOO_LARGE` | uploads |
| 409 | `WHATSAPP_NOT_CONFIGURED`, `WHATSAPP_TEMPLATE_NOT_APPROVED` | Section 23 |
| 422 | `WHATSAPP_CONSENT_REQUIRED`, `INVALID_PHONE_NUMBER` | Section 23 |
| 429 | `WHATSAPP_RESEND_LIMIT` | Section 23 (max 5 sends per bill) |
| 410 | `BILL_LINK_EXPIRED` | public bill link expired/revoked |
| 403 | `DEVICE_NOT_PAIRED`, `DEVICE_REVOKED` | Section 24 |
| 409 | `OFFLINE_DISABLED` | outlet has offline turned off |
| 413 | `SYNC_BATCH_TOO_LARGE` | > `SYNC_MAX_BATCH` commands |
| 422 | `PAIRING_CODE_INVALID`, `COMMAND_ID_REUSED`, `UNSUPPORTED_SCHEMA_VERSION`, `SERIES_MISMATCH` | Section 24 |
| 403 | `OPEN_ITEM_NOT_ALLOWED`, `MANAGER_PIN_REQUIRED` | Section 25 |
| 409 | `SHIFT_ALREADY_OPEN`, `SHIFT_REQUIRED`, `SHIFT_NOT_OPEN`, `OPEN_SHIFTS_EXIST`, `BILL_HAS_CREDIT_NOTES`, `CREDIT_NOTE_NEEDS_PAID_BILL`, `BARCODE_IN_USE`, `COUPON_CODE_IN_USE` | |
| 422 | `COUPON_NOT_FOUND`, `COUPON_INACTIVE`, `COUPON_NOT_YET_VALID`, `COUPON_EXPIRED`, `COUPON_WRONG_OUTLET`, `COUPON_WEEKDAY`, `COUPON_ORDER_TYPE`, `COUPON_MIN_BILL`, `COUPON_CUSTOMER_REQUIRED`, `COUPON_LIMIT_TOTAL`, `COUPON_LIMIT_DAY`, `COUPON_LIMIT_CUSTOMER`, `COUPON_NOT_STACKABLE`, `COUPON_NC_BILL`, `COUPON_NO_DISCOUNT` | one per reason (25.4) |
| 422 | `OPEN_ITEM_PRICE_TOO_HIGH`, `COMBO_EMPTY`, `COMBO_NESTING_NOT_ALLOWED`, `COMBO_COMPONENT_OTHER_OUTLET`, `COMBO_VARIANT_MISMATCH`, `COMBO_PARENT_NOT_COMBO`, `CUSTOMER_REQUIRED`, `CREDIT_LIMIT_EXCEEDED`, `REASON_REQUIRED` | |
| 422 | `REFUND_EXCEEDS_QUANTITY`, `REFUND_EXCEEDS_AMOUNT`, `REFUND_EXCEEDS_TAXABLE`, `REFUND_EXCEEDS_TAX`, `REFUND_EXCEEDS_GROSS`, `REFUND_EXCEEDS_BILL_TOTAL`, `REFUND_TOO_SMALL`, `CREDIT_LINE_OTHER_BILL`, `CREDIT_NOTE_OTHER_OUTLET`, `ILLEGAL_KITCHEN_TRANSITION`, `SHIFT_OTHER_OUTLET` | |

| 403 | `APPROVAL_REQUIRED`, `COUNT_SELF_APPROVAL` | Section 26 |
| 409 | `NEGATIVE_STOCK_BLOCKED`, `REVERSAL_EXCEEDS_ORIGINAL`, `RECIPE_IMMUTABLE`, `RECIPE_OVERLAP`, `DUPLICATE_VENDOR_INVOICE`, `GRN_NOT_DRAFT`, `GRN_POSTED_IMMUTABLE`, `GRN_VOID_IS_FINAL`, `GRN_VOID_STOCK_USED`, `IMPORT_DUPLICATE_FILE` | Section 26 |
| 422 | `UNIT_FAMILY_MISMATCH`, `UNIT_FACTOR_MISMATCH`, `QUANTITY_BASE_MISMATCH`, `ITEM_NOT_TRACKED`, `REVERSAL_TARGET_INVALID`, `RECIPE_INHERITS`, `PREP_NESTING_NOT_ALLOWED`, `PREP_TARGET_INVALID`, `EXPAND_ONLY_FOR_PREP`, `ALLOCATION_*` (4), `TRANSFER_CROSS_TENANT`, `IMPORT_HAS_ERRORS` | Section 26 |
| 500 | `COST_BASIS_MISMATCH`, `LEDGER_IMMUTABLE`, `STOCK_LEVEL_DIRECT_CHANGE` | Section 26: server bugs, log and alert |
| 401 | `WEBHOOK_SIGNATURE_INVALID` | public webhook routes only; nothing stored |
| 409 | `ORDER_NOT_MAPPED`, `ORDER_EXPIRED`, `MAPPING_EXISTS`, `CAPABILITY_NOT_SUPPORTED`, `EXTERNAL_ORDER_ALREADY_IMPORTED`, `INTEGRATION_NOT_CONNECTED` | Section 27.A |
| 409 | `INTENT_ALREADY_LIVE`, `SETTLEMENT_ALREADY_IMPORTED`, `GATEWAY_NOT_CONFIGURED` | Section 27.B (`BILL_NOT_PAYABLE` and `OVERPAYMENT` are existing) |
| 409 | `REGISTER_NOT_RECONCILED`, `EXPORT_ALREADY_RUNNING` | Section 28 |
| 410 | `EXPORT_EXPIRED` | download link/file expired |
| 409 | `LOYALTY_DISABLED`, `LOYALTY_INSUFFICIENT_POINTS`, `LOYALTY_OFFLINE`, `RESERVATION_OVERLAP`, `RESERVATION_INVALID_STATE`, `TABLE_BUSY`, `PAYMENT_MODE_INACTIVE` | Section 30 |
| 422 | `LOYALTY_BELOW_MINIMUM`, `LOYALTY_OVER_CAP`, `LOYALTY_CUSTOMER_REQUIRED`, `RESERVATION_TABLE_OTHER_OUTLET`, `RESERVATION_IN_PAST`, `PAYMENT_MODE_OTHER_OUTLET`, `PAYMENT_MODE_METHOD_MISMATCH` | Section 30 |
| 400 / 500 | `REPORT_RANGE_TOO_LARGE` (400), `REPORT_NOT_RECONCILED` (500) | Section 30.2 |
| 422 | `MISSING_LEDGER_MAPPING`, `INVALID_GSTIN_FORMAT`, `INVALID_FSSAI_NUMBER`, `INVALID_HSN_CODE` | Section 28 |

Note (Section 25): the V013 triggers raise these strings as database errors (SQLSTATE 23514); the Java layer maps the message text to the HTTP code above.

## APPENDIX C — Seed notification template defaults (English)
- `DELIVERY_PICKED_UP`: "Your order from {{outletName}} is on the way! Track it live: {{trackingUrl}}"
- `DELIVERY_ARRIVING`: "Your delivery from {{outletName}} is arriving now."
- `DELIVERY_DELIVERED`: "Delivered! Thank you for ordering from {{outletName}}."
- `DELIVERY_PLACED`: "We've received your order #{{orderNo}} at {{outletName}}."
- `DELIVERY_FAILED_STAFF`: "Delivery for order #{{orderNo}} failed: {{reason}}."
- `TENANT_WELCOME`, `TRIAL_REMINDER`, `INVOICE_ISSUED`, `PAYMENT_RECEIVED`, `PAST_DUE_NOTICE`, `SUSPENDED_NOTICE`, `PAYMENT_ACCOUNT_CHANGED`, `TICKET_REPLY`, `TICKET_NEW_STAFF` — English defaults seeded; wording to be written by the product owner.
- WhatsApp approved templates (Section 23.6): `galla_bill_v1` — "Hi {{1}}, thank you for visiting {{2}}. Your bill {{3}} for {{4}} is attached." (document header, footer "Reply STOP to stop receiving bills."). Delivery-update templates `galla_delivery_picked_up_v1`, `galla_delivery_delivered_v1` are written by the product owner.
- `due_reminder`: generic reminder for a customer with an outstanding balance — customer name, outlet name, amount; no bill details (Section 25.11).
- Section 26 adds **no** WhatsApp templates: the low-stock and PO mails use the existing outbox e-mail channel.
- `EOD_SUMMARY`: subject "Day summary — {{outletName}} — {{businessDate}}" (HTML layout per Section 10.4).

## APPENDIX D — First commands for the implementing agent
1. Create the monorepo layout of Section 2.4.
2. Copy the Flyway migrations from `migrations/` (V001–V017; they are the verified versions of the SQL in Sections 4, 5.12, 11.7, 18.8, 19.4, 21.7, 23.12, 24.12, 25.20, 26.16 and 28.F).
3. Write `BillCalculatorTest` containing vectors V1–V11 and the jqwik invariants (port `reference/test_vectors.py`, `test_props.py`, `test_delivery_sub.py`, `test_whatsapp.py`); make them pass with `BillCalculator`. Also port `golden_bill_vectors.json` into the Java and Vitest contract tests.
4. Only then build services, controllers and UI in the Phase 1 order.
5. Migration order: V001–V011, V012 (offline), V013 (billing extras), V014 (inventory; seeds `inventory_units` itself and needs `btree_gist`), V015 (integrations, gateway, compliance), V016 (cross-stream links: one foreign key and a same-outlet trigger), V017 (loyalty, payment-mode labels, reservations, token labels).

---

# PART II — PLATFORM (SaaS), SUPPORT, DELIVERY CHARGES, OWN-QR PAYMENTS (added in v1.1)

> Everything in Part II was added after the first version of this plan. Rules marked *(verified)* have an executable reference implementation in `reference/` with passing tests; SQL marked *(verified)* was executed on PostgreSQL 16 together with V001–V007 and constraint-tested. Part II follows the same conventions as Part I (money as strings, tenant scoping, idempotency, audit, error model).

---

## 18. PLATFORM (SaaS) LAYER — super admin, restaurants, plans, trial, subscriptions

### 18.1 Actors
| Actor | Stored in | Signs in at | Can do |
|---|---|---|---|
| **SUPER_ADMIN** (platform owner) | `platform_users` | `/platform/login` | Everything on the platform: onboard/activate/deactivate restaurants and their users, manage plans, trials, invoices, payments, tickets, platform users and settings |
| **SUPPORT** (optional platform staff) | `platform_users` | `/platform/login` | Tickets, feedback, read-only restaurant view (only while a restaurant has granted access) |
| **Restaurant Admin** (DB role `OWNER`; the UI says "Restaurant Admin") | `users` | `/login` | Everything inside their restaurant: outlets, menu, taxes, users (within plan limits), payment accounts, delivery charges, reports, subscription page, support |
| MANAGER, CASHIER, CAPTAIN, KITCHEN, RIDER | `users` | `/login` | As in Appendix A |
| **INVENTORY** (new role) | `users` | `/login` | Reads the menu, toggles item availability and works the inventory module (Section 26): stock items, purchases/GRN, wastage, counts, transfers and reports; no billing, no approvals of counts, no settings. Plans can limit the role; the module itself needs the plan feature `inventory` |

Platform users and restaurant users are **separate tables and separate tokens** (`typ=PLATFORM` vs `typ=TENANT` JWT claim, separate signing secrets). A platform token is rejected by tenant endpoints and vice-versa (tested).

### 18.2 Onboarding a restaurant (v1 = invite-only, done by the super admin)
`POST /platform/tenants` in one transaction:
1. Create `tenants` row (`ACTIVE`) with contact details.
2. Create `subscriptions` row: `status=TRIALING`, `trial_ends_at = now + trial_days` (`trial_days` from the chosen plan, default **30**), `billing_cycle=MONTHLY` (changeable), `price_snapshot` = plan price of that cycle, `grace_days` from `platform_settings.default_grace_days` (default 7).
3. Create the first user with role `OWNER`, `must_change_password=true`, a random temporary password (shown **once** to the super admin and emailed through the outbox, template `TENANT_WELCOME`).
4. Optionally create the first outlet (name + timezone + currency) so the admin lands in a usable app.
5. Audit log `TENANT_CREATED` (actor type `PLATFORM_USER`).
Self-signup ("Start free trial" page) is **not** in v1 — see Open Decision 9. One trial per restaurant, ever (`subscriptions.tenant_id` is unique).

### 18.3 Plans and limits
Super admin creates plans (table `plans`, V008). A plan defines: monthly price, yearly price, `trial_days`, `max_outlets`, `max_users`, **`role_limits`** (per-role caps such as `{"CASHIER":3,"CAPTAIN":10}`; a role not listed is limited only by `max_users`), and `features` flags. Canonical feature keys: `delivery`, `ai_summary`, `csv_export`, `inventory` (Section 26; gates the inventory module, screens S27–S34 and the EOD `inventory` object) (a missing key means **off**). Prices and limits are entered by the super admin — none are hard-coded; dev seed plans use **sample values only, not a pricing recommendation**.

`PlanLimitService` is the only place limits are checked:
- **Create/enable user** → counts only `ACTIVE` users (disabled users do not count). Total ≥ `max_users` → `409 PLAN_LIMIT_USERS`; role count ≥ its `role_limits` → `409 PLAN_LIMIT_ROLE`. The response body says which limit and the numbers (`used`, `limit`).
- **Create outlet** → `409 PLAN_LIMIT_OUTLETS`.
- **Feature-gated endpoints** (delivery, AI summary, CSV export) → `402 FEATURE_NOT_IN_PLAN`.
- **Plan change** (restaurant asks, or super admin sets): validated against current usage; if usage is above the new plan's limits → `409 PLAN_DOWNGRADE_BLOCKED` listing what to reduce. A change requested by the restaurant takes effect **at the next renewal** (`pending_plan_id` / `pending_billing_cycle`); the super admin may apply it immediately. Re-validated at renewal; if it no longer fits, the renewal stays on the old plan and the Restaurant Admin is notified.
- Inactive plans (`active=false`) cannot be newly chosen; existing subscribers keep them.
Tested vectors: S6 below.

### 18.4 Subscription lifecycle
**Persisted status:** `TRIALING`, `ACTIVE`, `PAST_DUE`, `SUSPENDED`, `CANCELLED`. **Effective status** is computed from the clock on every request (cached 60 s in Redis, invalidated on change) and persisted by an hourly job, so a missed job never grants or denies access wrongly.

```
TRIALING ──trial_ends_at──▶ PAST_DUE ──+grace_days──▶ SUSPENDED
    │ (paid invoice for the first period exists)         ▲   │
    └──at trial_ends_at──▶ ACTIVE ──period_end──▶ PAST_DUE ┘   │ payment / "Reactivate"
                             ▲           │                      ▼
                             └───────────┴──── payment ───── ACTIVE (re-anchored)
ACTIVE + cancel_at_period_end ──period_end──▶ CANCELLED (no grace)
```
*(verified: `reference/subscription.py`, tests S1–S10)*

| Effective status | Meaning | Access level |
|---|---|---|
| TRIALING | inside `trial_ends_at` | FULL |
| ACTIVE | inside current period | FULL |
| PAST_DUE | period/trial ended, inside `grace_days` | FULL + red banner and response header `X-Subscription-Warning` |
| SUSPENDED | grace over, unpaid | READ_ONLY_SETTLE |
| CANCELLED | cancelled at period end, or by super admin | READ_ONLY_SETTLE |

**READ_ONLY_SETTLE** is deliberate: a restaurant must never be stranded mid-service or lose its data. Allowed: every `GET`, reports and CSV export, paying/recording payment on bills that already exist, printing, day close, subscription/support/feedback/auth endpoints, and rider status/location for deliveries already out. Blocked with `402 SUBSCRIPTION_INACTIVE`: creating orders, items, KOTs, bills and deliveries. Enforced by one annotation `@RequiresActiveSubscription` on those controller methods; an ArchUnit test fails the build if any `POST` in `ordering`/`billing`/`delivery` lacks it.

**Boundaries** (instant is exclusive at the end): trial of 30 days from `2026-11-22T10:00Z` ends `2026-12-22T10:00Z`; at `09:59:59` it is TRIALING, at `10:00:00` PAST_DUE; with 7 grace days it is PAST_DUE until `2026-12-29T09:59:59Z` and SUSPENDED from `10:00:00`.

**Billing periods — anchor rule (no month-end drift).** `period k = [anchor + k cycles, anchor + (k+1) cycles)` using calendar arithmetic with clamping. Anchor `31 Jan` → period 0 = `31 Jan → 28 Feb`, period 1 = `28 Feb → 31 Mar` (it returns to the 31st). Yearly from `29 Feb 2028` ends `28 Feb 2029`.

**Renewal and payment rules:**
- A renewal invoice for the next period is issued `invoice_lead_days` (default 7) before `current_period_end`, unless `cancel_at_period_end`.
- Payment on time or inside grace → next period continues the same anchor (**no gap and no free days**): paid `25 Jan` for a period that began `22 Jan` still runs `22 Jan → 22 Feb`.
- Payment after `SUSPENDED` → the super admin presses **Reactivate**, which voids the stale invoice, issues a fresh invoice for `[now, now + cycle)`; payment re-anchors at that moment (period number 0).
- A first payment during the trial does **not** shorten the trial: the first paid period starts at `trial_ends_at`; the hourly job flips `TRIALING → ACTIVE` at that instant.
- **Extend trial** (super admin, reason required): `new_end = max(trial_ends_at, now) + N days`; status returns to TRIALING.
- **Cancel** (Restaurant Admin): sets `cancel_at_period_end`; can be undone with *Resume* before the period ends. No automatic data deletion in v1 (retention is an open decision).
- `price_snapshot` locks the price at subscribe/renew time; a later plan price change affects only new periods.

### 18.5 Invoices and receiving money
Galla's own fees are recorded in `subscription_invoices` / `subscription_payments` (V008), numbered `GL-INV-000001` from `platform_counters` with the same atomic-upsert pattern as bill numbers. **v1 collects money manually:** the invoice page shows the payment instructions typed by the super admin (`platform_settings.payment_instructions` — bank/UPI details) and the invoice number as the payment reference; after verifying the credit, the super admin records the payment (`POST /platform/invoices/{id}/payments`, **Idempotency-Key required**, method `BANK_TRANSFER|UPI|CARD|CASH|OTHER`, amount, reference, received date). Payments are summed; the invoice becomes `PAID` when the sum reaches `total_amount` (compare with `compareTo`); overpayment → `422 OVERPAYMENT`. Paying an invoice advances the subscription per 18.4 in the same transaction and queues a `PAYMENT_RECEIVED` email.
An automated gateway for recurring collection is a later phase and **was not researched** (Open Decision 11). Tax on Galla's own invoices is configurable (`invoice_tax_label`, `invoice_tax_percent`, default 0%) and **not verified** (Open Decision 10). Invoices render with the same `PrintDocument` pipeline as A4 HTML so they can be printed or saved as PDF from the browser.
**Dashboard MRR** = Σ monthly price of ACTIVE subscriptions (yearly price ÷ 12), grouped per currency, labelled "estimated".

### 18.6 Trial notifications and in-app banners
| When | What | Dedupe key |
|---|---|---|
| T-7, T-3, T-1 days and T-0 before `trial_ends_at` | email to the Restaurant Admin (`TRIAL_REMINDER`) *(verified: S10)* | `trial:<tenant>:<k>` |
| Remaining ≤ 10 days, and once at trial end | in-app feedback prompt (Section 19) | `feedback.context` |
| Renewal invoice issued | `INVOICE_ISSUED` | `invoice:<id>` |
| Payment recorded | `PAYMENT_RECEIVED` | `payment:<id>` |
| Entering PAST_DUE; 1 day before suspension | `PAST_DUE_NOTICE` | `pastdue:<sub>:<period>:<n>` |
| Entering SUSPENDED | `SUSPENDED_NOTICE` | `suspended:<sub>:<period>` |
App-shell banner under the top bar: trial → blue "Free trial: 12 days left — Choose a plan" (amber at ≤ 7 days); PAST_DUE → red "Payment overdue — new orders will be disabled on {date}"; SUSPENDED → persistent red "Subscription ended — you can view reports and settle open bills; new orders are disabled" with a **Pay / contact** button. Banners read `GET /subscription`; no color-only meaning (icons + text).

### 18.7 Activating and deactivating restaurants and users
- **Restaurant Admin / Manager** can create, edit, disable and enable users of their own restaurant (Managers cannot touch Owners). Every ACTIVE user counts against plan limits, and re-enabling a user re-checks them.
- **Super admin** can disable/enable any restaurant user, reset passwords, and **deactivate a whole restaurant** (reason required, typed-name confirmation) → `tenants.status=SUSPENDED`: every restaurant login fails with `403 TENANT_DEACTIVATED`, existing sessions are revoked. This is separate from subscription suspension (which is read-only, not lock-out).
- **Disabling takes effect immediately:** `status=DISABLED`, all refresh-token families revoked, `user:revoked:{id}` written to Redis for the access-token lifetime (15 min) and checked by the JWT filter, open SSE streams closed. Test: a still-valid access token of a just-disabled user gets `401` within 1 second.
- A restaurant must keep ≥ 1 active OWNER: disabling/demoting the last one → `409 LAST_OWNER`. Nobody can disable themselves.
- **Support view:** the Restaurant Admin may grant a time-boxed (default 2 h, max 24 h), read-only access (`support_access_grants`). Platform staff then use a `typ=SUPPORT_VIEW` token: only `GET` works (`403 SUPPORT_VIEW_READ_ONLY` otherwise), a visible amber banner shows the restaurant name and end time, and every request is audited with actor `PLATFORM_USER`. The grant can be revoked at any time.

### 18.8 Database — Migration V008 *(verified on PostgreSQL 16)*
```sql
-- V008 — platform (SaaS) layer: platform users, plans, subscriptions, invoices, support access
CREATE TABLE platform_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  password_hash text NOT NULL,
  full_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('SUPER_ADMIN','SUPPORT')),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DISABLED')),
  failed_login_attempts int NOT NULL DEFAULT 0,
  locked_until timestamptz,
  last_login_at timestamptz,
  totp_secret_encrypted text,                   -- AES-GCM encrypted with TOTP_ENCRYPTION_KEY; 2FA is mandatory for platform users before production (Phase 4)
  totp_enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX ux_platform_users_email ON platform_users (lower(email));

CREATE TABLE platform_refresh_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  platform_user_id uuid NOT NULL REFERENCES platform_users(id) ON DELETE CASCADE,
  family_id uuid NOT NULL,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  replaced_by uuid,
  user_agent text, ip text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,
  currency_code char(3) NOT NULL,
  price_monthly numeric(12,2) NOT NULL CHECK (price_monthly >= 0),
  price_yearly numeric(12,2) NOT NULL CHECK (price_yearly >= 0),
  trial_days int NOT NULL DEFAULT 30 CHECK (trial_days BETWEEN 0 AND 365),
  max_outlets int NOT NULL CHECK (max_outlets >= 1),
  max_users int NOT NULL CHECK (max_users >= 1),
  role_limits jsonb NOT NULL DEFAULT '{}',      -- e.g. {"CASHIER":3,"CAPTAIN":10}; role absent = only max_users applies
  features jsonb NOT NULL DEFAULT '{}',         -- e.g. {"delivery":true,"ai_summary":false,"whatsapp_bills":true}
  active boolean NOT NULL DEFAULT true,         -- inactive plans cannot be newly chosen; existing subscribers keep them
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);

ALTER TABLE tenants
  ADD COLUMN contact_name text,
  ADD COLUMN contact_email text,
  ADD COLUMN contact_phone text,
  ADD COLUMN created_by uuid REFERENCES platform_users(id),
  ADD COLUMN deactivated_at timestamptz,
  ADD COLUMN deactivated_reason text,
  ADD COLUMN deactivated_by uuid REFERENCES platform_users(id);

CREATE TABLE subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL UNIQUE REFERENCES tenants(id),
  plan_id uuid NOT NULL REFERENCES plans(id),
  billing_cycle text NOT NULL CHECK (billing_cycle IN ('MONTHLY','YEARLY')),
  status text NOT NULL CHECK (status IN ('TRIALING','ACTIVE','PAST_DUE','SUSPENDED','CANCELLED')),
  price_snapshot numeric(12,2) NOT NULL CHECK (price_snapshot >= 0),   -- price locked at subscribe/renew time
  currency_code char(3) NOT NULL,
  trial_ends_at timestamptz,
  billing_anchor_at timestamptz,                -- periods are anchor + k cycles (no month-end drift)
  period_number int NOT NULL DEFAULT 0,
  current_period_start timestamptz,
  current_period_end timestamptz,
  grace_days int NOT NULL DEFAULT 7 CHECK (grace_days BETWEEN 0 AND 60),
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  pending_plan_id uuid REFERENCES plans(id),    -- plan/cycle change takes effect at next renewal
  pending_billing_cycle text CHECK (pending_billing_cycle IN ('MONTHLY','YEARLY')),
  suspended_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0,
  CHECK (status <> 'TRIALING' OR trial_ends_at IS NOT NULL),
  CHECK (status NOT IN ('ACTIVE','PAST_DUE') OR (current_period_start IS NOT NULL AND current_period_end IS NOT NULL AND billing_anchor_at IS NOT NULL))
);
CREATE INDEX ix_subscriptions_status ON subscriptions(status);

CREATE TABLE platform_counters (
  name text PRIMARY KEY,                        -- 'invoice', 'ticket'
  last_no int NOT NULL
);

CREATE TABLE subscription_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  subscription_id uuid NOT NULL REFERENCES subscriptions(id),
  invoice_number text NOT NULL UNIQUE,          -- GL-INV-000001
  plan_name text NOT NULL,
  billing_cycle text NOT NULL CHECK (billing_cycle IN ('MONTHLY','YEARLY')),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  amount_before_tax numeric(12,2) NOT NULL CHECK (amount_before_tax >= 0),
  tax_label text,
  tax_percent numeric(5,2) NOT NULL DEFAULT 0 CHECK (tax_percent BETWEEN 0 AND 100),
  tax_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  total_amount numeric(12,2) NOT NULL CHECK (total_amount >= 0),
  currency_code char(3) NOT NULL,
  status text NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE','PAID','VOID')),
  due_at timestamptz NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  void_reason text,
  created_by uuid REFERENCES platform_users(id),
  CHECK (period_end > period_start),
  CHECK (total_amount = amount_before_tax + tax_amount)
);
CREATE UNIQUE INDEX ux_invoice_period ON subscription_invoices(subscription_id, period_start) WHERE status <> 'VOID';
CREATE INDEX ix_invoices_tenant ON subscription_invoices(tenant_id, issued_at DESC);

CREATE TABLE subscription_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  invoice_id uuid NOT NULL REFERENCES subscription_invoices(id),
  method text NOT NULL CHECK (method IN ('BANK_TRANSFER','UPI','CARD','CASH','OTHER')),
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  reference text,
  received_at timestamptz NOT NULL,
  recorded_by uuid NOT NULL REFERENCES platform_users(id),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE platform_settings (
  key text PRIMARY KEY,                         -- default_grace_days, default_trial_days, invoice_tax_label, invoice_tax_percent, support_email
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE support_access_grants (            -- restaurant admin lets platform staff view their data, read-only, time-boxed
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  granted_by uuid NOT NULL REFERENCES users(id),
  platform_user_id uuid REFERENCES platform_users(id),   -- NULL = any support user
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- existing tables
ALTER TABLE audit_logs ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE audit_logs ADD COLUMN actor_type text NOT NULL DEFAULT 'TENANT_USER' CHECK (actor_type IN ('TENANT_USER','PLATFORM_USER','SYSTEM'));
ALTER TABLE users ADD COLUMN must_change_password boolean NOT NULL DEFAULT false;
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('OWNER','MANAGER','CASHIER','CAPTAIN','KITCHEN','RIDER','INVENTORY'));
```

### 18.9 API (all under `/api/v1`; platform endpoints require a `PLATFORM` token)
**Platform auth & users**
| Method | Path | Who |
|---|---|---|
| POST | `/platform/auth/login`, `/platform/auth/refresh`, `/platform/auth/logout` | public / cookie |
| GET | `/platform/me` | platform |
| CRUD | `/platform/users` | SUPER_ADMIN |

**Restaurants**
| Method | Path | Notes |
|---|---|---|
| GET | `/platform/tenants?status=&q=&page=` | list with plan, effective status, usage, last activity |
| POST | `/platform/tenants` | onboarding (18.2) |
| GET / PUT | `/platform/tenants/{id}` | detail incl. subscription, usage by role, outlets |
| POST | `/platform/tenants/{id}/deactivate` `{reason}`, `/activate` | SUPER_ADMIN |
| GET | `/platform/tenants/{id}/users` | |
| POST | `/platform/tenants/{id}/users/{userId}/disable`, `/enable`, `/reset-password` | enable re-checks limits |
| POST | `/platform/tenants/{id}/subscription/change-plan` `{planId, cycle, immediate?}` | validates limits |
| POST | `/platform/tenants/{id}/subscription/extend-trial` `{days, reason}` | |
| POST | `/platform/tenants/{id}/subscription/reactivate` | issues fresh invoice (18.4) |
| POST | `/platform/tenants/{id}/subscription/cancel`, `/grace` `{days}` | |

**Plans, billing, settings, dashboard**
| Method | Path | Notes |
|---|---|---|
| CRUD | `/platform/plans` | no hard delete once subscribed (`active=false`) |
| GET | `/platform/invoices?status=&tenantId=` | |
| POST | `/platform/tenants/{id}/invoices` | manual invoice for the next period |
| POST | `/platform/invoices/{id}/payments` | **Idempotency-Key**; `{method, amount, reference?, receivedAt, notes?}` |
| POST | `/platform/invoices/{id}/void` `{reason}` | |
| GET / PUT | `/platform/settings` | trial/grace defaults, tax label/percent, payment instructions, support email, invoice lead days |
| GET | `/platform/dashboard` | counts per effective status, trials ending ≤ 7 d, overdue invoices, estimated MRR per currency, open tickets, 30-day rating |
| POST | `/platform/tenants/{id}/support-view` | needs an active grant → `SUPPORT_VIEW` token |

**Restaurant side**
| Method | Path | Roles |
|---|---|---|
| GET | `/subscription` | O,M — plan, status, effective status, dates, usage vs limits, pending change, banner data, `yearlySavings` (server-computed), payment instructions |
| GET | `/plans/public` | O — active plans for choosing |
| POST | `/subscription/choose-plan` `{planId, cycle}` | O — sets the pending change; first subscribe creates the first invoice |
| POST | `/subscription/cancel`, `/subscription/resume` | O |
| GET | `/subscription/invoices`, `/subscription/invoices/{id}/print-doc` | O |
| POST / DELETE | `/support-access` `{hours}` | O — grant / revoke |

### 18.10 Screens
**Platform console** (indigo accent `--platform` so nobody confuses it with a restaurant; a permanent "PLATFORM" badge in the top bar)
- **P0 Login** `/platform/login` — email, password, then 6-digit code once 2FA is enabled.
- **P1 Dashboard** — KPI cards (Active · On trial · Past due · Suspended), *Trials ending in 7 days* table (Extend / Open), *Overdue invoices*, *Estimated MRR* per currency, *Open tickets*, 30-day average rating.
- **P2 Restaurants** — search, status chips, columns: name, plan, status badge, trial/period end, users used/limit, last login, actions. **+ Onboard restaurant** = 3-step modal (Restaurant → Admin user → Plan & trial) ending with the one-time temporary password and a copy button.
- **P3 Restaurant detail** — tabs *Overview* (usage bars by role and outlets) · *Users* (enable/disable, reset password, role, last login) · *Subscription* (change plan, extend trial, reactivate, cancel, grace) · *Invoices & payments* (**Record payment** dialog) · *Tickets* · *Audit*. **Danger zone:** Deactivate restaurant.
- **P4 Plans** — table + editor drawer (prices, trial days, outlet/user limits, per-role limits editor, feature toggles incl. `inventory`, active) with a live "what the restaurant sees" preview.
- **P5 Invoices**, **P6 Tickets** and **P7 Ticket detail**, **P8 Feedback**, **P9 Settings**, **P10 Platform users** (SUPER_ADMIN only).
- **Support-view banner:** amber, sticky: "Read-only support view of {Restaurant} until 16:40 — Exit".

**Restaurant Admin pages**
- **R1 Subscription** `/settings/subscription`
```
┌ Plan: Growth · [Trial — 12 days left] ──────────────────────────────┐
│ Billing:  (•) Monthly  ( ) Yearly  — save {yearlySavings} yearly      │
│ Next charge: {amount} on {date}      [Change plan] [Cancel at period end]│
│ Usage   Users ████████░░ 4/5   Cashiers ██████████ 2/2 (limit)        │
│         Outlets ███░░░░░░ 1/3                                         │
│ Invoices  #GL-INV-000012  Due 22 Dec  {amount}  [View] [Print]        │
│ How to pay: {payment instructions}  Reference: invoice number         │
└──────────────────────────────────────────────────────────────────────┘
```
- **R2 Users** `/settings/users` — usage meter "4 of 5 users"; role dropdown disables a role that is at its limit with a tooltip "Plan limit reached — upgrade"; Active/Disabled toggle; **Add user** modal (name, email, phone, role, outlets, generated temporary password shown once with copy; "send invite email" checkbox).
- **R3 Help** `/help` — Send feedback · Raise a ticket · My tickets · **Allow support to view my account (read-only) for 2 hours**.

---

## 19. SUPPORT & FEEDBACK

### 19.1 What restaurants can do
- **Send feedback** — 1–5 stars, category (General, Billing, Menu, Printing, Delivery, Performance, Trial, Other), optional message. Also prompted automatically: once when ≤ 10 trial days remain and once when the trial ends (`context` = `TRIAL_ENDING` / `TRIAL_ENDED`; never shown twice; "Not now" snoozes 3 days).
- **Raise a ticket** — subject, category, priority (Low/Normal/High/Urgent), description (≤ 4 000 chars). The app **auto-attaches diagnostics** into `support_tickets.context` (app version, browser, current route, outlet id, the last error `traceId`). Every error state has a **Report this problem** button that pre-fills the ticket with the `traceId`.
- Follow the thread, reply, and close their own ticket. Replying to a `WAITING_CUSTOMER`/`RESOLVED` ticket reopens it.
- Limit: 5 new tickets per hour per restaurant (`429 RATE_LIMITED`).

### 19.2 What the platform team can do
Inbox with filters (status, priority, restaurant, assignee, age), assign to a platform user, reply (visible to the restaurant) or add an **internal note** (never returned by any tenant endpoint — API test), change status, open the restaurant's detail page, and (with a grant) the read-only support view. Feedback page: average rating (30 days), by category, recent comments, filter by restaurant.

### 19.3 Ticket states (illegal transition → `409 ILLEGAL_TRANSITION`)
| From | To | By |
|---|---|---|
| OPEN | IN_PROGRESS (first staff reply or assignment) | platform |
| IN_PROGRESS | WAITING_CUSTOMER, RESOLVED | platform |
| WAITING_CUSTOMER | OPEN (customer replies), RESOLVED | customer / platform |
| RESOLVED | OPEN (customer replies within `ticket_reopen_days`), CLOSED | customer / system |
| any open state | CLOSED | restaurant creator or platform |
`RESOLVED → CLOSED` runs automatically after `ticket_auto_close_days` (my defaults: 7 and 7, in `platform_settings`; not a commitment). Notifications through the outbox: new ticket → platform support email; staff reply → ticket creator; dedupe `ticket:<id>:msg:<messageId>`. No service-level promises are built into v1; the console only highlights ticket age.
Attachments (screenshots) are Phase 5; `support_ticket_messages.body` is plain text (HTML-escaped on render).

### 19.4 Database — Migration V009 *(verified on PostgreSQL 16)*
```sql
-- V009 — feedback and support tickets
CREATE TABLE feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  user_id uuid NOT NULL REFERENCES users(id),
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  category text NOT NULL DEFAULT 'GENERAL' CHECK (category IN ('GENERAL','BILLING','MENU','PRINTING','DELIVERY','PERFORMANCE','TRIAL','OTHER')),
  message text,
  context text,                                  -- e.g. 'TRIAL_DAY_20', 'TRIAL_ENDED', 'MANUAL'
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_feedback_created ON feedback(created_at DESC);

CREATE TABLE support_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  ticket_number text NOT NULL UNIQUE,            -- GL-TKT-000045
  created_by uuid NOT NULL REFERENCES users(id),
  subject text NOT NULL,
  category text NOT NULL DEFAULT 'GENERAL' CHECK (category IN ('GENERAL','BILLING','MENU','PRINTING','DELIVERY','SUBSCRIPTION','BUG','OTHER')),
  priority text NOT NULL DEFAULT 'NORMAL' CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','IN_PROGRESS','WAITING_CUSTOMER','RESOLVED','CLOSED')),
  assigned_to uuid REFERENCES platform_users(id),
  context jsonb,                                 -- auto-attached diagnostics: app version, browser, route, last traceId
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  version bigint NOT NULL DEFAULT 0
);
CREATE INDEX ix_tickets_tenant ON support_tickets(tenant_id, created_at DESC);
CREATE INDEX ix_tickets_open ON support_tickets(status, priority) WHERE status IN ('OPEN','IN_PROGRESS','WAITING_CUSTOMER');

CREATE TABLE support_ticket_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  author_type text NOT NULL CHECK (author_type IN ('TENANT_USER','PLATFORM_USER')),
  author_id uuid NOT NULL,
  body text NOT NULL CHECK (length(btrim(body)) > 0),
  internal_note boolean NOT NULL DEFAULT false,  -- visible to platform staff only
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT internal_note OR author_type = 'PLATFORM_USER')
);
CREATE INDEX ix_ticket_messages ON support_ticket_messages(ticket_id, created_at);
```

### 19.5 API
| Method | Path | Who |
|---|---|---|
| POST | `/feedback` `{rating, category, message?, context?}` | any restaurant user |
| GET / POST | `/support/tickets`, `/support/tickets/{id}` | creator; O,M see all of their restaurant's tickets |
| POST | `/support/tickets/{id}/messages` `{body}`; `/close`; `/reopen` | creator, O, M |
| GET | `/platform/tickets?status=&priority=&tenantId=&assignee=` | platform |
| GET | `/platform/tickets/{id}` | platform (includes internal notes) |
| POST | `/platform/tickets/{id}/messages` `{body, internal}`; `/assign` `{platformUserId}`; `/status` `{to}` | platform |
| GET | `/platform/feedback?tenantId=&category=&from=&to=` | platform |

---

## 20. DELIVERY CHARGES & PARTNER ORDERS

> Interpretation (confirm — Open Decision 16): "delivery partner / revenue partner delivering far from the restaurant" is handled two ways — (a) **delivery charge** rules by distance, and (b) **partner orders** (an order sent by an outside partner) and **partner riders** (a rider who is not your staff). Customer-facing ordering apps/websites are out of scope: staff enter phone and partner orders at the POS.

### 20.1 Restaurant settings (Settings → Delivery charges; Restaurant Admin/Manager)
| Setting | Meaning |
|---|---|
| Outlet coordinates (`latitude`, `longitude`) | set by clicking the map; required for distance modes |
| Mode | `NONE` · `FLAT` (one charge) · `DISTANCE_SLABS` (charge by distance band) |
| Flat charge | used by `FLAT` |
| Slabs | rows `from_km < distance ≤ to_km → charge`; the database forbids overlaps (exclusion constraint) and `to_km > from_km` |
| Free above | if the bill's subtotal **after discount** ≥ this amount, the delivery charge is 0 (inclusive `≥`) |
| Max radius (km) | beyond it delivery is refused unless a manager overrides |
| Distance factor | multiplies the straight-line distance (default **1.00**; allowed 1.00–3.00) because roads are longer than straight lines — the app does **not** use a road-routing service in v1 |
| Tax profile for delivery charge | optional; the charge is then taxed like any line |

### 20.2 Calculation *(verified: `reference/delivery_charge.py`, tests D1–D10)*
1. **Distance:** `distance_km = round2( haversine(outlet, destination) × factor )`, HALF_UP, Earth radius 6371.0 km. Stored in `deliveries.distance_km` when the delivery is created (recomputed if the destination changes before billing). Check: 1° of longitude on the equator = `111.19` km.
2. **Order of checks** (first match wins):
   1. A **manager override** exists (`charge_override`, reason + PIN required) → use it (0 = waive). Skips every other rule.
   2. Mode `NONE` → `0`.
   3. Max radius set and `distance > max_radius` → error `409 OUT_OF_DELIVERY_RANGE`.
   4. `free_above` set and subtotal-after-discount `≥ free_above` → `0`.
   5. `FLAT` → flat charge. `DISTANCE_SLABS` → distance unknown → `422 DELIVERY_DISTANCE_UNKNOWN` (staff must drop a map pin or get an override); find the slab with `from < d ≤ to`; none → `409 OUT_OF_DELIVERY_RANGE`.
3. **Slab boundaries:** with slabs `(0,3]=30`, `(3,6]=50`, `(6,10]=80`: `3.00 → 30`, `3.01 → 50`, `10.00 → 80`, `10.01 → out of range`.
4. **When:** at **bill generation** and in `POST /bills/preview` for orders of type `DELIVERY` (so the free-above test sees the final discounted amount). The result becomes a bill line of type `DELIVERY_CHARGE`.
5. **In the bill math (Section 5.3, Step 5b):** the delivery charge is **never discounted** and is **not part of the service-charge base**; it is taxed with the delivery tax profile (inclusive/exclusive like all lines) and included in round-off. `bills.delivery_charge_total` = the `line_total` of that line.
6. **Split bills:** the charge is carried by exactly **one** bill per order — the first non-void bill; the database enforces it (`ux_bills_delivery_charge_once`). Consequence: the free-above test uses the subtotal of the bill that carries the charge. Voiding that bill frees the charge for the next bill.
7. **Cash on delivery:** normal CASH payment recorded when the rider/cashier confirms (Section 11.1).

### 20.3 Partner orders and partner riders
- At order creation the POS "Source" selector offers **Direct / Phone / Partner**. Partner requires a **partner name** (free text) and optionally the partner's **order id** (`external_ref`) for reconciliation. The source appears on the KOT header and in reports (sales by source); it is **not** printed on the tax invoice.
- Riders have a type **OWN** or **PARTNER** (+ partner name). PARTNER riders do not sign in: staff move the delivery through its statuses (already permitted), and there is no live rider marker — only the destination — because there is no location feed. This limitation is shown in the UI.
- Rider payout/commission is **out of scope**.
- **Aggregator integration (Section 27.A):** an order accepted from an online platform becomes an ordinary internal order with `order_source = PARTNER`, `partner_name` = the integration account's display name and `external_ref` = the platform's order id. Manual partner entry stays as the fallback (outage, pending approval); typing the `external_ref` of an order already in the inbox is refused (`EXTERNAL_ORDER_ALREADY_IMPORTED`). Commission/settlement figures are stored as entered or reported, never calculated, and feed only the reconciliation report. The sentence "Customer-facing ordering apps/websites are out of scope" stays (receiving aggregator orders is not an ordering app of Galla's).

### 20.4 Screens
- **Settings → Delivery charges** — mode radio; flat amount; slab editor (add/remove rows, inline overlap + gap warnings); free-above; max radius; distance factor with helper text "Straight-line distance × factor. Roads are usually 1.2–1.5× longer" *(my rule of thumb, not measured)*; tax profile; map to place the outlet; **Try it** box: click a point on the map → shows distance, matching slab and charge.
- **Bill dialog (S4)** — a "Delivery charge" row with an info tooltip "4.20 km · slab 3–6 km"; **Change** → manager PIN + reason. Out of range → blocking dialog "Outside delivery radius (10 km)" with *Manager override* and *Cancel*.
- **Delivery board (S7)** — cards show distance, charge, and a "Partner" chip with partner name/order id; rider chip shows OWN/PARTNER.

### 20.5 Database
Delivery-charge, partner-order and rider-type columns are part of Migration V010 (Section 21.7).

### 20.6 API additions
| Method | Path | Roles |
|---|---|---|
| GET / PUT | `/outlets/{id}/delivery-settings` (mode, flat, free-above, radius, factor, tax profile, coordinates) | O,M (PUT: O) |
| CRUD | `/outlets/{id}/delivery-slabs` | O,M |
| POST | `/delivery-charge/quote` `{outletId?, destLat, destLng, subtotalAfterDiscount}` → `{distanceKm, charge, reason}` | O,M,C |
| POST | `/deliveries/{id}/charge-override` `{charge, reason}` 🔑 | audit `DELIVERY_CHARGE_OVERRIDDEN` |
`POST /orders` accepts `orderSource`, `partnerName`, `externalRef`; `POST /riders` accepts `riderType`, `partnerName`.

---

## 21. OWN UPI ID / QR UPLOAD — payment accounts

### 21.1 Idea
A restaurant adds its **own UPI ID (VPA)** or **uploads the QR it already has**. At payment time the app shows a QR for that account; the customer pays in their UPI app; the **cashier confirms** after seeing the credit in their bank/UPI app. This is the Mode A flow of Section 9 made configurable per outlet. Automatic confirmation (Mode B) still needs a payment gateway that has not been chosen.

### 21.2 Adding an account (Restaurant Admin only — see 21.5 for why)
| Option | What the server does | Resulting mode |
|---|---|---|
| **Enter UPI ID + payee name** | validates the ID with `^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$`, payee name ≤ 99 chars with control characters removed | `GENERATED` — a new QR per bill with the **amount locked** |
| **Upload QR image** (PNG/JPEG, ≤ 1 MB, ≤ 2 000 × 2 000 px) | verifies magic bytes (not just the extension), **re-encodes** the image (strips metadata), decodes the QR with ZXing. If the text is a `upi://pay?...` link with `pa=` → extracts `pa` (UPI ID) and `pn` (name) and shows them **for the admin to confirm** | `GENERATED` (preferred: amount can be locked) |
| Upload that decodes to something else, or no QR found | stores the image only and warns "The amount cannot be pre-filled; the customer must type the amount shown on screen" | `STATIC_IMAGE` |
The decoded text is treated purely as data (never opened or executed). Images are stored through `StorageService` (S3-compatible in production, a volume in dev) under random names and served only by an authenticated endpoint.

### 21.3 At payment time (Bill dialog → UPI tab)
- Account dropdown (default pre-selected); the chosen account is saved on the payment (`payments.payment_account_id`).
- `GENERATED`: QR from `upi://pay?pa={vpa}&pn={urlEncode(payee)}&am={amount, 2 dp}&cu={currency}&tn={bill_number}`; amount equals the **remaining balance** (Section 9.4).
- `STATIC_IMAGE`: the uploaded image plus a very large **"Amount to collect: {amount}"** panel.
- Both: expiry countdown and the button **Payment received**, helper text "Confirm only after your bank/UPI app shows the credit." The payment stays `PENDING` until pressed; `confirmed_by`/`confirmed_at` are stored.
- **Not verified:** whether every UPI app honours a pre-filled amount for every merchant QR. It must be tried on real phones/apps before launch; the cashier-confirmation step makes a wrong-amount payment visible, not impossible.

### 21.4 Fraud and reconciliation protections
- Only the **Restaurant Admin (OWNER)** can add, change, deactivate or re-default an account. Managers and cashiers can only choose among existing accounts.
- Every change is audited (`PAYMENT_ACCOUNT_ADDED/CHANGED/DEFAULT_CHANGED`) **and emailed** to the Restaurant Admin (`PAYMENT_ACCOUNT_CHANGED`, dedupe per change) so a swapped QR is noticed.
- Day-close summary and `/reports/payment-modes` include **manual UPI confirmations per cashier** (count and amount) so the owner can match them against the bank/UPI statement.

### 21.5 API
| Method | Path | Roles |
|---|---|---|
| GET | `/payment-accounts` | O,M,C (C/M: only `id, label, active, isDefault`, never the image) |
| POST | `/payment-accounts` `{label, vpa?, payeeName?, makeDefault?}` or multipart with `qrImage` | O |
| POST | `/payment-accounts/decode-qr` (multipart image) → `{upiId?, payeeName?, isUpiLink, warnings[]}` — saves nothing | O |
| PUT / DELETE | `/payment-accounts/{id}` (DELETE = deactivate), `POST /payment-accounts/{id}/default` | O |
| GET | `/payment-accounts/{id}/qr-image` | O,M,C (authenticated) |
| POST | `/bills/{id}/upi-qr` `{paymentAccountId?}` (default account if omitted) | O,M,C |
Errors: `422 INVALID_QR_IMAGE`, `422 INVALID_UPI_ID`, `413` for oversize files.

### 21.6 Screen — Settings → Payment accounts
List (label, UPI ID, mode chip, **Default** badge, active toggle) · **Add UPI ID** form · **Upload QR** drag-and-drop with preview → "We found UPI ID `shop@bank`, name `Shop Name` — is this correct?" → Save · **Preview QR** (amount fixed at 1.00, stamped "PREVIEW — not a payment").

### 21.7 Database — Migration V010 *(verified on PostgreSQL 16, including migration of an existing outlet UPI ID into the new table)*
```sql
-- V010 — own UPI accounts/QR, delivery charges, order source, partner riders
CREATE EXTENSION IF NOT EXISTS btree_gist;       -- needed for the slab no-overlap constraint (migration user needs CREATE privilege)

CREATE TABLE outlet_payment_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  label text NOT NULL,                           -- "Counter UPI", "Owner PhonePe"
  vpa text,                                      -- UPI ID, e.g. name@bank; entered or decoded from the uploaded QR
  payee_name text,
  qr_image_key text,                             -- object-storage key of the uploaded QR image (kept for display / audit)
  qr_decoded_payload text,                       -- raw text decoded from the uploaded image, if any
  qr_mode text NOT NULL DEFAULT 'GENERATED' CHECK (qr_mode IN ('GENERATED','STATIC_IMAGE')),
                                                 -- GENERATED = we build a per-bill QR with the amount; STATIC_IMAGE = show uploaded image (amount NOT locked)
  is_default boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (vpa IS NOT NULL OR qr_image_key IS NOT NULL),
  CHECK (qr_mode <> 'GENERATED' OR vpa IS NOT NULL)
);
CREATE UNIQUE INDEX ux_payment_accounts_default ON outlet_payment_accounts(outlet_id) WHERE is_default AND active;

INSERT INTO outlet_payment_accounts(tenant_id, outlet_id, label, vpa, payee_name, is_default)
  SELECT tenant_id, id, 'Default UPI', upi_vpa, upi_payee_name, true FROM outlets WHERE upi_vpa IS NOT NULL;
ALTER TABLE outlets DROP COLUMN upi_vpa, DROP COLUMN upi_payee_name;

ALTER TABLE payments ADD COLUMN payment_account_id uuid REFERENCES outlet_payment_accounts(id);

ALTER TABLE outlets
  ADD COLUMN latitude numeric(9,6) CHECK (latitude BETWEEN -90 AND 90),
  ADD COLUMN longitude numeric(9,6) CHECK (longitude BETWEEN -180 AND 180),
  ADD COLUMN delivery_charge_mode text NOT NULL DEFAULT 'NONE' CHECK (delivery_charge_mode IN ('NONE','FLAT','DISTANCE_SLABS')),
  ADD COLUMN delivery_flat_charge numeric(12,2) NOT NULL DEFAULT 0 CHECK (delivery_flat_charge >= 0),
  ADD COLUMN delivery_free_above numeric(12,2) CHECK (delivery_free_above IS NULL OR delivery_free_above > 0),
  ADD COLUMN delivery_max_radius_km numeric(6,2) CHECK (delivery_max_radius_km IS NULL OR delivery_max_radius_km > 0),
  ADD COLUMN delivery_distance_factor numeric(4,2) NOT NULL DEFAULT 1.00 CHECK (delivery_distance_factor BETWEEN 1.00 AND 3.00),
  ADD COLUMN delivery_tax_profile_id uuid REFERENCES tax_profiles(id);

CREATE TABLE delivery_charge_slabs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  from_km numeric(6,2) NOT NULL CHECK (from_km >= 0),   -- exclusive lower bound
  to_km numeric(6,2) NOT NULL,                          -- inclusive upper bound
  charge numeric(12,2) NOT NULL CHECK (charge >= 0),
  CHECK (to_km > from_km),
  EXCLUDE USING gist (outlet_id WITH =, numrange(from_km, to_km, '(]') WITH &&)
);

ALTER TABLE bills ADD COLUMN delivery_charge_total numeric(12,2) NOT NULL DEFAULT 0 CHECK (delivery_charge_total >= 0);
-- a delivery charge is billed exactly once per order (split bills: only the first bill carries it)
CREATE UNIQUE INDEX ux_bills_delivery_charge_once ON bills(order_id) WHERE delivery_charge_total > 0 AND status <> 'VOID';
ALTER TABLE bill_lines DROP CONSTRAINT bill_lines_line_type_check;
ALTER TABLE bill_lines ADD CONSTRAINT bill_lines_line_type_check CHECK (line_type IN ('ITEM','SERVICE_CHARGE','DELIVERY_CHARGE'));

ALTER TABLE deliveries
  ADD COLUMN distance_km numeric(6,2),
  ADD COLUMN charge_override numeric(12,2) CHECK (charge_override IS NULL OR charge_override >= 0),
  ADD COLUMN charge_override_reason text,
  ADD COLUMN charge_override_by uuid REFERENCES users(id),
  ADD CONSTRAINT deliveries_override_needs_reason CHECK (charge_override IS NULL OR (charge_override_reason IS NOT NULL AND charge_override_by IS NOT NULL));

ALTER TABLE orders
  ADD COLUMN order_source text NOT NULL DEFAULT 'DIRECT' CHECK (order_source IN ('DIRECT','PHONE','PARTNER')),
  ADD COLUMN partner_name text,                  -- free text, e.g. the aggregator or partner who sent the order
  ADD COLUMN external_ref text,                  -- partner's order id, for reconciliation
  ADD CONSTRAINT orders_partner_has_name CHECK (order_source <> 'PARTNER' OR partner_name IS NOT NULL);

ALTER TABLE riders
  ADD COLUMN rider_type text NOT NULL DEFAULT 'OWN' CHECK (rider_type IN ('OWN','PARTNER')),
  ADD COLUMN partner_name text;
```

---

## 22. LOGIN, ROLES, RULES — and "the app must never show a blank screen"

### 22.1 Login screen with a role selector
One login page with a **"Sign in as"** selector: **Platform admin · Restaurant admin · Staff**.
- *Platform admin* posts to `/platform/auth/login`; the other two post to `/auth/login`.
- The selector is a convenience and a safety check, **never a source of permission**: the server decides the real role from the credentials. After a successful restaurant login the UI compares the returned role with the selection (Restaurant admin ⇒ `OWNER`; Staff ⇒ any other role). A mismatch shows "This account is a *{actual role}*. Please choose *{label}*." and signs the user out of that attempt. Picking a higher role than you have grants nothing (tested).
- Generic failure text for wrong credentials; lock after 5 failures (15 min); `must_change_password` forces the change-password screen before anything else; a deactivated restaurant shows "This restaurant account is deactivated. Contact support."; subscription states never block login (they limit actions — 18.4).
- Platform login is also reachable directly at `/platform/login`.

### 22.2 Landing page and menu per role
| Role | Lands on | Sees |
|---|---|---|
| SUPER_ADMIN | `/platform` | everything in the platform console |
| SUPPORT | `/platform/tickets` | tickets, feedback, restaurants (read-only) |
| OWNER (Restaurant Admin) | `/reports/daily` | all restaurant screens + Subscription, Payment accounts, Delivery charges, Help |
| MANAGER | `/reports/daily` | as Owner except subscription changes, payment accounts, outlet creation |
| CASHIER | `/tables` | Tables, Orders, Bills, Delivery board (view/assign), Help |
| CAPTAIN | `/tables` | Tables, Orders |
| KITCHEN | `/kitchen` | Kitchen view |
| RIDER | `/rider` | Rider page |
| INVENTORY | `/inventory` (S27) when the plan has the `inventory` feature, otherwise `/menu` | Menu (read), item availability toggle, and with the `inventory` feature the inventory module (Section 26: stock, purchasing, wastage, counts, transfers, reports) |

Stream D screens (Sections 27–28): OWNER and MANAGER see all six (S35–S40); CASHIER sees S36 and the read-only list of its own intents in S38; KITCHEN sees S36 read-only with status buttons PREPARING/READY.

Offline status chip and queue badge are visible to every role that can work on a registered terminal (OWNER, MANAGER, CASHIER, CAPTAIN).

### 22.3 The rules the system enforces (one place to read them all)
**Configurable by the Restaurant Admin** (Settings): prices include tax or not · tax profiles/components · service charge % · round-off mode · cashier discount limit % · day-start hour · auto-print on payment · delivery charge rules · payment accounts · EOD email time/recipients · notification channels.
**Always enforced:**
| # | Rule | Section |
|---|---|---|
| 1 | Money is exact (BigDecimal/NUMERIC), rounded only where stated; the frontend never calculates bill totals **for online issue** (offline terminals use the golden-vector-tested port, 24.5) | 5.3 |
| 2 | One bill item can sit on only one active bill | 5.7 (DB-enforced) |
| 3 | Bill numbers are gapless per outlet/series/fiscal year, never reused | 5.5 (concurrency-tested) |
| 4 | Items sent to the kitchen can only be cancelled with a manager PIN and a reason | 5.2 |
| 5 | A cashier's discount above the configured limit needs a manager PIN; every discount needs a reason and is audited | 11.7 |
| 6 | Unpaid bills are voided by Manager/Owner; paid bills only by Owner; voided numbers stay used | 5.8 |
| 7 | A bill is paid only when payments sum to the total; no overpayment | 5.9 |
| 8 | UPI in manual mode is confirmed by a cashier who is recorded | 5.9, 21.3 |
| 9 | A table can have one active order (offline sync may create a flagged second one, 24.6) | 5.10 |
| 10 | After day close, no new orders/bills for that business date until the Owner reopens | 11.7 |
| 11 | Delivery statuses follow a fixed state machine | 11.1 |
| 12 | Delivery charge: radius → free-above → slab/flat; billed on one bill per order | 20.2 |
| 13 | Plan limits cap users, per-role users and outlets; disabled users do not count | 18.3 |
| 14 | Trial 30 days (plan default); then 7 days' grace; then read-only + settle | 18.4 |
| 15 | A restaurant always keeps ≥ 1 active Owner | 18.7 |
| 16 | A disabled user is locked out immediately | 18.7 |
| 17 | Only the Owner can change payment accounts; changes are emailed | 21.4 |
| 18 | Every request is tenant-scoped; cross-tenant access returns 404 | 3.3, 13.2 |
| 19 | Sensitive actions are audit-logged with who, what, before/after | 3.3 |
| 20 | Duplicate clicks/retries never create duplicates (idempotency keys) | 3.3 |
| 21 | A WhatsApp message is sent only with recorded customer consent, an approved template and a connected account; an opt-out blocks further sends | 23.5–23.7 |
| 22 | The WhatsApp access token is write-only: never returned, never logged | 23.3, 23.13 |
| 23 | A bill is sent to WhatsApp at most 5 times; delivery status shown is the webhook's, never assumed | 23.7 |
| 24 | A completed bill is never rejected or silently changed because of a sync conflict; conflicts are flagged | 24.5–24.6 |
| 25 | Bill numbers are never reused; a terminal's missing numbers are listed as gaps until they arrive or the Owner explains them | 24.4 |
| 26 | A refund is a credit note referencing the original bill; the bill itself is never edited | 25.12 |
| 27 | Ledgers, cash movements and credit notes are append-only | 25.10–25.12 |
| 28 | The price a customer saw on a line is the price on the bill (snapshot) | 25.5 |
| 29 | Billing is never blocked or slowed by stock: consumption failures are logged and retried | 26.7 |
| 30 | Stock quantity changes only through an append-only ledger | 26.3 |

### 22.4 No blank screens — frontend resilience rules
- A global **ErrorBoundary** wraps the app and each route; it renders ErrorState (message, **Retry**, **Copy error ID**, **Report this problem**) — never an empty page.
- Every route lazy-loads behind a skeleton (Section 12.2); unknown routes → 404 page; unauthorized → 403 page; expired session → modal that keeps the screen.
- API unreachable → persistent banner "We can't reach the server — retrying…" with exponential back-off (1 s → 30 s) and automatic recovery; mutating buttons disabled with a tooltip.
- A service-worker update shows "A new version is available — Refresh" instead of silently running stale code.
- **Test:** a Playwright suite visits every route while the API returns 500s, times out, or goes offline, and asserts that a heading, skeleton or ErrorState is always visible (never an empty body) and no uncaught console error occurs.

### 22.5 Routes added in Part II
Restaurant: `/settings/subscription`, `/settings/payment-accounts`, `/settings/delivery-charges`, `/help`, `/help/tickets/:id`.
Restaurant (Section 23): `/settings/whatsapp`; public: `/b/:token`.
Restaurant (Section 24): `/settings/devices`, `/sync/issues`.
Restaurant (Section 25): `/settings/coupons`, `/settings/price-rules`, `/settings/billing`, `/settings/central-menu`, `/shifts`, `/dues`, `/customers/:id/dues`, `/expo`, `/display`.
Restaurant (Stream D, Sections 27–28): `/settings/online-ordering` (S35), `/online-orders` (S36), `/online-orders/mapping` (S37), `/payments/attention` (S38), `/settings/compliance` (S39), `/settings/data` (S40).
Restaurant (Section 26): `/inventory`, `/inventory/items/:id`, `/inventory/recipes/:menuItem`, `/inventory/wastage`, `/inventory/counts/:id`, `/inventory/transfers`, `/inventory/production`, `/inventory/reports`, `/purchasing`, `/settings/inventory`.
Platform: `/platform/login`, `/platform`, `/platform/restaurants`, `/platform/restaurants/:id`, `/platform/plans`, `/platform/invoices`, `/platform/tickets`, `/platform/tickets/:id`, `/platform/feedback`, `/platform/settings`, `/platform/users`.
Design tokens `--platform`, `--platform-soft`, `--border-strong` are defined in Section 12.1 (contrast-checked).

---

## 23. WHATSAPP BILL DELIVERY *(added in v1.2)*

> **Goal:** after a bill is paid (or any time later), the cashier can send the bill to the customer on WhatsApp — automatically as a PDF when the number is on WhatsApp, and with sensible fallbacks when it is not. This is *Phase 2W*.

### 23.1 The honest constraint: "is this number on WhatsApp?" cannot be pre-checked
As of this plan, the official WhatsApp Business **Cloud API has no supported "is this number registered" lookup** that a restaurant billing app can call before sending (**not re-verified here — confirm against Meta's current documentation before building**; if Meta adds one, it can be slotted into step 3 below without changing the rest). Scraping or unofficial "number checker" tools violate WhatsApp's terms and put the restaurant's number at risk of a ban — **they are forbidden in this plan.**

So Galla uses **try → read the status → fall back**:
1. Cashier enters/confirms the customer's mobile number and ticks the consent box (23.5).
2. Galla normalises it to E.164 (`libphonenumber`, region = outlet country; reference: `reference/whatsapp.py`).
3. Galla sends the approved bill template with the PDF attached.
4. Meta's **webhook** reports `sent → delivered → read`, or `failed` with an error code. A number that is not on WhatsApp comes back as a failure (code **131026** "message undeliverable" — the same code is also used for other undeliverable reasons, so the UI says *"Could not be delivered on WhatsApp — the number may not be on WhatsApp"*, never a certain claim).
5. On failure, the Bill dialog and the Bills drawer show fallbacks: **Send by SMS/e-mail (if configured), "Share manually via WhatsApp" (wa.me link), Print, Show QR to the customer's phone** (public bill page, 23.4).
Only the webhook status is shown as truth: *Queued → Sent → Delivered → Read / Failed.* "Sent" is never shown as "delivered".

### 23.2 Two delivery modes
| Mode | When | How | Needs |
|---|---|---|---|
| **A. Automatic (API)** | The restaurant has connected its own WhatsApp Business number (23.3) and the plan includes `whatsapp_bills` | Server sends the template message with the bill PDF; status tracked by webhook | Meta Business account, approved template, consent |
| **B. Manual share** | No API connection, or API failed, or customer prefers it | Galla opens `https://wa.me/<number>?text=<message with public bill link>` in the cashier's WhatsApp (Web/app). The cashier presses send. | Nothing from Meta; the public bill page `/b/{token}` (23.4) |
Mode B works for every restaurant from day one; Mode A is the "automatic" experience. **Galla never sends from a shared Galla number on behalf of restaurants in v1** — each restaurant uses its own number/WABA, so messages show the restaurant's name and the restaurant owns its quality rating (see Open Decision 17.18).

### 23.3 Connecting a restaurant's WhatsApp number (Settings → WhatsApp)
Owner only. Table `whatsapp_accounts` (V011, 23.12): one account per outlet. Fields the Owner supplies: **WhatsApp Business Account ID, Phone-number ID, access token** (system-user token). Steps shown as a checklist with live status:
1. *Connect:* paste IDs + token → **Verify** (`POST /whatsapp/account/verify`) calls Meta to confirm the number, reads quality rating and messaging limit; sets `status=CONNECTED` or `ERROR` with a readable reason. The token is stored AES-GCM-encrypted (`WHATSAPP_TOKEN_ENCRYPTION_KEY`), is **never returned by any API**, never logged, and is masked in the UI ("•••• last 4").
2. *Create template:* **Create bill template** submits `galla_bill_v1` (23.6) to Meta; `bill_template_status` follows `PENDING → APPROVED/REJECTED` (webhook + a daily poll). Rejection reason is shown. **Sending is disabled until `APPROVED`.**
3. *Webhook:* the screen shows the callback URL (`{PUBLIC_BASE_URL}/webhooks/whatsapp`) and the verify token to paste into the Meta app (one platform-level Meta app in v1; see 17.18 for Embedded Signup as a later improvement).
4. *Test:* **Send test bill to my number** (uses the Owner's own number; consent is implied by the Owner doing it for themselves).
Until step 2 is `APPROVED`, the Bill dialog shows only Mode B and a hint "Set up automatic WhatsApp bills in Settings" (Owner/Manager only; others see Mode B without the hint).

### 23.4 Public bill page and share links
Table `bill_share_links`. `POST /bills/{id}/share-link` creates a random 128-bit token (URL-safe); **only the SHA-256 hash is stored**. URL: `{PUBLIC_BASE_URL}/b/{token}`; lifetime `outlets.bill_share_link_days` (default 90, max 365); revocable. The page (screen **S14**, no login) shows: restaurant name/address/tax registration labels, bill number, date, lines, discounts, taxes, service/delivery charge, round-off, grand total, payment status, **Download PDF**. It **never** shows: customer phone, staff names, internal notes, cost data, other bills. Responses: unknown/expired/revoked → `410 BILL_LINK_EXPIRED` page ("This bill link has expired. Please ask the restaurant."); `Cache-Control: no-store`, `noindex`, `Referrer-Policy: no-referrer`; rate-limited per IP (Bucket4j). Voided bills show a clear "VOID" banner. Tokens are compared by hash lookup (no timing leak), 404 and 410 pages look identical for unknown tokens.

### 23.5 Customer consent (required before any WhatsApp message)
Meta's policy requires the business to have the customer's **opt-in** before sending business-initiated messages, and local law (India: DPDP Act — **legal requirement not verified here; see 17.19**) may add duties. Galla therefore makes consent explicit and auditable:
- The Bill dialog shows a **required checkbox** (unchecked by default): *"Customer agrees to receive this bill on WhatsApp from {restaurantName}."* The exact sentence shown is stored in `customer_consents.statement_shown`, with who recorded it, when, method (`IN_PERSON`, `PAPER`, `STAFF_RECORDED`).
- Consent is **per phone number, per purpose** (`BILL`, `DELIVERY_UPDATES`) and **append-only**: the newest row wins (`reference/whatsapp.py::current_consent`; tie → highest sequence). Opt-out never deletes history.
- **Opt-out:** if the customer replies `STOP`, `UNSUBSCRIBE`, `CANCEL`, `NO` or `END` (case-insensitive, trimmed; list in `STOP_WORDS`), the webhook records `OPTED_OUT` (method `CUSTOMER_MESSAGE`); later sends to that number are refused with `WHATSAPP_CONSENT_REQUIRED` until a *new* in-person opt-in is recorded by staff. Staff can also record an opt-out the customer asks for.
- Delivery-update messages (`DELIVERY_UPDATES`) need their own consent; bill consent never covers marketing. **No promotional messages exist in this plan.**
- Template wording never contains promotions; category expected `UTILITY` (Meta decides; see 23.6).

### 23.6 Message template `galla_bill_v1` (submitted to Meta per restaurant account)
- Category requested: **UTILITY**; language `en` (additional languages: later). Meta may re-categorise it as MARKETING, which changes price and rules — `bill_template_category` stores what Meta reports, and the UI warns if it is not UTILITY.
- **Header:** document (the PDF). **Body** (4 variables):
  `Hi {{1}}, thank you for visiting {{2}}. Your bill {{3}} for {{4}} is attached.`
  `{{1}}` = customer name or "Guest"; `{{2}}` = outlet name; `{{3}}` = bill number; `{{4}}` = currency symbol + grand total (e.g. `₹1,240.00`).
- **Footer:** `Reply STOP to stop receiving bills.` No buttons in v1.
- Variables are sanitised by `clean_param` (reference): tabs/newlines removed, repeated spaces collapsed, trimmed, truncated to 40 chars, empty → "Guest". (Meta rejects newlines/tabs/4+ spaces in parameters — **stated from memory; verify**.)
- Template changes always create a new version name (`galla_bill_v2`…), never edit an approved one.
- Delivery-update templates (`galla_delivery_picked_up_v1`, `galla_delivery_delivered_v1`) follow the same rules and are enabled only with `DELIVERY_UPDATES` consent; they replace the SMS/stub path of Section 11.4 for restaurants that connect WhatsApp.

### 23.7 Sending flow (outbox worker)
`POST /bills/{id}/whatsapp` (header `Idempotency-Key` required; body `{phone, customerName?, consentConfirmed, method}`):
1. Authorise (CASHIER/MANAGER/OWNER of this outlet), the bill must be generated and not `VOID` → else `409 ILLEGAL_TRANSITION`.
2. Plan gate `whatsapp_bills` and subscription state (`@RequiresActiveSubscription`; read-only/after-grace blocks new sends: `402`).
3. Account must be `CONNECTED` and template `APPROVED` → else `409 WHATSAPP_NOT_CONFIGURED` / `409 WHATSAPP_TEMPLATE_NOT_APPROVED` (UI falls back to Mode B).
4. Normalise phone → `422 INVALID_PHONE_NUMBER` on failure. A syntactically valid but **non-mobile** number (landline, per libphonenumber type) returns a *warning* the cashier must confirm (`NOT_A_MOBILE_NUMBER`), not a hard error.
5. Consent: if `consentConfirmed` → append `OPTED_IN` row (if the newest row is not already opted-in); otherwise require an existing opt-in; opted-out ⇒ `422 WHATSAPP_CONSENT_REQUIRED`.
6. Resend limit: `can_resend` (max **5 sends per bill**) → `429 WHATSAPP_RESEND_LIMIT`.
7. In one DB transaction: insert `whatsapp_messages(QUEUED)` + `notification_outbox` row (`dedupe_key = "wa:bill:<billId>:<phone>:<idempotencyKey>"`). Respond `202` with the message id. The cashier is never blocked waiting for Meta.
8. Worker: render the bill PDF (the same `PrintDocument` HTML as Section 8, converted with an HTML-to-PDF library; ≤ 100 KB target, A5/80 mm-wide layout) → upload the media (or pass a short-lived link — **exact send-time JSON for a document header and media-id retention rules not verified; follow Meta's current docs**) → send the template → store `provider_message_id`, `status=SENT`.
9. Webhook `POST /webhooks/whatsapp` (23.8) updates the row; `merge_status` makes statuses monotonic: `QUEUED < SENT < DELIVERED < READ`; a late `FAILED` never downgrades `DELIVERED/READ`; a late `DELIVERED/READ` overrides an earlier `FAILED`.
10. Failures are classified by `classify_failure(code)`: **131026** undeliverable → no retry, show fallbacks; **130429** rate limit → retry with back-off; **132000/132001** template/parameter problem → no retry, alert Owner ("template needs attention"); **131048** account restricted → alert Owner; **131047** re-engagement window closed → alert (should not occur with templates); unknown → retry. **At most 3 attempts** (`MAX_ATTEMPTS`) then `FAILED`.
11. SSE event `whatsapp.status` updates the open Bill dialog/drawer in real time.

### 23.8 Webhook endpoint (public, signature-verified)
- `GET /webhooks/whatsapp` — Meta's subscription verification (`hub.mode`, `hub.verify_token`, `hub.challenge`): compare the token in constant time; echo the challenge.
- `POST /webhooks/whatsapp` — **verify the HMAC-SHA256 signature header against the raw request body with the app secret (`WHATSAPP_APP_SECRET`) in constant time; reject with 401 before parsing** (header name and format: *verify in Meta docs — not verified here*). Persist the event in `whatsapp_webhook_events` (unique `event_key` ⇒ Meta retries are idempotent), return **200 fast**, process asynchronously. Handles: message statuses, template status updates, quality/limit updates, inbound messages (only to detect STOP words — **inbound message text is not stored** beyond the opt-out record).
- Account is located by `phone_number_id` in the payload; unknown ids are acknowledged and ignored.

### 23.9 Limits, quality and cost
- **Messaging limits:** a new/unverified number can start at a low number of unique customers per 24 h (commonly **250**; tiers 250 → 2 000 → 10 000 → 100 000 → unlimited — *tier names and values from Meta's documentation as I understood it; verify*). Galla shows `used / limit` from `unique_recipients_24h` and `limit_state`: **OK, WARN at ≥ 80 %, AT_LIMIT** (new sends switch to Mode B with a banner), **UNKNOWN** if Meta did not report a tier.
- **Quality rating:** shown in Settings; if it drops (e.g. many blocks), the Owner sees a warning. Sending bills to people who did not ask for them is the fastest way to lose the number — hence the consent rule.
- **Cost:** Meta charges per message depending on category and country; **India rates and free-window rules were not verified**. v1 decision (Open Decision 17.17): the restaurant pays Meta directly through its own WhatsApp Business account; Galla's plans include the feature, not the message fees. `GET /reports/whatsapp-usage` shows counts by status/day so the owner can reconcile with Meta's bill.
- **Template pause/disable by Meta** → status `PAUSED`/`DISABLED` → automatic Mode B + Owner alert.

### 23.10 API summary (all tenant-scoped, 404 cross-tenant)
| Method & path | Role | Notes |
|---|---|---|
| `GET /whatsapp/account` | OWNER, MANAGER | status, template status, quality, limit; **never the token** |
| `PUT /whatsapp/account` | OWNER | set WABA id, phone-number id, token (write-only) — audited |
| `POST /whatsapp/account/verify` | OWNER | calls Meta; updates status |
| `POST /whatsapp/account/bill-template` | OWNER | create/submit `galla_bill_v1` |
| `GET /whatsapp/account/bill-template` | OWNER, MANAGER | status + rejection reason |
| `DELETE /whatsapp/account` | OWNER | disconnect; keeps history; audited |
| `POST /bills/{id}/whatsapp` | CASHIER, MANAGER, OWNER | 202; Idempotency-Key required |
| `GET /bills/{id}/whatsapp-messages` | CASHIER, MANAGER, OWNER | status history |
| `POST /bills/{id}/share-link` | CASHIER, MANAGER, OWNER | returns `url` + `wa.me` URL |
| `DELETE /bills/{id}/share-links` | MANAGER, OWNER | revoke all |
| `GET /public/bills/{token}`, `/pdf` | public | rate-limited, 410 when expired |
| `GET/POST /consents` | CASHIER+ | lookup newest by phone; record opt-in/out |
| `GET/POST /webhooks/whatsapp` | Meta | 23.8 |
| `GET /reports/whatsapp-usage` | MANAGER, OWNER | per day/status counts, failures by code |
New error codes (Appendix B): `WHATSAPP_NOT_CONFIGURED` (409), `WHATSAPP_TEMPLATE_NOT_APPROVED` (409), `WHATSAPP_CONSENT_REQUIRED` (422), `INVALID_PHONE_NUMBER` (422), `WHATSAPP_RESEND_LIMIT` (429), `BILL_LINK_EXPIRED` (410), `FEATURE_NOT_IN_PLAN` (402, existing).

### 23.11 UI specification
**Bill dialog — after payment (Step 3 "Done")**, panel "Send bill":
- Phone field with country-code select (default outlet country, `+91`), inline validation, remembers nothing between customers. If the order already has a customer with a phone, it is pre-filled.
- Optional name field (pre-filled).
- Consent checkbox (required) with the exact sentence; button **Send on WhatsApp** (primary) is disabled until phone is valid and the box is ticked; **Share manually** (secondary) opens wa.me; **Print** remains primary on the print row.
- After sending: a status chip **Queued → Sent → Delivered → Read** (icon + text, never color alone); on failure a red-text message "Could not be delivered on WhatsApp — the number may not be on WhatsApp" with buttons *Share manually*, *Send by e-mail/SMS* (if configured), *Try another number*.
- `outlets.whatsapp_bill_prompt = false` hides the panel by default (it remains reachable from the Bills drawer).
**Bills drawer:** "WhatsApp" row with last status and **Resend** (confirmation dialog showing the number; blocked after 5).
**Settings → WhatsApp (screen S15, Owner):** the checklist of 23.3 with status chips, template text preview, limit meter (`used/limit`), quality rating, "Send test bill", Disconnect (confirm dialog).
**Public bill page S14:** brand header, bill table, totals, Download PDF; mobile-first; works without JS for reading.
Empty/error/loading states for every panel follow Section 12.2; **the dialog never becomes blank if Meta or the network fails** — it shows the status chip with the fallbacks.

### 23.12 Database — Migration V011 *(verified on PostgreSQL 16 on top of V001–V010: 27 accept/reject cases pass)*
```sql
-- V011 — WhatsApp bill delivery: restaurant's WhatsApp account, consent history, message log, public bill links
CREATE TABLE whatsapp_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  provider text NOT NULL DEFAULT 'META_CLOUD' CHECK (provider IN ('META_CLOUD')),
  waba_id text NOT NULL,                          -- WhatsApp Business Account id
  phone_number_id text NOT NULL,                  -- Cloud API phone-number id (not the phone number itself)
  display_phone text,
  access_token_encrypted text NOT NULL,           -- AES-GCM with WHATSAPP_TOKEN_ENCRYPTION_KEY; never returned by any API
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','CONNECTED','ERROR','DISABLED')),
  last_error text,
  quality_rating text,                            -- as reported by Meta (e.g. GREEN/YELLOW/RED); informational
  messaging_limit text,                           -- e.g. TIER_250; informational, refreshed daily
  bill_template_name text NOT NULL DEFAULT 'galla_bill_v1',
  bill_template_language text NOT NULL DEFAULT 'en',
  bill_template_status text NOT NULL DEFAULT 'NOT_CREATED' CHECK (bill_template_status IN ('NOT_CREATED','PENDING','APPROVED','REJECTED','PAUSED','DISABLED')),
  bill_template_category text,                    -- as reported by Meta; expected UTILITY
  bill_template_rejection_reason text,
  last_verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (outlet_id),                             -- v1: one WhatsApp account per outlet
  UNIQUE (phone_number_id)
);

CREATE TABLE customer_consents (                  -- append-only history; the newest row per (phone, channel, purpose) is the current state
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  phone_e164 text NOT NULL CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  channel text NOT NULL CHECK (channel IN ('WHATSAPP')),
  purpose text NOT NULL DEFAULT 'BILL' CHECK (purpose IN ('BILL','DELIVERY_UPDATES')),
  status text NOT NULL CHECK (status IN ('OPTED_IN','OPTED_OUT')),
  method text NOT NULL CHECK (method IN ('IN_PERSON','PAPER','CUSTOMER_MESSAGE','STAFF_RECORDED')),
  statement_shown text NOT NULL CHECK (length(btrim(statement_shown)) > 0),   -- exact wording the customer agreed to, incl. the restaurant name
  recorded_by uuid REFERENCES users(id),          -- NULL when the customer opted out by replying
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CHECK (method <> 'CUSTOMER_MESSAGE' OR status = 'OPTED_OUT'),
  CHECK (method = 'CUSTOMER_MESSAGE' OR recorded_by IS NOT NULL)
);
CREATE INDEX ix_consents_lookup ON customer_consents(tenant_id, phone_e164, channel, purpose, recorded_at DESC);

CREATE TABLE whatsapp_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  account_id uuid NOT NULL REFERENCES whatsapp_accounts(id),
  kind text NOT NULL CHECK (kind IN ('BILL','DELIVERY_UPDATE')),
  bill_id uuid REFERENCES bills(id),
  delivery_id uuid REFERENCES deliveries(id),
  outbox_id uuid REFERENCES notification_outbox(id),
  to_phone text NOT NULL CHECK (to_phone ~ '^\+[1-9][0-9]{6,14}$'),
  template_name text NOT NULL,
  provider_message_id text,                       -- Meta's message id, used to match status webhooks
  status text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','SENT','DELIVERED','READ','FAILED')),
  attempts int NOT NULL DEFAULT 0,
  error_code text,
  error_text text,
  requested_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz, delivered_at timestamptz, read_at timestamptz, failed_at timestamptz,
  CHECK (kind <> 'BILL' OR bill_id IS NOT NULL),
  CHECK (kind <> 'DELIVERY_UPDATE' OR delivery_id IS NOT NULL)
);
CREATE UNIQUE INDEX ux_wa_msg_provider_id ON whatsapp_messages(provider_message_id) WHERE provider_message_id IS NOT NULL;
CREATE INDEX ix_wa_msg_bill ON whatsapp_messages(bill_id) WHERE bill_id IS NOT NULL;
CREATE INDEX ix_wa_msg_recent ON whatsapp_messages(outlet_id, created_at DESC);

CREATE TABLE whatsapp_webhook_events (            -- dedupes Meta's retries
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,                 -- e.g. "<wamid>:<status>:<timestamp>" or the inbound message id
  payload jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

CREATE TABLE bill_share_links (                   -- public read-only bill page for the customer (and for manual wa.me sharing)
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  bill_id uuid NOT NULL REFERENCES bills(id),
  token_hash text NOT NULL UNIQUE,                -- SHA-256 of the url token; the token itself is never stored
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_viewed_at timestamptz,
  view_count int NOT NULL DEFAULT 0 CHECK (view_count >= 0)
);
CREATE INDEX ix_share_links_bill ON bill_share_links(bill_id);

ALTER TABLE outlets
  ADD COLUMN whatsapp_bill_prompt boolean NOT NULL DEFAULT true,      -- show the "Send on WhatsApp" panel after payment
  ADD COLUMN bill_share_link_days int NOT NULL DEFAULT 90 CHECK (bill_share_link_days BETWEEN 1 AND 365);
```
Constraint tests that passed (27 cases): one account per outlet; unique `phone_number_id`; invalid account/template status rejected; E.164 regex rejects missing `+`, spaces, leading `0`; `CUSTOMER_MESSAGE` can only opt out; staff-recorded consent needs the recording user; blank consent statement rejected; BILL message needs `bill_id`; DELIVERY_UPDATE needs `delivery_id`; duplicate `provider_message_id` rejected but many `NULL`s allowed (queued rows); duplicate webhook event key rejected; duplicate share-link token hash rejected; negative view count and `bill_share_link_days = 0` rejected; newest-consent query returns the opt-out.

### 23.13 Security and privacy
- Access token encrypted at rest, write-only, never logged; webhook verified by signature; verify-token compared in constant time.
- Phone numbers are personal data: shown masked (`+91 ••••• ••210`) in lists and logs; full number only in the send dialog and the message detail for authorised roles. Webhook payloads stored in `whatsapp_webhook_events` are purged after 30 days by a daily job (retention numbers are **my default — confirm in 17.19**).
- Public bill link: random 128-bit token, hash stored, expiry, revocation, rate limit, `noindex`, no personal data of the customer on the page.
- Tenant isolation: every query filters by `tenant_id`; webhook resolves the tenant from the stored account only.
- Audit log: connect/disconnect, token change, template creation, consent records, manual resend.
- Plan feature flag `whatsapp_bills` (`plans.features`), default off in the dev seed for the lowest plan.
- Environment variables: `WHATSAPP_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_TOKEN_ENCRYPTION_KEY`, `WHATSAPP_GRAPH_BASE_URL` (default Meta Graph API; overridable so tests use a fake server), `WHATSAPP_API_VERSION` (pinned; upgrade deliberately).

### 23.14 Tests (what the implementing agent must write)
- **Reference vectors (executable now):** `reference/test_whatsapp.py` **W1–W12** — phone normalisation (valid, invalid, non-mobile), wa.me URL encoding, parameter cleaning, newest-consent-wins incl. same-instant tie, STOP words, status monotonic merge, failure classification, 24-hour unique-recipient counting, limit thresholds, resend cap. Port them to Java 1:1.
- **Integration (Testcontainers + a fake Meta server):** send → webhook `sent/delivered/read` updates the row; webhook replay is idempotent; invalid signature → 401 and nothing stored; `failed 131026` → no retry, fallbacks visible; `130429` → retried then succeeds; token never appears in any response or log line (log-capture test); cross-tenant message id → 404; opted-out number refused; unapproved template refused; double click with the same Idempotency-Key = one message.
- **E2E 25:** connect account (fake Meta) → template APPROVED → pay a bill → tick consent → send → chip goes Queued → Sent → Delivered → Read; resend; STOP reply → next send refused.
- **E2E 26:** number not on WhatsApp (fake Meta returns 131026) → red message + fallbacks → *Share manually* opens a `wa.me` link whose text contains a working `/b/{token}` link → public page opens, shows totals equal to the bill; expired link → 410 page.
- **E2E 27:** no WhatsApp account connected → only Mode B is offered; plan without `whatsapp_bills` → `402 FEATURE_NOT_IN_PLAN` for API mode.
- **Not testable without Meta:** real template approval, real delivery to a handset, real rates and limits — a manual checklist in `docs/WHATSAPP_GO_LIVE.md` (agent to create) with 5 steps: create Meta app + WABA, add number, create template, send to 3 real phones (one not on WhatsApp), confirm webhook statuses.

---

## 24. OFFLINE MODE *(added in v1.3)*

> **Goal:** a billing terminal keeps working when the internet is down — orders, KOT, bills, payments and printing — and everything is delivered to the server later, exactly once, without losing or silently changing a bill. This is *Phase 2O*. It replaces the old "Offline (v1): banner only" rule (Section 12.6).

### 24.1 What "offline" means here — and what it does not
- **Per terminal.** Each registered terminal (a browser profile on the counter PC/tablet, installed as a PWA) keeps its own local copy of the data it needs and its own queue of work to send. **Terminals do not see each other while offline** (no LAN sync in v1). An optional on-premise relay that lets terminals share state without internet is a later phase (Open Decision 24).
- **Recommendation, not enforcement:** during an outage let **one designated terminal** bill per outlet. Two terminals can bill offline at the same time — the design survives it (separate bill series, conflicts flagged, nothing dropped) — but staff will not see each other's tables.
- **Kitchen screens do not update offline** (Section 12.4 S8 is online-only). The printed KOT is the kitchen's channel during an outage.
- **No data is invented.** If a terminal has never synced (no catalog snapshot), it cannot work offline and says so (24.3).
- **Not a backup.** Unsynced data lives only in that browser. Section 24.9 lists how it is protected and what is *not* guaranteed.

### 24.2 What works offline, what is blocked, and why
| Action | Offline? | Reason / rule |
|---|---|---|
| Open an order, add/edit draft lines, modifiers, notes, table transfer of the terminal's own orders | ✔ | Uses the local catalog/table snapshot |
| Send KOT (prints on the LAN thermal printer through the print agent, 24.8) | ✔ | Printing needs no internet. KOT shows the device KOT number, e.g. `A-07` |
| Generate bill, cashier-limit discount, service/packaging/delivery charges already configured | ✔ | Totals computed on the terminal by the ported `BillCalculator` (24.5) |
| Coupon | ✘ (blocked) | Coupon validation needs the server because redemption limits are global (Section 25.4, Decision 33). The button shows the reason. *(Replaces an earlier row that allowed coupons from a cached list.)* |
| Cash / card (manual) payment, change calculation | ✔ | No third party involved |
| UPI with the restaurant's own QR (manual confirmation) | ✔ | The `upi://` QR with the locked amount is built on the terminal from the stored UPI ID; the cashier confirms receipt (21.3) |
| Print / reprint bill | ✔ | Local print agent, or browser print |
| Send bill on WhatsApp | ✔ *queued* | Becomes a `WHATSAPP_BILL_SEND` command; sent after the bill has synced, using the consent captured at the counter (23.5). The panel shows "Will send when online" |
| Shift open | ✔ *queued* | Same rule (cashier shifts are defined in Section 25.10) |
| Shift close, refunds / credit notes, complimentary (NC) bills, customer-dues settlements, central-menu publishing | ✘ | Need the server (and a manager PIN where stated); the reason is shown |
| Combos, price-rule snapshots, open items (if permitted), packaging charge, tips | ✔ | Pure local calculation on the snapshot (Section 25) |
| `ON_ACCOUNT` payment | ✔ **only if** the customer's cached credit headroom allows | Otherwise blocked; the limit is re-checked at sync (Section 25.11) |
| Anything that needs a **manager PIN** (cancel after KOT, discount above the cashier limit, void, refund, price edit) | ✘ | The PIN hashes of managers are **not** stored on terminals (stolen-device risk). Buttons show "Needs internet and a manager" |
| Day close, reopen day | ✘ | Needs the complete picture from all terminals |
| Users, plans, subscription, settings, tax, menu edits | ✘ | Must be authoritative and audited |
| Delivery map, rider tracking, assignment | ✘ | Live data by nature |
| Online payment providers (provider QR/webhook) | ✘ | Confirmation comes from the provider |
| Reports, EOD e-mail, AI summary | ✘ | Computed by the server from synced data (a local "today on this terminal" tally is shown, labelled *not final*) |
| Login of a new user, password change | ✘ | Needs the server (24.7) |

### 24.3 Local data on the terminal
- **PWA + service worker** (vite-plugin-pwa / Workbox): app shell, fonts, icons precached; **updates never swap the app mid-queue** — a new version waits until the queue is empty or the cashier presses "Refresh".
- **IndexedDB through Dexie** (stores): `snapshot` (outlet settings, tax profiles, catalog, tables, printers/agent address, payment accounts incl. UPI ID, `price_rules`, `combo_components`, `outlet_menu_versions.version`, outlet billing settings (packaging, tips, credit, shifts; no coupons), `catalogVersion`, `fetchedAt`), `orders`, `kots`, `bills`, `payments`, `outbox` (commands), `counters` (bill/order/KOT counters per fiscal year/business date), `session` (last online validation time, last seen client time, quick-PIN hashes), `log` (last 500 sync events).
- **Snapshot:** `GET /sync/snapshot` (full) and `GET /sync/pull?since=<version>` (delta) with `ETag`/version; refreshed on login, every 5 minutes while online, and after every successful push.
- **Persistence:** the app calls `navigator.storage.persist()` at first run and shows a warning if the browser refuses (data could be evicted under storage pressure). Whether every browser honours it is **not verified** (Open Decision 28).
- **Queue badge** in the top bar: "7 waiting to sync" (icon + text), turning amber after 1 hour unsynced and red after 12 hours.
- **Logout / clear-data guard:** sign-out and "clear data" are blocked while the outbox is not empty ("7 bills are not on the server yet"). An Owner/Manager can override only after **Export unsynced data** (a JSON file with the whole outbox and local documents) has been downloaded.
- **Emergency export:** Settings → Sync → *Export unsynced data*; the same button appears on the lock screen (24.7), so a locked terminal never traps data.
- **Payload versions:** every command carries `schemaVersion`; the server accepts the **current and the previous** version (24.6). A terminal on an older app version is shown "Update needed" but can still deliver.

### 24.4 Terminals ("devices") and numbering
**Registering a terminal** (Owner/Manager, Settings → Devices): *Add terminal* → name ("Counter 1") and a **series code** (1–3 characters, upper-case, starts with a letter, not `B`) → a **one-time pairing code** (valid 30 minutes, only its hash is stored). On the terminal: Settings → *Pair this terminal* → enter the code → the server returns a **device key** once (stored hashed on the server; kept in IndexedDB on the terminal). Series codes are unique per outlet and **never reused**, even after the terminal is revoked.

**Bill numbers on registered terminals.** Bill numbers keep the format of Section 5.5 — `series-fiscalYear-sequence` — but a registered terminal uses **its own series** (e.g. `A-2026-27-000041`) and **allocates the sequence itself from a local counter, always — also when online**. (If online and offline bills came from different counters, the same terminal could not tell whether a number is free.) Online-only browsers (not registered) keep the server-allocated default series `B` and the atomic upsert of Section 5.5 — **that path is unchanged.**

How this fits the existing design (V004 / Section 5.5):
- `UNIQUE (outlet_id, series, fiscal_year, bill_seq)` and `UNIQUE (outlet_id, bill_number)` still guarantee that **no number is ever stored twice**. A bill pushed again is a duplicate and is answered `DUPLICATE`.
- For a device series, `bill_counters.last_no` means "**highest sequence the server has seen**", not "last issued by the server". The server never increments it itself for a device series.
- At sync, `register_seq` (reference: `sync_rules.py`) compares the arriving sequence with `last_no`: **in order** → nothing to do; **ahead of `last_no + 1`** → the skipped range is recorded in `bill_number_gaps` (`OPEN`, cause `NOT_YET_SYNCED`) and an `INFO/WARN` `NUMBER_GAP` conflict is created; **inside an open gap** → the gap shrinks, splits or closes (`FILLED`); inside an *explained* gap → accepted and flagged; **otherwise** → duplicate.
- A gap is not an error by itself: the missing bill may simply still be on its terminal. The Owner sees *Gaps* (S17) and must either wait until it fills or **explain** it (≥ 5 characters, recorded with name and time).
- **Day close warns** while any gap is `OPEN` for that outlet (not a hard block; the Owner can close with the warning acknowledged).

**Order and KOT numbers.** `orders.order_no` and `kots.kot_no` are server counters per outlet/business date and cannot be issued offline. An offline order therefore gets a **device order number** (`device_order_no`, e.g. `A-12`) printed on the KOT and shown on screen; the server assigns the normal `order_no` at sync, and the UI then shows both (`#45 · A-12`). The same holds for KOTs (`device_kot_no`). Both device numbers are unique per `(device, business date)`.

**Terminal storage lost** (browser data cleared, PC replaced): an Owner generates a **re-pairing code**; the terminal pairs again (same series code, `registration_count + 1`) and asks for `resume_seq`. Because bills issued after the last sync cannot be known, it resumes at **max(last synced, last reported by heartbeat) + 10 + 1** (the *safety skip* is configurable, default 10) so a number the customer may already hold is never reused. The skipped range becomes an `OPEN` gap with cause `STORAGE_LOST`. Heartbeats (every 60 s when online) report the terminal's local counter and queue length for exactly this reason.

**Revoking a terminal** (lost/stolen): `status = REVOKED`; its device key stops working immediately. Commands that it created **before** the revocation time may still be delivered for **7 days** through an Owner-approved *final sync* (e.g. a re-paired replacement exporting the file) — the reference rule is `revoked_device_accepts`. Anything created after revocation is rejected.

**What is NOT guaranteed — read this before launch:**
1. *Legal acceptability of several bill series per outlet* (one per terminal) under Indian invoicing rules is **not verified**. If a single consecutive series is mandatory, the fallback is a **number-block lease** per terminal (each terminal reserves a block of sequences while online, unused numbers at the end of the day are void-booked) — Open Decision 22.
2. "Gapless" is guaranteed **only for the default series `B`**. For device series the guarantee is: *no number reused, and no number silently missing* — every missing number is listed until it arrives or is explained.
3. Unsynced bills in a destroyed browser are lost; the gap list proves they existed, not what they contained.

### 24.5 Calculating on the terminal (amends Section 3.3 rule 1 and 22.3 rule 1)
**Amended rule 1:** *the frontend never calculates bill totals **for online issue**; the server's `BillCalculator` is the only authority. A registered terminal calculates totals **only while offline** (and for the offline preview), using a TypeScript port of the same algorithm.* An online terminal always asks the server (`POST /bills`), which returns the numbers to print.

**Parity is enforced by shared golden vectors, not by hope:**
- `reference/gen_golden.py` runs `bill_calculator.py` on **424 cases** (the 11 plan vectors, packaging-charge vectors X1–X4, edge cases such as 100 % discount, half-paise tax, three-way tax split, and 400 seeded-random cases covering inclusive/exclusive tax, percent/amount discounts, service, delivery and packaging charges, both round-off modes) plus 18 device-rule cases (fiscal-year labels, business dates incl. day-start hour and time zones) and writes `golden_bill_vectors.json` (all money as strings).
- `reference/billCalculator.mjs` is the JS port (decimal.js pinned to 10.4.3, precision 28, explicit HALF_UP rounding, canonical line-id sort); `reference/test_golden.mjs` must reproduce **every** vector exactly. **Result when written: 443 checks passed, 0 failed.**
- **CI contract:** the same JSON file is loaded by a Java test (`BillCalculator`) and by a Vitest test (`billCalculator.ts`). A change to the calculator that changes any expected value fails both until the vectors are regenerated and reviewed.
- The TypeScript port lives in `frontend/src/lib/billing/` and may be used **only** by the offline path (ArchUnit-style lint: the online bill screen imports no calculator).
- The terminal needs three more local rules: fiscal-year label (5.5), business date from the outlet time zone and `day_start_hour` (5.6), and the bill-number format — all in `deviceRules.mjs`, covered by the same golden file.

**At sync the server recomputes** each offline bill from the lines the terminal sent and compares. The bill is **always accepted as issued** — the customer already holds that paper — and stored with the terminal's numbers. If the server's totals differ, or the terminal's own document is internally inconsistent (line totals do not add up), a **`CALC_MISMATCH` conflict (severity CRITICAL)** records both sets of numbers for the Owner and for engineering. **Nothing is silently changed.** Fix path: the Owner can void and re-issue through the normal flow (online, manager PIN).

### 24.6 Sync protocol
**Commands.** Everything the terminal does is stored as an immutable command in the outbox, with: `commandId` (UUID), `deviceSeq` (the terminal's own counter), `type`, `schemaVersion`, `aggregateType/aggregateId`, `dependsOn` (a commandId), `clientCreatedAt`, `payload`. Types: `ORDER_OPEN`, `ORDER_UPDATE`, `KOT_SEND`, `BILL_GENERATE`, `PAYMENT_ADD`, `PAYMENT_CONFIRM`, `WHATSAPP_BILL_SEND`, `SHIFT_OPEN`, `SHIFT_CLOSE`, `PRINT_LOG` (the list is extended by later sections; the DB only requires `UPPER_SNAKE`).

**Push.** `POST /sync/push` with up to 50 commands, in `deviceSeq` order. For each command the server answers one of:
| Result | Meaning |
|---|---|
| `APPLIED` | stored and applied |
| `DUPLICATE` | this `commandId` was already processed — the earlier result is returned (idempotency, `UNIQUE (tenant_id, command_id)`); same id with a different payload hash → `REJECTED / COMMAND_ID_REUSED` |
| `CONFLICT_FLAGGED` | applied, and one or more `sync_conflicts` were created |
| `WAITING_DEPENDENCY` | the command it depends on has not arrived (can happen after a parked command or a lost batch); retried by the server as soon as the dependency is applied — in any order of arrival the final state is the same (property test OF20) |
| `REJECTED(reason)` | **only protocol violations**: `UNKNOWN_DEVICE`, `DEVICE_REVOKED`, `UNSUPPORTED_SCHEMA_VERSION`, `SERIES_MISMATCH` (bill number not in the terminal's series), `BILL_NUMBER_MALFORMED`, `COMMAND_ID_REUSED`, `SUBSCRIPTION_INACTIVE` for commands created after the subscription's enforcement time. **The payload is always kept** (visible to the Owner, can be retried by the Owner after the cause is fixed — `POST /sync/commands/{id}/retry`). |

**Business-rule conflicts never reject a completed bill.** They are flagged (table `sync_conflicts`, screen S17):
| Conflict | When | Severity | What the server does |
|---|---|---|---|
| `TABLE_CONFLICT` | two orders on one table whose offline lifetimes overlap (decided by **client** times, so it does not depend on arrival order: the earlier-opened order is the main one, the later is flagged) | WARN | both orders kept; the later has `needs_attention = true` with a reason; the floor view shows "2 orders on T1 — needs attention"; Manager resolves with **Merge** (5.11) or leaves them |
| `ITEM_INACTIVE` | an item on the bill was deactivated/removed after the snapshot | INFO | bill kept as issued |
| `PRICE_CHANGED` | the server's current price differs from the price the terminal used | INFO | bill kept as issued (the line price is a snapshot anyway) |
| `CALC_MISMATCH` | 24.5 | CRITICAL | bill kept as issued |
| `NUMBER_GAP` | 24.4 | WARN | gap recorded |
| `CLOCK_SKEW` | terminal clock differs from the server by > 15 minutes (`devices.clock_skew_seconds`) | WARN | `client_created_at` kept; the business date from the terminal is kept but shown in the conflict so the Owner can check |
| `USER_DEACTIVATED` | the user who issued the bill was disabled before it synced | WARN | bill accepted (the customer has it); the conflict lets the Owner check what happened |
| `LATE_FOR_CLOSED_DAY` | the bill's business date is already closed (rule 10 in 22.3) | WARN | bill accepted into its **original** business date; the Owner is notified; a "late bills added" notice (not a second full EOD e-mail) is queued with dedupe key `eod:<outlet>:<date>:late:<n>` |

**Ordering and dependencies.** One terminal's commands are sent in `deviceSeq` order. A `BILL_GENERATE` depends on its `ORDER_OPEN`/`KOT_SEND`, a `PAYMENT_ADD` on its `BILL_GENERATE`, `WHATSAPP_BILL_SEND` on the bill. Different aggregates are independent.

**Retry, back-off and poison commands (client).** Network failure → retry with back-off 5 s, 10 s, 20 s … capped at 5 minutes (`backoff_seconds`). A command that the server answers with a non-retryable error, or that fails **5 times**, is **parked** (status `PARKED`, shown in Settings → Sync with the error and a *Retry* / *Export* button). A parked command blocks **only the commands that depend on it**; everything independent keeps flowing (`next_runnable`). The terminal never deletes a parked command.

**Pull.** After a successful push the terminal pulls the delta (`GET /sync/pull?since=`) to learn server-assigned `order_no`s, bill states changed elsewhere and the new catalog version. Local documents are marked `synced`.

**Heartbeat.** `POST /sync/heartbeat` every 60 s when online: queue length, local bill counter and fiscal year, app version, client clock. Day close (S12) uses it: *"Terminal A reported 3 unsynced bills 12 minutes ago"* — a readiness warning (Section 24.11).

Offline-synced bills consume stock at sync, dated with the sale's business date and using the recipe version effective at the sale time (Section 26.7). A bill for an already-closed day is consumed with its own date and shown as *late* in the next Consumption report; the closed day's EOD is not rewritten.

### 24.7 Sign-in, session and clock while offline
- **Sign in first.** A user must have signed in on that terminal while online before going offline (no offline first login).
- **Offline session length:** `outlets.offline_max_hours` (default **72**, 1–720, Owner setting). The clock starts at the **last successful online validation** of the session. After that the terminal shows the **Locked** screen: read-only view of local data, **Export unsynced data**, and "Connect to the internet to continue".
- **Subscription:** the last known subscription state is cached. The offline period **never extends past the subscription's enforcement time** (e.g. read-only after the grace period, 18.4): the deadline is the *earlier* of the two (`session_state`).
- **Clock tampering:** the terminal stores the highest client time it has seen. If the clock later reads more than 5 minutes **earlier**, the terminal locks (`CLOCK_MOVED_BACKWARDS`) until it is online again. This stops "set the clock back to keep working", it cannot stop every manipulation — the server still compares client and server time at every contact (`CLOCK_SKEW`).
- **Quick-PIN for switching cashiers offline:** each user who has signed in on the terminal may set a 4–6 digit **terminal PIN**. Only a salted **PBKDF2-HMAC-SHA256** hash is cached, **on that terminal only**, never the password and never manager override PINs. 5 wrong PINs disable the quick-PIN until the user signs in with the password while online. Iteration count: follow current OWASP guidance at build time (the reference uses 600 000 as a placeholder — **not verified**).
- **Deactivated users:** a user disabled on the server cannot be noticed by an offline terminal until it reconnects (that is the price of offline work). Their offline bills are **accepted** and flagged `USER_DEACTIVATED`; on the next contact the terminal signs them out and drops their quick-PIN.
- **Business date on the terminal:** computed from the outlet time zone and `day_start_hour` (5.6), stored with each document; the terminal's date can differ from the server's only if its clock is wrong (`CLOCK_SKEW`).

### 24.8 Printing without the internet
- **Print agent, loopback mode.** The agent (Section 8.6) additionally listens on `127.0.0.1` (default port 9171) with a **pairing token** shown once in the agent and pasted into Settings → Printers on the terminal. The browser sends the `PrintDocument` (JSON, never raw bytes from untrusted input) directly to the agent, which encodes ESC/POS and writes to the LAN/USB printer exactly as for server jobs. KOT and bill printing therefore work with the internet down, provided the printer is on the LAN or USB.
- **Fallback:** browser print of the same `PrintDocument` HTML (Section 8.5).
- The loopback endpoint requires the token on every request, rejects requests whose `Origin` is not the app's origin, accepts only the two document types, and never exposes printer addresses to the page. Whether all browsers allow an HTTPS page to call a loopback address (mixed-content and private-network-access rules) is **not verified**; the agent can serve HTTPS with a locally generated certificate if needed (Open Decision 28).
- Offline prints are **not** recorded as `print_jobs` on the server; the terminal logs them and sends a `PRINT_LOG` summary at sync (reprint stamp `** DUPLICATE **` still applies and is decided locally: any second print of a bill).

### 24.9 Protecting data that has not reached the server yet
- Unsynced data sits in IndexedDB **unencrypted** (browser-level protection only). Customer phone numbers and names may be in it. Mitigations: lock screen after inactivity (default 10 min, quick-PIN to continue), outbox purged only after the server confirmed, nothing sensitive in the service worker cache, and the *emergency export* file is plain JSON — treat it like a cash drawer key (Open Decision 25: encrypting local data with a key derived from the PIN).
- A **stolen terminal** is handled by revoking it (24.4); data already on it cannot be recalled.
- **Lost browser data** loses unsynced bills; mitigation: the badge and amber/red ageing (24.3), heartbeat-reported queue length visible to the Owner, and the gap list.

### 24.10 API summary (tenant-scoped, 404 cross-tenant; terminal endpoints need the user token **and** the device key header `X-Device-Key`)
| Method & path | Role | Notes |
|---|---|---|
| `GET /devices`, `POST /devices` | OWNER, MANAGER (view) / OWNER (create) | name + series code → pairing code shown once |
| `POST /devices/{id}/pairing-code` | OWNER | new code (also used for re-pairing after storage loss) |
| `POST /devices/pair` | public (pairing code) | returns device key once; returns `resumeSeq` per fiscal year |
| `POST /devices/{id}/revoke` | OWNER | audited |
| `GET /sync/snapshot`, `GET /sync/pull?since=` | any terminal user | ETag/version |
| `POST /sync/push` | CASHIER, CAPTAIN, MANAGER, OWNER | ≤ 50 commands; per-command results |
| `POST /sync/heartbeat` | any terminal user | queue length, counter, clock, app version |
| `GET /sync/conflicts`, `POST /sync/conflicts/{id}/resolve` | MANAGER, OWNER | resolution note ≥ 5 chars |
| `GET /sync/gaps`, `POST /sync/gaps/{id}/explain` | OWNER (explain), MANAGER (view) | explanation ≥ 5 chars |
| `GET /sync/commands?status=REJECTED`, `POST /sync/commands/{id}/retry` | OWNER | rejected payloads are never lost |
| `PUT /outlets/{id}/offline-settings` | OWNER | `offlineEnabled`, `offlineMaxHours` |
New error codes (Appendix B): `DEVICE_NOT_PAIRED` (403), `DEVICE_REVOKED` (403), `PAIRING_CODE_INVALID` (422), `COMMAND_ID_REUSED` (422), `UNSUPPORTED_SCHEMA_VERSION` (422), `SERIES_MISMATCH` (422), `OFFLINE_DISABLED` (409), `SYNC_BATCH_TOO_LARGE` (413).
Plan gate: offline mode is part of the base product (no feature flag); `outlets.offline_enabled = false` turns it off for an outlet.

### 24.11 UI specification
**Connection states** (top bar chip + banner, always icon + text): **Online** (no banner); **Working offline** — amber banner "Working offline — bills are saved on this terminal. Sign-in valid for 71 h." (replaces the old red offline banner; red is reserved for *Locked*); **Syncing** — blue "Sending 7 items…" with progress; **Sync problem** — amber "2 items need attention" linking to S17; **Locked** — red full-width "This terminal has been offline for 72 hours. Connect to the internet to continue." + **Export unsynced data**.
**Disabled actions offline** keep their button visible, disabled with the tooltip reason from 24.2 ("Needs internet and a manager") — never silently hidden.
**Bill dialog offline:** after payment the *Done* step shows "Saved on this terminal — will be sent when online" with print and (queued) WhatsApp.
**S16 Devices & Sync (Settings → Devices):** list of terminals (name, series, status chip, last seen, queue length, app version, clock skew), *Add terminal* (series code, pairing code dialog with copy), *Re-pair*, *Revoke* (confirm dialog, reason), offline settings (enable, max hours). On a terminal: *This terminal* card with pairing status, snapshot age, queue (pending/parked), **Retry parked**, **Export unsynced data**, last 20 sync log lines.
**S17 Sync issues (`/sync/issues`, Manager/Owner):** tabs **Conflicts** (type, bill/order link, severity chip, details, *Acknowledge/Resolve* with note), **Number gaps** (series, range, cause, status, *Explain*), **Rejected commands** (error, payload viewer, *Retry*, *Export*). Empty states: "Nothing needs attention."
**Floor view:** a table with two active orders shows a warning chip "2 orders — needs attention" and opens a chooser (Merge / Open each).
**Day close wizard (S12) readiness step additions:** unsynced terminals (from heartbeats), open number gaps, open CALC_MISMATCH/CRITICAL conflicts — each with a link; the first two are warnings the Owner can acknowledge, a CRITICAL conflict requires an acknowledgement note.
All new screens follow Section 12.2 (skeleton, empty, error states) and never render blank.

### 24.12 Database — Migration V012 *(verified on PostgreSQL 16 on top of V001–V011: 71 accept/reject cases pass; also applied over a database that already contained orders and bills)*
```sql
-- V012 — offline mode: registered terminals (devices), sync command log, bill-number gaps, sync conflicts
-- Requires the btree_gist extension (bundled with PostgreSQL; managed services normally allow it).
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE devices (                            -- a registered billing terminal (browser profile) that may work offline
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  name text NOT NULL CHECK (length(btrim(name)) > 0),               -- "Counter 1"
  series_code text NOT NULL CHECK (series_code ~ '^[A-Z][A-Z0-9]{0,2}$' AND series_code <> 'B'),   -- 'B' stays the server-allocated default series
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','ACTIVE','REVOKED')),
  pairing_code_hash text,                         -- one-time code shown to the Owner/Manager; only its hash is stored
  pairing_expires_at timestamptz,
  device_key_hash text,                           -- hash of the secret the terminal received when it paired
  registered_at timestamptz,
  registration_count int NOT NULL DEFAULT 0 CHECK (registration_count >= 0),   -- +1 each (re-)pairing, e.g. after browser data was lost
  app_version text,
  user_agent text,
  last_seen_at timestamptz,
  last_reported_seq int CHECK (last_reported_seq IS NULL OR last_reported_seq >= 0),   -- the terminal's own local bill counter at last heartbeat
  last_reported_fiscal_year text,
  pending_count int NOT NULL DEFAULT 0 CHECK (pending_count >= 0),             -- unsynced commands reported at last heartbeat
  clock_skew_seconds int,                         -- device clock minus server clock at last contact
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  revoked_by uuid REFERENCES users(id),
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (outlet_id, series_code),                -- a series code is never shared and never reused, even after revocation
  CHECK (status <> 'PENDING' OR (pairing_code_hash IS NOT NULL AND pairing_expires_at IS NOT NULL)),
  CHECK (status <> 'ACTIVE' OR (device_key_hash IS NOT NULL AND registered_at IS NOT NULL)),
  CHECK (status <> 'REVOKED' OR (revoked_at IS NOT NULL AND revoked_by IS NOT NULL)),
  CHECK ((last_reported_seq IS NULL) = (last_reported_fiscal_year IS NULL))
);
CREATE INDEX ix_devices_outlet ON devices(outlet_id, status);

CREATE TABLE sync_commands (                      -- every command a terminal pushed; also the idempotency record for /sync/push
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  device_id uuid NOT NULL REFERENCES devices(id),
  command_id uuid NOT NULL,                       -- generated on the terminal
  device_seq bigint NOT NULL CHECK (device_seq > 0),   -- the terminal's own monotonic command counter
  command_type text NOT NULL CHECK (command_type ~ '^[A-Z][A-Z_]{2,39}$'),
  schema_version int NOT NULL CHECK (schema_version >= 1),
  aggregate_type text NOT NULL CHECK (aggregate_type IN ('ORDER','KOT','BILL','PAYMENT','SHIFT','MESSAGE')),
  aggregate_id uuid NOT NULL,
  depends_on_command_id uuid,                     -- e.g. a PAYMENT_ADD depends on the BILL_GENERATE that created its bill
  payload jsonb NOT NULL,
  payload_hash text NOT NULL,                     -- same command_id + different hash = client bug → rejected, never overwritten
  status text NOT NULL DEFAULT 'RECEIVED' CHECK (status IN ('RECEIVED','WAITING_DEPENDENCY','APPLIED','CONFLICT_FLAGGED','REJECTED')),
  result jsonb,
  error_code text,
  attempts int NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  client_created_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  applied_at timestamptz,
  UNIQUE (tenant_id, command_id),                 -- idempotency
  UNIQUE (device_id, device_seq),
  CHECK (depends_on_command_id IS NULL OR depends_on_command_id <> command_id),
  CHECK (status NOT IN ('APPLIED','CONFLICT_FLAGGED') OR applied_at IS NOT NULL),
  CHECK (status <> 'REJECTED' OR error_code IS NOT NULL),
  CHECK (status <> 'WAITING_DEPENDENCY' OR depends_on_command_id IS NOT NULL)
);
CREATE INDEX ix_sync_commands_waiting ON sync_commands(device_id, status) WHERE status IN ('RECEIVED','WAITING_DEPENDENCY');
CREATE INDEX ix_sync_commands_aggregate ON sync_commands(aggregate_type, aggregate_id);

CREATE TABLE bill_number_gaps (                   -- missing sequence numbers inside a device series; shrinks/splits as late bills arrive
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  device_id uuid REFERENCES devices(id),
  series text NOT NULL,
  fiscal_year text NOT NULL,
  from_seq int NOT NULL CHECK (from_seq >= 1),
  to_seq int NOT NULL,
  cause text NOT NULL DEFAULT 'NOT_YET_SYNCED' CHECK (cause IN ('NOT_YET_SYNCED','STORAGE_LOST','DEVICE_REVOKED','UNKNOWN')),
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','FILLED','EXPLAINED')),
  explanation text,
  explained_by uuid REFERENCES users(id),
  explained_at timestamptz,
  detected_at timestamptz NOT NULL DEFAULT now(),
  filled_at timestamptz,
  CHECK (to_seq >= from_seq),
  CHECK (status <> 'EXPLAINED' OR (explanation IS NOT NULL AND length(btrim(explanation)) >= 5 AND explained_by IS NOT NULL AND explained_at IS NOT NULL)),
  CHECK (status <> 'FILLED' OR filled_at IS NOT NULL),
  -- two unresolved gaps of one series/year can never overlap
  EXCLUDE USING gist (outlet_id WITH =, series WITH =, fiscal_year WITH =, int4range(from_seq, to_seq, '[]') WITH &&) WHERE (status <> 'FILLED')
);
CREATE INDEX ix_gaps_open ON bill_number_gaps(outlet_id, status) WHERE status = 'OPEN';

CREATE TABLE sync_conflicts (                     -- things the server accepted but a human should look at
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  device_id uuid REFERENCES devices(id),
  command_id uuid,
  order_id uuid REFERENCES orders(id),
  bill_id uuid REFERENCES bills(id),
  conflict_type text NOT NULL CHECK (conflict_type IN ('TABLE_CONFLICT','ITEM_INACTIVE','PRICE_CHANGED','CALC_MISMATCH','NUMBER_GAP','CLOCK_SKEW','USER_DEACTIVATED','LATE_FOR_CLOSED_DAY')),
  severity text NOT NULL CHECK (severity IN ('INFO','WARN','CRITICAL')),
  details jsonb NOT NULL DEFAULT '{}',            -- e.g. client vs server totals for CALC_MISMATCH
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','ACKNOWLEDGED','RESOLVED')),
  resolution_note text,
  resolved_by uuid REFERENCES users(id),
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'RESOLVED' OR (resolved_by IS NOT NULL AND resolved_at IS NOT NULL AND resolution_note IS NOT NULL AND length(btrim(resolution_note)) >= 5)),
  CHECK (conflict_type <> 'CALC_MISMATCH' OR (bill_id IS NOT NULL AND severity = 'CRITICAL')),
  CHECK (conflict_type <> 'TABLE_CONFLICT' OR order_id IS NOT NULL),
  CHECK (conflict_type <> 'NUMBER_GAP' OR device_id IS NOT NULL)
);
CREATE INDEX ix_sync_conflicts_open ON sync_conflicts(outlet_id, status) WHERE status <> 'RESOLVED';

-- Records created on a terminal while offline (or by any registered terminal)
ALTER TABLE orders
  ADD COLUMN origin_device_id uuid REFERENCES devices(id),
  ADD COLUMN offline_created boolean NOT NULL DEFAULT false,
  ADD COLUMN client_created_at timestamptz,
  ADD COLUMN synced_at timestamptz,
  ADD COLUMN device_order_no int CHECK (device_order_no IS NULL OR device_order_no > 0),   -- number printed on the offline KOT, e.g. "A-12"
  ADD COLUMN needs_attention boolean NOT NULL DEFAULT false,                              -- e.g. second order on the same table created offline
  ADD COLUMN attention_reason text,
  ADD CONSTRAINT orders_offline_has_device CHECK (NOT offline_created OR (origin_device_id IS NOT NULL AND client_created_at IS NOT NULL AND device_order_no IS NOT NULL)),
  ADD CONSTRAINT orders_attention_has_reason CHECK (NOT needs_attention OR attention_reason IS NOT NULL);
CREATE UNIQUE INDEX ux_orders_device_no ON orders(origin_device_id, business_date, device_order_no) WHERE device_order_no IS NOT NULL;

ALTER TABLE kots
  ADD COLUMN origin_device_id uuid REFERENCES devices(id),
  ADD COLUMN offline_created boolean NOT NULL DEFAULT false,
  ADD COLUMN client_created_at timestamptz,
  ADD COLUMN synced_at timestamptz,
  ADD COLUMN device_kot_no int CHECK (device_kot_no IS NULL OR device_kot_no > 0),
  ADD CONSTRAINT kots_offline_has_device CHECK (NOT offline_created OR (origin_device_id IS NOT NULL AND client_created_at IS NOT NULL AND device_kot_no IS NOT NULL));
CREATE UNIQUE INDEX ux_kots_device_no ON kots(origin_device_id, business_date, device_kot_no) WHERE device_kot_no IS NOT NULL;

ALTER TABLE bills
  ADD COLUMN origin_device_id uuid REFERENCES devices(id),
  ADD COLUMN offline_created boolean NOT NULL DEFAULT false,
  ADD COLUMN client_created_at timestamptz,
  ADD COLUMN synced_at timestamptz,
  ADD CONSTRAINT bills_offline_has_device CHECK (NOT offline_created OR (origin_device_id IS NOT NULL AND client_created_at IS NOT NULL));

ALTER TABLE payments
  ADD COLUMN origin_device_id uuid REFERENCES devices(id),
  ADD COLUMN offline_created boolean NOT NULL DEFAULT false,
  ADD COLUMN client_created_at timestamptz,
  ADD COLUMN synced_at timestamptz,
  ADD CONSTRAINT payments_offline_has_device CHECK (NOT offline_created OR (origin_device_id IS NOT NULL AND client_created_at IS NOT NULL));

ALTER TABLE outlets
  ADD COLUMN offline_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN offline_max_hours int NOT NULL DEFAULT 72 CHECK (offline_max_hours BETWEEN 1 AND 720);
```
Constraint tests that passed: series code format, `B` reserved, one series code per outlet (reusable across outlets), device status/pairing/key/revocation rules; unique `command_id` (idempotency) and unique `(device, deviceSeq)`; `APPLIED`/`REJECTED`/`WAITING_DEPENDENCY` field rules; no self-dependency; command type/aggregate checks; unresolved gaps can never overlap (exclusion constraint) while a `FILLED` gap's range can be reused; explained gaps need an explanation ≥ 5 chars, user and time; conflict rules (`CALC_MISMATCH` must be CRITICAL and name a bill, `TABLE_CONFLICT` needs an order, `NUMBER_GAP` needs a device, `RESOLVED` needs note+user+time); offline order/KOT/bill/payment must carry device and client time; device order/KOT numbers unique per device and date; the database **allows** two open orders on one table (the later one is flagged, never dropped); duplicate bill sequence/number rejected; `offline_max_hours` limited to 1–720.
*Note:* V012 needs the `btree_gist` extension (shipped with PostgreSQL; some managed services need it enabled once).

### 24.13 Failure modes
| Situation | Behaviour |
|---|---|
| Internet drops mid-request | The request is retried from the outbox with the same `commandId`; the server answers `DUPLICATE` if it had already applied it |
| Internet returns but the server is unreachable | Banner stays "Working offline"; back-off 5 s → 5 min; the cashier is never blocked |
| App update while the queue is not empty | Update waits (24.3) |
| Same bill number pushed twice | `DUPLICATE` (unique constraint as the last line of defence) |
| Bill with a number outside its terminal's series | `REJECTED SERIES_MISMATCH`, payload kept, CRITICAL notice to Owner |
| Terminal storage wiped | Re-pair + resume with safety skip; `STORAGE_LOST` gap to explain |
| Two terminals open the same table | `TABLE_CONFLICT`, both kept |
| Terminal and server totals differ | Accepted as issued + `CALC_MISMATCH` CRITICAL |
| Poison command | Parked after 5 failures or a non-retryable answer; independent commands continue; visible in S16/S17 |
| Offline session expires | Locked screen + export (24.7) |
| Device clock wrong | `CLOCK_SKEW`, locks if the clock moves backwards |
| Bill arrives for a closed day | Accepted into its original date, `LATE_FOR_CLOSED_DAY`, late-bills notice |
| Subscription turned read-only while offline | Commands created before enforcement are applied; after it → `REJECTED SUBSCRIPTION_INACTIVE`, payload kept, Owner can retry after reactivation |

### 24.14 Security
- Device key: random 256-bit, shown once, only a hash stored server-side; sent in `X-Device-Key` with every sync call together with the user's token; revocable instantly. Pairing codes: single use, 30-minute expiry, hash only, rate-limited.
- Every sync command is tenant/outlet scoped from the **tokens**, never from the payload; a payload naming another outlet is `REJECTED`.
- Commands are authorised **as the user who issued them at that role** (a cashier terminal cannot push a `VOID`); unknown command types are rejected.
- The loopback print endpoint is token-protected (24.8). No manager PINs, password hashes, WhatsApp tokens or payment secrets are stored on terminals.
- Audit log: terminal paired/revoked/re-paired, gap explained, conflict resolved, rejected command retried, offline settings changed; every offline bill carries `origin_device_id`, `client_created_at`, `synced_at`.

### 24.15 Tests (what the implementing agent must write)
- **Golden parity (executable now):** `reference/test_golden.mjs` — 443 checks (424 bill cases, 18 device-rule cases, bill-number format) + 418 order-independence checks, **0 failures**. Port to Vitest (`billCalculator.ts`) and Java (`BillCalculator`) against the same JSON.
- **Reference vectors OF1–OF20** (`reference/test_sync_rules.py`, executable now): gap opening/filling/splitting incl. out-of-order and duplicate arrival, arrival inside an explained gap, resume after storage loss, session expiry (72 h boundary), subscription deadline, clock rolled back, clock-skew threshold (900 s boundary), quick-PIN (valid/invalid/lockout after 5), back-off schedule, poison parking and dependants-only blocking, conflict classification, protocol-only rejection, revoked-device window, idempotent push with dependency wait, table-conflict independent of arrival order, and **OF20, a property test: any permutation and duplication of a valid multi-terminal command stream gives the same final server state, with no gap and nothing waiting**. (Mutation check done: breaking the gap-fill or the dependency drain makes OF2/OF18/OF20 fail.)
- **Database:** the 71 cases of V012 (24.12).
- **Integration (Testcontainers):** push the same batch twice → one set of rows; kill the connection mid-batch → no half-applied command; concurrent pushes from two terminals; unique-violation race on a bill number → `DUPLICATE`, not 500; rejected payload retained and retryable; heartbeat updates `last_seen_at`; revoked device key → 403 but final-sync window works; cross-tenant device id → 404.
- **E2E (Playwright with network emulation; scenarios numbered after 27):**
  28. Go offline mid-service: dine-in order → KOT prints through the (emulated) loopback agent → bill → cash → print; badge counts up; reconnect → everything syncs; server totals and numbers equal the printed ones; syncing twice creates no duplicate.
  29. Two terminals offline open the same table → both sync → `TABLE_CONFLICT`, both orders present and flagged → Manager merges.
  30. Terminal A issues 1–5 offline; 1, 2, 5 arrive first → gap 3–4 `OPEN` (S17); 3 and 4 arrive → gap closed. Separate run: wipe the terminal's storage → re-pair → numbers resume above the last known + safety skip → `STORAGE_LOST` gap → Owner explains.
  31. Offline for the configured limit → Locked screen, **Export unsynced data** works, reconnect → resumes; clock set back → locked; deactivated user's offline bill → accepted + `USER_DEACTIVATED`.
  32. Fake server calculator returns different tax → bill accepted as issued, `CALC_MISMATCH` CRITICAL with both totals, printed copy unchanged.
  33. Offline: manager-PIN actions disabled with the reason; WhatsApp bill queued → sent after sync only with recorded consent; revoked terminal delivers its pre-revocation bills inside the window and nothing after; bill for an already-closed day → accepted + `LATE_FOR_CLOSED_DAY`.
- **Not testable without real devices:** browser storage eviction, service-worker update behaviour on every browser, loopback calls from an HTTPS page, a real power cut with a real printer — a manual checklist in `docs/OFFLINE_GO_LIVE.md` (agent to create): unplug the router during service on two real terminals and one thermal printer, complete five bills, reconnect, compare paper to server.

### 24.16 Build phase — Phase 2O *(after Phase 2 printing; ≈ 4 weeks; the riskiest phase — do not start before Phases 1 and 2 are accepted)*
**Tasks:** V012 → devices (pairing, series, revoke) → golden vectors in Java and TypeScript (`billCalculator.ts`) → Dexie stores, snapshot/pull → service worker (PWA, update-after-queue rule) → command outbox + `/sync/push` with idempotency, dependency wait, protocol-only rejections → bill-number gap service → conflict classification and S17 → heartbeat → offline session/lock/quick-PIN → loopback print mode in the agent → offline UI states and disabled-action tooltips → day-close readiness additions → emergency export → E2E 28–33 and `docs/OFFLINE_GO_LIVE.md`.
**Accept when:** golden vectors pass in JS, TS and Java; OF1–OF20 pass as Java tests; E2E 28–33 pass; no scenario loses or duplicates a bill; manual go-live checklist done on real hardware.

---

---

## 25. EVERYDAY BILLING FEATURES *(added in v1.3)*

> **Goal:** the features a working counter needs every day that the first plan left out: combos, coupons, happy-hour prices, packaging charges, open items, complimentary (NC) bills, tips, cashier shifts and the cash drawer, customer credit (dues), refunds with credit notes, a real kitchen display, barcode scanning, a customer-facing display and a central menu for several outlets. It is *Phase 1B* and extends Sections 5.3, 5.8, 5.9, 8, 10 and 12. Money rules are executable: `reference/` (Python, Decimal) has 60 tests for this section, the migration (25.20) has 231 accept/reject cases, all run on 24 Nov 2026.

### 25.1 Overview, vocabulary and what is deliberately not here
| # | Feature | Short rule | Section |
|---|---|---|---|
| 1 | Combos | one fixed price, split over component lines so the sum is exact; each component keeps its own tax | 25.3 |
| 2 | Coupons | one coupon per bill, validated with a reason code, usage limits enforced in the database | 25.4 |
| 3 | Time-based prices | happy hour etc.; resolved when the line is added, price snapshot stored on the line | 25.5 |
| 4 | Packaging charge | an extra bill line, taxed, never discounted | 25.6 |
| 5 | Open items | name + price typed at order time; permission, max price, flagged in reports | 25.7 |
| 6 | Complimentary (NC) | 100 % discount, reason code, manager PIN, two tax modes | 25.8 |
| 7 | Tips | on the payment, outside the bill total, no tax | 25.9 |
| 8 | Shifts and cash drawer | opening float, pay-in/out/drop, counted close, variance | 25.10 |
| 9 | Credit sales (dues) | ON_ACCOUNT payments, append-only ledger, statements, aging | 25.11 |
| 10 | Refunds and credit notes | by line and quantity, own gapless series `CN`, tax reversed from the original | 25.12 |
| 11 | Kitchen display | status per item NEW → PREPARING → READY → SERVED, timers, expo | 25.13 |
| 12 | Barcode | unique per outlet; keyboard-wedge scanner rule | 25.14 |
| 13 | Customer-facing display | second window, no personal data | 25.15 |
| 14 | Central menu | master outlet publishes to other outlets; per-outlet overrides | 25.16 |
| 15 | Hold bill, reprint, audit log | already exist — only the interactions are listed | 25.17 |

**Differences from the first plan and from the request, stated up front**
- The catalog in V002 is **outlet-level** (`menu_items.outlet_id`), not tenant-level. "Central menu" therefore means *copy and keep in sync* (columns `source_item_id`, `overridden_fields`), not a shared table (25.16).
- Kitchen status lives on the existing **`order_items`** (V003 has no `kot_items` table); one KOT can hold items in different states.
- Combo components are **not** nested (a combo cannot contain a combo; DB trigger).
- Not built: label printing, gift cards (loyalty points are in Section 30), stacking several coupons, automatic card/UPI refunds through a provider (the cashier refunds physically and records it, exactly like the old void rule in 5.8), a KDS hardware integration.
- **Legal points are not verified**: how a credit note must be numbered or worded, whether tips or NC bills carry tax, whether a separate `CN` series is acceptable — each is an open decision (30–39) for a tax professional. The software stores the data so that either answer can be implemented.

### 25.2 Calculation order (amends Section 5.3)
The shared `BillCalculator` stays the only place that does money. What changes is **what is fed into it**:
1. **Lines.** Normal items, **combo component lines** (the combo *header* is not billed: `order_items.combo_role = 'HEADER'`; each `COMPONENT` carries `fixed_line_amount`, and is fed as `qty = 1, unit_price = fixed_line_amount` so `round2(qty × unit_price)` equals the allocated amount exactly — 25.3), **open items** (price typed by staff, tax profile chosen), and items whose price came from a **price rule** (the snapshot price on the order line, not today's menu price).
2. **Discount (Step 3 of 5.3) — one per bill.** Either a manual discount, a **coupon**, or **NC (100 %)**; the three exclude each other in v1 (`COUPON_NOT_STACKABLE`, `COUPON_NC_BILL`). A coupon becomes a flat bill-level amount: `PERCENT`: `round2(subtotal × value / 100)`; then `min(…, max_discount)`; then `min(…, subtotal)`. The cap is applied **before** allocation, so Step 4 (largest remainder) distributes the already-capped amount and `Σ discount_i = discount_total` still holds. The base is the ITEM-line subtotal (combo components, open items included; packaging, service and delivery charges excluded).
3. **Service charge (Step 5).** Base `subtotal − discount_total` — unchanged; packaging is **not** in the base.
4. **Extra charge lines (Step 5b).** After the delivery charge: `PACKAGING_CHARGE` (25.6), taxed with the outlet's packaging tax profile, not discounted. The calculator already accepts `extra_charges` (52 existing tests); the `bill_lines.line_type` CHECK is widened in V013.
5. **Tax and totals (Steps 6–7)** unchanged. **NC** is the same engine with a 100 % discount (every line: `discount = gross`, `taxable = 0`, `tax = 0`); the tax the restaurant would owe is computed by a *separate* function (`nc.tax_on_list_price`) and stored in `bills.nc_tax_liability` (25.8).
6. **Tips** are never an input to the calculator (25.9).
7. **Credit notes** are not recalculated at all: they copy proportional parts of the *stored* bill lines (25.12).

### 25.3 Combos
- A menu item with `item_kind = 'COMBO'` has a fixed `base_price` and rows in `combo_components (combo_item_id, component_item_id, component_variant_id, quantity)`. Components must be `STANDARD` items of the same outlet; a variant must belong to its component item (trigger, errors `COMBO_NESTING_NOT_ALLOWED`, `COMBO_COMPONENT_OTHER_OUTLET`, `COMBO_VARIANT_MISMATCH`, `COMBO_PARENT_NOT_COMBO`).
- **Adding a combo to an order** creates one `HEADER` order line (quantity N, no price of its own) and one `COMPONENT` line per component (`combo_parent_id` → header, quantity = component quantity × N). If a component has price rules or variants, its **list price at that moment** is the allocation weight.
- **Allocation:** `allocate(combo_price × N, weights)` from `bill_calculator.py` (largest remainder, ties → lower line id), weights = `round2(qty × list_price)` in cents. If every weight is 0 the weights are the quantities. Result: `Σ fixed_line_amount = combo_price × N` to the paisa (property test BX07, 300 random combos; order independent BX08). Each component keeps **its own tax profile**, so a combo of a 5 % and an 18 % item reports 5 % and 18 % GST on the allocated amounts.
- **Changing N after the KOT** is cancel-and-re-add, the same rule as any KOT'd item. Cancelling the header cancels its components (`ON DELETE CASCADE` on the header; the app uses status changes, not deletes).
- **KOT** prints the header line "COMBO Meal ×2" and below it the components indented, no prices (Section 8.3). Each component goes to its **own station**.
- **Bill print:** the header row shows the combo name and its total; component rows are indented with quantity and **no** amount unless the outlet's tax invoice needs per-line amounts (`bill_lines` always store them).
- **Stock interface for the inventory module (stream C):** ordering N combos consumes `N × combo_components.quantity` of every `(component_item_id, component_variant_id)`; the header itself has no recipe. Reference: `combo.consumption()`. A refunded combo component line returns stock for that component only (25.12).
- **Discounts and coupons** apply to component lines like any other line (they share the bill subtotal).

### 25.4 Coupons
- Table `coupons`: `code` (3–24 chars, unique **per tenant, case-insensitive** — index on `lower(code)`), `discount_type PERCENT|AMOUNT`, `value`, `max_discount`, `min_bill` (compared with the ITEM subtotal before discount), `valid_from`/`valid_to` (`valid_to` exclusive), `weekdays` (outlet-local ISO weekday), `order_types`, `usage_limit_total/per_customer/per_day`, `stackable` (always false in v1, the CHECK keeps it so), `active`, optional `outlet_id` (NULL = every outlet of the tenant).
- **Validation order and reason codes** (the first failing check is returned; the UI shows the text, the API the code): `COUPON_NOT_FOUND`, `COUPON_INACTIVE`, `COUPON_NC_BILL`, `COUPON_NOT_STACKABLE` (a manual discount is already on the bill), `COUPON_WRONG_OUTLET`, `COUPON_NOT_YET_VALID`, `COUPON_EXPIRED`, `COUPON_WEEKDAY`, `COUPON_ORDER_TYPE`, `COUPON_MIN_BILL`, `COUPON_CUSTOMER_REQUIRED` (a per-customer limit needs a customer on the order), `COUPON_LIMIT_TOTAL`, `COUPON_LIMIT_DAY`, `COUPON_LIMIT_CUSTOMER`, `COUPON_NO_DISCOUNT`. Reference `coupon.py` (BX10–BX19) returns each of them.
- **Redemption.** Applying a coupon to a **GENERATED** bill inserts `coupon_redemptions(status = 'ACTIVE')` in the same transaction that sets `bills.coupon_id/coupon_code` and the discount. The *database* enforces: at most one ACTIVE redemption per bill (`ux_coupon_one_active_per_bill`), and the three usage limits inside a trigger that **locks the coupon row**, so two cashiers redeeming the last use at the same moment cannot both succeed (the second gets `COUPON_LIMIT_TOTAL`). The application's pre-check is only for a friendly message.
- **Release.** A voided bill releases its redemption automatically (trigger `trg_bill_void_release_coupon`: ACTIVE → RELEASED, reason `BILL_VOIDED`). A **full** refund (credit notes covering the whole bill) releases it from the application in the same transaction (`REFUNDED_IN_FULL`); a partial refund does not. Rows are never deleted and never edited except that one transition (trigger).
- **Per-day limit** counts per outlet and **business date** (not calendar date).
- **Changing a coupon** does not change past bills (the discount amount is stored on the bill and the redemption). Deleting is not offered; set `active = false`.
- Offline: coupon validation needs the server (limits are global), so **coupons are blocked offline** (Section 24.2 gets one row, edits.md).

### 25.5 Time-based pricing (happy hour, lunch menu, delivery-only prices)
- Table `price_rules` (per outlet): scope `ITEM | VARIANT | CATEGORY`; `weekdays`; `start_time`/`end_time`; `valid_from`/`valid_to` (dates); `order_types`; action `PRICE_OVERRIDE` (a price) or `PERCENT_OFF` (of the list price); `priority` 0–1000; `active`. A category rule can only be `PERCENT_OFF`.
- **Windows.** `start ≤ t < end`. If `end < start` the window **crosses midnight**; `end = start` is invalid. The **weekday and the valid dates belong to the day on which the window STARTS**: a Monday 22:00–02:00 rule is also active on Tuesday 01:00; Monday 01:00 belongs to Sunday's window (BX31, BX32, BX38). Time is the **outlet's local time** (`outlets.timezone`); `business_date` plays no part, so a bar whose business day ends at 03:00 prices by the clock, not by the ledger day.
- **Resolution (one rule, no stacking):** highest `priority`; tie → more specific scope (VARIANT > ITEM > CATEGORY); tie → lower resulting price; tie → lower rule id (deterministic). No match → list price (BX33–BX37).
- **Snapshot.** At line-add time the server (and an offline terminal from its snapshot, Section 24.3) resolves the price and stores `unit_price` (the price used for billing), `list_unit_price`, `price_source` (`LIST | PRICE_RULE | OPEN_ITEM | COMBO`), `price_rule_id`, `price_rule_name` on the order line. Editing or deleting a rule later changes nothing already on an order. A line added at 18:55 keeps its happy-hour price even if the bill is generated at 19:05.
- The POS shows a chip "Happy hour −20 %" on affected lines and a tag in the item grid while a rule is active. `/catalog/pos` carries the rules; its ETag changes when rules change (25.16).
- Rules and coupons are different things: rules change the *price of a line*, a coupon is a *bill discount*. They can both apply (a coupon on top of happy-hour prices) because the coupon is computed on the already-reduced subtotal.

### 25.6 Packaging charge
- Outlet settings: `packaging_mode NONE | FLAT_PER_ORDER | PER_ITEM`, `packaging_flat_charge`, `packaging_order_types` (default TAKEAWAY, DELIVERY), `packaging_tax_profile_id`. `PER_ITEM` uses `menu_items.packaging_charge` (per unit; a combo header's own value is used, its components' are ignored).
- The charge is an extra bill line `PACKAGING_CHARGE` (qty 1): **not discounted** (so a coupon or NC does not reduce it — except NC, which carries no extras at all: `bills_nc_no_extras`), **not in the service-charge base**, taxed by its own profile. Inclusive/exclusive handling follows the outlet like every other line.
- **Split bills:** a `FLAT_PER_ORDER` charge appears **once per order** — on the first bill that is generated; a partial unique index (`ux_bills_packaging_flat_once`, VOID bills excluded) makes a second one impossible, and if that first bill is voided the next one picks it up. `PER_ITEM` follows the items, so each split bill carries the packaging of its own items.
- Dine-in orders carry no packaging unless the outlet lists DINE_IN. `bills.packaging_charge_total` and `bills.packaging_kind` (FLAT/PER_ITEM) are stored; reports show packaging separately (EOD key `packaging`).

### 25.7 Open / custom items
- At order time a staff member with the permission **OPEN_ITEM** adds a line with a name (1–80 chars), a price (`0 < price ≤ outlet.open_item_max_price`, default 500), a tax profile and a station. The order line has `menu_item_id = NULL`, `is_open_item = true`, `price_source = 'OPEN_ITEM'` (DB checks keep these three consistent).
- **Permission:** built-in default OWNER and MANAGER only; the Owner can grant or withdraw it per role and outlet (`outlet_role_permissions`, a missing row = the default). `outlets.open_items_enabled` (default **false**) switches the feature on.
- Flagged everywhere: a badge "Open" on POS, KOT and bill drawer; reports have an *Open items* table (name, qty, amount, who) and the EOD summary counts them. A discount on an open item works like any other.
- **Save as menu item:** a manager can convert an open line into a real menu item (a new item with the same name/price/tax/station, `POST /order-items/{id}/save-as-menu-item`); the old line stays an open item.
- Open items have no recipe, so no stock is consumed (inventory stream: report as "unrecorded consumption").

### 25.8 Complimentary (NC) bills
- A manager (or any role after a **manager PIN override**, Section 22) marks an order's bill **NC**: it needs a **reason code** (`reason_codes` kind `NC`, e.g. STAFF_MEAL, OWNER_GUEST, SERVICE_RECOVERY, MARKETING — editable list) and the bill is generated with a 100 % discount; `grand_total = 0` (DB `bills_nc_shape`). An NC bill carries **no** packaging, delivery, service charge or coupon (`bills_nc_no_extras`) and takes no payment (it becomes PAID at once with no payment row; shown "NC — Complimentary").
- Numbering: NC bills use the normal bill series (a gapless sequence must not have holes). Reports show NC **separately** (count, list value, by reason code, by user) and net sales exclude them.
- **Tax mode per outlet** (`outlets.nc_tax_mode`): `ZERO_TAX` — the bill shows zero tax; `TAX_ON_LIST_PRICE` — the bill still totals 0 for the guest, and the tax that would be due on the list price is computed by a **separate function** (`nc.py::tax_on_list_price`, BX45–BX48, inclusive and exclusive pricing) and stored in `bills.nc_tax_liability`. It is **informational** for the owner and the accountant: it is *not* collected from the guest and not added to the bill. **Which treatment the law requires is not verified** (Open Decision 31) — the outlet chooses.
- `list_unit_price` on order lines keeps the price before any rule, so NC reports show the list value.

### 25.9 Tips
- Column `payments.tip_amount` (≥ 0) with optional `tip_staff_id`. The tip is **outside the bill**: not in `grand_total`, no tax, no round-off, never part of "remaining". A payment of 340.00 with a tip of 20.00 gives `amount = 340.00` and `tip_amount = 20.00`. `ON_ACCOUNT` payments cannot carry a tip (DB check). Whether a tip is taxable or must be reported is **not verified** (Decision 32); the software keeps it out of the tax base.
- The bill print shows it **after** the grand total as "Tip (not part of bill)"; the S4 dialog shows quick buttons (5/10/15 % of the grand total — helper only — and "custom"). If the QR is shown for a UPI payment with a tip, the QR amount is `amount + tip` (the cashier sees both numbers). Cash tips count into the drawer (25.10); paying them out to staff is a PAY_OUT with reason TIP_PAYOUT.
- `tips_enabled` per outlet (default true). Reports: tips per day, per payment method, per staff.

### 25.10 Cashier shifts and the cash drawer
- **Shift** (`cashier_shifts`): a cashier *opens* a shift with an **opening float**, optionally on a device; **one open shift per cashier and per device** (partial unique indexes, reference `shift.can_open`). Every payment taken while a shift is open is stamped with `payments.shift_id`; with `outlets.shifts_required = true` a payment without a shift is rejected (`SHIFT_REQUIRED`), and a shift of another outlet is rejected (`SHIFT_OTHER_OUTLET`).
- **Cash movements** (`cash_movements`, append-only): `PAY_IN`, `PAY_OUT`, `DROP` (cash moved to the safe), each with amount > 0 and a **reason code** (kind `CASH_MOVEMENT`).
- **Closing:** the cashier counts the drawer and enters `counted_cash`. The server computes
  `expected = opening_float + cash payments applied + cash tips + cash credit settlements + pay-ins − cash refunds − pay-outs − drops`, and `variance = counted − expected` (negative = short). Cash payments count the *applied* amount (change already handed back). Two terms go beyond the original request and are explained: tips in cash and customers paying their dues in cash are physically in the drawer. Reference `shift.py` (BX60–BX66, property: expected equals the running sum of the movements; variance is 0 when the count equals expected). The closed shift stores `expected_cash`, `counted_cash`, `variance`, `closed_by`, optional `handover_to` (another user) and a note; a shift cannot be reopened.
- **Day close** requires every shift of the outlet to be CLOSED (trigger `OPEN_SHIFTS_EXIST`; the S12 wizard lists open shifts with a "Close shift" link). The old single cash reconciliation (EOD `cash`) is replaced by a per-shift list.
- **Cash drawer kick:** a printer with `opens_cash_drawer = true` receives the ESC/POS pulse (`ESC p 0 25 250`) when a **cash** payment is saved, a pay-out is saved, or the cashier presses *Open drawer* (audited; needs the OPEN_DRAWER permission of the cashier role). Whether a given drawer/printer combination responds to this command is **not verified** and must be tried on the real hardware.
- A cashier sees only their own shift in detail; a manager sees all (S21).

### 25.11 Credit sales (dues)
- `customers.credit_limit` (0 = no credit). An outlet enables it with `credit_sales_enabled`. Paying a bill with method **`ON_ACCOUNT`** (a new value of the `payments.method` CHECK) needs a **customer**, no tip, no tendered cash (DB checks), and is blocked when `balance + amount > credit_limit` (equal is allowed) with `CREDIT_LIMIT_EXCEEDED`; a **manager override** (PIN, reason) lets it pass and is written to the audit log (`credit.can_charge`, BX70).
- **Ledger** `customer_ledger` is append-only (UPDATE/DELETE trigger): `CHARGE` (+, with bill), `PAYMENT` (−, settlement with method), `CREDIT_NOTE` (−, refund to account), `ADJUSTMENT` (± with a reason of at least 5 characters; kind `CREDIT_ADJUSTMENT` reason codes: WRITE_OFF, CORRECTION). **Balance = SUM(amount)**; positive = the customer owes. Corrections are new rows, never edits. Property tests BX75: balance equals the sum; settling the full balance gives 0; aging buckets add up to the balance.
- **Settlement:** `POST /customers/{id}/settlements` records a PAYMENT row (cash/UPI/card/other, reference); a cash settlement is stamped with the open shift so the drawer reconciles. A settlement can be partial or larger than the balance (the surplus shows as "advance").
- **Aging** (reference `credit.aging`, BX73–BX74): credits are applied **oldest charge first** (FIFO); what remains of each charge is bucketed by age: 0–30, 31–60, 61–90, 90+ days.
- **Statement screen** (S22): balance, limit, ledger lines, aging, *Settle*, *Adjust*, **CSV export** and print. **Reminder hook:** a manager can send a reminder through the WhatsApp module (Section 23) using a *generic* template `due_reminder` (customer name, outlet, amount, no bill details); it respects the consent rules of 23; nothing is sent automatically in v1.
- Voiding a bill that was paid ON_ACCOUNT is blocked in the same way as other paid bills (25.12): use a credit note with refund method ON_ACCOUNT.

### 25.12 Refunds and credit notes
**Relation to the existing void rule (5.8).** *Void* (Owner only for a PAID bill) cancels the **whole sale as a mistake**: all lines inactive, all payments REFUNDED, order reopened. A **credit note** is the normal path for a return **after** the sale: part or all of a PAID bill, the bill stays PAID, a new numbered document records what was returned. A bill that already has a credit note **cannot be voided** any more (`BILL_HAS_CREDIT_NOTES`). Section 5.8 is amended accordingly (edits.md).

- **Who/what:** MANAGER or OWNER, or a cashier **with a manager PIN override** (the approving user is stored in `approved_by`); a **reason code** (kind `REFUND`) and free text of at least 5 characters. Allowed only on a PAID bill of the same outlet.
- **By line and quantity** (`credit_note_lines`: `bill_line_id`, `quantity`, amounts). Quantities may be fractional (3 decimals). Service/delivery/packaging lines can be refunded as lines too (quantity 1).
- **Tax is reversed from the ORIGINAL stored line, never recomputed** (`credit_note.refund_line`): for a partial quantity `q` of `Q`: `x = round2(original_x × q / Q)` for taxable and tax, each clamped to what is left of the line; the component taxes are split by **largest remainder** over the original component taxes so `Σ components = tax` exactly. The refund that takes the **last remaining quantity** gets exactly what is left, so refunding everything in any number of pieces **equals the original line to the paisa** (property tests BX90 — 250 random bills with discounts, inclusive/exclusive, 1–5 lines, random piece sizes and note groupings — and BX91).
- **Header amounts:** `total_before_round_off = Σ line totals`. If the note **completes the bill** it hands back exactly what is left of the bill's `grand_total` (so the bill's own round-off is returned too). Otherwise the amount is **rounded down to a whole rupee** (never over-refund; the remainder returns with the final note); a note that would be 0 is refused (`REFUND_TOO_SMALL`). Outlets with round-off `NONE` refund the exact amount (Decision 38 explains the choice).
- **Hard limits in the database**, safe under concurrent requests (row locks on the bill and on each bill line): quantity, gross, taxable, tax and line total of all credit notes on a line never exceed the line (`REFUND_EXCEEDS_QUANTITY/AMOUNT/TAXABLE/TAX/GROSS`); all credit notes of a bill never exceed its `grand_total` (`REFUND_EXCEEDS_BILL_TOTAL`); the credit note must belong to the line's bill (`CREDIT_LINE_OTHER_BILL`) and outlet.
- **Numbering:** series `CN`, fiscal year, gapless, `CN-2026-27-000001`; uses **`bill_counters` with `series = 'CN'`** and the same atomic upsert as bills (Section 5.5: `INSERT … ON CONFLICT DO UPDATE SET last_no = last_no + 1 RETURNING`), in the transaction that inserts the credit note, so a rolled-back note leaves no gap. Whether credit notes need their own series is **not verified** (Decision 30).
- **Refund method:** `CASH` (leaves the drawer; reduces the shift's expected cash), `CARD`/`UPI`/`OTHER` (the cashier refunds outside the system and types the reference — v1 does **not** call a provider's refund API), or `ON_ACCOUNT` (needs a customer; a ledger row `CREDIT_NOTE` reduces the balance). "Original method" is a UI shortcut that preselects the bill's payment method (`credit_note.refund_destination`).
- **Releases and hooks:** a full refund releases the bill's coupon (25.4); each line has `restock` (a boolean the cashier ticks for returned goods; the inventory module reads `credit_note_lines WHERE restock` to put ingredients back — stream C interface); the `payments` rows are **not** changed (history stays; the credit note is the correcting document). Reports: net sales = bills − credit notes by business date of the *credit note*.
- **Print** (Section 8 addendum): header "CREDIT NOTE", number, date, **against bill** number and date, lines (name, qty returned, taxable, tax), tax summary, round-off, refund total, refund method, reason, approved-by; no QR. Reprint is marked "DUPLICATE". Credit notes are immutable (triggers).
- Immutable and audited: `credit_notes`, `credit_note_lines`, `credit_note_line_taxes` reject UPDATE and DELETE.

### 25.13 Kitchen display (KDS)
- Replaces the read-only S8 with an interactive screen (S24). Each **order item that has been sent on a KOT** has `kitchen_status`: `NEW → PREPARING → READY → SERVED`, with timestamps `preparing_at`, `ready_at`, `served_at`. Cancelling stays the existing item status (`CANCELLED`), not a kitchen state. `order_items_kitchen_only_after_kot` forbids a status before the item is on a KOT.
- **Allowed moves** (enforced by a trigger *and* by `kds.py`, which has the same list, BX50–BX55): forward by one, **NEW → READY** (quick bump), and **recall** one step back (PREPARING → NEW, READY → PREPARING, SERVED → READY). Everything else is `ILLEGAL_KITCHEN_TRANSITION`.
- **Bump** = move one step forward (touch the ticket, or key `B`/`Space` on a selected ticket; "bump all" per ticket); **recall** = a "Recall" button on the last bumped tickets (last 10). Station filter (chips; multi-select), toggle "All stations", and an **expo** view (S24b) that lists an order's tickets together and highlights orders where every item is READY (`kds.expo_ready`).
- **SLA colours:** per station `sla_warn_minutes` (default 10) and `sla_late_minutes` (default 20), `warn < late`. A ticket's timer starts at KOT print time: green < warn ≤ amber < late ≤ red; READY/SERVED tickets show no timer (BX53). Colours always come with the minute count and an icon, never colour alone.
- **Events:** SSE `kitchen.item.status` `{orderItemId, kotId, orderId, from, to, at}` (Section 7 gets one event); the order screen shows a small chip per item (preparing/ready) so waiters see "Ready — pick up".
- **Sound:** a short chime on a new ticket (user-toggle, default on; browsers require one tap before audio — the screen shows "Tap to enable sound" until then). A distinct tone when a ticket goes red.
- Combo components appear as separate lines under the combo heading and can be bumped separately (each at its own station).
- KDS is **online-only**; offline the printed KOT is the channel (Section 24.1 stays true).

### 25.14 Barcode
- `menu_items.barcode` (4–32 chars `[0-9A-Za-z-]`), **unique per outlet among active items** (`ux_menu_items_barcode`); the same item can be scanned by its barcode in the POS search box.
- **Keyboard-wedge rule** (scanners that type): in the POS search input, a burst of **≥ 4 characters typed with ≤ 35 ms between keystrokes, ending with Enter**, is a scan: it looks up the barcode exactly (no fuzzy match), adds one unit, plays a short beep, and does not open the search results. A human typing slowly is never treated as a scan. Unknown barcode → toast "Barcode 8901234 not found" and the field is kept. (35 ms and 4 characters are starting values; test with the actual scanners — **not verified**.)
- Label printing is out of scope. Barcode in the CSV import of items is a later task.

### 25.15 Customer-facing display (specification only)
A second window `/display` opened from the POS ("Customer display") on the second monitor. The POS tab publishes to a `BroadcastChannel('galla-display-v1')`; the display tab only listens, so it **works offline** and needs no server. Message `{type:'cart', lines:[{name, qty, amount}], subtotal, discount, tax, total, upiQr?, outletName, state:'IDLE|ORDERING|PAYING|THANKS'}`. It shows the lines, the total and, when paying by UPI, the QR from the bill dialog. **No personal data**: no customer name/phone/address, no table or staff names, no order numbers of other tables. Idle state shows the outlet name and a thank-you. Same-origin only; the tabs must be in the same browser profile. Display tab is read-only (no inputs). Not built: remote displays on another device (would need a server channel and a pairing step).

### 25.16 Central menu (several outlets of one tenant)
- Catalog tables are outlet-level (V002). A **master outlet** (the one the Owner picks in S25) *publishes* categories, items, variants and modifier groups to other outlets: first time it creates copies with `source_*_id` pointing at the master record (unique per outlet, so a copy cannot be duplicated); later publishes update the copies.
- **Outlet overrides:** when an outlet edits a published item (price, name, availability, station, tax profile, packaging charge, description, variants), the field name is added to `menu_items.overridden_fields`; a re-publish **skips overridden fields** and reports them (`skippedOverridden`). "Reset to master" removes the override. Items an outlet created itself have no source and are never touched. Modes: `ADD_AND_UPDATE` (default) or `ADD_ONLY`. Items removed at the master are deactivated at the outlets, never deleted (history). Every run is stored in `menu_publish_runs` with a summary and shown in S25.
- The central menu does **not** own taxes: a published item's `tax_profile_id` is mapped to the target outlet's profile with the same name; no match → the publish for that item fails with a listed error (nothing is half-published; the run is one transaction per target outlet).
- **ETag:** `outlet_menu_versions.version` is bumped **in the same transaction** as any change that affects `/catalog/pos` (items, variants, modifiers, combos, price rules, publish runs); the ETag of `/catalog/pos` is `W/"<outletId>-<version>"`. The offline snapshot (Section 24.3) uses the same version. A new outlet gets its `outlet_menu_versions` row when it is created.
- **Interaction with price rules:** price rules are per outlet and are **not** published in v1 (a happy hour is usually local); an item's list price may be published, rules then apply on top of the outlet's own price.
- Tax registration, bill series and printers stay per outlet.

### 25.17 Interactions with features that already exist
- **Hold bill:** a held order keeps its combo/open lines and price snapshots; a coupon is applied only when the bill is generated, so a held order has none. **Reprint:** reprints show the same lines/packaging/tip; credit notes have their own reprint. **Audit log:** every action here writes an audit row — coupon create/change/redeem/release, price-rule change, open item added, NC bill (with reason), tip override, shift open/close/variance, cash movement, credit override, settlement, adjustment, credit note (with approver), publish run, permission change.
- **Day close:** needs all shifts closed (25.10). **EOD summary** gets new keys (25.19). **Delivery charge** and **packaging** are independent extra lines. **WhatsApp bill** (Section 23) links the bill, not credit notes (a credit-note PDF is a later task). **Offline (Section 24):** combos, price-rule snapshots, open items, packaging and tips work offline (they are pure local calculation or data); coupons, refunds/credit notes, shift close, credit limits/settlements, NC and publishing need the server and a manager (blocked with a reason).

### 25.18 API summary (tenant-scoped; every outlet-scoped path checks the user's outlet; 404 across tenants)
| Method & path | Role | Notes |
|---|---|---|
| `GET/POST /coupons`, `PUT /coupons/{id}`, `GET /coupons/{id}/redemptions` | OWNER, MANAGER | no delete; `active=false` |
| `POST /bills/{id}/coupon` `{code}` / `DELETE /bills/{id}/coupon` | CASHIER, MANAGER, OWNER | GENERATED bills only; 422 with the reason code; delete releases |
| `GET /coupons/validate?code=&orderId=` | CASHIER+ | dry run, returns discount preview or reason code |
| `GET/POST /price-rules`, `PUT/DELETE /price-rules/{id}` | OWNER, MANAGER | bumps menu version |
| `POST /orders/{id}/items` (extended) | CAPTAIN, CASHIER, MANAGER, OWNER | `comboItemId` for combos; `open: {name, price, taxProfileId, stationId}` needs OPEN_ITEM; barcode lookup `GET /catalog/items?barcode=` |
| `GET/PUT /menu/combos/{itemId}/components` | OWNER, MANAGER | validates 25.3 |
| `POST /order-items/{id}/save-as-menu-item` | OWNER, MANAGER | |
| `PUT /outlets/{id}/billing-settings` | OWNER | packaging, NC tax mode, open-item max, tips, shifts required, credit sales |
| `GET/PUT /outlets/{id}/role-permissions` | OWNER | OPEN_ITEM per role |
| `GET/POST/PUT /reason-codes?kind=` | OWNER, MANAGER (read all) | |
| `POST /bills` (extended) | CASHIER+ | `complimentary: {reasonCode}` needs manager PIN header |
| `POST /bills/{id}/payments` (extended) | CASHIER+ | `tipAmount`, `tipStaffId`, `customerId` for ON_ACCOUNT |
| `POST /shifts` (open), `GET /shifts?date=`, `GET /shifts/{id}`, `POST /shifts/{id}/movements`, `POST /shifts/{id}/close` | CASHIER (own), MANAGER, OWNER | close takes `countedCash`, `handoverTo`, `note` |
| `POST /drawer/open` | CASHIER, MANAGER, OWNER | audited |
| `GET /customers/{id}/ledger`, `.../statement.csv`, `POST .../settlements`, `POST .../adjustments`, `PUT .../credit-limit` | CASHIER (ledger, settle), MANAGER (adjust), OWNER (limit) | |
| `GET /reports/dues-aging` | MANAGER, OWNER | |
| `POST /customers/{id}/due-reminder` | MANAGER, OWNER | via WhatsApp module |
| `GET /bills/{id}/refundable`, `POST /bills/{id}/credit-notes`, `GET /credit-notes?…`, `GET /credit-notes/{id}`, `POST /credit-notes/{id}/print` | CASHIER (needs manager PIN), MANAGER, OWNER | `Idempotency-Key` required on POST |
| `GET /kitchen/tickets?stationId=&status=`, `POST /order-items/{id}/kitchen-status` `{to}`, `POST /kots/{id}/bump` | KITCHEN, MANAGER, OWNER (cashier read-only) | SSE `kitchen.item.status` |
| `PUT /kitchen-stations/{id}/sla` | OWNER, MANAGER | |
| `POST /menu/publish` `{sourceOutletId, targetOutletIds[], mode}`, `GET /menu/publish-runs`, `POST /menu/items/{id}/reset-overrides` | OWNER | |
| `GET /reports/nc`, `/reports/open-items`, `/reports/tips`, `/reports/coupons`, `/reports/refunds` | MANAGER, OWNER | |
New error codes (Appendix B): see edits.md E-B.

### 25.19 UI specification (screens S18–S26; all follow Section 12.2: skeleton, empty and error states, never blank)
- **S18 Coupons (`/settings/coupons`, Owner/Manager):** table (code, type/value, validity chip, uses/limit, status). *New coupon* drawer: code (live "already used" check), type, value, cap, min bill, validity, weekdays (7 toggle chips), order types, three limits, active. Empty: "No coupons yet — create your first." Error on save shows the field. Row → redemptions list. On the bill dialog (S4): a "Coupon" field; failure text maps each reason code to a sentence ("Valid only Mon–Fri", "Minimum bill Rs 500", "Already used the maximum number of times").
- **S19 Price rules (`/settings/price-rules`):** list grouped by item/category, a weekly strip showing the active window (midnight-crossing windows drawn across two days), test box "What is the price of *item* on *day, time*?" calling the resolver. Conflict hint when two rules overlap with the same priority.
- **S20 Combo editor (inside S13 menu):** pick *Combo* as item kind, add component rows (item, variant, quantity), shows the **allocation preview** at the list prices. Validation messages for nesting/outlet/variant.
- **S21 Shifts & cash (`/shifts`):** *Open shift* (float, device), live shift card (expected so far, payments by method, tips, movements), *Pay-in / Pay-out / Drop* dialogs with reason, *Close shift* (count by denomination optional, counted total, shows expected and variance **after** counting; variance ≠ 0 needs a note), handover user. Manager list with variance chips. Empty: "No shift is open — open one to take payments" (only when `shifts_required`).
- **S22 Customer dues (`/customers/:id/dues`):** balance/limit meter (not colour alone), ledger table, aging chips, *Settle*, *Adjust*, *Export CSV*, *Send reminder*. A list view `/dues` sorted by balance with aging columns.
- **S23 Refund / credit note dialog (from the bill drawer, "Refund / Return"):** step 1 choose lines and quantities (steppers limited to refundable), step 2 reason + method (+ customer for ON_ACCOUNT, + "return to stock" toggles), step 3 totals preview from the server, manager PIN, *Issue credit note* → print. Disabled with reason when the bill is not PAID or nothing is refundable.
- **S24 Kitchen display (`/kitchen`) and S24b Expo (`/expo`):** full-screen, dark-theme default, ticket cards with timer and colour + minute count, bump/recall, station chips, sound toggle, connection chip ("Reconnecting… tickets may be stale"). Empty: "No tickets — all clear."
- **S25 Central menu (`/settings/central-menu`, Owner):** choose master outlet, target outlets, mode, **preview** (counts of created/updated/skipped), *Publish*; run history with summaries; per-item badge "Overridden at this outlet" with *Reset to master*.
- **S26 Billing settings (`/settings/billing`, Owner):** packaging, NC tax mode (with the "legal treatment not verified" note), open items (on/off, max price, role permission matrix), tips, shifts required, credit sales, reason-code lists (NC / refund / cash movement / adjustment), printers' "Open drawer on cash payment".
- **POS (S3/S4) additions:** barcode scan (25.14), "Open item" button (only with permission), combo tile with component preview, price-rule chip, tip buttons, "On account" payment method (only with a customer attached), "NC" action (manager PIN), "Hold" unchanged. **Customer display** button (25.15). **S12 Day close:** open shifts step; **S11 Reports:** NC, open items, tips, coupons, refunds, dues tabs.
- **EOD summary JSON (amends Section 10.3):** new keys `"nc":{"bills":2,"listValue":"640.00","taxLiability":"32.00","byReason":[…]}`, `"coupons":{"redeemed":9,"discount":"1240.00","byCode":[…]}`, `"packaging":"310.00"`, `"tips":{"total":"540.00","cash":"300.00","other":"240.00"}`, `"creditSales":{"charged":"2100.00","settled":"800.00","outstanding":"15400.00"}`, `"shifts":[{"cashier":"Asha","opening":"2000.00","expected":"24100.00","counted":"24050.00","variance":"-50.00"}]`, `"refunds":{"count":3,"amount":"620.00","byMethod":[…]}`, `"openItems":{"count":4,"amount":"900.00"}`. The old single `cash` object is replaced by `shifts` (kept for outlets without shifts).
- **Print layouts (amends Section 8.2/8.3):** *Bill* — combo header with indented components, `Packaging charge` line, `Coupon WELCOME10 −36.00` instead of `Discount`, `NC — Complimentary` banner with the reason, `Tip (not part of bill)` after the total, `Paid: On account` with the customer's name and balance (no balance if the setting is off), no QR for NC. *KOT* — combo heading and indented components, "OPEN ITEM" tag, "Order type · Table". *Credit note* — see 25.12.

### 25.20 Database — Migration V013 *(verified on PostgreSQL 16 on top of V001–V011: 231 accept/reject cases pass, every FAIL case with the intended error)*
The SQL is in 25.26. Table groups and what they enforce: outlet settings (packaging, NC mode, open items, tips, shifts, credit); `reason_codes`, `outlet_role_permissions`; `menu_items` (barcode, packaging charge, combo kind, central-menu links); `combo_components` (+ guard trigger); `price_rules`; `order_items` (open item, combo, price snapshot, kitchen status machine); `cashier_shifts`, `cash_movements` (append-only), day-close trigger; `customers.credit_limit`, `customer_ledger` (append-only); `coupons`, `coupon_redemptions` (limits under a row lock, release only); `bills` (NC, packaging, coupon) and the widened `bill_lines` type CHECK; `payments` (ON_ACCOUNT, tips, shift guard); `credit_notes`, `credit_note_lines`, `credit_note_line_taxes` (immutable, caps, void guard); `outlet_menu_versions`, `menu_publish_runs`. Columns that point at tables of other streams (`cashier_shifts.device_id`) are plain `uuid`; their foreign keys are added in V016. New outlets must get an `outlet_menu_versions` row from the application; default `reason_codes` are seeded by the application (not by SQL).

### 25.21 Security and abuse controls
- **Manager PIN** (Section 22 override) is required for: NC, refund/credit note by a cashier, credit-limit override, price/permission changes by non-owners; the approving user id is stored (`credit_notes.approved_by`) and audited; PIN attempts are rate-limited by the existing override rules.
- **Fraud-prone actions are visible:** open items, NC bills, discounts via coupon, refunds, drawer opens, cash pay-outs, ledger adjustments and shift variances all appear in reports and in the EOD summary with the user. Append-only tables (cash movements, ledger, credit notes and their lines, coupon redemptions except release) reject UPDATE/DELETE even for the application user — a bug or a malicious change fails at the database.
- Coupon codes are not secrets but are rate-limited on `GET /coupons/validate` (20 per minute per user) to stop guessing. A coupon can never be applied across tenants (404).
- Tenant isolation: every new table carries `tenant_id`; every query is tenant-scoped from the token; ids in payloads (customer, coupon, shift, bill line) are checked against the token's tenant and outlet.
- Customer dues and statements are personal data: access limited by role; the customer display (25.15) and the reminder template (25.11) carry no bill details; CSV exports are audited.
- **Idempotency:** `POST /bills/{id}/credit-notes`, settlements, movements and coupon apply take `Idempotency-Key`, so a double tap cannot refund twice (the DB caps are the second line of defence).
- Clock: price windows, coupon validity and shift dates use the **server clock in the outlet timezone**; an offline terminal uses its own clock for price snapshots only (Section 24.7 clock-skew rules apply).

### 25.22 Failure modes
| Situation | Behaviour |
|---|---|
| Two cashiers redeem the last coupon use | one succeeds, the other `COUPON_LIMIT_TOTAL` (row lock in trigger) |
| Refund requested for more than is left (double tap, two managers) | `REFUND_EXCEEDS_*`, nothing written; the second request is also deduplicated by `Idempotency-Key` |
| Credit note insert fails after the counter was incremented | same transaction, rolled back: no `CN` number is lost |
| Shift left open overnight | day close blocked (`OPEN_SHIFTS_EXIST`); manager can close it on the cashier's behalf with a count and a note |
| Cashier's device dies mid-shift | the shift is closed from another device by a manager; payments keep their `shift_id` |
| Price rule changes while an order is open | existing lines keep their snapshot; new lines use the new rule |
| Master menu publish fails for one outlet | that outlet's transaction rolls back, others succeed; the run summary lists the error |
| Customer over limit at counter | `CREDIT_LIMIT_EXCEEDED` with "Ask a manager to approve" |
| KDS loses its connection | banner "Reconnecting — tickets may be stale"; on reconnect it reloads the full list; the printed KOT is unaffected |
| Barcode unknown or duplicated | toast / unique violation `BARCODE_IN_USE` |

### 25.23 Tests (what the implementing agent must write)
- **Python reference (executable now, `reference/` — 60 tests, all pass; run together with the 52 existing ones):** BX01–BX08 combos (exact sums, tax per component, stock interface, 300 random combos), BX10–BX19 coupons (every reason code, caps, inclusive/exclusive boundaries, case-insensitive find, property: discount ≤ min(subtotal, cap)), BX30–BX39 price rules (window edges, midnight crossing, valid dates on the start day, priority ties, snapshot contract, property: window membership), BX45–BX48 NC (both tax modes, inclusive pricing), BX50–BX55 KDS (transition table identical to the DB trigger, bump/recall, SLA colours, random walk), BX60–BX66 shifts (expected, variance, one-open rules, property), BX70–BX75 credit (limit boundary, balance, FIFO aging, property), BX80–BX91 credit notes (proportional refund, last piece exact, header rounding, 250-case property "refund everything in random pieces equals the original exactly and never exceeds it").
- **Database:** the 231 cases of V013 (25.20): every CHECK, unique index, trigger and append-only rule, including parallel-safe limits modelled sequentially.
- **Java:** port `combo.py`, `coupon.py`, `pricing_rules.py`, `nc.py`, `shift.py`, `credit.py`, `credit_note.py`, `kds.py` as services with the **same vectors**; jqwik properties for BX07, BX75, BX90 (10 000 cases). Contract test: the credit-note service output equals `credit_note.py` for 500 generated bills.
- **Integration (Testcontainers):** concurrent coupon redemption (20 threads, limit 5 → exactly 5); concurrent refunds of the same line; void of a bill with a coupon releases it; `CN` numbering gapless under rollback; day close blocked by an open shift; payment without shift when required; ON_ACCOUNT over the limit; kitchen transitions via API incl. illegal one; publish run with an overridden field; `/catalog/pos` ETag changes after a price-rule edit; tenant isolation on every new endpoint.
- **Frontend (Vitest/Playwright component):** barcode burst detection (fast burst = scan; slow typing = text; Enter without burst = text), customer display receives only the whitelisted fields, KDS timer colours at the boundaries.

### 25.24 E2E scenarios (numbered after 33)
34. **Combo:** add "Thali Combo ×2" (two components at two stations) → two KOTs with indented components → bill shows allocated amounts, per-component GST; sum equals combo price × 2; refund one component line → credit note amount equals that line's stored amounts.
35. **Coupon:** apply `welcome10` (lower-case) → discount capped at `max_discount`; second coupon refused (`COUPON_NOT_STACKABLE`); two cashiers redeem the last use at once → one `COUPON_LIMIT_TOTAL`; void the bill → the use is available again.
36. **Happy hour:** rule 16:00–19:00 −20 %; item added 18:55 keeps the price when billed 19:05; a Fri 22:00–02:00 rule still applies at Sat 01:00; edit the rule → open order unchanged.
37. **Packaging:** takeaway flat charge appears once; split into two bills → only the first has it; void the first → the second shows it; discount does not reduce it; service charge base excludes it.
38. **Open item:** cashier without permission gets 403 and no button; manager adds "Special thali" 450 (max 500) → flagged on KOT/bill/report; price 501 refused; "save as menu item" creates the item.
39. **NC:** manager PIN + reason → total 0, no payment, "NC" on print; mode `TAX_ON_LIST_PRICE` shows the liability in the NC report, `ZERO_TAX` shows 0; coupon on an NC bill refused.
40. **Tips and shifts:** open shift (float 2000) → cash bill 340 with tip 20 → UPI bill → pay-out 100 "supplier" → drop 1000 → close with count: expected, variance and note shown; day close blocked while a second cashier's shift is open, allowed after it is closed; drawer pulse sent on cash payment (emulated printer).
41. **Credit sales:** customer limit 1000; ON_ACCOUNT 900 ok; +200 blocked; manager override passes and is audited; settle 500 cash → drawer expected increases; statement CSV equals ledger; aging buckets after backdated rows.
42. **Refund / credit note:** paid bill → partial refund 1 of 3 units (card, reference typed) → CN number 1 → refund the rest → totals equal the original to the paisa; refund again → `REFUND_EXCEEDS_*`; void now refused; ON_ACCOUNT refund lowers the balance; coupon released after a full refund; credit note prints with "against bill".
43. **Kitchen display:** ticket appears with sound after "Tap to enable"; amber at 10 min, red at 20; bump to READY → waiter chip "Ready"; recall; expo highlights an all-READY order; illegal jump blocked.
44. **Barcode, customer display, central menu:** scan "8901234" → item added with one beep, slow typing does not scan; `/display` shows lines and QR without any name/phone; publish master → branch gets items; branch changes a price → re-publish skips it and reports it; `/catalog/pos` ETag changes.
- **Not testable without real hardware:** drawer kick on a real cash drawer, barcode scanners' timing, a second monitor, sound autoplay policies per browser — a manual checklist `docs/EVERYDAY_BILLING_GO_LIVE.md` (agent to create).

### 25.25 Build phase — Phase 1B *(after Phase 1; ≈ 4–5 weeks; before offline mode if the first customers need dues and refunds)*
**Tasks, in order:** V013 → reason codes, permissions, billing settings → price rules + resolver (Java port) → combos (header/components, allocation) → packaging line → open items → coupons (+ concurrency) → NC → tips → shifts and cash movements, drawer kick, day-close gate → credit ledger and ON_ACCOUNT → credit notes (CN counter, caps, print) → KDS (status API, SSE, S24/S24b) → barcode → customer display → central menu publish → reports and EOD keys → screens S18–S26 → E2E 34–44 → go-live checklist.
**Accept when:** every reference test BX01–BX91 passes as a Java test on the same vectors; the 231 V013 cases pass on a clean database and on a database that already holds orders and bills; E2E 34–44 pass; no scenario produces a bill or credit note whose parts do not add up to the paisa; the manual hardware checklist is done.

### 25.26 Migration SQL (exactly as verified)
```sql
-- V013 — everyday billing features: combos, coupons, time-based prices, packaging, open items, NC bills, tips,
--        cashier shifts & cash drawer, customer credit (dues), credit notes, kitchen display, barcode, central menu.
-- Applies on top of V001..V011. Columns that point at tables owned by other streams (e.g. devices) are plain uuid; FK added in V016.

-- ============ 1. outlet settings ============
ALTER TABLE outlets
  ADD COLUMN packaging_mode text NOT NULL DEFAULT 'NONE' CHECK (packaging_mode IN ('NONE','FLAT_PER_ORDER','PER_ITEM')),
  ADD COLUMN packaging_flat_charge numeric(12,2) NOT NULL DEFAULT 0 CHECK (packaging_flat_charge >= 0),
  ADD COLUMN packaging_order_types text[] NOT NULL DEFAULT '{TAKEAWAY,DELIVERY}'
        CHECK (packaging_order_types <@ ARRAY['DINE_IN','TAKEAWAY','DELIVERY']::text[]),
  ADD COLUMN packaging_tax_profile_id uuid REFERENCES tax_profiles(id),
  ADD COLUMN nc_tax_mode text NOT NULL DEFAULT 'ZERO_TAX' CHECK (nc_tax_mode IN ('ZERO_TAX','TAX_ON_LIST_PRICE')),
  ADD COLUMN open_items_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN open_item_max_price numeric(12,2) NOT NULL DEFAULT 500 CHECK (open_item_max_price > 0),
  ADD COLUMN tips_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN shifts_required boolean NOT NULL DEFAULT false,
  ADD COLUMN credit_sales_enabled boolean NOT NULL DEFAULT false,
  ADD CONSTRAINT outlets_packaging_flat_needs_amount CHECK (packaging_mode <> 'FLAT_PER_ORDER' OR packaging_flat_charge > 0);

ALTER TABLE printers ADD COLUMN opens_cash_drawer boolean NOT NULL DEFAULT false;   -- ESC/POS drawer kick on cash payment / pay-out

ALTER TABLE kitchen_stations
  ADD COLUMN sla_warn_minutes int NOT NULL DEFAULT 10 CHECK (sla_warn_minutes BETWEEN 1 AND 240),
  ADD COLUMN sla_late_minutes int NOT NULL DEFAULT 20 CHECK (sla_late_minutes BETWEEN 1 AND 480),
  ADD CONSTRAINT stations_sla_order CHECK (sla_warn_minutes < sla_late_minutes);

-- ============ 2. reason codes & per-outlet role permissions ============
CREATE TABLE reason_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  kind text NOT NULL CHECK (kind IN ('NC','REFUND','CASH_MOVEMENT','CREDIT_ADJUSTMENT')),
  code text NOT NULL CHECK (code ~ '^[A-Z0-9_]{2,30}$'),
  label text NOT NULL CHECK (length(btrim(label)) > 0),
  active boolean NOT NULL DEFAULT true,
  UNIQUE (tenant_id, kind, code)
);

CREATE TABLE outlet_role_permissions (            -- a missing row = the built-in default (OPEN_ITEM: OWNER and MANAGER only)
  outlet_id uuid NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  role text NOT NULL CHECK (role IN ('OWNER','MANAGER','CASHIER','CAPTAIN','KITCHEN','RIDER','INVENTORY')),
  permission text NOT NULL CHECK (permission IN ('OPEN_ITEM')),
  allowed boolean NOT NULL,
  PRIMARY KEY (outlet_id, role, permission)
);

-- ============ 3. menu: barcode, packaging, combos, central-menu links ============
ALTER TABLE menu_items
  ADD COLUMN barcode text CHECK (barcode IS NULL OR barcode ~ '^[0-9A-Za-z-]{4,32}$'),
  ADD COLUMN packaging_charge numeric(12,2) NOT NULL DEFAULT 0 CHECK (packaging_charge >= 0),   -- per unit, used when outlet.packaging_mode = PER_ITEM
  ADD COLUMN item_kind text NOT NULL DEFAULT 'STANDARD' CHECK (item_kind IN ('STANDARD','COMBO')),
  ADD COLUMN source_item_id uuid REFERENCES menu_items(id),                 -- set on copies published from a master outlet's item
  ADD COLUMN overridden_fields text[] NOT NULL DEFAULT '{}'                  -- fields the outlet changed itself; re-publish skips them
        CHECK (overridden_fields <@ ARRAY['name','base_price','tax_profile_id','station_id','available','description','packaging_charge','variants']::text[]);
CREATE UNIQUE INDEX ux_menu_items_barcode ON menu_items(outlet_id, barcode) WHERE barcode IS NOT NULL AND active;
CREATE UNIQUE INDEX ux_menu_items_source ON menu_items(outlet_id, source_item_id) WHERE source_item_id IS NOT NULL;
ALTER TABLE menu_categories ADD COLUMN source_category_id uuid REFERENCES menu_categories(id);
CREATE UNIQUE INDEX ux_menu_categories_source ON menu_categories(outlet_id, source_category_id) WHERE source_category_id IS NOT NULL;
ALTER TABLE modifier_groups ADD COLUMN source_group_id uuid REFERENCES modifier_groups(id);
CREATE UNIQUE INDEX ux_modifier_groups_source ON modifier_groups(outlet_id, source_group_id) WHERE source_group_id IS NOT NULL;

CREATE TABLE combo_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  combo_item_id uuid NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  component_item_id uuid NOT NULL REFERENCES menu_items(id),
  component_variant_id uuid REFERENCES item_variants(id),
  quantity numeric(10,3) NOT NULL CHECK (quantity > 0),
  sort_order int NOT NULL DEFAULT 0,
  CHECK (combo_item_id <> component_item_id)
);
CREATE UNIQUE INDEX ux_combo_components ON combo_components(combo_item_id, component_item_id, COALESCE(component_variant_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE FUNCTION fn_combo_components_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k_combo text; k_comp text; o_combo uuid; o_comp uuid;
BEGIN
  SELECT item_kind, outlet_id INTO k_combo, o_combo FROM menu_items WHERE id = NEW.combo_item_id;
  SELECT item_kind, outlet_id INTO k_comp,  o_comp  FROM menu_items WHERE id = NEW.component_item_id;
  IF k_combo <> 'COMBO' THEN RAISE EXCEPTION 'COMBO_PARENT_NOT_COMBO' USING ERRCODE = '23514'; END IF;
  IF k_comp  <> 'STANDARD' THEN RAISE EXCEPTION 'COMBO_NESTING_NOT_ALLOWED' USING ERRCODE = '23514'; END IF;
  IF o_combo <> o_comp THEN RAISE EXCEPTION 'COMBO_COMPONENT_OTHER_OUTLET' USING ERRCODE = '23514'; END IF;
  IF NEW.component_variant_id IS NOT NULL AND NOT EXISTS
     (SELECT 1 FROM item_variants WHERE id = NEW.component_variant_id AND menu_item_id = NEW.component_item_id)
  THEN RAISE EXCEPTION 'COMBO_VARIANT_MISMATCH' USING ERRCODE = '23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_combo_components_guard BEFORE INSERT OR UPDATE ON combo_components FOR EACH ROW EXECUTE FUNCTION fn_combo_components_guard();

-- ============ 4. time-based price rules ============
CREATE TABLE price_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  scope_type text NOT NULL CHECK (scope_type IN ('ITEM','VARIANT','CATEGORY')),
  menu_item_id uuid REFERENCES menu_items(id),
  variant_id uuid REFERENCES item_variants(id),
  category_id uuid REFERENCES menu_categories(id),
  weekdays smallint[] NOT NULL DEFAULT '{1,2,3,4,5,6,7}'                  -- ISO: 1 = Monday .. 7 = Sunday; the weekday on which the WINDOW STARTS
        CHECK (cardinality(weekdays) >= 1 AND weekdays <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),
  start_time time NOT NULL,
  end_time time NOT NULL,                                                   -- end < start means the window crosses midnight; end = start is invalid
  valid_from date, valid_to date,
  order_types text[] NOT NULL DEFAULT '{DINE_IN,TAKEAWAY,DELIVERY}'
        CHECK (cardinality(order_types) >= 1 AND order_types <@ ARRAY['DINE_IN','TAKEAWAY','DELIVERY']::text[]),
  action text NOT NULL CHECK (action IN ('PRICE_OVERRIDE','PERCENT_OFF')),
  price numeric(12,2) CHECK (price IS NULL OR price >= 0),
  percent_off numeric(5,2) CHECK (percent_off IS NULL OR (percent_off > 0 AND percent_off <= 100)),
  priority int NOT NULL DEFAULT 0 CHECK (priority BETWEEN 0 AND 1000),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_time <> end_time),
  CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
  CHECK ((action = 'PRICE_OVERRIDE' AND price IS NOT NULL AND percent_off IS NULL)
      OR (action = 'PERCENT_OFF'    AND percent_off IS NOT NULL AND price IS NULL)),
  CHECK ((scope_type = 'ITEM'     AND menu_item_id IS NOT NULL AND variant_id IS NULL AND category_id IS NULL)
      OR (scope_type = 'VARIANT'  AND variant_id IS NOT NULL AND menu_item_id IS NULL AND category_id IS NULL)
      OR (scope_type = 'CATEGORY' AND category_id IS NOT NULL AND menu_item_id IS NULL AND variant_id IS NULL)),
  CHECK (scope_type <> 'CATEGORY' OR action = 'PERCENT_OFF')                -- a category has no single price to override
);
CREATE INDEX ix_price_rules_outlet ON price_rules(outlet_id) WHERE active;

-- ============ 5. order lines: open items, combos, price snapshot, kitchen status ============
ALTER TABLE order_items
  ALTER COLUMN menu_item_id DROP NOT NULL,
  ADD COLUMN is_open_item boolean NOT NULL DEFAULT false,
  ADD COLUMN price_source text NOT NULL DEFAULT 'LIST' CHECK (price_source IN ('LIST','PRICE_RULE','OPEN_ITEM','COMBO')),
  ADD COLUMN list_unit_price numeric(12,2) CHECK (list_unit_price IS NULL OR list_unit_price >= 0),  -- price before any rule (used by NC TAX_ON_LIST_PRICE reporting)
  ADD COLUMN price_rule_id uuid REFERENCES price_rules(id) ON DELETE SET NULL,
  ADD COLUMN price_rule_name text,
  ADD COLUMN combo_role text NOT NULL DEFAULT 'NONE' CHECK (combo_role IN ('NONE','HEADER','COMPONENT')),
  ADD COLUMN combo_parent_id uuid REFERENCES order_items(id) ON DELETE CASCADE,
  ADD COLUMN fixed_line_amount numeric(12,2) CHECK (fixed_line_amount IS NULL OR fixed_line_amount >= 0),  -- allocated combo amount for the WHOLE component line
  ADD COLUMN kitchen_status text NOT NULL DEFAULT 'NEW' CHECK (kitchen_status IN ('NEW','PREPARING','READY','SERVED')),
  ADD COLUMN preparing_at timestamptz, ADD COLUMN ready_at timestamptz, ADD COLUMN served_at timestamptz,
  ADD CONSTRAINT order_items_open_item_shape CHECK (is_open_item = (menu_item_id IS NULL)),
  ADD CONSTRAINT order_items_open_item_source CHECK (NOT is_open_item OR price_source = 'OPEN_ITEM'),
  ADD CONSTRAINT order_items_combo_shape CHECK (
        (combo_role = 'COMPONENT') = (combo_parent_id IS NOT NULL)
    AND (combo_role <> 'COMPONENT' OR fixed_line_amount IS NOT NULL)
    AND (combo_role = 'COMPONENT' OR fixed_line_amount IS NULL)),
  ADD CONSTRAINT order_items_kitchen_only_after_kot CHECK (kitchen_status = 'NEW' OR kot_id IS NOT NULL);
CREATE INDEX ix_order_items_kitchen ON order_items(kot_id, kitchen_status) WHERE kot_id IS NOT NULL AND status = 'ACTIVE';

-- the kitchen status machine (forward by one or skip, plus recall one step back)
CREATE FUNCTION fn_order_items_kitchen_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.kitchen_status IS DISTINCT FROM OLD.kitchen_status THEN
    IF NOT ((OLD.kitchen_status, NEW.kitchen_status) IN
        (('NEW','PREPARING'),('NEW','READY'),('PREPARING','READY'),('READY','SERVED'),
         ('PREPARING','NEW'),('READY','PREPARING'),('SERVED','READY'))) THEN
      RAISE EXCEPTION 'ILLEGAL_KITCHEN_TRANSITION % -> %', OLD.kitchen_status, NEW.kitchen_status USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_order_items_kitchen BEFORE UPDATE OF kitchen_status ON order_items FOR EACH ROW EXECUTE FUNCTION fn_order_items_kitchen_transition();

-- ============ 6. cashier shifts, cash movements ============
CREATE TABLE cashier_shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  device_id uuid,                                                           -- terminal; FK to devices added in V016
  cashier_id uuid NOT NULL REFERENCES users(id),
  business_date date NOT NULL,
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','CLOSED')),
  opened_at timestamptz NOT NULL DEFAULT now(),
  opening_float numeric(12,2) NOT NULL DEFAULT 0 CHECK (opening_float >= 0),
  closed_at timestamptz,
  counted_cash numeric(12,2) CHECK (counted_cash IS NULL OR counted_cash >= 0),
  expected_cash numeric(12,2),
  variance numeric(12,2),                                                   -- counted - expected
  closed_by uuid REFERENCES users(id),
  handover_to uuid REFERENCES users(id),
  note text,
  CHECK ((status = 'OPEN'   AND closed_at IS NULL AND counted_cash IS NULL AND expected_cash IS NULL AND variance IS NULL)
      OR (status = 'CLOSED' AND closed_at IS NOT NULL AND counted_cash IS NOT NULL AND expected_cash IS NOT NULL AND variance IS NOT NULL AND closed_by IS NOT NULL)),
  CHECK (variance IS NULL OR variance = counted_cash - expected_cash),
  CHECK (handover_to IS NULL OR handover_to <> cashier_id)
);
CREATE UNIQUE INDEX ux_shift_one_open_per_cashier ON cashier_shifts(cashier_id) WHERE status = 'OPEN';
CREATE UNIQUE INDEX ux_shift_one_open_per_device  ON cashier_shifts(device_id) WHERE status = 'OPEN' AND device_id IS NOT NULL;
CREATE INDEX ix_shifts_outlet_date ON cashier_shifts(outlet_id, business_date);

CREATE TABLE cash_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  shift_id uuid NOT NULL REFERENCES cashier_shifts(id),
  kind text NOT NULL CHECK (kind IN ('PAY_IN','PAY_OUT','DROP')),
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  reason_code text NOT NULL CHECK (length(btrim(reason_code)) > 0),
  note text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_cash_movements_shift ON cash_movements(shift_id);

CREATE FUNCTION fn_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'APPEND_ONLY_TABLE % cannot be %', TG_TABLE_NAME, TG_OP USING ERRCODE = '23514'; END $$;
CREATE TRIGGER trg_cash_movements_append_only BEFORE UPDATE OR DELETE ON cash_movements FOR EACH ROW EXECUTE FUNCTION fn_append_only();

-- day close needs every shift of the outlet closed
CREATE FUNCTION fn_day_close_needs_closed_shifts() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'CLOSED' AND OLD.status <> 'CLOSED'
     AND EXISTS (SELECT 1 FROM cashier_shifts WHERE outlet_id = NEW.outlet_id AND status = 'OPEN') THEN
    RAISE EXCEPTION 'OPEN_SHIFTS_EXIST' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_day_close_shifts BEFORE UPDATE OF status ON day_closings FOR EACH ROW EXECUTE FUNCTION fn_day_close_needs_closed_shifts();

-- ============ 7. customer credit (dues) ============
ALTER TABLE customers ADD COLUMN credit_limit numeric(12,2) NOT NULL DEFAULT 0 CHECK (credit_limit >= 0);   -- 0 = no credit allowed

CREATE TABLE customer_ledger (                                              -- append-only; balance = SUM(amount); positive = customer owes
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  customer_id uuid NOT NULL REFERENCES customers(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  entry_type text NOT NULL CHECK (entry_type IN ('CHARGE','PAYMENT','CREDIT_NOTE','ADJUSTMENT')),
  amount numeric(12,2) NOT NULL CHECK (amount <> 0),
  bill_id uuid REFERENCES bills(id),
  payment_id uuid REFERENCES payments(id),
  credit_note_id uuid,                                                      -- FK added below (credit_notes is defined later in this file)
  method text CHECK (method IN ('CASH','CARD','UPI','OTHER')),              -- how a settlement PAYMENT was made
  reference text,
  reason text,
  shift_id uuid REFERENCES cashier_shifts(id),                              -- a cash settlement lands in this shift's drawer
  business_date date NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (entry_type <> 'CHARGE'      OR (amount > 0 AND bill_id IS NOT NULL)),
  CHECK (entry_type <> 'PAYMENT'     OR (amount < 0 AND method IS NOT NULL)),
  CHECK (entry_type <> 'CREDIT_NOTE' OR (amount < 0 AND credit_note_id IS NOT NULL)),
  CHECK (entry_type <> 'ADJUSTMENT'  OR (reason IS NOT NULL AND length(btrim(reason)) >= 5)),
  CHECK (method IS NULL OR entry_type = 'PAYMENT')
);
CREATE INDEX ix_ledger_customer ON customer_ledger(tenant_id, customer_id, created_at);
CREATE TRIGGER trg_ledger_append_only BEFORE UPDATE OR DELETE ON customer_ledger FOR EACH ROW EXECUTE FUNCTION fn_append_only();

-- ============ 8. coupons ============
CREATE TABLE coupons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),                                    -- NULL = every outlet of the tenant
  code text NOT NULL CHECK (code ~ '^[A-Za-z0-9_-]{3,24}$'),
  description text,
  discount_type text NOT NULL CHECK (discount_type IN ('PERCENT','AMOUNT')),
  value numeric(12,2) NOT NULL CHECK (value > 0),
  max_discount numeric(12,2) CHECK (max_discount IS NULL OR max_discount > 0),
  min_bill numeric(12,2) NOT NULL DEFAULT 0 CHECK (min_bill >= 0),
  valid_from timestamptz, valid_to timestamptz,
  weekdays smallint[] NOT NULL DEFAULT '{1,2,3,4,5,6,7}' CHECK (cardinality(weekdays) >= 1 AND weekdays <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),
  order_types text[] NOT NULL DEFAULT '{DINE_IN,TAKEAWAY,DELIVERY}' CHECK (cardinality(order_types) >= 1 AND order_types <@ ARRAY['DINE_IN','TAKEAWAY','DELIVERY']::text[]),
  usage_limit_total int CHECK (usage_limit_total IS NULL OR usage_limit_total > 0),
  usage_limit_per_customer int CHECK (usage_limit_per_customer IS NULL OR usage_limit_per_customer > 0),
  usage_limit_per_day int CHECK (usage_limit_per_day IS NULL OR usage_limit_per_day > 0),
  stackable boolean NOT NULL DEFAULT false CHECK (stackable = false),       -- v1: one coupon per bill; the column exists so a later version can relax it
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (discount_type <> 'PERCENT' OR value <= 100),
  CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);
CREATE UNIQUE INDEX ux_coupons_code ON coupons(tenant_id, lower(code));

-- ============ 9. bills: NC, packaging, coupon ============
ALTER TABLE bills
  ADD COLUMN is_complimentary boolean NOT NULL DEFAULT false,
  ADD COLUMN nc_reason_code text,
  ADD COLUMN nc_tax_liability numeric(12,2) NOT NULL DEFAULT 0 CHECK (nc_tax_liability >= 0),   -- tax the restaurant bears when outlet.nc_tax_mode = TAX_ON_LIST_PRICE (informational; not payable by the guest)
  ADD COLUMN packaging_charge_total numeric(12,2) NOT NULL DEFAULT 0 CHECK (packaging_charge_total >= 0),
  ADD COLUMN packaging_kind text CHECK (packaging_kind IN ('FLAT','PER_ITEM')),                   -- how the packaging line was computed
  ADD COLUMN coupon_id uuid REFERENCES coupons(id),
  ADD COLUMN coupon_code text,
  ADD CONSTRAINT bills_nc_shape CHECK (NOT is_complimentary OR (grand_total = 0 AND nc_reason_code IS NOT NULL AND length(btrim(nc_reason_code)) > 0)),
  ADD CONSTRAINT bills_nc_no_extras CHECK (NOT is_complimentary OR (packaging_charge_total = 0 AND delivery_charge_total = 0 AND service_charge_total = 0 AND coupon_id IS NULL)),
  ADD CONSTRAINT bills_nc_liability_only_nc CHECK (is_complimentary OR nc_tax_liability = 0),
  ADD CONSTRAINT bills_packaging_kind_set CHECK ((packaging_charge_total = 0) = (packaging_kind IS NULL)),
  ADD CONSTRAINT bills_coupon_has_discount CHECK (coupon_id IS NULL OR (discount_total > 0 AND coupon_code IS NOT NULL));
-- a FLAT packaging charge is charged once per order (split bills); PER_ITEM follows the items, so each bill carries its own
CREATE UNIQUE INDEX ux_bills_packaging_flat_once ON bills(order_id) WHERE packaging_kind = 'FLAT' AND status <> 'VOID';
ALTER TABLE bill_lines DROP CONSTRAINT bill_lines_line_type_check;
ALTER TABLE bill_lines ADD CONSTRAINT bill_lines_line_type_check CHECK (line_type IN ('ITEM','SERVICE_CHARGE','DELIVERY_CHARGE','PACKAGING_CHARGE'));

CREATE TABLE coupon_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  coupon_id uuid NOT NULL REFERENCES coupons(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  bill_id uuid NOT NULL REFERENCES bills(id),
  customer_id uuid REFERENCES customers(id),
  business_date date NOT NULL,
  discount_amount numeric(12,2) NOT NULL CHECK (discount_amount > 0),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RELEASED')),
  released_at timestamptz, release_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((status = 'ACTIVE' AND released_at IS NULL) OR (status = 'RELEASED' AND released_at IS NOT NULL AND release_reason IS NOT NULL))
);
CREATE UNIQUE INDEX ux_coupon_one_active_per_bill ON coupon_redemptions(bill_id) WHERE status = 'ACTIVE';
CREATE INDEX ix_coupon_redemptions_coupon ON coupon_redemptions(coupon_id, status);

-- usage limits are enforced INSIDE the database under a row lock on the coupon, so parallel redemptions cannot overshoot a limit
CREATE FUNCTION fn_coupon_redemption_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c coupons%ROWTYPE; n int;
BEGIN
  SELECT * INTO c FROM coupons WHERE id = NEW.coupon_id FOR UPDATE;
  IF NEW.status = 'ACTIVE' THEN
    IF NOT c.active THEN RAISE EXCEPTION 'COUPON_INACTIVE' USING ERRCODE = '23514'; END IF;
    IF c.usage_limit_total IS NOT NULL THEN
      SELECT count(*) INTO n FROM coupon_redemptions WHERE coupon_id = c.id AND status = 'ACTIVE';
      IF n >= c.usage_limit_total THEN RAISE EXCEPTION 'COUPON_LIMIT_TOTAL' USING ERRCODE = '23514'; END IF;
    END IF;
    IF c.usage_limit_per_customer IS NOT NULL THEN
      IF NEW.customer_id IS NULL THEN RAISE EXCEPTION 'COUPON_CUSTOMER_REQUIRED' USING ERRCODE = '23514'; END IF;
      SELECT count(*) INTO n FROM coupon_redemptions WHERE coupon_id = c.id AND customer_id = NEW.customer_id AND status = 'ACTIVE';
      IF n >= c.usage_limit_per_customer THEN RAISE EXCEPTION 'COUPON_LIMIT_CUSTOMER' USING ERRCODE = '23514'; END IF;
    END IF;
    IF c.usage_limit_per_day IS NOT NULL THEN
      SELECT count(*) INTO n FROM coupon_redemptions WHERE coupon_id = c.id AND outlet_id = NEW.outlet_id AND business_date = NEW.business_date AND status = 'ACTIVE';
      IF n >= c.usage_limit_per_day THEN RAISE EXCEPTION 'COUPON_LIMIT_DAY' USING ERRCODE = '23514'; END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_coupon_redemption_guard BEFORE INSERT ON coupon_redemptions FOR EACH ROW EXECUTE FUNCTION fn_coupon_redemption_guard();

-- only ACTIVE -> RELEASED is allowed; nothing else about a redemption may change, and rows are never deleted
CREATE FUNCTION fn_coupon_redemption_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'APPEND_ONLY_TABLE coupon_redemptions cannot be DELETE' USING ERRCODE = '23514'; END IF;
  IF OLD.status = 'ACTIVE' AND NEW.status = 'RELEASED'
     AND (NEW.coupon_id, NEW.bill_id, NEW.outlet_id, NEW.discount_amount, NEW.business_date, NEW.tenant_id)
         IS NOT DISTINCT FROM (OLD.coupon_id, OLD.bill_id, OLD.outlet_id, OLD.discount_amount, OLD.business_date, OLD.tenant_id)
  THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'APPEND_ONLY_TABLE coupon_redemptions allows only ACTIVE -> RELEASED' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_coupon_redemption_immutable BEFORE UPDATE OR DELETE ON coupon_redemptions FOR EACH ROW EXECUTE FUNCTION fn_coupon_redemption_immutable();

-- ============ 10. payments: ON_ACCOUNT, tips, shift ============
ALTER TABLE payments
  ADD COLUMN tip_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (tip_amount >= 0),
  ADD COLUMN tip_staff_id uuid REFERENCES users(id),
  ADD COLUMN customer_id uuid REFERENCES customers(id),
  ADD COLUMN shift_id uuid REFERENCES cashier_shifts(id);
ALTER TABLE payments DROP CONSTRAINT payments_method_check;
ALTER TABLE payments ADD CONSTRAINT payments_method_check CHECK (method IN ('CASH','CARD','UPI','OTHER','ON_ACCOUNT'));
ALTER TABLE payments
  ADD CONSTRAINT payments_on_account_needs_customer CHECK (method <> 'ON_ACCOUNT' OR customer_id IS NOT NULL),
  ADD CONSTRAINT payments_on_account_no_tip CHECK (method <> 'ON_ACCOUNT' OR tip_amount = 0),
  ADD CONSTRAINT payments_on_account_no_tender CHECK (method <> 'ON_ACCOUNT' OR (tendered_amount IS NULL AND change_amount IS NULL));
CREATE INDEX ix_payments_shift ON payments(shift_id) WHERE shift_id IS NOT NULL;

CREATE FUNCTION fn_payments_shift_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE req boolean; sh_outlet uuid;
BEGIN
  SELECT shifts_required INTO req FROM outlets WHERE id = NEW.outlet_id;
  IF req AND NEW.shift_id IS NULL THEN RAISE EXCEPTION 'SHIFT_REQUIRED' USING ERRCODE = '23514'; END IF;
  IF NEW.shift_id IS NOT NULL THEN
    SELECT outlet_id INTO sh_outlet FROM cashier_shifts WHERE id = NEW.shift_id;
    IF sh_outlet <> NEW.outlet_id THEN RAISE EXCEPTION 'SHIFT_OTHER_OUTLET' USING ERRCODE = '23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_payments_shift_guard BEFORE INSERT ON payments FOR EACH ROW EXECUTE FUNCTION fn_payments_shift_guard();

-- ============ 11. credit notes (partial / full refunds on PAID bills) ============
-- numbering reuses bill_counters with series 'CN' (same atomic upsert as bills, Section 5.5)
CREATE TABLE credit_notes (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  bill_id uuid NOT NULL REFERENCES bills(id),
  series text NOT NULL DEFAULT 'CN',
  fiscal_year text NOT NULL,
  cn_seq int NOT NULL,
  cn_number text NOT NULL,
  business_date date NOT NULL,
  reason_code text NOT NULL CHECK (length(btrim(reason_code)) > 0),
  reason text NOT NULL CHECK (length(btrim(reason)) >= 5),
  refund_method text NOT NULL CHECK (refund_method IN ('CASH','CARD','UPI','OTHER','ON_ACCOUNT')),
  refund_reference text,
  customer_id uuid REFERENCES customers(id),
  shift_id uuid REFERENCES cashier_shifts(id),
  taxable_total numeric(12,2) NOT NULL CHECK (taxable_total >= 0),
  tax_total numeric(12,2) NOT NULL CHECK (tax_total >= 0),
  total_before_round_off numeric(12,2) NOT NULL CHECK (total_before_round_off >= 0),
  round_off numeric(12,2) NOT NULL DEFAULT 0,
  grand_total numeric(12,2) NOT NULL CHECK (grand_total > 0),               -- the money handed back
  approved_by uuid NOT NULL REFERENCES users(id),                           -- manager / owner who approved (PIN override)
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, series, fiscal_year, cn_seq),
  UNIQUE (outlet_id, cn_number),
  CHECK (series = 'CN'),
  CHECK (grand_total = total_before_round_off + round_off),
  CHECK (refund_method <> 'ON_ACCOUNT' OR customer_id IS NOT NULL)
);
CREATE INDEX ix_credit_notes_bill ON credit_notes(bill_id);

CREATE TABLE credit_note_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  credit_note_id uuid NOT NULL REFERENCES credit_notes(id),
  bill_line_id uuid NOT NULL REFERENCES bill_lines(id),
  quantity numeric(10,3) NOT NULL CHECK (quantity > 0),
  line_gross numeric(12,2) NOT NULL CHECK (line_gross >= 0),
  discount_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  taxable_amount numeric(12,2) NOT NULL CHECK (taxable_amount >= 0),
  tax_amount numeric(12,2) NOT NULL CHECK (tax_amount >= 0),
  line_total numeric(12,2) NOT NULL CHECK (line_total >= 0),
  restock boolean NOT NULL DEFAULT false,                                   -- hook for the inventory module: return the ingredients to stock
  CHECK (line_total = taxable_amount + tax_amount)
);
CREATE INDEX ix_credit_note_lines_bill_line ON credit_note_lines(bill_line_id);
CREATE TABLE credit_note_line_taxes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  credit_note_line_id uuid NOT NULL REFERENCES credit_note_lines(id),
  component_name text NOT NULL,
  rate_percent numeric(5,2) NOT NULL,
  taxable_amount numeric(12,2) NOT NULL CHECK (taxable_amount >= 0),
  tax_amount numeric(12,2) NOT NULL CHECK (tax_amount >= 0)
);
ALTER TABLE customer_ledger ADD CONSTRAINT fk_ledger_credit_note FOREIGN KEY (credit_note_id) REFERENCES credit_notes(id);
CREATE TRIGGER trg_credit_notes_immutable BEFORE UPDATE OR DELETE ON credit_notes FOR EACH ROW EXECUTE FUNCTION fn_append_only();
CREATE TRIGGER trg_credit_note_lines_immutable BEFORE UPDATE OR DELETE ON credit_note_lines FOR EACH ROW EXECUTE FUNCTION fn_append_only();
CREATE TRIGGER trg_credit_note_line_taxes_immutable BEFORE UPDATE OR DELETE ON credit_note_line_taxes FOR EACH ROW EXECUTE FUNCTION fn_append_only();

-- one bill line can never be refunded for more than it was sold for (quantity and every money column), even under parallel requests
CREATE FUNCTION fn_credit_note_line_cap() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE bl bill_lines%ROWTYPE; cn_bill uuid; q numeric; g numeric; tx numeric; t numeric; lt numeric;
BEGIN
  SELECT * INTO bl FROM bill_lines WHERE id = NEW.bill_line_id FOR UPDATE;
  SELECT bill_id INTO cn_bill FROM credit_notes WHERE id = NEW.credit_note_id;
  IF bl.bill_id <> cn_bill THEN RAISE EXCEPTION 'CREDIT_LINE_OTHER_BILL' USING ERRCODE = '23514'; END IF;
  SELECT COALESCE(sum(quantity),0), COALESCE(sum(taxable_amount),0), COALESCE(sum(tax_amount),0), COALESCE(sum(line_total),0), COALESCE(sum(line_gross),0)
    INTO q, tx, t, lt, g FROM credit_note_lines WHERE bill_line_id = NEW.bill_line_id;
  IF q  + NEW.quantity        > bl.quantity       THEN RAISE EXCEPTION 'REFUND_EXCEEDS_QUANTITY' USING ERRCODE = '23514'; END IF;
  IF lt + NEW.line_total      > bl.line_total     THEN RAISE EXCEPTION 'REFUND_EXCEEDS_AMOUNT' USING ERRCODE = '23514'; END IF;
  IF tx + NEW.taxable_amount  > bl.taxable_amount THEN RAISE EXCEPTION 'REFUND_EXCEEDS_TAXABLE' USING ERRCODE = '23514'; END IF;
  IF t  + NEW.tax_amount      > bl.tax_amount     THEN RAISE EXCEPTION 'REFUND_EXCEEDS_TAX' USING ERRCODE = '23514'; END IF;
  IF g  + NEW.line_gross      > bl.line_gross     THEN RAISE EXCEPTION 'REFUND_EXCEEDS_GROSS' USING ERRCODE = '23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_credit_note_line_cap BEFORE INSERT ON credit_note_lines FOR EACH ROW EXECUTE FUNCTION fn_credit_note_line_cap();

-- a bill that already has a credit note can no longer be voided (void = whole-bill cancellation for mistakes; credit note = return after the sale)
CREATE FUNCTION fn_bill_void_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'VOID' AND OLD.status <> 'VOID' AND EXISTS (SELECT 1 FROM credit_notes WHERE bill_id = NEW.id) THEN
    RAISE EXCEPTION 'BILL_HAS_CREDIT_NOTES' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_bill_void_guard BEFORE UPDATE OF status ON bills FOR EACH ROW EXECUTE FUNCTION fn_bill_void_guard();

-- a credit note needs a PAID bill, and all credit notes of a bill together can never hand back more than the bill's grand total
CREATE FUNCTION fn_credit_note_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b bills%ROWTYPE; refunded numeric;
BEGIN
  SELECT * INTO b FROM bills WHERE id = NEW.bill_id FOR UPDATE;
  IF b.status <> 'PAID' THEN RAISE EXCEPTION 'CREDIT_NOTE_NEEDS_PAID_BILL' USING ERRCODE = '23514'; END IF;
  IF b.outlet_id <> NEW.outlet_id THEN RAISE EXCEPTION 'CREDIT_NOTE_OTHER_OUTLET' USING ERRCODE = '23514'; END IF;
  SELECT COALESCE(sum(grand_total),0) INTO refunded FROM credit_notes WHERE bill_id = NEW.bill_id;
  IF refunded + NEW.grand_total > b.grand_total THEN RAISE EXCEPTION 'REFUND_EXCEEDS_BILL_TOTAL' USING ERRCODE = '23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_credit_note_guard BEFORE INSERT ON credit_notes FOR EACH ROW EXECUTE FUNCTION fn_credit_note_guard();

-- voiding a bill gives its coupon use back (the redemption row stays, marked RELEASED)
CREATE FUNCTION fn_bill_void_release_coupon() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'VOID' AND OLD.status <> 'VOID' THEN
    UPDATE coupon_redemptions SET status = 'RELEASED', released_at = now(), release_reason = 'BILL_VOIDED'
     WHERE bill_id = NEW.id AND status = 'ACTIVE';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_bill_void_release_coupon AFTER UPDATE OF status ON bills FOR EACH ROW EXECUTE FUNCTION fn_bill_void_release_coupon();

-- ============ 12. central menu: version counter and publish audit ============
CREATE TABLE outlet_menu_versions (                                         -- bumped in the same transaction as ANY change that affects /catalog/pos (items, variants, modifiers, combos, price rules, availability, outlet settings used by the POS)
  outlet_id uuid PRIMARY KEY REFERENCES outlets(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  version bigint NOT NULL DEFAULT 1 CHECK (version >= 1),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO outlet_menu_versions(outlet_id, tenant_id) SELECT id, tenant_id FROM outlets;

CREATE TABLE menu_publish_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  source_outlet_id uuid NOT NULL REFERENCES outlets(id),
  target_outlet_ids uuid[] NOT NULL CHECK (cardinality(target_outlet_ids) >= 1),
  mode text NOT NULL DEFAULT 'ADD_AND_UPDATE' CHECK (mode IN ('ADD_AND_UPDATE','ADD_ONLY')),
  started_by uuid NOT NULL REFERENCES users(id),
  summary jsonb NOT NULL DEFAULT '{}',                                     -- {created, updated, skippedOverridden, deactivated, errors[]}
  created_at timestamptz NOT NULL DEFAULT now()
);
```

---

## 26. INVENTORY, RECIPES & PURCHASING *(added in v1.3)*

> **Goal:** know what is in the store room, what every dish costs, what was bought, what was thrown away and what is missing — without ever slowing down or blocking a bill. Stock moves **only** through an append-only ledger; on-hand quantity and average cost are derived from it in the same transaction. This is *Phase 5I* (the old "Phase 5 inventory" item). It fills the `inventory` key of the end-of-day summary (Section 10.3) and gives the `INVENTORY` role real rights (Sections 1.3, 18.1, 22.2, 24.3). Plan feature flag: `inventory`.

### 26.1 Scope, principles and what is NOT in v1
**Principles**
1. **Billing never waits for stock.** A bill is paid first; consumption is posted in the same database transaction *as a separate step that cannot fail the payment* (26.7). A missing recipe, a negative balance or an unknown cost is reported, never an error for the cashier.
2. **The ledger is the truth.** `stock_movements` is append-only (a database trigger rejects UPDATE, DELETE and TRUNCATE). Corrections are new movements. `stock_levels` (on-hand, average cost) can only change through a movement insert — direct writes are rejected by trigger.
3. **Exact arithmetic.** Quantities `NUMERIC(14,4)` in the item's **base unit** (g, ml or pcs); unit cost `NUMERIC(16,6)` per base unit; money `NUMERIC(14,2)`. Java `BigDecimal`, `HALF_UP`, one rounding per stated step (26.4). The Python reference `ref/inventory.py` is the executable spec.
4. **Old sales are never recomputed.** A sale stores the cost it used. Recipes are versioned; the version effective at the sale time is the one used, forever.
5. **No tax interpretation.** Vendor GST amounts are recorded as printed on the invoice and are not used for input-tax credit or stock cost. GSTIN is free text (not validated).

**In v1:** units and conversions; stock items (raw, prep, retail), categories, reorder/par levels, preferred vendor; per-outlet stock levels; recipes (item, variant, modifier, one-level prep recipes, combos through their components); consumption when a bill is paid and its reversal on void/credit note; purchase orders, goods receipts (GRN), purchase returns, vendor payables with manual payments and aging; wastage and adjustments; stock counts with approval; transfers between outlets; production runs of prep items; alerts and reports; CSV import; the EOD `inventory` object.

**NOT in v1 (stated so nobody assumes it):** **expiry dates and batch/lot tracking** (stock is valued as one pool per item per outlet; expiry is only a wastage reason code, `EXPIRED`); FIFO costing (moving weighted average only); barcode scanning of vendor invoices or OCR; automatic purchase ordering (a *suggested order* list exists, the PO is created by a person); vendor portal; supplier e-invoicing; input-tax-credit or reverse-charge treatment; landed-cost allocation of freight (freight is stored in `other_charges` and **not** added to item cost); sub-recipes nested more than one level; recipe costing in a currency other than the outlet currency; a bank/payment gateway for vendor payments (payments are recorded manually); central kitchen planning.

### 26.2 Units and conversions (exact)
| Family | Base unit | Other units (exact factor to base) |
|---|---|---|
| MASS | `g` | `kg` = 1000 |
| VOLUME | `ml` | `l` = 1000 |
| COUNT | `pcs` | `dozen` = 12 |
| PACK | — | `pack`, `box`, `bottle`, `can`, `tray`, `bag`, `crate` — **no table factor**; each item declares how many base units one pack holds (`purchase_to_base`, e.g. crate of eggs = 30 pcs) |

Rules (mirrored by `trg_stock_item_units` and `ref/inventory.py`):
- A stock item has a **base unit** (`g`, `ml` or `pcs` — never `kg`), a **purchase unit** and `purchase_to_base`. If the purchase unit is MASS/VOLUME/COUNT it must be of the **same family** as the base unit (`UNIT_FAMILY_MISMATCH`) and `purchase_to_base` must equal the table factor (`UNIT_FACTOR_MISMATCH`). PACK units take any positive factor.
- Recipe lines are entered in any non-PACK unit of the item's family (e.g. `250 g` for an item counted in `g`, or `0.25 kg`); the system stores `quantity` (as typed), `unit_code` and `quantity_base = round(quantity × factor, 4)`; the database rejects an inconsistent `quantity_base` (`QUANTITY_BASE_MISMATCH`). Litres for a gram item are `UNIT_FAMILY_MISMATCH`. **No density conversions** (1 l of oil ≠ 1 kg) — the owner enters such an item in the unit he uses.
- Conversion = one exact multiplication/division, **rounded once to 4 decimals**. Goods-receipt line: `qty_base = round(qty × purchase_to_base, 4)`; `unit_cost_base = round(unit_price ÷ purchase_to_base, 6)`; `line_amount = round(qty × unit_price, 2)` — all three are database CHECKs. Example: 5 kg at 84.50 → 5000.0000 g at 0.084500 per g, amount 422.50; 3 packs of 7 at 100.00 → 21.0000 pcs at 14.285714, amount 300.00.

### 26.3 Stock items, categories and levels
- **Item kinds:** `RAW` (bought, used in recipes), `PREP` (made in-house from raw items by a production run — gravy base, dough), `RETAIL` (bought and sold as is — soft drink, packaged water; its menu item has a one-line recipe "1 pcs").
- Fields: name (unique per tenant, case-insensitive), SKU, barcode (unique when present), category, base/purchase unit, `default_vendor_id`, `reorder_level` and `par_level` (base units; `par ≥ reorder`), `track_stock` (false = movements are rejected with `ITEM_NOT_TRACKED`), active. Items are **tenant-wide**; **levels are per outlet** (`stock_levels`: on-hand, `avg_cost`, `avg_cost_known`, last purchase cost, per-outlet reorder/par override).
- **No divergence.** Every insert into `stock_movements` updates the matching `stock_levels` row in the same transaction (trigger, row-locked). Direct INSERT/UPDATE/DELETE on `stock_levels` fails with `STOCK_LEVEL_DIRECT_CHANGE`. Proof: property test P1 (ledger sum = on-hand for 300 random operation streams) and this check query, run nightly and in CI (it must return zero rows):
```sql
SELECT l.outlet_id, l.stock_item_id, l.on_hand, COALESCE(m.q,0) AS ledger_sum
FROM stock_levels l
LEFT JOIN (SELECT outlet_id, stock_item_id, sum(quantity_base) q FROM stock_movements GROUP BY 1,2) m
  ON m.outlet_id=l.outlet_id AND m.stock_item_id=l.stock_item_id
WHERE l.on_hand IS DISTINCT FROM COALESCE(m.q,0);
```
- Outlet settings (`inventory_settings`): `negative_stock_policy` (`ALLOW` default | `BLOCK_MANUAL`), `wastage_approval_threshold` (default 500.00), `price_change_alert_percent` (default 10), low-stock alerts on/off and recipients, `dead_stock_days` (7–365, default 30), `count_blind_default`.

### 26.4 Costing — moving weighted average
Per item per outlet. `avg_cost` is per base unit, 6 decimals.
1. **Inflow with a real cost** (`OPENING`, `PURCHASE`, `TRANSFER_IN`, `PRODUCTION_OUTPUT`; cost basis `ACTUAL`): if on-hand ≤ 0 the new cost **replaces** the average; otherwise `avg' = round6((on_hand × avg + qty × cost) ÷ (on_hand + qty))`. The average therefore always lies between the lowest and highest purchase price seen (property P2).
2. **Outflow** (`SALE`, `WASTAGE`, `VENDOR_RETURN`, `TRANSFER_OUT`, `PRODUCTION_CONSUME`, negative `ADJUSTMENT`/`COUNT_VARIANCE`) is valued at the current average and **does not change the average**. If on-hand ≤ 0 or the average was never known, the **last purchase price** is used and the movement is flagged `cost_estimated` (basis `LAST_PURCHASE`); if no purchase ever happened, cost 0 with basis `UNKNOWN` (shown as "cost unknown" in every report, never hidden).
3. **Found stock** (positive `ADJUSTMENT`/`COUNT_VARIANCE`) enters at the current average (basis `AVERAGE`) — a count can never invent a price.
4. **Reversal** (`SALE_REVERSAL`) returns stock **at the original sale's cost** (basis `REVERSAL`), never at today's average. The sum of reversals of one sale can never exceed the sale (`REVERSAL_EXCEEDS_ORIGINAL`); a reversal of a non-sale is `REVERSAL_TARGET_INVALID`. Property P4: sale then full reversal returns quantity and value exactly.
5. The database re-derives the expected basis and cost and rejects a caller-supplied wrong one (`COST_BASIS_MISMATCH`). `line_value = round(qty × unit_cost, 2)` is a generated column; **valuation** = `round(on_hand × avg_cost, 2)` per item, summed (sum of rounded values, not rounded sum).
6. **Negative stock policy.** `ALLOW` (default): the balance may go negative, a warning chip shows on the item and in the daily alerts. `BLOCK_MANUAL`: manual outflows (wastage, adjustment, transfer out, vendor return, production consume) that would take on-hand below zero fail with `NEGATIVE_STOCK_BLOCKED`; **sales are never blocked** by any policy.
7. **Purchase-price alert:** when a GRN line's `unit_cost_base` differs from the previous purchase cost by more than `price_change_alert_percent` (`price_change_percent = round2((new − old) ÷ old × 100)`; none if there is no previous price) it appears in the *Price changes* report and in the EOD count.

Ledger movement kinds: `OPENING`, `PURCHASE`, `SALE`, `SALE_REVERSAL`, `WASTAGE`, `ADJUSTMENT`, `COUNT_VARIANCE`, `TRANSFER_OUT`, `TRANSFER_IN`, `VENDOR_RETURN`, `PRODUCTION_CONSUME`, `PRODUCTION_OUTPUT`. Each row stores signed `quantity_base`, `unit_cost`, `cost_basis`, `occurred_at`, **`business_date`**, actor (NULL = system), `reason_code`, note, reference (`ref_type`/`ref_id`), `consumption_id`, `reverses_movement_id` and a unique `dedupe_key` (idempotency).

### 26.5 Recipes
- **Targets:** a menu item, a **variant** (either its own lines, or `inherit_item_recipe` × `portion_factor`, e.g. Half = 0.5), a **modifier** (extra cheese: its lines are added per portion sold), or a **prep item** (the recipe of a production batch, with `yield_qty_base`; shared by all outlets).
- **Lines:** ingredient, quantity in a recipe unit (26.2), `wastage_percent` (0–<100), `consume_mode`. The quantity is the **net** amount per portion; the **gross** consumption is `net × 100 ÷ (100 − wastage%)` (20 % trim on 100 g paneer → 125 g). One ingredient once per recipe.
- **One-level sub-recipes:** a recipe line may name a `PREP` item. `DIRECT` consumes the prep item's own stock; `EXPAND` consumes the prep recipe's raw ingredients pro rata (`line gross ÷ yield × prep line gross`). A prep recipe may use only RAW/RETAIL items (`PREP_NESTING_NOT_ALLOWED`) — so a cycle is impossible by construction. The import validator additionally runs a general cycle detector (`find_cycle`, vector IN15 + property P8) and reports the cycle path per row. `EXPAND` on a non-prep ingredient is `EXPAND_ONLY_FOR_PREP`.
- **Combos** (the combo tables are owned by the billing-extras section; soft reference only, no FK): a combo has **no recipe of its own**; at sale time its components are expanded to menu items/variants and each component's recipe is consumed. Interface: Billing passes the consumption service a flat list `[(menuItemId, variantId?, qty, modifierIds[])]` already expanded; until the billing-extras combos exist, a combo line without components is a `NO_RECIPE` skip.
- **Versioning:** a recipe is `DRAFT` → `ACTIVE` → `ARCHIVED`. An ACTIVE recipe is **immutable** (lines cannot be added, edited or deleted — `RECIPE_IMMUTABLE`); to change it you create the next version (copy), edit the draft, and *Activate with effective-from*, which end-dates the previous version at the same instant. A database exclusion constraint forbids two ACTIVE versions of one target overlapping in time. A sale uses the version whose `[effective_from, effective_to)` contains the **bill's business time**; offline-synced and late bills therefore use the recipe that was valid when they were sold.
- **Live cost in the editor:** cost per portion = Σ line `round2(gross_base × avg_cost)`, margin and food-cost % against the item's price (price excl. tax).

### 26.6 Calculation specs (exact; `ref/inventory.py`)
**Consumption of one paid bill.** For each bill line (menu item/variant, quantity `q` portions, modifiers): find the effective recipe → for each recipe line add `gross × q × portion_factor` to the accumulator of that stock item (EXPAND lines expand through the prep recipe). Modifier recipes add `gross × q`. Accumulate **per stock item across the whole bill**, then **round once to 4 decimals** per item and post one `SALE` movement per item (so a 2-line bill with the same ingredient never double-rounds). Lines without a usable recipe are not consumed and are written to `stock_consumption_skips` with a reason (`NO_RECIPE`, `RECIPE_EMPTY`, `ITEM_NOT_TRACKED`) and their net amount (that is what `sales_coverage_percent` uses).
Worked example: 3 × Paneer Tikka (paneer 100 g net, 20 % trim; oil 10 g) → paneer 375.0000 g, oil 30.0000 g. Sub-recipe: 4 × Dal (200 g of gravy each, gravy batch yield 800 g = onion 600 g + tomato 400 g with 10 % trim) with EXPAND → onion 600.0000 g, tomato 444.4444 g; with DIRECT → gravy 800.0000 g.

**Reversal (void / credit note).** Proportional, per original `SALE` movement: `return = round4(original × fraction)` capped at what is left; the **final** reversal (full void, or the credit note that completes the bill) returns exactly what is left, so the reversals of a bill add up to exactly the sale (vector IN16, property P3). Fraction for a credit note = credited net amount of the line ÷ line net amount (interface to the billing-extras credit notes: it passes `(billLineId, fraction, creditNoteId)`; soft reference).

**Theoretical cost / food-cost %.** `theoretical_cost = Σ round2(consumed_qty × avg_cost_at_sale)`; `food_cost_% = round2(cost ÷ net_sales × 100)` (none when sales are 0). **Variance** (count to count): `actual = opening_count + purchases + net_transfers_in − closing_count`; `variance = actual − theoretical` (positive = more used than the recipes explain = loss).

**Alerts.** `low_stock` ⇔ on-hand ≤ reorder level (override first) and level > 0; *suggested order* = `max(0, par − on_hand)` in base units (shown in the purchase unit rounded up to a whole pack, by the UI only). Vendor aging buckets by due date: not due, 1–30, 31–60, 61–90, 90+ days.

**Reference vectors IN1–IN22 and properties P1–P8** are executable now: `ref/test_in.py` — **30 tests pass** (22 vectors + 8 hypothesis properties). The implementing agent ports them to Java unchanged. Properties: P1 ledger sum = on-hand (300 random streams, both policies); P2 weighted average within [min, max] purchase price; P3 consumption then proportional reversals restores quantity exactly; P4 sale then reversal restores value and uses the same cost both ways; P5 replaying every idempotency key changes nothing; P6 unit round trips are exact; P7 consumption is non-negative and rounded once; P8 cycle detector agrees with brute force.

### 26.7 Consumption when a bill is paid (the trigger)
1. **When:** the bill reaches `PAID` (same transaction as the payment that completes it; offline-synced bills at sync). The service calls `InventoryConsumptionService.consume(billId)` inside a **savepoint**: if it throws (bug, deadlock, anything), the savepoint is rolled back, the bill stays paid, an `INVENTORY_CONSUMPTION_FAILED` audit row and a retry job are created. Billing is never blocked and never slowed by more than the one batched insert.
2. **Idempotency:** one row per bill in `stock_consumptions` (`UNIQUE(bill_id)`), every movement has a deterministic `dedupe_key = 'SALE:' || bill_id || ':' || stock_item_id`. Re-running (retry, double submit, sync replay) inserts nothing new — database-tested.
3. **Business date:** `business_date` and `occurred_at` of the movements are the **sale's** (offline bills: the terminal's bill time, `source = OFFLINE_SYNC`), not the sync time. If the day is already closed the movements are still written with the sale's date and the day's EOD is **not** rewritten; the late consumption shows as *late* in the next day's *Consumption* report (the same rule as late offline bills, 24.6).
4. **Void / credit note:** posts `SALE_REVERSAL` movements (26.6) at the original cost and sets the consumption `PARTIALLY_REVERSED` / `REVERSED`. A void of an unpaid bill has nothing to reverse.
5. **No recipe:** the line is skipped and listed in the **No-recipe report** (menu item, units sold, sales amount, last sold) — the owner's to-do list for building recipes; it is never an error at the counter.
6. **Not-tracked and disabled:** with the flag `inventory` off, or the outlet's inventory not started, nothing is consumed and nothing is skipped (no rows).
7. Concurrency: levels are updated under a row lock in a fixed order (by item id) to avoid deadlocks between simultaneous bills.

### 26.8 Purchasing
- **Vendors:** name (unique per tenant, case-insensitive), contact, phone, e-mail, address, **GSTIN as free text (≤ 20 chars, not validated)**, payment terms in days (0–365), notes, active.
- **Purchase order:** `DRAFT → SENT → PARTIALLY_RECEIVED → RECEIVED`, or `CANCELLED` (reason required). Lines in the item's **purchase unit** with price before tax; one line per item; number `PO-<outlet>-<seq>` gapless per outlet. *Send* records `sent_at` (and can e-mail/WhatsApp the PO text through the existing outbox — a plain message, no template needed beyond the outlet's own channel; **WhatsApp business templates are not assumed**). Received quantities accumulate from GRNs; over-receipt is allowed with a warning (deliveries vary).
- **GRN (goods receipt):** created from a PO (lines pre-filled) or free-standing. Per line: quantity and unit price in purchase units, `qty_base`, `unit_cost_base`, `line_amount` (26.2). Header: **vendor invoice number and date (required to post)**, due date, subtotal, **tax total (as printed; not interpreted)**, other charges, round-off, total (`total = subtotal + tax + other + round-off`, CHECK). Attachment: photo/PDF of the vendor invoice through the existing storage service (JPEG/PNG/PDF, ≤ 5 MB). **Posting** writes one `PURCHASE` movement per line (updating average cost) and the PO status; a posted GRN is immutable and can only be **voided** (reason; writes negative movements at the original cost; blocked with `GRN_VOID_STOCK_USED` if the stock is already consumed below what the void would remove, unless negative stock is allowed).
- **Duplicate-invoice guard:** unique (tenant, vendor, normalised invoice number — case and spaces ignored) among non-void GRNs, across outlets (`DUPLICATE_VENDOR_INVOICE`, shows the existing GRN).
- **Purchase return:** posted against a GRN or free; `VENDOR_RETURN` movements at the current average; creates a credit that reduces the vendor payable.
- **Vendor payables:** payable per GRN = total − allocations; **manual payments** (cash, UPI, bank transfer, cheque, card, other; reference text) allocated to invoices; DB triggers forbid allocating more than the payment, more than the invoice, across vendors, or to a non-posted GRN; a voided payment frees its allocations. **Aging** by due date (26.6). No payment gateway, no bank reconciliation in v1.

### 26.9 Wastage, adjustments, stock counts, transfers, production
- **Wastage** (quick entry): item, quantity (any unit of the family), reason code `SPOILAGE`, `EXPIRED`, `SPILL`, `DAMAGED`, `RETURNED_BY_CUSTOMER`, `STAFF_MEAL`, `TRANSIT_LOSS`, `THEFT_SUSPECTED`, `OTHER` (`OTHER` needs a note). Valued at the average. If the value exceeds the outlet's `wastage_approval_threshold`, a **manager PIN** is required (Section 18 PIN rules; INVENTORY users cannot approve their own entry) and `approved_by` is stored.
- **Adjustment** (correction/found stock): signed quantity, reason `DATA_ENTRY_CORRECTION`, `FOUND_STOCK`, `DAMAGED`, `OTHER`; same threshold rule.
- **Stock count:** a sheet (`FULL`, `CATEGORY`, `SELECTED`) freezes the system quantity and average cost per item when started; **blind** mode hides the system quantity from the counter; counters enter quantities (several sessions, save as you go); *Submit* shows the **variance valuation** (`variance_qty`, `variance_value = round2((counted − system) × frozen cost)`); a **different** user with approval rights *Approves* (four-eyes, CHECK) → one `COUNT_VARIANCE` movement per item with a variance, of `counted − system_at_freeze` (exactly the `variance_qty` stored on the line). **Known limitation:** sales or deliveries posted between the freeze and the physical count are not part of that figure; the review screen therefore shows "moved since freeze" per item (from the ledger) and the approver can *Re-freeze* the sheet; the recommended practice is to count before opening or after closing. Uncounted lines post nothing. Cancelling posts nothing.
- **Transfers between outlets (same tenant):** two steps. *Send* (from-outlet): `TRANSFER_OUT` at average, status `IN_TRANSIT`, unit cost frozen on the line. *Receive* (to-outlet): quantities received (≤ sent); `TRANSFER_IN` at the frozen cost; a shortfall is posted as `WASTAGE` with reason `TRANSIT_LOSS` at the sending outlet's cost (needs the same approval rule). The *In transit* report lists unreceived transfers; their value is shown separately in valuation and **not** in either outlet's on-hand.
- **Production run:** consumes the prep recipe's ingredients (`PRODUCTION_CONSUME`, at average) and produces the prep item (`PRODUCTION_OUTPUT`, quantity = **actual output**, may differ from batches × yield; cost = total input value ÷ output quantity, 6 dp). Variance between expected and actual output is shown.

### 26.10 Alerts, reports, EOD, import
- **Low-stock alert:** a daily job (and after a movement that crosses the level) lists items at/under reorder level; one notification per item per day (`stock_levels.low_stock_alerted_on`) through the **existing outbox** to the owner/manager e-mail recipients (and `low_stock_recipients`). Push/WhatsApp are not used for this in v1.
- **Reports** (all CSV-exportable, outlet and date range, tenant-scoped): **Stock on hand & valuation** (item, on-hand, avg cost, value, flags *estimated cost*, *negative*); **Consumption** (by item, with late sales marked); **Theoretical vs actual variance** (needs two approved counts; otherwise "needs a count"); **Food cost % by menu item / by category** (cost snapshot at sale ÷ net sales; items without recipe excluded and counted); **Wastage** (by reason, item, user); **Purchase register** (GRN list with invoice no/date, vendor, subtotal/tax/total — tax shown as recorded); **Vendor payables & aging**; **No-recipe items**; **Price changes** (> threshold); **Dead stock** (on-hand > 0 and no outflow for `dead_stock_days`, valued); **In-transit transfers**; **Ledger** per item. **Expiry reports do not exist in v1** (26.1).
- **EOD `inventory` object** (replaces `"inventory": null` in Section 10.3; `null` still when the outlet has not started inventory). Computed by SQL from `stock_snapshots` (written at day close) and the ledger — never by the LLM:
```json
"inventory": {
  "opening_value": "50000.00", "purchases_value": "12000.00", "consumption_value": "9000.00",
  "wastage_value": "400.00", "adjustments_value": "-100.00", "other_movements_value": "-20.00",
  "closing_value": "52480.00", "low_stock_count": 4, "no_recipe_items_count": 3,
  "price_alert_count": 1, "sales_coverage_percent": "90.00" }
```
**Invariant (tested, IN22):** `closing = opening + purchases − consumption − wastage + adjustments + other`, where `consumption` is sales consumption net of reversals, `adjustments` is signed (adjustments + count variances), and `other` = transfers, vendor returns, production net and GRN voids (it is derived as the remainder and shown so the e-mail never hides a difference). `sales_coverage_percent` = covered ÷ (covered + uncovered) net sales of the day (100.00 when there were no sales). All money are strings. In the EOD e-mail the object becomes a small **Stock** block under Sales: the valuation walk (opening → closing), consumption vs purchases, and one line each for low-stock items, items without recipe and price alerts, with links to the reports; the block is omitted when `inventory` is `null`.
- **CSV import** (stock items, opening stock, recipes): upload → **validate** (nothing is written) → the result lists **row-level errors** (`{"row":7,"column":"unit","code":"UNIT_FAMILY_MISMATCH","message":"…"}`, first 500 stored) → the owner either fixes the file or *Import valid rows only* (explicit tick) → commit. The same file (SHA-256) cannot be committed twice. Opening stock posts `OPENING` movements at the stated cost (dated the opening date); recipes import as DRAFT versions and are activated by a person. Encoding UTF-8, comma-separated, header row, max 5,000 rows, formulas in cells (`=`, `+`, `-`, `@` at the start) are rejected on import and escaped on export (CSV-injection rule of Section 13).

### 26.11 API summary (tenant- and outlet-scoped, 404 cross-tenant, feature flag `inventory`; role legend: O OWNER, M MANAGER, I INVENTORY; CASHIER, CAPTAIN, KITCHEN, RIDER: **none**)
| Method & path | Role | Notes |
|---|---|---|
| `GET/POST/PUT /stock-items`, `POST /stock-items/{id}/deactivate` | O, M, I | optimistic `version`; unit rules 26.2 |
| `GET/POST/PUT /stock-categories` | O, M, I | |
| `GET /stock-levels?outlet=`, `PUT /stock-levels/{item}/overrides` | O, M, I (view) / O, M (overrides) | reorder/par per outlet |
| `GET /stock-items/{id}/ledger` | O, M, I | paged, filter by kind/date |
| `GET/POST /recipes`, `GET /recipes/{id}`, `POST /recipes/{id}/new-version`, `PUT /recipes/{id}` (draft only), `POST /recipes/{id}/activate` | read: O, M, I; write/activate: O, M | live cost in `GET`; activation sets the effective-from (default: now) |
| `GET /recipes/costing?menuItemId=` | O, M, I | cost, margin, food-cost % |
| `GET/POST/PUT /vendors` | O, M, I | GSTIN free text |
| `GET/POST/PUT /purchase-orders`, `POST …/{id}/send`, `POST …/{id}/cancel` | O, M, I | cancel needs reason |
| `GET/POST/PUT /goods-receipts`, `POST …/{id}/post`, `POST …/{id}/void`, `POST …/{id}/attachment` | O, M, I (void: O, M) | duplicate invoice → 409 |
| `GET/POST /purchase-returns` | O, M, I | |
| `GET/POST /vendor-payments`, `POST …/{id}/void`, `GET /vendors/{id}/payables` | O, M (I: view) | manual payments |
| `POST /stock/wastage`, `POST /stock/adjustments` | O, M, I | PIN above threshold (`X-Manager-Pin` or approval body, as Section 18) |
| `GET/POST /stock-counts`, `POST …/{id}/start`, `PUT …/{id}/lines`, `POST …/{id}/submit`, `POST …/{id}/approve`, `POST …/{id}/cancel` | count/submit: O, M, I; approve: O, M (not the submitter) | blind flag per sheet |
| `GET/POST /stock-transfers`, `POST …/{id}/send`, `POST …/{id}/receive`, `POST …/{id}/cancel` | O, M, I | receive at the destination outlet |
| `POST /production-runs`, `GET /production-runs` | O, M, I | |
| `GET /inventory/reports/{report}` (`valuation`, `consumption`, `variance`, `food-cost`, `wastage`, `purchase-register`, `payables`, `no-recipe`, `price-changes`, `dead-stock`, `in-transit`) + `?format=csv` | O, M, I (payables: O, M) | |
| `GET /inventory/alerts/low-stock`, `GET /inventory/suggested-order?vendorId=` | O, M, I | |
| `POST /inventory/imports` (validate), `GET /inventory/imports/{id}`, `POST …/{id}/commit` | O, M | idempotent by file hash |
| `GET/PUT /outlets/{id}/inventory-settings` | O | negative policy, thresholds, recipients |
| `POST /inventory/consumption/{billId}/retry` | O, M | after `INVENTORY_CONSUMPTION_FAILED` |
New error codes (Appendix B): `UNIT_FAMILY_MISMATCH` (422), `UNIT_FACTOR_MISMATCH` (422), `QUANTITY_BASE_MISMATCH` (422), `ITEM_NOT_TRACKED` (422), `NEGATIVE_STOCK_BLOCKED` (409), `REVERSAL_EXCEEDS_ORIGINAL` (409), `REVERSAL_TARGET_INVALID` (422), `COST_BASIS_MISMATCH` (500: server bug), `LEDGER_IMMUTABLE` (500), `STOCK_LEVEL_DIRECT_CHANGE` (500), `RECIPE_IMMUTABLE` (409), `RECIPE_INHERITS` (422), `PREP_NESTING_NOT_ALLOWED` (422), `PREP_TARGET_INVALID` (422), `EXPAND_ONLY_FOR_PREP` (422), `RECIPE_OVERLAP` (409), `DUPLICATE_VENDOR_INVOICE` (409), `GRN_NOT_DRAFT` (409), `GRN_POSTED_IMMUTABLE` (409), `GRN_VOID_IS_FINAL` (409), `GRN_VOID_STOCK_USED` (409), `ALLOCATION_EXCEEDS_PAYMENT` / `ALLOCATION_EXCEEDS_INVOICE` / `ALLOCATION_VENDOR_MISMATCH` / `ALLOCATION_GRN_NOT_POSTED` (422), `APPROVAL_REQUIRED` (403, PIN missing above threshold), `COUNT_SELF_APPROVAL` (403), `TRANSFER_CROSS_TENANT` (422), `IMPORT_DUPLICATE_FILE` (409), `IMPORT_HAS_ERRORS` (422). The database codes appear in the exception text; the API maps them to the HTTP codes above.

### 26.12 UI specification (screens S27–S34; every screen follows Section 12.2 — skeleton while loading, a helpful empty state, an error state with *Retry*; never blank)
- **S27 Stock list** (`/inventory`): table (name, category, on-hand in the *purchase* unit and base unit, avg cost, value, status chips *Low*, *Negative*, *Estimated cost*), filters, search, outlet switcher, *Add item*, *Import*. Empty: "No stock items yet — add your first ingredient or import a CSV." Error: banner + Retry.
- **S28 Item detail** (`/inventory/items/:id`): header with unit setup, tabs **Ledger** (every movement: date, kind, signed qty, cost, basis chip, reason, actor, link to the bill/GRN/count), **Levels per outlet**, **Used in recipes**, **Purchases & price history** (mini chart of unit cost). Warns when cost is estimated.
- **S29 Recipe editor** (`/inventory/recipes/:menuItem`): left = ingredient lines (item search, qty + unit, wastage %, DIRECT/EXPAND), right = **live cost panel** (cost per portion, selling price, margin, food-cost %, per-line share) recomputed in the browser *for display only* from API-provided average costs; versions list; *Save draft*, *Activate from…* with a confirm "Old bills keep the old recipe". Empty: "No recipe — sales of this item are skipped by stock." Variant tab with "Same as item × factor". Keyboard: Enter adds a line, Ctrl+S saves.
- **S30 Purchasing** (`/purchasing`): tabs POs, GRNs, Returns, Vendors, Payables. **Keyboard-first PO/GRN forms:** item search focus on open, Enter moves quantity → price → next line, Tab order logical, totals live, duplicate-invoice warning appears as soon as vendor + invoice no are typed, photo upload with camera on mobile, *Post* needs invoice no/date. Empty states per tab.
- **S31 Wastage quick entry** (`/inventory/wastage`, mobile-friendly): big item picker (recent first), quantity pad, reason chips, optional photo/note; shows value and, above the threshold, the manager-PIN dialog. Success toast with *Undo within 5 minutes* implemented as a correcting `ADJUSTMENT` (the ledger is never edited).
- **S32 Stock count** (`/inventory/counts/:id`): sheet ordered by storage category; blind mode hides system quantity; barcode/keyboard entry; progress bar; *Submit* → variance review (sorted by value) → *Approve* (another user). Offline is not supported (online only, like the other manager-approval screens in the Section 24.2 table).
- **S33 Transfers & production** (`/inventory/transfers`, `/inventory/production`): send/receive wizard with in-transit list; production run form with expected vs actual output.
- **S34 Inventory reports & alerts** (`/inventory/reports`): report picker, filters, CSV export, low-stock banner on S27, *Suggested order* button that opens a draft PO per vendor. EOD wizard (S12) gets a readiness line "N items without recipe, M items low".
Settings → *Inventory* (S5 extension): negative-stock policy, thresholds, recipients, start inventory (date + opening stock import). Roles: INVENTORY lands on S27; the cashier and captain menus show no inventory entry.

### 26.13 Failure modes
| Situation | Behaviour |
|---|---|
| Consumption throws while paying | Payment stays; savepoint rolled back; audit `INVENTORY_CONSUMPTION_FAILED`; retry job; the owner sees a banner on S34 |
| Same bill consumed twice (retry/sync replay) | No new rows (unique bill, unique dedupe key) |
| Sale of an item with no recipe | Skipped, listed in the No-recipe report, coverage % lowered |
| Stock goes negative | Allowed with warning (default) or manual outflows blocked; sales never blocked |
| Cost unknown | Valued at last purchase price (flagged) or 0 (`UNKNOWN`, flagged) |
| Recipe changed during service | New version effective-from; bills already sold keep their cost |
| Two users post to the same item | Row lock; both movements posted; cost per movement deterministic |
| GRN with a duplicate invoice number | 409 `DUPLICATE_VENDOR_INVOICE`, shows the existing GRN |
| Count approved by its submitter | Rejected (CHECK and API) |
| Transfer received short | Shortfall posted as transit-loss wastage at the sender |
| Import file with 12 bad rows | Nothing written; row-level errors; option to import the valid rows |
| Feature flag off / plan without inventory | API 404 `FEATURE_NOT_ENABLED`; no consumption; EOD `inventory: null` |

### 26.14 Security and audit
- Tenant scope from the token; every table carries `tenant_id` and trigger checks reject mixed-tenant rows (`STOCK_ITEM_TENANT_MISMATCH`, `OUTLET_TENANT_MISMATCH`, `TRANSFER_CROSS_TENANT`, `RECIPE_TARGET_TENANT_MISMATCH`). INVENTORY users are limited to their assigned outlets.
- Cost data is sensitive: only OWNER, MANAGER and INVENTORY see costs and margins; no cashier/captain endpoint returns them.
- Attachments: type and size whitelist (JPEG/PNG/PDF ≤ 5 MB), stored under an unguessable key through the existing storage service, served by short-lived signed URLs.
- **Audit log:** item/recipe/vendor created or changed (before/after), recipe activated, GRN posted/voided, PO sent/cancelled, wastage and adjustments (with approver), count approved, transfer sent/received, payments recorded/voided, import committed, settings changed, consumption retried. The ledger itself is the audit trail for quantities.
- Manager-PIN approvals are rate-limited like Section 18 PINs; an INVENTORY user cannot approve his own wastage.
- Retention: ledger and purchase documents are kept with the other financial records (Section 13 retention); stock items are deactivated, never deleted once they have movements (FK).

### 26.15 Tests (what the implementing agent must write)
- **Reference (executable now):** `ref/test_in.py` — **30 tests, all pass** (IN1–IN22 vectors, P1–P8 hypothesis properties). Port to Java as JUnit + jqwik against the same expectations.
- **Database:** the cases of V014 listed at the end of this section (`t014.sql`: **217 accept/reject cases, 217 as expected**), incl. the no-divergence check query, the append-only trigger (UPDATE, DELETE, TRUNCATE), the unique-consumption-per-bill index, reversal caps, recipe immutability and overlap exclusion, duplicate-invoice guard, payment allocation limits.
- **Integration (Testcontainers):** pay a bill → movements + level + consumption row in one transaction; pay it twice → nothing new; throw inside consumption → bill still PAID, audit row; void → reversal equals the sale exactly; two partial credit notes + final void sum to the sale; offline-synced bill consumes with the sale date and the recipe version of that time; recipe change mid-day; GRN post → average updated, PO status moves; duplicate invoice; count approval posts variances; transfer send/receive; concurrency (50 parallel bills on one item: ledger sum = on-hand); import with errors; EOD `inventory` invariant on a seeded day.
- **E2E (Playwright; numbered after 44):**
  45. Set up: import 40 stock items and opening stock; build 3 recipes (one with a prep sub-recipe); the stock list shows the right valuation.
  46. Service: 20 bills with those items → on-hand drops by the exact recipe amounts; one item without a recipe appears in the No-recipe report; a void returns the stock exactly.
  47. Purchasing: PO → send → GRN with photo → post → average cost changes → price-change alert appears; the same invoice number again → blocked; a payment is allocated and aging updates.
  48. Wastage above the threshold asks for a manager PIN; below it does not; negative-stock policy `BLOCK_MANUAL` blocks a wastage but never a sale.
  49. Stock count (blind) by the INVENTORY user → approval by the manager (self-approval refused) → variance movements and report; transfer between two outlets incl. a short receipt.
  50. Day close: EOD e-mail shows the Stock block; the invariant holds; a recipe changed mid-day does not change yesterday's food-cost %; INVENTORY user cannot open billing screens; CASHIER gets 403/404 on inventory endpoints.
- **Not verified here:** Java implementation, Postgres performance at 100k movements per outlet per month, real invoice photos, interaction with the billing-extras combos and credit notes (soft references only).

### 26.16 Database — Migration V014 *(verified on PostgreSQL 16 on top of V001–V011: 217 accept/reject cases pass; needs `btree_gist`; no foreign keys to tables of other streams — `credit_notes`, `combo_components` and device tables are referenced by plain uuid columns, FKs added in V016)*
Tables: `inventory_units`, `stock_categories`, `vendors`, `stock_items`, `inventory_settings`, `inventory_counters`, `stock_levels`, `stock_consumptions`, `stock_consumption_skips`, `stock_movements`, `stock_snapshots`, `recipes`, `recipe_lines`, `purchase_orders`, `purchase_order_lines`, `goods_receipts`, `goods_receipt_lines`, `purchase_returns`, `purchase_return_lines`, `vendor_payments`, `vendor_payment_allocations`, `stock_adjustments`, `stock_counts`, `stock_count_lines`, `stock_transfers`, `stock_transfer_lines`, `production_runs`, `inventory_import_jobs`. Triggers: unit rules, level maintenance and cost-basis check on every movement, append-only ledger, no direct level changes, recipe rules and immutability, GRN immutability, allocation limits, transfer same-tenant, tenant-consistency checks. The consumption service itself is application code; the database provides the idempotency anchors (`UNIQUE(bill_id)`, `dedupe_key`).

```sql
-- V014 — Inventory, recipes, purchasing (plan Section 26). Applies on top of V001–V011.
-- Cross-stream references (credit notes, combo components) are plain uuid columns; their FKs are added in V016.
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- needed for the recipe-version exclusion constraint

-- ---------------------------------------------------------------- units
CREATE TABLE inventory_units (
  code text PRIMARY KEY,
  name text NOT NULL,
  family text NOT NULL CHECK (family IN ('MASS','VOLUME','COUNT','PACK')),
  factor_to_base numeric(18,6) CHECK (factor_to_base > 0),
  base_code text,
  CHECK ((family = 'PACK' AND factor_to_base IS NULL AND base_code IS NULL)
      OR (family <> 'PACK' AND factor_to_base IS NOT NULL AND base_code IS NOT NULL))
);
INSERT INTO inventory_units(code,name,family,factor_to_base,base_code) VALUES
 ('g','gram','MASS',1,'g'), ('kg','kilogram','MASS',1000,'g'),
 ('ml','millilitre','VOLUME',1,'ml'), ('l','litre','VOLUME',1000,'ml'),
 ('pcs','piece','COUNT',1,'pcs'), ('dozen','dozen','COUNT',12,'pcs');
INSERT INTO inventory_units(code,name,family) VALUES
 ('pack','pack','PACK'),('box','box','PACK'),('bottle','bottle','PACK'),('can','can','PACK'),
 ('tray','tray','PACK'),('bag','bag','PACK'),('crate','crate','PACK');
ALTER TABLE inventory_units ADD FOREIGN KEY (base_code) REFERENCES inventory_units(code);

-- ---------------------------------------------------------------- masters
CREATE TABLE stock_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  sort_order int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  UNIQUE (tenant_id, name)
);

CREATE TABLE vendors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  contact_person text, phone text, email text, address text,
  gstin text CHECK (gstin IS NULL OR length(btrim(gstin)) BETWEEN 1 AND 20),   -- stored as text; NOT validated against any registry
  payment_terms_days int NOT NULL DEFAULT 0 CHECK (payment_terms_days BETWEEN 0 AND 365),
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX ux_vendors_name ON vendors(tenant_id, lower(name));

CREATE TABLE stock_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  category_id uuid REFERENCES stock_categories(id),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  sku text,
  barcode text,
  item_kind text NOT NULL DEFAULT 'RAW' CHECK (item_kind IN ('RAW','PREP','RETAIL')),
  base_unit_code text NOT NULL REFERENCES inventory_units(code) CHECK (base_unit_code IN ('g','ml','pcs')),
  purchase_unit_code text NOT NULL REFERENCES inventory_units(code),
  purchase_to_base numeric(18,6) NOT NULL CHECK (purchase_to_base > 0),   -- base units in ONE purchase unit
  default_vendor_id uuid REFERENCES vendors(id),
  reorder_level numeric(14,4) NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),   -- base units; per-outlet override in stock_levels
  par_level numeric(14,4) CHECK (par_level IS NULL OR par_level >= reorder_level),
  track_stock boolean NOT NULL DEFAULT true,
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX ux_stock_items_name ON stock_items(tenant_id, lower(name));
CREATE UNIQUE INDEX ux_stock_items_sku ON stock_items(tenant_id, lower(sku)) WHERE sku IS NOT NULL;
CREATE UNIQUE INDEX ux_stock_items_barcode ON stock_items(tenant_id, barcode) WHERE barcode IS NOT NULL;

-- purchase unit must be a PACK unit, or a unit of the same family as the base unit with the exact table factor
CREATE FUNCTION trg_stock_item_units() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE bu inventory_units%ROWTYPE; pu inventory_units%ROWTYPE;
BEGIN
  SELECT * INTO bu FROM inventory_units WHERE code = NEW.base_unit_code;
  SELECT * INTO pu FROM inventory_units WHERE code = NEW.purchase_unit_code;
  IF pu.family <> 'PACK' THEN
    IF pu.family <> bu.family THEN
      RAISE EXCEPTION 'UNIT_FAMILY_MISMATCH: purchase unit % cannot convert to base unit %', pu.code, bu.code USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.purchase_to_base <> pu.factor_to_base THEN
      RAISE EXCEPTION 'UNIT_FACTOR_MISMATCH: % must be % base units', pu.code, pu.factor_to_base USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_items_units BEFORE INSERT OR UPDATE OF base_unit_code, purchase_unit_code, purchase_to_base
  ON stock_items FOR EACH ROW EXECUTE FUNCTION trg_stock_item_units();

CREATE TABLE inventory_settings (
  outlet_id uuid PRIMARY KEY REFERENCES outlets(id),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  negative_stock_policy text NOT NULL DEFAULT 'ALLOW' CHECK (negative_stock_policy IN ('ALLOW','BLOCK_MANUAL')),
  wastage_approval_threshold numeric(12,2) NOT NULL DEFAULT 500 CHECK (wastage_approval_threshold >= 0),
  price_change_alert_percent numeric(5,2) NOT NULL DEFAULT 10 CHECK (price_change_alert_percent > 0),
  low_stock_alerts_enabled boolean NOT NULL DEFAULT true,
  low_stock_recipients text[] NOT NULL DEFAULT '{}',
  dead_stock_days int NOT NULL DEFAULT 30 CHECK (dead_stock_days BETWEEN 7 AND 365),
  count_blind_default boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory_counters (                  -- gapless per outlet and kind: PO, GRN, RET, TRF, CNT, ADJ, PRD
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  kind text NOT NULL CHECK (kind IN ('PO','GRN','RET','TRF','CNT','ADJ','PRD')),
  last_value bigint NOT NULL DEFAULT 0 CHECK (last_value >= 0),
  PRIMARY KEY (outlet_id, kind)
);

-- ---------------------------------------------------------------- stock levels (trigger-maintained) and the ledger
CREATE TABLE stock_levels (
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  on_hand numeric(14,4) NOT NULL DEFAULT 0,                    -- may be negative (policy ALLOW)
  avg_cost numeric(16,6) NOT NULL DEFAULT 0 CHECK (avg_cost >= 0),   -- moving weighted average per base unit
  avg_cost_known boolean NOT NULL DEFAULT false,
  last_purchase_cost numeric(16,6) CHECK (last_purchase_cost IS NULL OR last_purchase_cost >= 0),
  last_purchase_at timestamptz,
  last_movement_at timestamptz,
  reorder_level_override numeric(14,4) CHECK (reorder_level_override IS NULL OR reorder_level_override >= 0),
  par_level_override numeric(14,4) CHECK (par_level_override IS NULL OR par_level_override >= 0),
  low_stock_alerted_on date,
  PRIMARY KEY (outlet_id, stock_item_id)
);

CREATE TABLE stock_consumptions (                  -- one row per bill that consumed stock (idempotency anchor)
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  bill_id uuid NOT NULL UNIQUE REFERENCES bills(id),         -- ONE consumption per bill
  business_date date NOT NULL,
  source text NOT NULL CHECK (source IN ('BILL_PAID','OFFLINE_SYNC')),
  status text NOT NULL DEFAULT 'APPLIED' CHECK (status IN ('APPLIED','PARTIALLY_REVERSED','REVERSED')),
  covered_net_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (covered_net_amount >= 0),     -- sales lines that had a recipe
  uncovered_net_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (uncovered_net_amount >= 0), -- sales lines skipped
  consumed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_consumptions_outlet_date ON stock_consumptions(outlet_id, business_date);

CREATE TABLE stock_consumption_skips (            -- the "no recipe" report: never blocks billing
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consumption_id uuid NOT NULL REFERENCES stock_consumptions(id) ON DELETE CASCADE,
  menu_item_id uuid NOT NULL REFERENCES menu_items(id),
  variant_id uuid REFERENCES item_variants(id),
  quantity numeric(10,3) NOT NULL CHECK (quantity > 0),
  line_net_amount numeric(12,2) NOT NULL CHECK (line_net_amount >= 0),
  reason text NOT NULL CHECK (reason IN ('NO_RECIPE','RECIPE_EMPTY','ITEM_NOT_TRACKED'))
);

CREATE TABLE stock_movements (                    -- APPEND-ONLY ledger
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  kind text NOT NULL CHECK (kind IN ('OPENING','PURCHASE','SALE','SALE_REVERSAL','WASTAGE','ADJUSTMENT','COUNT_VARIANCE',
                                      'TRANSFER_OUT','TRANSFER_IN','VENDOR_RETURN','PRODUCTION_CONSUME','PRODUCTION_OUTPUT')),
  quantity_base numeric(14,4) NOT NULL CHECK (quantity_base <> 0),   -- signed, base units
  unit_cost numeric(16,6) NOT NULL CHECK (unit_cost >= 0),
  cost_basis text NOT NULL CHECK (cost_basis IN ('ACTUAL','REVERSAL','AVERAGE','LAST_PURCHASE','UNKNOWN')),
  cost_estimated boolean GENERATED ALWAYS AS (cost_basis IN ('LAST_PURCHASE','UNKNOWN')) STORED,
  line_value numeric(14,2) GENERATED ALWAYS AS (round(quantity_base * unit_cost, 2)) STORED,
  occurred_at timestamptz NOT NULL,
  business_date date NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  actor_id uuid REFERENCES users(id),               -- NULL = system (bill-paid trigger)
  reason_code text,
  note text,
  ref_type text CHECK (ref_type IN ('BILL','BILL_VOID','CREDIT_NOTE','GRN','PURCHASE_RETURN','ADJUSTMENT','COUNT','TRANSFER','PRODUCTION','IMPORT')),
  ref_id uuid,
  consumption_id uuid REFERENCES stock_consumptions(id),
  reverses_movement_id uuid REFERENCES stock_movements(id),
  dedupe_key text NOT NULL UNIQUE,
  CHECK ((kind IN ('OPENING','PURCHASE','SALE_REVERSAL','TRANSFER_IN','PRODUCTION_OUTPUT') AND quantity_base > 0)
      OR (kind IN ('SALE','WASTAGE','VENDOR_RETURN','TRANSFER_OUT','PRODUCTION_CONSUME') AND quantity_base < 0)
      OR kind IN ('ADJUSTMENT','COUNT_VARIANCE')),
  CHECK ((quantity_base > 0 AND cost_basis IN ('ACTUAL','REVERSAL','AVERAGE'))
      OR (quantity_base < 0 AND cost_basis IN ('AVERAGE','LAST_PURCHASE','UNKNOWN'))),
  CHECK (cost_basis <> 'UNKNOWN' OR unit_cost = 0),
  CHECK (kind NOT IN ('OPENING','PURCHASE','TRANSFER_IN','PRODUCTION_OUTPUT') OR cost_basis = 'ACTUAL'),
  CHECK (kind <> 'SALE_REVERSAL' OR cost_basis IN ('REVERSAL','AVERAGE')),
  CHECK (kind NOT IN ('ADJUSTMENT','COUNT_VARIANCE') OR quantity_base < 0 OR cost_basis = 'AVERAGE'),   -- found stock enters at the current average
  CHECK (kind <> 'SALE' OR consumption_id IS NOT NULL),
  CHECK (kind <> 'SALE_REVERSAL' OR reverses_movement_id IS NOT NULL),
  CHECK (kind <> 'PURCHASE' OR (ref_type = 'GRN' AND ref_id IS NOT NULL)),
  CHECK (kind NOT IN ('WASTAGE','ADJUSTMENT','COUNT_VARIANCE') OR (reason_code IS NOT NULL AND length(btrim(reason_code)) > 0))
);
CREATE INDEX ix_movements_item_time ON stock_movements(outlet_id, stock_item_id, occurred_at);
CREATE INDEX ix_movements_date_kind ON stock_movements(outlet_id, business_date, kind);
CREATE INDEX ix_movements_consumption ON stock_movements(consumption_id) WHERE consumption_id IS NOT NULL;
CREATE INDEX ix_movements_reverses ON stock_movements(reverses_movement_id) WHERE reverses_movement_id IS NOT NULL;

-- ledger is append-only
CREATE FUNCTION trg_stock_movements_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'LEDGER_IMMUTABLE: stock_movements is append-only (% not allowed)', TG_OP USING ERRCODE = 'restrict_violation'; END $$;
CREATE TRIGGER stock_movements_no_update BEFORE UPDATE OR DELETE ON stock_movements FOR EACH ROW EXECUTE FUNCTION trg_stock_movements_immutable();
CREATE TRIGGER stock_movements_no_truncate BEFORE TRUNCATE ON stock_movements FOR EACH STATEMENT EXECUTE FUNCTION trg_stock_movements_immutable();

-- BEFORE INSERT: validate (cost rules, policy, reversal cap) under a row lock on the level
CREATE FUNCTION trg_stock_movements_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE lv stock_levels%ROWTYPE; pol text; orig stock_movements%ROWTYPE; already numeric;
        exp_basis text; exp_cost numeric; tracked boolean;
BEGIN
  SELECT track_stock INTO tracked FROM stock_items WHERE id = NEW.stock_item_id AND tenant_id = NEW.tenant_id;
  IF tracked IS NULL THEN RAISE EXCEPTION 'STOCK_ITEM_TENANT_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
  IF NOT tracked THEN RAISE EXCEPTION 'ITEM_NOT_TRACKED' USING ERRCODE = 'check_violation'; END IF;
  IF NOT EXISTS (SELECT 1 FROM outlets WHERE id = NEW.outlet_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'OUTLET_TENANT_MISMATCH' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO stock_levels(outlet_id, stock_item_id, tenant_id) VALUES (NEW.outlet_id, NEW.stock_item_id, NEW.tenant_id)
    ON CONFLICT DO NOTHING;
  SELECT * INTO lv FROM stock_levels WHERE outlet_id = NEW.outlet_id AND stock_item_id = NEW.stock_item_id FOR UPDATE;

  IF NEW.quantity_base < 0 THEN               -- outflow cost is DETERMINED by the level, never by the caller
    IF lv.on_hand > 0 AND lv.avg_cost_known THEN exp_basis := 'AVERAGE'; exp_cost := lv.avg_cost;
    ELSIF lv.last_purchase_cost IS NOT NULL THEN exp_basis := 'LAST_PURCHASE'; exp_cost := lv.last_purchase_cost;
    ELSE exp_basis := 'UNKNOWN'; exp_cost := 0; END IF;
    IF NEW.cost_basis <> exp_basis OR NEW.unit_cost <> exp_cost THEN
      RAISE EXCEPTION 'COST_BASIS_MISMATCH: expected % at %', exp_basis, exp_cost USING ERRCODE = 'check_violation';
    END IF;
    SELECT negative_stock_policy INTO pol FROM inventory_settings WHERE outlet_id = NEW.outlet_id;
    IF COALESCE(pol, 'ALLOW') = 'BLOCK_MANUAL' AND lv.on_hand + NEW.quantity_base < 0
       AND NEW.kind IN ('WASTAGE','ADJUSTMENT','TRANSFER_OUT','VENDOR_RETURN','PRODUCTION_CONSUME') THEN
      RAISE EXCEPTION 'NEGATIVE_STOCK_BLOCKED' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF NEW.cost_basis = 'AVERAGE' AND NEW.unit_cost <> lv.avg_cost THEN
    RAISE EXCEPTION 'COST_BASIS_MISMATCH: AVERAGE inflow must use the current average %', lv.avg_cost USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.kind = 'SALE_REVERSAL' THEN
    SELECT * INTO orig FROM stock_movements WHERE id = NEW.reverses_movement_id;
    IF NOT FOUND OR orig.kind <> 'SALE' OR orig.stock_item_id <> NEW.stock_item_id OR orig.outlet_id <> NEW.outlet_id THEN
      RAISE EXCEPTION 'REVERSAL_TARGET_INVALID' USING ERRCODE = 'check_violation';
    END IF;
    SELECT COALESCE(sum(quantity_base), 0) INTO already FROM stock_movements
      WHERE reverses_movement_id = NEW.reverses_movement_id AND kind = 'SALE_REVERSAL';
    IF already + NEW.quantity_base > -orig.quantity_base THEN
      RAISE EXCEPTION 'REVERSAL_EXCEEDS_ORIGINAL' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.unit_cost <> orig.unit_cost THEN       -- a reversal always returns stock at the ORIGINAL sale cost
      RAISE EXCEPTION 'REVERSAL_COST_MISMATCH: must equal the original unit cost %', orig.unit_cost USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_movements_before BEFORE INSERT ON stock_movements FOR EACH ROW EXECUTE FUNCTION trg_stock_movements_before();

-- AFTER INSERT: apply to the level (fires only for rows really inserted, so ON CONFLICT DO NOTHING cannot diverge)
CREATE FUNCTION trg_stock_movements_after() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE lv stock_levels%ROWTYPE; n_on numeric; n_avg numeric; n_known boolean; n_lp numeric; n_lpat timestamptz;
BEGIN
  PERFORM set_config('galla.stock_trigger', '1', true);
  SELECT * INTO lv FROM stock_levels WHERE outlet_id = NEW.outlet_id AND stock_item_id = NEW.stock_item_id FOR UPDATE;
  n_on := lv.on_hand + NEW.quantity_base;
  n_avg := lv.avg_cost; n_known := lv.avg_cost_known; n_lp := lv.last_purchase_cost; n_lpat := lv.last_purchase_at;
  IF NEW.quantity_base > 0 AND NEW.cost_basis IN ('ACTUAL','REVERSAL') THEN
    IF lv.on_hand <= 0 THEN n_avg := NEW.unit_cost;
    ELSE n_avg := round((lv.on_hand * lv.avg_cost + NEW.quantity_base * NEW.unit_cost) / (lv.on_hand + NEW.quantity_base), 6);
    END IF;
    IF NEW.cost_basis = 'ACTUAL' THEN n_known := true; END IF;
  END IF;
  IF NEW.kind = 'PURCHASE' AND (lv.last_purchase_at IS NULL OR NEW.occurred_at >= lv.last_purchase_at) THEN
    n_lp := NEW.unit_cost; n_lpat := NEW.occurred_at;
  END IF;
  UPDATE stock_levels SET on_hand = n_on, avg_cost = n_avg, avg_cost_known = n_known,
         last_purchase_cost = n_lp, last_purchase_at = n_lpat,
         last_movement_at = GREATEST(COALESCE(lv.last_movement_at, NEW.occurred_at), NEW.occurred_at)
   WHERE outlet_id = NEW.outlet_id AND stock_item_id = NEW.stock_item_id;
  PERFORM set_config('galla.stock_trigger', '0', true);
  RETURN NULL;
END $$;
CREATE TRIGGER stock_movements_after AFTER INSERT ON stock_movements FOR EACH ROW EXECUTE FUNCTION trg_stock_movements_after();

-- levels can only be changed through the ledger
CREATE FUNCTION trg_stock_levels_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF COALESCE(current_setting('galla.stock_trigger', true), '') = '1' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF; RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'STOCK_LEVEL_DIRECT_CHANGE' USING ERRCODE = 'restrict_violation'; END IF;
  IF TG_OP = 'INSERT' THEN       -- a level row starts empty; quantity and cost arrive only through the ledger
    IF NEW.on_hand <> 0 OR NEW.avg_cost <> 0 OR NEW.avg_cost_known OR NEW.last_purchase_cost IS NOT NULL
       OR NEW.last_purchase_at IS NOT NULL OR NEW.last_movement_at IS NOT NULL THEN
      RAISE EXCEPTION 'STOCK_LEVEL_DIRECT_CHANGE: a new level starts at zero' USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF (NEW.on_hand, NEW.avg_cost, NEW.avg_cost_known, NEW.last_purchase_cost, NEW.last_purchase_at, NEW.last_movement_at)
     IS DISTINCT FROM (OLD.on_hand, OLD.avg_cost, OLD.avg_cost_known, OLD.last_purchase_cost, OLD.last_purchase_at, OLD.last_movement_at) THEN
    RAISE EXCEPTION 'STOCK_LEVEL_DIRECT_CHANGE: on-hand and cost change only through stock_movements' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_levels_guard BEFORE INSERT OR UPDATE OR DELETE ON stock_levels FOR EACH ROW EXECUTE FUNCTION trg_stock_levels_guard();

CREATE TABLE stock_snapshots (                    -- written by day close; opening/closing valuation of the EOD e-mail
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  business_date date NOT NULL,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  on_hand numeric(14,4) NOT NULL,
  avg_cost numeric(16,6) NOT NULL CHECK (avg_cost >= 0),
  value_amount numeric(14,2) GENERATED ALWAYS AS (round(on_hand * avg_cost, 2)) STORED,
  PRIMARY KEY (outlet_id, business_date, stock_item_id)
);

-- ---------------------------------------------------------------- recipes (versioned, immutable once active)
CREATE TABLE recipes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),                       -- NULL only for PREP_ITEM recipes (shared by all outlets)
  target_type text NOT NULL CHECK (target_type IN ('MENU_ITEM','VARIANT','MODIFIER','PREP_ITEM')),
  menu_item_id uuid REFERENCES menu_items(id),
  variant_id uuid REFERENCES item_variants(id),
  modifier_id uuid REFERENCES modifiers(id),
  prep_stock_item_id uuid REFERENCES stock_items(id),
  target_id uuid GENERATED ALWAYS AS (COALESCE(prep_stock_item_id, modifier_id, variant_id, menu_item_id)) STORED,
  version int NOT NULL CHECK (version >= 1),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','ARCHIVED')),
  effective_from timestamptz NOT NULL,
  effective_to timestamptz,
  yield_qty_base numeric(14,4) CHECK (yield_qty_base IS NULL OR yield_qty_base > 0),   -- PREP only: output of ONE batch
  inherit_item_recipe boolean NOT NULL DEFAULT false,          -- VARIANT only: use the item's recipe x portion_factor
  portion_factor numeric(8,4) NOT NULL DEFAULT 1 CHECK (portion_factor > 0),
  note text,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (effective_to IS NULL OR effective_to > effective_from),
  CHECK ((target_type = 'MENU_ITEM' AND menu_item_id IS NOT NULL AND variant_id IS NULL AND modifier_id IS NULL AND prep_stock_item_id IS NULL)
      OR (target_type = 'VARIANT'   AND variant_id IS NOT NULL AND menu_item_id IS NULL AND modifier_id IS NULL AND prep_stock_item_id IS NULL)
      OR (target_type = 'MODIFIER'  AND modifier_id IS NOT NULL AND menu_item_id IS NULL AND variant_id IS NULL AND prep_stock_item_id IS NULL)
      OR (target_type = 'PREP_ITEM' AND prep_stock_item_id IS NOT NULL AND menu_item_id IS NULL AND variant_id IS NULL AND modifier_id IS NULL)),
  CHECK ((target_type = 'PREP_ITEM') = (yield_qty_base IS NOT NULL)),
  CHECK ((target_type = 'PREP_ITEM') = (outlet_id IS NULL)),
  CHECK (NOT inherit_item_recipe OR target_type = 'VARIANT'),
  UNIQUE (target_id, version),
  EXCLUDE USING gist (target_id WITH =, tstzrange(effective_from, effective_to) WITH &&) WHERE (status = 'ACTIVE')
);

CREATE TABLE recipe_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id uuid NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  line_no int NOT NULL CHECK (line_no >= 1),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  quantity numeric(14,4) NOT NULL CHECK (quantity > 0),              -- NET quantity per portion (or per batch for PREP), in unit_code
  unit_code text NOT NULL REFERENCES inventory_units(code),
  quantity_base numeric(14,4) NOT NULL CHECK (quantity_base > 0),    -- = round(quantity * unit factor, 4); validated by trigger
  wastage_percent numeric(5,2) NOT NULL DEFAULT 0 CHECK (wastage_percent >= 0 AND wastage_percent < 100),
  consume_mode text NOT NULL DEFAULT 'DIRECT' CHECK (consume_mode IN ('DIRECT','EXPAND')),   -- EXPAND: use the prep item's raw ingredients instead of its stock
  UNIQUE (recipe_id, line_no),
  UNIQUE (recipe_id, stock_item_id)
);

CREATE FUNCTION trg_recipe_lines_rules() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r recipes%ROWTYPE; si stock_items%ROWTYPE; u inventory_units%ROWTYPE; bu inventory_units%ROWTYPE; rid uuid; st text; prep stock_items%ROWTYPE;
BEGIN
  rid := CASE WHEN TG_OP = 'DELETE' THEN OLD.recipe_id ELSE NEW.recipe_id END;
  SELECT * INTO r FROM recipes WHERE id = rid;
  IF r.status <> 'DRAFT' THEN RAISE EXCEPTION 'RECIPE_IMMUTABLE: create a new version instead' USING ERRCODE = 'restrict_violation'; END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF r.inherit_item_recipe THEN RAISE EXCEPTION 'RECIPE_INHERITS: a variant that inherits the item recipe has no lines' USING ERRCODE = 'check_violation'; END IF;
  SELECT * INTO si FROM stock_items WHERE id = NEW.stock_item_id;
  IF si.tenant_id <> r.tenant_id THEN RAISE EXCEPTION 'STOCK_ITEM_TENANT_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
  SELECT * INTO u FROM inventory_units WHERE code = NEW.unit_code;
  SELECT * INTO bu FROM inventory_units WHERE code = si.base_unit_code;
  IF u.family = 'PACK' OR u.family <> bu.family THEN
    RAISE EXCEPTION 'UNIT_FAMILY_MISMATCH: % cannot be used for an item counted in %', u.code, bu.code USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.quantity_base <> round(NEW.quantity * u.factor_to_base, 4) THEN
    RAISE EXCEPTION 'QUANTITY_BASE_MISMATCH' USING ERRCODE = 'check_violation';
  END IF;
  IF r.target_type = 'PREP_ITEM' THEN
    IF si.item_kind = 'PREP' THEN RAISE EXCEPTION 'PREP_NESTING_NOT_ALLOWED: a prep recipe may only use raw/retail items' USING ERRCODE = 'check_violation'; END IF;
    SELECT * INTO prep FROM stock_items WHERE id = r.prep_stock_item_id;
    IF prep.item_kind <> 'PREP' THEN RAISE EXCEPTION 'PREP_TARGET_INVALID' USING ERRCODE = 'check_violation'; END IF;
  END IF;
  IF NEW.consume_mode = 'EXPAND' AND si.item_kind <> 'PREP' THEN
    RAISE EXCEPTION 'EXPAND_ONLY_FOR_PREP' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER recipe_lines_rules BEFORE INSERT OR UPDATE OR DELETE ON recipe_lines FOR EACH ROW EXECUTE FUNCTION trg_recipe_lines_rules();

CREATE FUNCTION trg_recipes_rules() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN RAISE EXCEPTION 'RECIPE_IMMUTABLE: only drafts can be deleted' USING ERRCODE = 'restrict_violation'; END IF;
    RETURN OLD;
  END IF;
  IF TG_OP = 'INSERT' THEN
    -- malformed target / outlet combinations are reported by the table CHECKs, so skip the cross-table lookups for them
    IF (NEW.target_type <> 'PREP_ITEM' AND NEW.outlet_id IS NULL)
       OR (NEW.target_type = 'MENU_ITEM' AND NEW.menu_item_id IS NULL) OR (NEW.target_type = 'VARIANT' AND NEW.variant_id IS NULL)
       OR (NEW.target_type = 'MODIFIER' AND NEW.modifier_id IS NULL) OR (NEW.target_type = 'PREP_ITEM' AND NEW.prep_stock_item_id IS NULL) THEN
      RETURN NEW;
    END IF;
    IF NEW.target_type = 'PREP_ITEM' THEN
      IF NOT EXISTS (SELECT 1 FROM stock_items WHERE id = NEW.prep_stock_item_id AND tenant_id = NEW.tenant_id) THEN
        RAISE EXCEPTION 'RECIPE_TARGET_TENANT_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
    ELSIF NEW.target_type = 'MENU_ITEM' THEN
      IF NOT EXISTS (SELECT 1 FROM menu_items WHERE id = NEW.menu_item_id AND tenant_id = NEW.tenant_id AND outlet_id = NEW.outlet_id) THEN
        RAISE EXCEPTION 'RECIPE_TARGET_OUTLET_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
    ELSIF NEW.target_type = 'VARIANT' THEN
      IF NOT EXISTS (SELECT 1 FROM item_variants v JOIN menu_items m ON m.id = v.menu_item_id
                      WHERE v.id = NEW.variant_id AND m.tenant_id = NEW.tenant_id AND m.outlet_id = NEW.outlet_id) THEN
        RAISE EXCEPTION 'RECIPE_TARGET_OUTLET_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
    ELSE
      IF NOT EXISTS (SELECT 1 FROM modifiers md JOIN modifier_groups g ON g.id = md.group_id
                      WHERE md.id = NEW.modifier_id AND md.tenant_id = NEW.tenant_id AND g.outlet_id = NEW.outlet_id) THEN
        RAISE EXCEPTION 'RECIPE_TARGET_OUTLET_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.status <> 'DRAFT' THEN
    IF (NEW.tenant_id, NEW.outlet_id, NEW.target_type, NEW.menu_item_id, NEW.variant_id, NEW.modifier_id, NEW.prep_stock_item_id, NEW.version, NEW.effective_from, NEW.yield_qty_base, NEW.inherit_item_recipe, NEW.portion_factor)
       IS DISTINCT FROM (OLD.tenant_id, OLD.outlet_id, OLD.target_type, OLD.menu_item_id, OLD.variant_id, OLD.modifier_id, OLD.prep_stock_item_id, OLD.version, OLD.effective_from, OLD.yield_qty_base, OLD.inherit_item_recipe, OLD.portion_factor)
       OR (OLD.status = 'ARCHIVED' AND NEW.status <> 'ARCHIVED') OR (OLD.status = 'ACTIVE' AND NEW.status = 'DRAFT') THEN
      RAISE EXCEPTION 'RECIPE_IMMUTABLE: an active recipe only gets an end date or is archived' USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER recipes_rules BEFORE INSERT OR UPDATE OR DELETE ON recipes FOR EACH ROW EXECUTE FUNCTION trg_recipes_rules();

-- ---------------------------------------------------------------- purchasing
CREATE TABLE purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  vendor_id uuid NOT NULL REFERENCES vendors(id),
  po_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SENT','PARTIALLY_RECEIVED','RECEIVED','CANCELLED')),
  expected_date date,
  notes text,
  total_estimate numeric(14,2) NOT NULL DEFAULT 0 CHECK (total_estimate >= 0),
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  cancelled_reason text,
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (outlet_id, po_number),
  CHECK (status <> 'CANCELLED' OR (cancelled_reason IS NOT NULL AND length(btrim(cancelled_reason)) > 0)),
  CHECK (status NOT IN ('SENT','PARTIALLY_RECEIVED','RECEIVED') OR sent_at IS NOT NULL)
);

CREATE TABLE purchase_order_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  po_id uuid NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  ordered_qty numeric(14,4) NOT NULL CHECK (ordered_qty > 0),        -- in the item's purchase unit
  unit_price numeric(16,6) NOT NULL CHECK (unit_price >= 0),         -- per purchase unit, before tax
  received_qty numeric(14,4) NOT NULL DEFAULT 0 CHECK (received_qty >= 0),
  UNIQUE (po_id, stock_item_id)
);

CREATE TABLE goods_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  vendor_id uuid NOT NULL REFERENCES vendors(id),
  po_id uuid REFERENCES purchase_orders(id),
  grn_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','POSTED','VOID')),
  invoice_number text,
  invoice_date date,
  due_date date,
  received_at timestamptz NOT NULL DEFAULT now(),
  subtotal numeric(14,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  tax_total numeric(14,2) NOT NULL DEFAULT 0 CHECK (tax_total >= 0),      -- recorded exactly as on the vendor invoice; NOT interpreted
  other_charges numeric(14,2) NOT NULL DEFAULT 0,                          -- freight etc.; NOT added to stock cost in v1
  round_off numeric(14,2) NOT NULL DEFAULT 0,
  total_amount numeric(14,2) NOT NULL CHECK (total_amount >= 0),
  attachment_key text,
  attachment_content_type text CHECK (attachment_content_type IN ('image/jpeg','image/png','application/pdf')),
  attachment_size_bytes int CHECK (attachment_size_bytes IS NULL OR attachment_size_bytes BETWEEN 1 AND 5242880),
  notes text,
  created_by uuid NOT NULL REFERENCES users(id),
  posted_by uuid REFERENCES users(id),
  posted_at timestamptz,
  voided_by uuid REFERENCES users(id),
  void_reason text,
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (outlet_id, grn_number),
  CHECK (total_amount = subtotal + tax_total + other_charges + round_off),
  CHECK (status <> 'POSTED' OR (invoice_number IS NOT NULL AND length(btrim(invoice_number)) > 0 AND invoice_date IS NOT NULL AND posted_by IS NOT NULL AND posted_at IS NOT NULL)),
  CHECK (status <> 'VOID' OR (void_reason IS NOT NULL AND length(btrim(void_reason)) > 0)),
  CHECK ((attachment_key IS NULL) = (attachment_content_type IS NULL))
);
CREATE UNIQUE INDEX ux_grn_vendor_invoice ON goods_receipts(tenant_id, vendor_id, lower(btrim(invoice_number)))
  WHERE invoice_number IS NOT NULL AND status <> 'VOID';          -- duplicate-invoice guard

CREATE TABLE goods_receipt_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  grn_id uuid NOT NULL REFERENCES goods_receipts(id) ON DELETE CASCADE,
  po_line_id uuid REFERENCES purchase_order_lines(id),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  qty_purchase numeric(14,4) NOT NULL CHECK (qty_purchase > 0),
  purchase_unit_code text NOT NULL REFERENCES inventory_units(code),   -- snapshots, so later item edits never change history
  purchase_to_base numeric(18,6) NOT NULL CHECK (purchase_to_base > 0),
  qty_base numeric(14,4) NOT NULL CHECK (qty_base > 0),
  unit_price numeric(16,6) NOT NULL CHECK (unit_price >= 0),           -- per purchase unit, before tax
  unit_cost_base numeric(16,6) NOT NULL CHECK (unit_cost_base >= 0),   -- per base unit; this is the cost that enters the ledger
  line_amount numeric(14,2) NOT NULL CHECK (line_amount >= 0),
  tax_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  price_change_percent numeric(8,2),
  price_alert boolean NOT NULL DEFAULT false,
  UNIQUE (grn_id, stock_item_id),
  CHECK (qty_base = round(qty_purchase * purchase_to_base, 4)),
  CHECK (unit_cost_base = round(unit_price / purchase_to_base, 6)),
  CHECK (line_amount = round(qty_purchase * unit_price, 2))
);

-- a posted receipt is frozen: lines never change, the header can only be voided (the stock effect is reversed by new ledger rows)
CREATE FUNCTION trg_grn_lines_draft_only() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text;
BEGIN
  SELECT status INTO st FROM goods_receipts WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.grn_id ELSE NEW.grn_id END;
  IF st IS DISTINCT FROM 'DRAFT' THEN RAISE EXCEPTION 'GRN_NOT_DRAFT: lines of a posted or void receipt cannot change' USING ERRCODE = 'restrict_violation'; END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER grn_lines_draft_only BEFORE INSERT OR UPDATE OR DELETE ON goods_receipt_lines FOR EACH ROW EXECUTE FUNCTION trg_grn_lines_draft_only();

CREATE FUNCTION trg_grn_header_rules() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN RAISE EXCEPTION 'GRN_NOT_DRAFT: only a draft receipt can be deleted' USING ERRCODE = 'restrict_violation'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.status = 'VOID' THEN RAISE EXCEPTION 'GRN_VOID_IS_FINAL' USING ERRCODE = 'restrict_violation'; END IF;
  IF OLD.status = 'POSTED' THEN
    IF NEW.status NOT IN ('POSTED','VOID')
       OR (NEW.tenant_id, NEW.outlet_id, NEW.vendor_id, NEW.po_id, NEW.grn_number, NEW.invoice_number, NEW.invoice_date, NEW.subtotal,
           NEW.tax_total, NEW.other_charges, NEW.round_off, NEW.total_amount, NEW.posted_by, NEW.posted_at)
          IS DISTINCT FROM
          (OLD.tenant_id, OLD.outlet_id, OLD.vendor_id, OLD.po_id, OLD.grn_number, OLD.invoice_number, OLD.invoice_date, OLD.subtotal,
           OLD.tax_total, OLD.other_charges, OLD.round_off, OLD.total_amount, OLD.posted_by, OLD.posted_at) THEN
      RAISE EXCEPTION 'GRN_POSTED_IMMUTABLE: a posted receipt can only be voided' USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER grn_header_rules BEFORE UPDATE OR DELETE ON goods_receipts FOR EACH ROW EXECUTE FUNCTION trg_grn_header_rules();

CREATE TABLE purchase_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  vendor_id uuid NOT NULL REFERENCES vendors(id),
  grn_id uuid REFERENCES goods_receipts(id),
  return_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','POSTED','VOID')),
  reason text NOT NULL CHECK (length(btrim(reason)) > 0),
  credit_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (credit_amount >= 0),    -- what the vendor credits us (may differ from stock value)
  created_by uuid NOT NULL REFERENCES users(id),
  posted_by uuid REFERENCES users(id),
  posted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, return_number),
  CHECK (status <> 'POSTED' OR (posted_by IS NOT NULL AND posted_at IS NOT NULL))
);
CREATE TABLE purchase_return_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id uuid NOT NULL REFERENCES purchase_returns(id) ON DELETE CASCADE,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  qty_base numeric(14,4) NOT NULL CHECK (qty_base > 0),
  UNIQUE (return_id, stock_item_id)
);

CREATE TABLE vendor_payments (                     -- recorded manually; no gateway in v1
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  vendor_id uuid NOT NULL REFERENCES vendors(id),
  outlet_id uuid REFERENCES outlets(id),
  paid_on date NOT NULL,
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  method text NOT NULL CHECK (method IN ('CASH','UPI','BANK_TRANSFER','CHEQUE','CARD','OTHER')),
  reference text,
  recorded_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  voided_at timestamptz
);
CREATE TABLE vendor_payment_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES vendor_payments(id),
  grn_id uuid NOT NULL REFERENCES goods_receipts(id),
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  UNIQUE (payment_id, grn_id)
);
CREATE FUNCTION trg_vendor_alloc_limits() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pay numeric; used_pay numeric; grn_total numeric; used_grn numeric; v1 uuid; v2 uuid;
BEGIN
  SELECT amount, vendor_id INTO pay, v1 FROM vendor_payments WHERE id = NEW.payment_id;
  SELECT total_amount, vendor_id INTO grn_total, v2 FROM goods_receipts WHERE id = NEW.grn_id AND status = 'POSTED';
  IF v2 IS NULL THEN RAISE EXCEPTION 'ALLOCATION_GRN_NOT_POSTED' USING ERRCODE = 'check_violation'; END IF;
  IF v1 <> v2 THEN RAISE EXCEPTION 'ALLOCATION_VENDOR_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
  SELECT COALESCE(sum(amount), 0) INTO used_pay FROM vendor_payment_allocations WHERE payment_id = NEW.payment_id;
  SELECT COALESCE(sum(a.amount), 0) INTO used_grn FROM vendor_payment_allocations a JOIN vendor_payments p ON p.id = a.payment_id
    WHERE a.grn_id = NEW.grn_id AND p.voided_at IS NULL;
  IF used_pay > pay THEN RAISE EXCEPTION 'ALLOCATION_EXCEEDS_PAYMENT' USING ERRCODE = 'check_violation'; END IF;
  IF used_grn > grn_total THEN RAISE EXCEPTION 'ALLOCATION_EXCEEDS_INVOICE' USING ERRCODE = 'check_violation'; END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER vendor_alloc_limits AFTER INSERT ON vendor_payment_allocations
  DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION trg_vendor_alloc_limits();

-- ---------------------------------------------------------------- adjustments, counts, transfers, production
CREATE TABLE stock_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  adjustment_number text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('WASTAGE','ADJUSTMENT')),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  quantity_base numeric(14,4) NOT NULL CHECK (quantity_base <> 0),             -- signed; WASTAGE is negative
  reason_code text NOT NULL,
  note text,
  value_amount numeric(14,2) NOT NULL CHECK (value_amount >= 0),               -- |qty| x cost at the time
  requires_approval boolean NOT NULL DEFAULT false,                            -- value above outlet threshold (manager PIN)
  approved_by uuid REFERENCES users(id),
  movement_id uuid,                                                           -- stock_movements.id (no FK: movement is written in the same txn)
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, adjustment_number),
  CHECK (kind <> 'WASTAGE' OR quantity_base < 0),
  CHECK (kind <> 'WASTAGE' OR reason_code IN ('SPOILAGE','EXPIRED','SPILL','DAMAGED','RETURNED_BY_CUSTOMER','STAFF_MEAL','TRANSIT_LOSS','THEFT_SUSPECTED','OTHER')),
  CHECK (kind <> 'ADJUSTMENT' OR reason_code IN ('DATA_ENTRY_CORRECTION','FOUND_STOCK','DAMAGED','OTHER')),
  CHECK (reason_code <> 'OTHER' OR (note IS NOT NULL AND length(btrim(note)) > 0)),
  CHECK (NOT requires_approval OR approved_by IS NOT NULL)
);

CREATE TABLE stock_counts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  count_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','IN_PROGRESS','SUBMITTED','APPROVED','CANCELLED')),
  scope text NOT NULL DEFAULT 'FULL' CHECK (scope IN ('FULL','CATEGORY','SELECTED')),
  category_id uuid REFERENCES stock_categories(id),
  blind boolean NOT NULL DEFAULT true,
  started_by uuid REFERENCES users(id),
  started_at timestamptz,
  submitted_by uuid REFERENCES users(id),
  submitted_at timestamptz,
  approved_by uuid REFERENCES users(id),
  approved_at timestamptz,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, count_number),
  CHECK (scope <> 'CATEGORY' OR category_id IS NOT NULL),
  CHECK (status <> 'APPROVED' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL AND submitted_by IS NOT NULL)),
  CHECK (status NOT IN ('SUBMITTED','APPROVED') OR (submitted_by IS NOT NULL AND submitted_at IS NOT NULL)),
  CHECK (approved_by IS NULL OR submitted_by IS NULL OR approved_by <> submitted_by)    -- four-eyes: approver is not the submitter
);
CREATE TABLE stock_count_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  count_id uuid NOT NULL REFERENCES stock_counts(id) ON DELETE CASCADE,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  system_qty_base numeric(14,4) NOT NULL,                     -- frozen when the sheet is started; hidden from counters in blind mode
  avg_cost_snapshot numeric(16,6) NOT NULL CHECK (avg_cost_snapshot >= 0),
  counted_qty_base numeric(14,4) CHECK (counted_qty_base IS NULL OR counted_qty_base >= 0),
  variance_qty numeric(14,4) GENERATED ALWAYS AS (counted_qty_base - system_qty_base) STORED,
  variance_value numeric(14,2) GENERATED ALWAYS AS (round((counted_qty_base - system_qty_base) * avg_cost_snapshot, 2)) STORED,
  note text,
  UNIQUE (count_id, stock_item_id)
);

CREATE TABLE stock_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  from_outlet_id uuid NOT NULL REFERENCES outlets(id),
  to_outlet_id uuid NOT NULL REFERENCES outlets(id),
  transfer_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','IN_TRANSIT','RECEIVED','CANCELLED')),
  sent_by uuid REFERENCES users(id), sent_at timestamptz,
  received_by uuid REFERENCES users(id), received_at timestamptz,
  note text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (from_outlet_id, transfer_number),
  CHECK (from_outlet_id <> to_outlet_id),
  CHECK (status NOT IN ('IN_TRANSIT','RECEIVED') OR (sent_by IS NOT NULL AND sent_at IS NOT NULL)),
  CHECK (status <> 'RECEIVED' OR (received_by IS NOT NULL AND received_at IS NOT NULL))
);
CREATE FUNCTION trg_transfer_same_tenant() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.from_outlet_id = NEW.to_outlet_id THEN RETURN NEW; END IF;   -- the CHECK reports this case
  IF (SELECT count(*) FROM outlets WHERE id IN (NEW.from_outlet_id, NEW.to_outlet_id) AND tenant_id = NEW.tenant_id) <> 2 THEN
    RAISE EXCEPTION 'TRANSFER_CROSS_TENANT' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_transfers_same_tenant BEFORE INSERT OR UPDATE OF from_outlet_id, to_outlet_id, tenant_id ON stock_transfers
  FOR EACH ROW EXECUTE FUNCTION trg_transfer_same_tenant();
CREATE TABLE stock_transfer_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id uuid NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  qty_sent_base numeric(14,4) NOT NULL CHECK (qty_sent_base > 0),
  unit_cost_sent numeric(16,6) CHECK (unit_cost_sent IS NULL OR unit_cost_sent >= 0),   -- set when sent
  qty_received_base numeric(14,4) CHECK (qty_received_base IS NULL OR qty_received_base >= 0),
  UNIQUE (transfer_id, stock_item_id),
  CHECK (qty_received_base IS NULL OR qty_received_base <= qty_sent_base)
);

CREATE TABLE production_runs (                    -- turns raw items into a PREP item (gravy base, dough, ...)
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  run_number text NOT NULL,
  prep_stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  recipe_id uuid NOT NULL REFERENCES recipes(id),
  batches numeric(10,3) NOT NULL CHECK (batches > 0),
  output_qty_base numeric(14,4) NOT NULL CHECK (output_qty_base > 0),     -- actual output (may differ from batches x yield)
  produced_at timestamptz NOT NULL,
  business_date date NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, run_number)
);

-- ---------------------------------------------------------------- CSV import
CREATE TABLE inventory_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  kind text NOT NULL CHECK (kind IN ('STOCK_ITEMS','OPENING_STOCK','RECIPES')),
  file_key text NOT NULL,
  file_sha256 char(64) NOT NULL,
  status text NOT NULL DEFAULT 'VALIDATED' CHECK (status IN ('VALIDATED','COMMITTED','REJECTED')),
  total_rows int NOT NULL CHECK (total_rows >= 0),
  ok_rows int NOT NULL CHECK (ok_rows >= 0),
  error_rows int NOT NULL CHECK (error_rows >= 0),
  errors jsonb NOT NULL DEFAULT '[]',               -- [{"row":7,"column":"unit","code":"UNIT_FAMILY_MISMATCH","message":"..."}], max 500 stored
  commit_valid_only boolean NOT NULL DEFAULT false,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  committed_at timestamptz,
  CHECK (ok_rows + error_rows = total_rows),
  CHECK (status <> 'COMMITTED' OR (committed_at IS NOT NULL AND (error_rows = 0 OR commit_valid_only)))
);
CREATE UNIQUE INDEX ux_import_committed_file ON inventory_import_jobs(tenant_id, kind, file_sha256) WHERE status = 'COMMITTED';   -- re-uploading the same file cannot double-import
```

### 26.17 Build phase — Phase 5I *(replaces the old "Phase 5: inventory"; ≈ 6–7 weeks; after Phase 4 and the billing-extras stream; behind feature flag `inventory`)*
**Tasks:** V014 → units, items, levels and the ledger service (with the P1 check in CI) → costing engine ported from `ref/inventory.py` → recipes (versions, live cost) → consumption on bill paid (savepoint, retry) and reversal on void/credit note → vendors, PO, GRN with attachment, duplicate guard → payables and aging → wastage, adjustments (PIN threshold) → counts, transfers, production → reports and alerts → EOD `inventory` and e-mail block → CSV import → S27–S34 → permission rows and audit.
**Accept when:** IN1–IN22 and P1–P8 pass as Java tests; the 217 database cases pass; the no-divergence query returns zero rows after the E2E run; E2E 45–50 pass; a bill is never blocked by any inventory failure (fault-injection test).

---

## 27. ONLINE ORDER AGGREGATORS & PAYMENT AUTO-CONFIRMATION *(added in v1.3)*

> **Goal:** (A) orders from online food-ordering platforms arrive in Galla as ordinary orders, without re-typing, and status changes go back to the platform; (B) a UPI payment made against a gateway QR confirms itself, safely, without the cashier pressing "Payment received". Both depend on **third parties whose API details are not verified here**. This section therefore specifies Galla's side only: a provider-agnostic adapter, an idempotent inbox, a state machine, mapping, reconciliation and the failure rules. Nothing below describes any real provider's fields, headers, deadlines, fees or approval process; those come from the provider's own documentation after onboarding (Open Decisions 50 and 51).

### 27.0 Honest constraints
- **Access is not guaranteed.** Whether a given aggregator lets a small restaurant software vendor integrate directly, requires a partnership/approval, or only works through a middleware company is **not verified**. Two routes are designed for, behind one interface: **direct** partner API (`kind = AGGREGATOR`) and **middleware** (`kind = MIDDLEWARE`, a company that already holds the aggregator relationships). Which one is realistic is Open Decision 50. Phase 6 is **gated** on getting written access.
- **The manual path is the product until then.** Section 20.3 (staff type partner orders at the POS) stays and remains the fallback; 27.A.9 explains how the two coexist.
- **No provider is named in the schema, the code paths or the tests.** `integration_accounts.provider` is a lower-case adapter code (`^[a-z][a-z0-9_]{1,30}$`). Test doubles use the code `provx` / `fakegw`.
- **Galla does not interpret commission, fees, taxes collected by platforms, or payout rules.** It stores figures exactly as reported or typed and subtracts nothing on its own (27.A.8).

---

### 27.A  AGGREGATOR ORDERS

### 27.A.1 Rules in one place
1. **One inbox, idempotent.** Every provider order is stored first (`external_orders`, raw payload kept) and only then processed. Uniqueness is `(integration_account_id, external_order_id)`; a replayed webhook or a poll that returns the same order again is a **no-op returning 200**.
2. **Status changes are appended**, never edited: `external_status_events` is append-only (the database refuses UPDATE/DELETE). A provider's own event id, when it sends one, is unique per order, so a retried event is stored once.
3. **Unmapped items block auto-accept.** An order is auto-accepted only when **every** line is mapped (or explicitly `IGNORED`), the account has `auto_accept = true`, the store is open and the deadline has not passed. A line whose **variant** is unmapped is unmapped (no silent fallback to the base item).
4. **Galla's menu prices win.** The internal order/bill uses Galla's prices and tax profiles. The provider's total is stored as reported (`provider_order_total`) and any difference is shown as information, never applied.
5. **SLA deadline.** `accept_by = received_at + accept_sla_seconds` (default 180 s is a **placeholder**; the real window comes from the provider's documentation). Past it the order becomes `EXPIRED` (no accept is sent) and a Manager alert is raised.
6. **Cancel is never silent.** A provider cancel of an order already accepted cancels the internal order **by rule**, prints a "CANCELLED — do not prepare" slip on the kitchen printer, raises a Manager alert and writes an audit row. What to do with food already made is a human decision.
7. **Source = PARTNER.** An accepted order is an ordinary internal order with `order_source = 'PARTNER'`, `partner_name` = the account's display name, `external_ref` = the provider's order id (Section 20.3; V010 columns). It is billed, printed and reported like any partner order; it is **not** printed on the tax invoice as the source.
8. **Money is typed, not guessed.** `commission_percent`, `commission_amount`, `settlement_amount` are optional, entered by staff (or copied from the provider's payload as given) and never recalculated.
9. **Outbound calls go through jobs.** Accept, reject, preparing, ready, handover, cancel acknowledgement, menu push, availability push and store open/close are `integration_sync_jobs` rows executed by a worker with the outbox's retry rules (Section 10.1), `dedupe_key` such as `ext:<id>:ACCEPT`. A failed push never blocks the kitchen: the internal state changes, the job retries, a banner shows "Not yet confirmed with {provider}".
10. **Tenant isolation.** Every table carries `tenant_id`; webhook routes resolve the account from the URL token, never from the payload; cross-tenant access returns 404.

### 27.A.2 Adapter interface (provider-agnostic)
```java
public interface OrderChannelAdapter {
  String code();                                                  // "provx": matches integration_accounts.provider
  boolean supportsWebhook();  boolean supportsPolling();         // a provider may offer either or both
  VerifiedInbound verifyAndParse(String rawBody, Map<String,String> headers, AccountSecrets s);   // throws SignatureInvalid
  List<InboundOrder> pollNewOrders(AccountSecrets s, Instant since);                              // only if supportsPolling
  OutboundResult accept(AccountSecrets s, String externalOrderId, Integer prepMinutes);
  OutboundResult reject(AccountSecrets s, String externalOrderId, RejectReason reason);          // reason enum mapped by the adapter
  OutboundResult markPreparing(AccountSecrets s, String externalOrderId);
  OutboundResult markReady(AccountSecrets s, String externalOrderId);
  OutboundResult markHandedOver(AccountSecrets s, String externalOrderId);
  OutboundResult acknowledgeCancel(AccountSecrets s, String externalOrderId);
  OutboundResult pushMenu(AccountSecrets s, MenuSnapshot m);                  // optional capability
  OutboundResult pushAvailability(AccountSecrets s, List<ItemAvailability> a); // optional capability
  OutboundResult setStoreOpen(AccountSecrets s, boolean open);                 // optional capability
}
```
`InboundOrder` is Galla's normalised model: `externalOrderId`, `placedAt`, `lines[{externalItemId, externalVariantId, name, qty, unitPrice}]`, `customerName?`, `customerPhone?`, `deliveryAddress?`, `paymentMode (PREPAID|COD|UNKNOWN)`, `providerTotal?`, `note?`, `raw` (the original JSON). Each adapter declares which optional capabilities it has; missing ones are shown in the UI as "not available with this provider" instead of failing. **Everything that varies per provider (auth scheme, endpoints, event names, reject-reason codes, deadlines) lives inside the adapter and is learned from that provider's documentation.**

### 27.A.3 Status machine *(verified: `reference/external_order.py`, tests A1–A13, AP1–AP2)*
```
RECEIVED ─► NEEDS_MAPPING ─► MAPPED ─► ACCEPTED ─► PREPARING ─► READY ─► HANDED_OVER
   │            │               │  ▲         │          │         │
   │            │               │  └─(mapping deleted)  └─────────┴──► CANCELLED
   └────────────┴───────────────┴──► REJECTED | CANCELLED | EXPIRED          (terminal: REJECTED, HANDED_OVER, CANCELLED, EXPIRED)
```
Allowed edges: `RECEIVED→{NEEDS_MAPPING, MAPPED, REJECTED, CANCELLED, EXPIRED}`; `NEEDS_MAPPING→{MAPPED, REJECTED, CANCELLED, EXPIRED}`; `MAPPED→{ACCEPTED, REJECTED, CANCELLED, EXPIRED, NEEDS_MAPPING}`; `ACCEPTED→{PREPARING, READY, CANCELLED}`; `PREPARING→{READY, CANCELLED}`; `READY→{HANDED_OVER, CANCELLED}`. Any other move: `409 ILLEGAL_TRANSITION`. A request to move to the status the order already has is a no-op (not an error), which makes replays safe.

**Intake decision** (runs right after the order is stored): no lines, any unmapped line, or only `IGNORED` lines → `NEEDS_MAPPING`; deadline already passed → `EXPIRED`; `auto_accept` and store open → **auto-accept**; otherwise `MAPPED` (waits for a person).

**Auto-accept transaction:** one DB transaction creates the internal order (`PARTNER`), its lines from the mappings, marks `ACCEPTED` (`auto_accepted = true`, `accepted_by` NULL), writes the status event and enqueues the `ACCEPT` job and the KOT print. The database refuses `ACCEPTED` without `order_id` and `accepted_at`, refuses a second inbox row for the same internal order, and refuses an acceptance with neither a user nor the auto-accept flag.

**Reject:** needs a reason (non-blank, enforced by the database). Reasons offered in the UI: *Item out of stock, Too busy, Store closing, Cannot deliver there, Other (text)*. The adapter maps them to the provider's own list.

### 27.A.4 Item mapping ("Mapping needed")
- `external_item_mappings (integration_account_id, external_item_id, external_variant_id)` is unique; `external_variant_id = ''` means "no variant". Status `MAPPED` needs `menu_item_id` (and optionally `item_variant_id`); `IGNORED` (a non-food line such as a platform fee) needs neither.
- When a new order carries a line with no mapping, the line is added to the **Mapping needed** list (S37) with the provider's name and the first order that had it. Mapping it re-evaluates every open order of that account (`NEEDS_MAPPING → MAPPED`, or auto-accept).
- Deleting a mapping moves open `MAPPED` orders back to `NEEDS_MAPPING`. Orders already accepted are unaffected (the internal lines are copies).
- **Menu push is optional and one-directional** (Galla → provider) and only for adapters that declare the capability; the first version of Phase 6 relies on the owner keeping the provider's menu themselves and **mapping** it. Availability push (item out of stock → provider) uses `AVAILABILITY_PUSH` jobs, de-duplicated per item.

### 27.A.5 Kitchen and print flow
Accepted → the order is created and the **KOT prints** like any order (Section 8.3), with a header chip "PARTNER · {display_name} · #{externalOrderId}". `PREPARING` is set when the kitchen screen (S8) starts it; `READY` when marked ready; `HANDED_OVER` when the rider picks it up (a person presses it; Galla has no pick-up feed). Each triggers the matching outbound job if the adapter supports it. A sound/banner alerts on every `RECEIVED`, and on `accept_by − 60 s` (amber `WARN`) and expiry (red).

### 27.A.6 Store availability
Setting "store open" is per integration account: **Open / Paused / Closed** buttons on S35 enqueue `STORE_OPEN` / `STORE_CLOSE` jobs if the adapter supports them; otherwise the UI says "Set this in the provider's own app". While `store_open = false` nothing is auto-accepted. The flag is Galla's belief, not a verified provider state (it is refreshed only by acknowledged jobs).

### 27.A.7 Webhook endpoint (public, signature-verified)
`POST /webhooks/orders/{provider}/{accountToken}`: `accountToken` is a random 32-byte value per account (stored hashed) so the account is found without trusting the body. Steps: read the **raw body bytes** → size limit 256 KB → rate limit → `adapter.verifyAndParse` (constant-time signature compare over the raw bytes; invalid → `401`, nothing stored, counted) → insert inbox row with `ON CONFLICT DO NOTHING` → `200` (also for duplicates) → processing continues asynchronously. **Polling** (`POLL_ORDERS` job, interval from the adapter) feeds the same inbox, so webhook + poll overlap is harmless.

### 27.A.8 Reconciliation report (orders vs payouts)
Screen S37 tab "Reconciliation": pick account and period. *Expected* = Σ `settlement_amount` of `HANDED_OVER` orders in the period **that have one** (typed in the orders list or copied from the provider's payload); *Received* = Σ `partner_payouts.amount_received` entered by staff for the period; *Difference* = Received − Expected; plus the **count of handed-over orders without a settlement amount** (shown in red; they are not guessed). Per-order list with provider total, Galla bill total, commission as entered. *(verified: `reconcile()` in `reference/external_order.py`, test A12)*. CSV export kind `PARTNER_RECONCILIATION`. Galla draws **no conclusion** about why a difference exists.

### 27.A.9 Relationship to Section 20.3 (manual partner orders)
- The POS "Source = Partner" quick entry stays. With an active integration account for that partner, the partner name offered in the selector is the account's `display_name`; typing the provider's order id as `external_ref` for an order that is *also* in the inbox is blocked with the message "This order already came in automatically" (`409 EXTERNAL_ORDER_ALREADY_IMPORTED`) when `external_ref` matches an `external_orders` row of that account.
- **Fallback during an outage or a pending approval:** staff keep entering orders manually; the reconciliation report treats them as orders with no inbox row ("Manual partner orders" block, counted and totalled by `external_ref`), so nothing is lost when the integration is later connected.
- Section 20.3's sentence "Customer-facing ordering apps/websites are out of scope" is unchanged: Galla still has no ordering app; aggregators are the customer-facing side.

### 27.A.10 Security
- Credentials (`credentials_encrypted`, `webhook_secret_encrypted`) are AES-GCM encrypted with `INTEGRATION_ENCRYPTION_KEY`; **never returned by any API**, never logged; the UI shows "Connected / Replace credentials". Rotation re-encrypts on write.
- Raw payloads contain customer names, phones and addresses: purged by the retention job after `external_order_payload_retention_days` (default **90**, proposal; Section 28.D); the order and bill keep what Galla itself stored.
- Webhook failures are rate-limited per account token; 10 consecutive signature failures raise a Manager notification "possible misconfiguration or abuse".
- Provider 5xx or timeouts → job retry with back-off; permanent 4xx → job `FAILED`, banner, audit row. After 3 failed `ACCEPT` pushes before the deadline the UI says **"Accept in the provider's own app"**.
- Platform support (`SUPPORT`) sees account status and last error, never credentials.

### 27.A.11 API (tenant-scoped, `/api/v1`)
| Method | Path | Roles | Notes |
|---|---|---|---|
| GET | `/integrations` | O,M | accounts of the outlet (no secrets), status, last sync |
| POST | `/integrations` `{provider, kind, displayName, externalStoreId, credentials{…}, autoAccept?, acceptSlaSeconds?}` | O | 422 `VALIDATION_ERROR` for bad provider code; 409 for duplicate store |
| PATCH | `/integrations/{id}` (auto-accept, SLA, display name, status DISABLED/…) | O (auto-accept: O,M) | `If-Match` version; audit `INTEGRATION_CHANGED` |
| POST | `/integrations/{id}/credentials` | O | replace secrets; audit |
| POST | `/integrations/{id}/store` `{open: bool}` | O,M | enqueues job |
| POST | `/integrations/{id}/test` | O | adapter health check; result only |
| GET | `/external-orders?status=&accountId=&from=&to=` | O,M,C,K(read) | inbox list, SLA state |
| GET | `/external-orders/{id}` | O,M,C,K(read) | detail incl. mapped lines; raw payload only for O,M |
| POST | `/external-orders/{id}/accept` `{prepMinutes?}` | O,M,C | `409 ORDER_NOT_MAPPED` if lines unmapped; `409 ORDER_EXPIRED` |
| POST | `/external-orders/{id}/reject` `{reason, note?}` | O,M,C | reason required |
| POST | `/external-orders/{id}/status` `{status: PREPARING\|READY\|HANDED_OVER}` | O,M,C,K | state machine; idempotent |
| PATCH | `/external-orders/{id}/settlement` `{commissionPercent?, commissionAmount?, settlementAmount?}` | O,M | audit `PARTNER_SETTLEMENT_ENTERED` |
| GET / PUT / DELETE | `/integrations/{id}/mappings`, `/mappings/{mid}` | O,M | `409 MAPPING_EXISTS` on duplicate |
| GET | `/integrations/{id}/unmapped-items` | O,M | the "Mapping needed" list |
| POST | `/integrations/{id}/menu-push`, `/availability-push` | O,M | `409 CAPABILITY_NOT_SUPPORTED` |
| GET / POST | `/partner-payouts` | O,M | typed-in payouts |
| GET | `/reports/partner-reconciliation?accountId=&from=&to=` | O,M | JSON or CSV |
| POST | `/webhooks/orders/{provider}/{accountToken}` | public, signature | 200 also for duplicates |

New error codes (Appendix B): `ORDER_NOT_MAPPED` (409), `ORDER_EXPIRED` (409), `MAPPING_EXISTS` (409), `CAPABILITY_NOT_SUPPORTED` (409), `EXTERNAL_ORDER_ALREADY_IMPORTED` (409), `INTEGRATION_NOT_CONNECTED` (409), `WEBHOOK_SIGNATURE_INVALID` (401, public route only).

### 27.A.12 UI specification
**S35 Settings → Online ordering (O,M).** List of accounts: provider, display name, store id, status chip (Pending / Connected / Error / Disabled), "last order received 12:41", **Open / Paused / Closed** control, auto-accept toggle with text "Orders are accepted automatically only when every item is mapped", SLA field with helper "Use the provider's own limit". *Empty:* "No online ordering connected. Until then, enter partner orders by hand (Order → Source → Partner)." *Error:* a red banner with `last_error` and "Replace credentials". *Not in plan:* `402 FEATURE_NOT_IN_PLAN` → upgrade message.
**S36 Online orders (O,M,C; K read-only).** Live list (SSE `external_order.*`): cards with provider chip, order id, items, total, payment mode (PREPAID/COD/UNKNOWN), **countdown to accept_by** (green > 60 s, amber ≤ 60 s, red expired). Buttons **Accept** (prep minutes), **Reject** (reason picker). Orders in `NEEDS_MAPPING` show "Map 2 items to continue" linking to S37 and cannot be accepted. After accept: PREPARING / READY / HANDED OVER buttons. Cancelled-by-provider cards show a red "Customer/provider cancelled" strip and the kitchen slip status. Sound toggle. *Empty:* "No online orders yet. New orders appear here the moment they arrive." *Offline browser:* banner "Reconnecting — orders are still received by the server".
**S37 Mapping needed & reconciliation (O,M).** Tab 1 *Mapping needed*: table of provider items (name, variant, seen in N orders) with a menu-item picker (+ variant), **Ignore (not food)** and **Create item**. Tab 2 *Mapped items*: search, edit, delete (with the warning "Open orders will return to Mapping needed"). Tab 3 *Reconciliation*: 27.A.8, payout entry form, difference highlight, export.
All three screens use the shared empty/error/skeleton components (Section 22.4); no blank state.

### 27.A.13 Tests (prefix IG)
- **IG-A1…A13, AP1–AP2** — `reference/external_order.py` (status machine; mapping with variant strictness; auto-accept blocked by unmapped lines, closed store or passed deadline; SLA states; idempotent receive/event; cancel effects; reconciliation without interpretation; price difference informational; property tests: terminal states are sticky, replayed keys are stored once).
- **IG-DB-A** — 58 constraint cases of V015 section A (accounts, mappings, inbox, events, jobs, partner payouts) (inbox uniqueness, mapping uniqueness, accepted-needs-order, reject-needs-reason, append-only events, job rules).
- **IG-API-1…12** — each endpoint: role matrix, cross-tenant 404, secrets never in any response, signature invalid → 401 with no row, duplicate webhook → 200 with one row, accept on unmapped → 409.
- **IG-WK-1** — fake adapter (`provx`) contract test suite that every real adapter must pass: duplicate delivery, out-of-order events, timeout, 5xx, cancel after accept.
- **IG-UI-1…6** — S35/S36/S37 states (empty, error, countdown colours, mapping flow).

### 27.A.14 E2E scenarios (extend Section 14.2; 51–55 cover both 27.A and 27.B)
51. **Auto-accept happy path (A):** fake provider posts a signed order with two mapped items → inbox row, internal PARTNER order, KOT printed, `ACCEPT` job sent, status events recorded; the same webhook posted twice creates nothing new.
52. **Unmapped item (A):** order with one unknown item → `NEEDS_MAPPING`, no auto-accept; staff map it on S37 → order becomes `MAPPED` and (auto-accept on) accepted; an unmapped *variant* needs its own mapping.
53. **SLA expiry, reject, provider cancel (A):** order not accepted before `accept_by` → `EXPIRED`, Manager alert, no accept call made; another order rejected with a reason → `REJECTED`, `REJECT` job queued, a reject without a reason is refused; provider cancel after accept → internal order cancelled by rule, kitchen "CANCELLED" slip, Manager alert, `ACK_CANCEL` job; a cancel for an already `HANDED_OVER` order is ignored and logged.
54. **Gateway auto-confirmation (B):** (a) exact in-time webhook confirms the payment, bill `PAID`, dialog closes by SSE; (b) the same webhook twice → one payment; (c) cashier presses "Payment received" while a gateway QR is live → the later webhook is flagged `DUPLICATE_PAYMENT` and the bill is unchanged; (d) success after expiry → `LATE_SUCCESS` on S38; wrong amount → `AMOUNT_MISMATCH`; Manager resolves each with a note.
55. **Reconciliation (A+B):** three handed-over partner orders (two with settlement amounts) and one typed payout → report shows expected, received, difference and "1 order without a settlement amount"; a manual partner order with the same `external_ref` as an inbox order is refused; a provider settlement CSV is imported (matched / amount-diff / unmatched lines), the same file again is refused.

---

### 27.B  PAYMENT GATEWAY, MODE B — AUTO-CONFIRMATION

> This replaces and extends Section 9.3. Section 9.1's `UpiPaymentProvider` stays the plug-in point; this section defines the **intent** around it, the event resolver and the duplicate-payment guard. Which gateway (if any) is used is **not decided** (Open Decision 51, which replaces old Decision 2). Provider fields, signature schemes, QR formats, expiry rules and fees are **not verified** and live inside each provider adapter.

### 27.B.1 Rules
1. **Amount locked.** A `payment_intents` row is created for exactly the **remaining balance of a `GENERATED` bill** (Section 9.4). `amount > 0`, never edited. A different amount needs a new intent (and the old one is closed).
2. **One live intent per bill.** The database refuses a second `CREATED`/`PENDING` intent for the same bill (partial unique index). Creating a new QR while one is live first expires the old one.
3. **Provider events are facts, stored first.** Every webhook is stored in `payment_webhook_events` (existing V004 table, extended in V015) with unique `(provider, event_id)` **before** anything else happens; the signature is verified **before** storing; a duplicate returns 200 without processing. The row is immutable except `processed_at`, `outcome`, `intent_id`, `tenant_id` (database trigger); deletion only by the retention job after ≥ 1 day.
4. **The intent's state is derived, not hand-edited.** It is a pure function of the set of distinct provider events plus the intent's expiry, so **arrival order and duplicate delivery cannot change it** *(verified by property test PP1)*.
5. **Auto-confirmation applies money exactly once**, only for an **exact-amount SUCCESS event whose provider time is ≤ `expires_at`**, only when the bill is still `GENERATED` with `remaining ≥ amount`. Then, in one transaction (row lock on the bill, Section 5.9): the intent's pending `payments` row becomes `SUCCESS` (`confirmation = PROVIDER`), the standard bill-paid logic runs, SSE `bill.paid` is sent.
6. **Everything else goes to "needs attention", never silently fixed:** `AMOUNT_MISMATCH`, `LATE_SUCCESS`, `DUPLICATE_PAYMENT`, `BILL_NOT_PAYABLE` (S38). The bill is **not** touched; a Manager resolves it.
7. **Refunds are manual in v1.** Galla never calls a refund API. Resolution screens say "Refund through the provider's dashboard, then mark as resolved".
8. **Settlements are reconciled by import** (27.B.7). Galla does not read the restaurant's bank account.

### 27.B.2 Flow *(extends 9.3)*
1. Cashier opens the Bill dialog → UPI → **Gateway QR** (only if the outlet has an active gateway provider and the plan allows). `POST /bills/{id}/payment-intents` → server checks the bill is `GENERATED`, computes `remaining`, creates the intent (`CREATED`) and a `PENDING` payment (`confirmation = PROVIDER`, `payment_id` stored), calls `provider.createQr`, stores `provider_ref`, `qr_payload`, `expires_at`; intent → `PENDING`.
2. Dialog shows the QR, the locked amount, the countdown and the text **"This confirms automatically. You can also press Payment received if the customer shows a success screen."** Dialog subscribes to `bill.paid` SSE and polls `GET /bills/{id}` every 3 s.
3. Provider calls `POST /webhooks/payments/{provider}` (signature verified over the raw bytes; secret from encrypted settings/env, constant-time compare) → event stored → resolver (27.B.3) → state/attention written → payment/bill updated when 27.B.1(5) holds.
4. A scheduled job (every minute) writes an internal `EXPIRE_TICK` for intents past `expires_at` and re-runs the resolver; the `PENDING` payment row becomes `EXPIRED` as in 5.9.

### 27.B.3 Resolver *(verified: `reference/payment_intent.py`, tests P1–P19, PP1–PP3)*
Inputs: the intent (`amount`, `expires_at`, whether the QR was acknowledged), the **distinct** events (`event_id`, `kind` SUCCESS | FAILED | OTHER | EXPIRE_TICK, `amount`, provider `occurred_at`), the bill context (`status`, `remaining`).
- **In time** means `occurred_at ≤ expires_at` (exactly at expiry counts as in time; test P7). An event with no provider time is **not** in time (it can only be late/flagged).
- **Exact** means `amount == intent.amount` compared as `NUMERIC`/`BigDecimal.compareTo`, never as a float (P14).
- Chosen success = the earliest exact in-time SUCCESS (ties by `event_id`).

| Situation | Intent status | Attention | Bill/payment |
|---|---|---|---|
| exact in-time SUCCESS, bill `GENERATED`, `remaining ≥ amount` | `SUCCESS` (`received_amount = amount`, `success_at`) | none | **applied once** (P1, P2 duplicate delivery no-op) |
| same, but bill already `PAID` (cashier confirmed manually first) | `SUCCESS` (money really arrived) | `DUPLICATE_PAYMENT` | **not applied**; refund needed (P10) |
| same, bill `VOID` | `SUCCESS` | `BILL_NOT_PAYABLE` | not applied (P11) |
| same, bill `remaining < amount` (partly paid otherwise) | `SUCCESS` | `DUPLICATE_PAYMENT` | not applied (P12) |
| two different exact in-time SUCCESS events (customer paid twice) | `SUCCESS` | `DUPLICATE_PAYMENT` | applied once; the extra is flagged (P3) |
| SUCCESS with a different amount | unchanged (`PENDING`/`EXPIRED`…) | `AMOUNT_MISMATCH`; `received_amount` = the reported amount | **not applied** (P4) |
| exact SUCCESS **after** expiry | `EXPIRED` | `LATE_SUCCESS` | **not applied** (P5): the cashier may have started a new QR or taken cash |
| in-time success whose event arrives after the expiry tick | `SUCCESS` | none | applied (P6: provider time decides, not our arrival time) |
| FAILED only | `FAILED` | none | none (P9); FAILED then in-time SUCCESS → `SUCCESS` (P8) |
| no events | `CREATED` / `PENDING` (QR acknowledged) / `EXPIRED` after tick | none | none (P13) |

State edges: `CREATED→{PENDING,SUCCESS,FAILED,EXPIRED}`, `PENDING→{SUCCESS,FAILED,EXPIRED}`, `FAILED→SUCCESS` (retry on the same QR before expiry — a design rule, provider behaviour not verified), `EXPIRED→SUCCESS` (only an in-time payment whose event arrived late), `SUCCESS` terminal. Attention priority: `DUPLICATE_PAYMENT > BILL_NOT_PAYABLE > AMOUNT_MISMATCH > LATE_SUCCESS`. Database guards: a `SUCCESS` intent must have `success_at` and `received_amount = amount`; an attention can be resolved only if raised and only with the resolving user.
**Property tests:** PP1 any permutation and duplication of the same events gives the same final state/attention/outcomes; PP2 money is applied at most once and only for an exact amount; PP3 adding events never moves a `SUCCESS` intent out of `SUCCESS`.
*Honest limit:* the bill context (paid manually first vs provider first) is a real race; the resolver is deterministic **given** the bill state at the moment the money is applied, and the row lock on the bill (5.9) decides who is first. Whichever is second is flagged — never both applied.

### 27.B.4 Manual confirmation and the duplicate-payment guard (consistent with 5.9) *(P17)*
- Pressing **Payment received** on a bill with a live intent first **expires the intent** (superseded) in the same transaction, then records the manual payment. If the provider's success then arrives it resolves to `DUPLICATE_PAYMENT` / `LATE_SUCCESS` — flagged on S38, not applied.
- A manual payment larger than `remaining`, or on a non-`GENERATED` bill, is refused (`409 BILL_NOT_PAYABLE` / `422 OVERPAYMENT`).
- Creating a gateway QR for a bill that already has a manual `PENDING` UPI payment is refused until that payment is confirmed or cancelled.

### 27.B.5 Webhook endpoint
`POST /webhooks/payments/{provider}` (public): body limit 256 KB, per-IP and per-provider rate limit; verify signature (helper `verify_hmac_sha256_hex` shows the generic pattern — HMAC-SHA256 over the **raw** bytes, constant-time compare; each real provider defines its own scheme, **not verified**); insert event with `ON CONFLICT (provider, event_id) DO NOTHING`; if no row inserted → 200; unknown intent → store with outcome `UNKNOWN_INTENT`, 200, alert; always respond quickly and resolve asynchronously when the provider requires fast acknowledgement (provider-specific). Invalid signature → 401, counted, nothing stored.

### 27.B.6 Needs-attention handling (S38)
Each flagged intent shows bill number, amount, reported amount, time, reason in plain words, and actions (Manager/Owner): **Mark resolved** (required note: "refunded in provider dashboard" / "accepted as is" / …; stores `attention_resolved_by/at`), **Apply to bill** (only `LATE_SUCCESS`/`AMOUNT_MISMATCH` on a still-`GENERATED` bill with matching remaining: records a manual `UPI` payment with a note referencing the provider event; audit `PAYMENT_ATTENTION_APPLIED`). A dashboard badge shows the unresolved count; EOD e-mail lists unresolved items (Section 10.3 amendment).

### 27.B.7 Settlements and reconciliation
- Owner uploads the provider's settlement CSV (S38 tab "Settlements"). The CSV layout is provider-specific, so each adapter ships a **column mapping** (transaction id, amount, settlement ref/date, fee) — **not verified for any real provider**; the generic importer accepts our own canonical CSV `provider_txn_id,amount` + header fields `settlement_ref,settlement_date,gross,fee,net`.
- Import creates `provider_settlements` (unique `(tenant, provider, settlement_ref)`: the same file twice is refused) and `provider_settlement_lines` (unique per settlement and transaction id). Each line is **MATCHED** to an intent when the transaction id equals a `provider_ref`/event txn id, the amount is equal and the intent is `SUCCESS`; **AMOUNT_DIFF** when found but different; **UNMATCHED** otherwise *(P19)*. `net = gross − fee` is checked at import (the database enforces it). Fees are one reported figure; Galla does not interpret components or taxes.
- Reverse check: **SUCCESS intents with no settlement line** older than N days (default 7, configurable) are listed as "Not yet settled". Export kind `SETTLEMENT_RECONCILIATION`.

### 27.B.8 Security
Provider secrets: encrypted at rest (`PAYMENT_PROVIDER_ENCRYPTION_KEY`), never returned; QR payloads are not secrets but are not logged in full; amounts in logs are fine, secrets are not. Every automatic payment writes an audit row (`PAYMENT_AUTO_CONFIRMED`, event id, intent id). Replay protection is the unique event id **plus** the intent's one-time `SUCCESS` guard. Time skew: the provider's `occurred_at` is trusted only for judging "in time"; events further in the future than 5 minutes are treated as untimed (flagged).

### 27.B.9 API
| Method | Path | Roles | Notes |
|---|---|---|---|
| POST | `/bills/{id}/payment-intents` | O,M,C | creates intent + QR; `409 BILL_NOT_PAYABLE`; `409 INTENT_ALREADY_LIVE` returns the live one |
| GET | `/payment-intents/{id}` | O,M,C | status, attention, countdown |
| POST | `/payment-intents/{id}/cancel` | O,M,C | expires a live intent |
| GET | `/payment-intents?attention=open&outlet=` | O,M | S38 list |
| POST | `/payment-intents/{id}/resolve` `{note, action: RESOLVED\|APPLY}` 🔑 | O,M | audit |
| POST | `/webhooks/payments/{provider}` | public, signature | 200 for duplicates |
| POST | `/settlements/import` (multipart CSV, `provider`) | O | `409 SETTLEMENT_ALREADY_IMPORTED` |
| GET | `/settlements`, `/settlements/{id}` | O,M | lines with match status |
| GET | `/reports/settlement-reconciliation?from=&to=` | O,M | JSON/CSV |
| GET/PUT | `/outlets/{id}/gateway-settings` (provider code, credentials, intent expiry minutes) | O | secrets write-only |

New error codes: `INTENT_ALREADY_LIVE` (409), `SETTLEMENT_ALREADY_IMPORTED` (409), `GATEWAY_NOT_CONFIGURED` (409).

### 27.B.10 UI
**Bill dialog (S4) UPI tab:** segmented control *Own QR (manual)* | *Gateway QR (automatic)*. Gateway: QR, locked amount, countdown, status line "Waiting for payment… → Payment received ✔ (automatic)"; on expiry "QR expired — create a new one"; on attention "Payment arrived but needs a manager" (does not close the bill). **S38 Payments needing attention & settlements (O,M):** two tabs; *Empty:* "Nothing needs attention." *Error:* retry panel. Never blank.

### 27.B.11 Tests (prefix IG)
IG-P1…P19, PP1–PP3 (resolver, 22 tests, `reference/payment_intent.py`); IG-DB-B (46 cases: one live intent per bill, amount > 0, SUCCESS needs exact amount, provider-ref uniqueness, event uniqueness, event immutability, settlement uniqueness, `net = gross − fee`); IG-API-13…22 (webhook duplicate → one payment, signature invalid, concurrent manual vs provider confirm on one bill → one applied + one flagged, amount mismatch, late success); IG-UI-7…9.

### 27.B.12 E2E scenarios
E2E 54 and 55 (listed in 27.A.14) are the gateway scenarios; they are also run against the fake provider `fakegw`.

### 27.C Phases
- **Phase 4 (amendment):** adds **27.B** (gateway Mode B) — only after a provider is chosen (Open Decision 51). Section 9.3 is replaced by 27.B. Without a provider, Mode A stays and nothing in 27.B is active. Acceptance: resolver tests, DB cases, webhook idempotency, E2E 54–55 pass against a fake provider.
- **Phase 6 — Aggregator integration (new; ≈ 3–4 weeks per adapter; GATED on written partner/middleware access):** 27.A framework + the `provx` fake adapter and contract suite first (can be built without access), then one real adapter after onboarding. Acceptance: IG-A/DB/API/WK tests, E2E 51–55 against the fake, then a supervised pilot on one outlet with the real adapter. If access is never granted, the framework still ships and the manual path (20.3) remains.

### 27.D What is verified and what is not
**Verified:** status machine, intake decision, SLA, idempotent inbox model, reconciliation arithmetic (`reference/external_order.py`, 15 tests); resolver and duplicate-payment guard incl. property tests (`reference/payment_intent.py`, 22 tests); V015 A/B tables on PostgreSQL 16 (see Section 28 for the full migration and case count).
**Not verified:** any aggregator's API, approval, deadlines, reject reasons, menu-push format or fees; any gateway's signature scheme, QR/expiry rules, fees, settlement file layout or refund API; whether webhook-only or polling is available per provider; real-world latency.

---

## 28. COMPLIANCE, REGISTERS, EXPORTS, LANGUAGES & DATA MANAGEMENT *(added in v1.3)*

> **Goal:** give the restaurant's accountant and the owner what they need from Galla — legal fields on the bill, registers that add up exactly to the bills, files to import into accounting software, bills and screens in Hindi, and the owner's control over their data — **without Galla asserting any Indian tax, food-safety or privacy rule.** Every legal requirement below is either a **configurable field** or an item on the **CA checklist (28.A.6)**. Where this section states an external fact it names the official source it was read from; everything else is marked *not verified*. Galla is not a tax adviser.

### 28.0 What is verified, what is not (read first)
| Topic | Status |
|---|---|
| Register arithmetic: per bill `taxable + tax + round-off = grand total`; every register sums to the sales register; void bills excluded (`reference/registers.py`, tests R1–R6 incl. random bills made with `bill_calculator.py`); the register SQL ran on PostgreSQL 16 against a fixture with a VOID bill and the reconciliation query returned zero rows | **verified** (arithmetic and SQL only — not the legal adequacy of any register) |
| V015 constraints (193 accept/reject cases on PostgreSQL 16 on top of V001–V011) | **verified** |
| Tally voucher XML builds, balances to zero, escapes special characters, refuses to guess a missing ledger (`reference/tally_export.py`, T1–T4, TP1) | **verified as Python**; **NOT verified against a real Tally installation** |
| Indian digit grouping `1,00,000.00` (I1, IP1 round-trip property) | **verified** |
| FSSAI: the order of 8 June 2021, deferred by an order of 30 Sept 2021 to **1 Jan 2022**, requires the **14-digit** licence/registration number on cash receipts, invoices, cash memos and bills (read from FSSAI's order PDF, <https://mail.fssai.gov.in/upload/advisories/2021/10/6156936ac80bbOrder_License_Number_Print_01_10_2021.pdf>, 2026-11-26). Whether it applies to a given outlet, and exact placement, is for the owner/CA | **read from the official order; applicability to a given business not verified** |
| Tally XML structure (`ENVELOPE/HEADER/BODY`, `TALLYREQUEST Import`, `VOUCHER … ACTION="Create"`, `LEDGERENTRIES.LIST`, `ISDEEMEDPOSITIVE`, YYYYMMDD dates; debit and credit must match) | read from Tally's published sample page <https://help.tallysolutions.com/sample-xml/> (2026-11-26; its basic-voucher example does not balance, so only the structure was relied on); **import not tested** |
| DPDP Rules, 2025: notified **14 Nov 2025** with an **18-month phased compliance period** (PIB document <https://static.pib.gov.in/WriteReadData/specificdocs/documents/2025/nov/doc20251117695301.pdf>, 2026-11-26) | **notification date and the existence of a phased period read; which duty starts when, and what any duty requires of a restaurant, is NOT verified** |
| GSTIN checksum, GSTIN existence, HSN digit requirements, e-invoice thresholds, composition rules, what a "tax invoice" must contain, credit-note rules, retention periods, complimentary/packaging GST treatment | **not verified — CA checklist 28.A.6** |
| Devanagari rendering on a thermal printer (raster path, golden images) | designed; **not tested on any printer** |
| RPO/RTO numbers, retention defaults, deadlines for data requests | **proposals / configurable, not legal advice** |

---

### 28.A  COMPLIANCE FIELDS (structure only)

### 28.A.1 Legal profile of an outlet (Settings → Legal & invoice; O)
| Field | Rule in Galla | Not asserted |
|---|---|---|
| Legal name (`outlets.legal_name`) | free text, printed on the bill header when set | whether it must differ from the trade name |
| GSTIN (`outlets.gstin`) | text; **format check only** `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$`, upper case; if `state_code` is set its value must equal the first two digits; if `pan` is set it must equal characters 3–12 | checksum, whether it exists or is active (**not verified**); the UI says "Format checked only" |
| State code (`state_code`, 2 digits) | seller state for place-of-supply configuration | the code list |
| PAN (optional) | `^[A-Z]{5}[0-9]{4}[A-Z]$` | |
| Registration type | `REGULAR` / `COMPOSITION` / `UNREGISTERED` — a **label that selects the default document title** (below) and nothing else | what each type may or must charge/print |
| FSSAI licence no. | **14 digits**, digits only (`^[0-9]{14}$`), printed on bills when set (source: FSSAI order, see 28.0) | applicability to the outlet |
| Document title | `TAX_INVOICE` / `BILL_OF_SUPPLY` / `INVOICE` / `BILL` (printed at the top of the bill); default `BILL` | which title the law requires for which outlet — owner/CA chooses |
| Print HSN/SAC | boolean; prints the item's code per line when set | digits required |
| Place-of-supply mode | `OUTLET_STATE` (always the seller's state) or `DESTINATION_STATE` (the delivery address's state, for delivery orders) | when either is correct |
| Bill language | see 28.C | |

### 28.A.2 Item and customer fields
`menu_items.hsn_sac_code` (existing column) is now format-checked: **2–8 digits**; how many digits a business must use is a CA question. `bill_lines.hsn_sac_code` snapshots the code at billing so a later menu edit never rewrites an old bill. `customers` gain `legal_name` and `gstin` (same format check) for "bill to a company"; Section 5 billing is unchanged (no B2B invoice workflow is added).

### 28.A.3 Place of supply and tax profiles — configuration only
`tax_profile_pairs (intra_profile_id → inter_profile_id)` lets the Owner/CA say **"for a delivery to another state use profile Y instead of profile X"** (e.g. a CGST+SGST profile paired with an IGST profile the restaurant created itself). At billing: if the outlet's `place_of_supply_mode = DESTINATION_STATE`, the order is a delivery with a known destination state, and that state ≠ the outlet's `state_code`, Galla substitutes the paired profile for lines that use the intra profile; `bills.place_of_supply_state_code` records the state used. **Galla ships no pairs and no rates**, never decides what is intra- or inter-state beyond comparing two 2-digit codes the owner entered, and does not assert that an IGST profile is right for any sale. Without a pair, nothing changes. The calculation itself (Section 5.3) is untouched: only *which profile* is applied differs.

### 28.A.4 Bill snapshot (what was actually printed)
At generation the server copies into `bills`: `document_title`, `seller_legal_name`, `seller_gstin`, `seller_state_code`, `seller_fssai_licence_no`, `place_of_supply_state_code`, `buyer_legal_name`, `buyer_gstin` (when the customer has one and the cashier chose "bill to company"), `bill_language`. Editing the outlet later never changes an issued bill; reprints use the snapshot. Bills generated before V015 have NULLs and reprint as before (header from the outlet as it was; the UI shows no legal block).

### 28.A.5 Bill header/footer (amends Section 8.2)
Header block, each line only when the field is set: **document title** · trade/legal name · address · **GSTIN** · **FSSAI Lic. No.** · phone. Per-line HSN when `print_hsn`. Footer: free text (existing) and, when an `INVOICE`/`TAX_INVOICE` title is chosen, nothing else is added automatically — **mandatory-content rules are not asserted**; the owner's CA decides the fields and the title. A bill printed without a field the CA later requires is a configuration gap, not a Galla bug; the checklist exists to close that gap before go-live.

### 28.A.6 Checklist — "Compliance to verify with a CA / lawyer before launch" (none of these is asserted by Galla)
1. Which document title applies to this outlet (tax invoice, bill of supply, plain bill) and the **mandatory fields** of each.
2. **E-invoicing** — whether this business is above any threshold and must use it (Galla issues no e-invoice and has no IRN/QR integration).
3. **Composition scheme** — what a composition outlet may print or charge; whether the label alone is enough.
4. **HSN/SAC** — digits required for this turnover; the right code per item; whether it must be printed.
5. **FSSAI** — the number format is read from the official order (28.0); confirm display on bills, menus and premises, and for each outlet/licence.
6. **GSTIN** — checksum validation (Galla validates format only), place-of-supply rules for delivery and aggregator orders, IGST vs CGST+SGST for a given sale.
7. **Complimentary items, discounts, packaging and delivery charges, service charge, tips** — GST treatment and how they must appear on a bill (Section 5.3 computes what the owner configures).
8. **Credit notes / returns** — when needed and in what form (Stream B stores them; the register lists them).
9. **Aggregator sales** — who collects and reports tax on platform orders, and how platform fees/commission are treated (Galla stores figures as reported, 27.A).
10. **Retention** of bills, registers, audit logs and purchase records (Galla defaults in 28.D are proposals).
11. **Consent and privacy** wording for phone numbers, WhatsApp, data requests (28.D.2; DPDP duties not verified).
12. **Galla's own subscription invoices** — tax, label, format (Open Decision 53).

---

### 28.B  REGISTERS AND ACCOUNTING EXPORTS

### 28.B.1 Principles
- All registers are **computed by SQL from stored bill rows** (never from the browser, never by an LLM), for one outlet and a **business-date range**, in the outlet's currency, with the same rounding already stored on the bills (the registers **re-add** stored figures; they do not recalculate tax).
- **VOID bills are excluded.** `GENERATED` (unpaid) and `PAID` bills are included; the `status` column says which.
- **Reconciliation gate (R6):** before any register file is produced the server runs `Σ taxable + tax_total + round_off = grand_total` per bill; any mismatching bill aborts the export with `409 REGISTER_NOT_RECONCILED` and the bill numbers listed. The gate has never failed on bills produced by `BillCalculator`; it exists for data fixed by hand.
- Files are generated by a background job (`export_jobs`), stored in object storage, downloadable by a time-limited link (`export_file_retention_days`, default 7), with a SHA-256 and row count recorded.
- Money columns are plain decimals with two places and a `.`; **no thousands separators and no currency symbols in files** (screens show `1,00,000.00`, files stay machine-readable). Dates are `YYYY-MM-DD`. CSV: UTF-8 **with BOM** (so Excel shows Devanagari correctly), `,` separator, `"`-quoting, header row, `\r\n`. XLSX has the same columns, money as numbers with the cell format `0.00`.

### 28.B.2 Register column lists (stable; a column is only ever appended, never renamed)
| Register (kind) | Columns, in this order |
|---|---|
| **Sales register** (`SALES_REGISTER`) one row per bill | `business_date, bill_number, document_title, status, customer_name, buyer_gstin, place_of_supply_state_code, gross_items, discount_total, taxable_value, tax_total, round_off, grand_total` |
| **Sales by tax rate** (second sheet / `SALES_REGISTER` with `layout=by_rate`) | `bill_number, rate_percent, taxable_value, tax_amount, line_total` |
| **HSN summary** (`HSN_SUMMARY`) | `hsn_sac_code, rate_percent, quantity, taxable_value, tax_amount, line_total, lines_without_hsn_flag` |
| **Tax summary** (`TAX_SUMMARY`) | `component_name, rate_percent, taxable_value, tax_amount` |
| **Payment-mode summary** (`PAYMENT_MODE_SUMMARY`) | `method, payments, amount` |
| **Credit-note register** (`CREDIT_NOTE_REGISTER`) — from Stream B | `business_date, credit_note_number, original_bill_number, reason, taxable_value, tax_total, round_off, total` (**soft reference**: the tables are Stream B's; the query is added when B's migration exists, FK work in V016) |
| **Purchase register** (`PURCHASE_REGISTER`) — from Stream C | `business_date, purchase_number, supplier_name, supplier_gstin, taxable_value, tax_total, total, paid_status` (**soft reference** to Stream C's tables) |
| Notes | "rate_percent" of a line = the **sum of its component rates** (CGST 2.5 + SGST 2.5 = 5.00). Service charge, delivery and packaging lines appear as lines like any other; lines with no HSN appear under an empty code and set `lines_without_hsn_flag` — **never dropped** |

### 28.B.3 The SQL *(verified on PostgreSQL 16 against a fixture: two live bills, one VOID bill; reconciliation query returned no rows)*
Parameters (psql variables here, bound parameters in code): `:outlet_id`, `:d_from`, `:d_to`.
```sql
-- Register queries (Section 28.B). Parameters: :outlet_id (uuid), :d_from, :d_to (business dates, inclusive). VOID bills are excluded everywhere.
-- R1 sales register, one row per bill
SELECT o.business_date, b.bill_number, coalesce(b.document_title,'BILL') AS document_title, b.status, b.customer_name, b.buyer_gstin, b.place_of_supply_state_code,
       coalesce(sum(l.line_gross) FILTER (WHERE l.line_type='ITEM'),0.00) AS gross_items, b.discount_total,
       coalesce(sum(l.taxable_amount),0.00) AS taxable_value, b.tax_total, b.round_off, b.grand_total
FROM bills b JOIN orders o ON o.id=b.order_id LEFT JOIN bill_lines l ON l.bill_id=b.id AND l.active
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY o.business_date, b.id ORDER BY o.business_date, b.bill_number;
-- R2 sales by tax rate, per bill (a bill's rate = sum of its component rates on the line; CGST 2.5 + SGST 2.5 = 5.00)
SELECT b.bill_number, lr.rate_percent, sum(lr.taxable_amount) AS taxable_value, sum(lr.tax_amount) AS tax_amount, sum(lr.line_total) AS line_total
FROM bills b JOIN orders o ON o.id=b.order_id
JOIN (SELECT l.bill_id, l.id, l.taxable_amount, l.tax_amount, l.line_total,
             coalesce((SELECT sum(t.rate_percent) FROM bill_line_taxes t WHERE t.bill_line_id=l.id),0.00) AS rate_percent
      FROM bill_lines l WHERE l.active) lr ON lr.bill_id=b.id
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY b.bill_number, lr.rate_percent ORDER BY b.bill_number, lr.rate_percent;
-- R3 HSN summary (lines without a code are grouped under '' and flagged, never dropped)
SELECT coalesce(l.hsn_sac_code,'') AS hsn_sac_code, lr.rate_percent, sum(CASE WHEN l.line_type='ITEM' THEN l.quantity ELSE 0 END) AS quantity,
       sum(l.taxable_amount) AS taxable_value, sum(l.tax_amount) AS tax_amount, sum(l.line_total) AS line_total,
       bool_or(l.hsn_sac_code IS NULL) AS lines_without_hsn_flag
FROM bills b JOIN orders o ON o.id=b.order_id JOIN bill_lines l ON l.bill_id=b.id AND l.active
CROSS JOIN LATERAL (SELECT coalesce(sum(t.rate_percent),0.00) AS rate_percent FROM bill_line_taxes t WHERE t.bill_line_id=l.id) lr
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY coalesce(l.hsn_sac_code,''), lr.rate_percent ORDER BY 1,2;
-- R4 tax summary by component
SELECT t.component_name, t.rate_percent, sum(t.taxable_amount) AS taxable_value, sum(t.tax_amount) AS tax_amount
FROM bills b JOIN orders o ON o.id=b.order_id JOIN bill_lines l ON l.bill_id=b.id AND l.active JOIN bill_line_taxes t ON t.bill_line_id=l.id
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY t.component_name, t.rate_percent ORDER BY 1,2;
-- R5 payment-mode summary (SUCCESS payments of live bills; the method of a bill that is only partly paid still counts what was received)
SELECT p.method, count(*) AS payments, sum(p.amount) AS amount
FROM payments p JOIN bills b ON b.id=p.bill_id JOIN orders o ON o.id=b.order_id
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND p.status='SUCCESS' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY p.method ORDER BY p.method;
-- R6 reconciliation check (must return zero rows; the export refuses to produce a file otherwise and raises REGISTER_NOT_RECONCILED)
SELECT b.bill_number, b.grand_total, (sum(l.taxable_amount) + b.tax_total + b.round_off) AS recomputed
FROM bills b JOIN orders o ON o.id=b.order_id JOIN bill_lines l ON l.bill_id=b.id AND l.active
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY b.id HAVING sum(l.taxable_amount) + b.tax_total + b.round_off <> b.grand_total;
```
Credit-note and purchase registers follow the same pattern over the other streams' tables once they exist. The register total equality is also asserted in Python: `reconcile()` in `reference/registers.py` returns nine differences that must all be exactly `0.00` — per-bill identity, sales register vs bills, by-rate taxable/tax/total, HSN taxable/tax, tax summary, payment modes vs paid bills *(R1 over random bills, 6 tests)*.

### 28.B.4 Generic accounting CSVs (stable columns)
| Export (kind) | Columns |
|---|---|
| Sales (`ACCOUNTING_SALES`) | `date, voucher_no, party, taxable_value, <one column per tax component name used in the range, in alphabetical order>, round_off, grand_total, status` |
| Receipts (`ACCOUNTING_RECEIPTS`) | `date, bill_number, method, amount, reference, confirmed_by` (SUCCESS payments; one row per payment) |
| Purchases (`ACCOUNTING_PURCHASES`) — Stream C | `date, purchase_number, supplier, taxable_value, tax_total, total, paid_status` |
| Party ledger (`ACCOUNTING_PARTY_LEDGER`) | `date, party, document_type, document_no, debit, credit, running_balance` (credit-customer bills as debit, receipts as credit; **Stream B's credit tables are the source**; empty if that feature is absent) |
To keep the columns stable, the tax columns are emitted for **every component name that exists in the outlet's tax profiles** (alphabetical), zero-filled, not only those used in the range.

### 28.B.5 Tally XML voucher export — best effort, NOT verified against real Tally
- Kind `TALLY_VOUCHERS`, format XML. One **Sales voucher per bill** (`VCHTYPE="Sales"`, `ACTION="Create"`), `<ISINVOICE>No</ISINVOICE>` (accounting-voucher view; no inventory/GST-invoice view is generated). Dates `YYYYMMDD`. Voucher number = bill number. Optional `SVCURRENTCOMPANY`. VOID bills are skipped.
- **Ledger names are the restaurant's own, mapped by the Owner/accountant** (`tally_ledger_mappings` by purpose; `tally_tax_ledger_mappings` per tax component name). A missing mapping stops the export with **`422 MISSING_LEDGER_MAPPING`** and the list of names — Galla never invents a ledger *(T3)*.
| Purpose key | What it carries | Side |
|---|---|---|
| `SALES` | ITEM lines' taxable amount | credit |
| `SERVICE_CHARGE`, `DELIVERY_CHARGE`, `PACKAGING_CHARGE` | the matching line's taxable amount | credit |
| tax component (per name) | that component's tax | credit |
| `ROUND_OFF` | `round_off` (signed) | credit if positive, debit if negative |
| `CASH`, `CARD`, `UPI`, `OTHER_PAYMENT` | each SUCCESS payment by method | debit |
| `CREDIT_CUSTOMERS` | an unpaid (GENERATED) bill's grand total | debit |
| `TIP`, `PURCHASES` | reserved for Stream B / Stream C exports | — |
- Amount signs follow the sample page: credit ledgers `ISDEEMEDPOSITIVE No` with a positive `AMOUNT`; debit ledgers `ISDEEMEDPOSITIVE Yes` with a negative `AMOUNT`; the entries of every voucher sum to **0.00** *(T1, TP1 random vouchers)*. Special characters in names are XML-escaped *(T4)*.
- **Disclaimer shown on the export screen and in the file's first comment:** "Prepared for import into Tally. Not tested against your Tally version. Import a one-day file into a test company first." Whether Tally accepts the file, rejects vouchers with a "Voucher totals do not match" style message, or needs other tags for GST is **not verified** (Open Decision 57).

### 28.B.6 Export screen S39
Tabs: **Legal & invoice** (28.A.1 with "Format checked only" hints), **Registers** (outlet, date range, register, format CSV/XLSX, *Create*; list of recent jobs with status chips QUEUED/RUNNING/DONE/FAILED/EXPIRED, download, checksum), **Accounting** (generic CSVs and Tally XML; ledger-mapping table with "Missing" rows highlighted), **Languages** (28.C). *Empty:* "No exports yet — choose a register and a date range." *Error:* job failure shows `error` text and *Retry*; reconcile failure lists bill numbers. Long ranges (> 366 days) are refused with `422 VALIDATION_ERROR` to protect the database.

---

### 28.C  LANGUAGES (i18n)

### 28.C.1 Two separate settings
- **UI language per user** (`users.ui_language`, default `en`): the web app's menus and messages. Selector in the profile menu; takes effect immediately; stored server-side so it follows the user across terminals.
- **Bill language per outlet** (`outlets.bill_language`, default `en`): the language of printed/shared bills and KOTs. A cashier's UI language never changes what a customer's bill says.
First launch languages: **`en` and `hi`**. The codes are BCP-47-like (`hi`, `mr`, `ta`, …) so adding a language is a data change (a locale file + font), not a schema change.

### 28.C.2 Frontend
- **i18next + react-i18next**; locale files `src/locales/{en,hi}/common.json` plus one namespace per screen group; keys are English dot-paths (`bill.pay_now`). ICU-style plurals; **no string concatenation** to build sentences.
- **Fallback:** a missing key in `hi` falls back to `en`; a missing key in `en` shows the key's last segment; **never a blank**. CI **warns** (lists) keys that `hi` lacks, and **fails** if a key used in code is missing from `en`.
- **Numbers and money on screen use Indian digit grouping** `1,00,000.00` (and `-1,00,000.00`); implemented by `inrGroup()` (string work on the decimal string — no float, no locale dependence) *(verified: `inr_group` in `reference/tally_export.py`, tests I1 and round-trip property IP1)*. Files use plain decimals (28.B.1).
- Fonts: bundle **Noto Sans / Noto Sans Devanagari** (self-hosted, subset, `font-display: swap`); the licence of the exact files is checked when they are added (**not verified here**).
- Hindi translations are drafted with machine help and **must be reviewed by a native speaker before release** (Open Decision 58); restaurant-specific terms (KOT, GST, UPI) stay as is.
- Item names: `menu_item_translations (menu_item_id, language, name)` supplies the item name in the bill language; **no row → the item's own (English) name**; a bill stores the printed name in `bill_lines.name` at billing, so later translation edits do not alter old bills.

### 28.C.3 Printing Devanagari on thermal printers
ESC/POS text mode uses printer code pages; **Devanagari conjuncts and vowel signs cannot be produced through a code page**, so Hindi bills and KOTs are **rendered as an image**: the backend lays the `PrintDocument` out with a bundled Devanagari font (HarfBuzz-capable shaping, so conjuncts and matras are placed correctly), rasterises it at the printer's dot width (576 dots for 80 mm, 384 for 58 mm — typical values; confirm per printer model), dithers to 1-bit and sends it as an ESC/POS raster image (`GS v 0` is the common command; support varies — **not tested on any printer**). English-only bills keep the fast text path. Consequences stated in the UI: raster bills print slower and use more paper feed; the "bill language" selector shows a warning when `hi` is chosen on a printer whose profile has `raster_supported = false`. The browser-print and PDF/WhatsApp paths use normal HTML/CSS and web fonts. **Golden-image tests:** a fixed bill in `hi` is rendered to PNG and compared pixel-for-pixel with a stored golden image (tolerance 0); a second set renders the same text in `en` to catch metrics drift. The golden files are regenerated only in a reviewed change.

### 28.C.4 Tests
IG-I1 `inrGroup` vectors (`0`, `999`, `1,000`, `99,999`, `1,00,000`, `1,23,45,678.90`, negatives); IG-IP1 round-trip property; IG-I2 key-parity script (every key used in code exists in `en`); IG-I3 fallback (hi missing key → English text, never empty); IG-I4 golden image `hi` 80 mm and 58 mm; IG-I5 bill-language vs UI-language independence (cashier in `hi`, bill in `en`); IG-I6 item with and without a translation.

---

### 28.D  DATA MANAGEMENT

### 28.D.1 Tenant data export (Owner)
`POST /data-export` creates an `export_jobs` row kind `TENANT_DATA_EXPORT`, format **ZIP**: one CSV per table group (outlets, users without password hashes, menu, customers, orders, bills + lines + taxes, payments, expenses/purchases/inventory when those modules exist, registers for the whole history, integration mappings) plus a `manifest.json` (table, row count, SHA-256, export time, schema version) and a README of columns. **Excluded by design:** password hashes, PIN hashes, encrypted credentials and webhook secrets, raw provider payloads, other tenants' data. The link is time-limited (`export_file_retention_days`), access audited (`TENANT_DATA_EXPORTED`), and the job is limited to one running per tenant. Replaces old Open Decision 14 (export on request) — answered by design as "yes, ZIP of CSV + JSON manifest, Owner only", the retention of the *files* being configurable.

### 28.D.2 Customer data requests (DPDP-style; legal duties NOT verified)
`data_subject_requests` records requests received from a customer (by phone number or customer id): **ACCESS_EXPORT, ERASURE, CORRECTION**, with received time, **configurable due date** (default 30 days — a proposal, not the legal deadline), status RECEIVED → IN_PROGRESS → COMPLETED | REJECTED, handler, outcome note.
- **Access export:** a JSON/ZIP of what Galla holds for that customer (profile, consent records, bills they appear on, WhatsApp message log).
- **Erasure = anonymise, not hard delete:** the customer row's name, phone, e-mail and address are overwritten with a non-identifying marker and the WhatsApp/consent identifiers are cleared; bills keep their numbers and amounts because bills are records the restaurant may have to keep (**which records, for how long: not verified; `legal_hold_reason` records the reason when something is kept**). The database refuses hard deletion of a customer who has a request, so the audit trail survives.
- Completed/rejected requests need a handler and (for rejection) a written reason; every step is audited. A Manager can create requests on behalf of a customer; there is no customer-facing portal in v1.
- **Consent wording, notice content, duty deadlines and who is the "data fiduciary" for restaurant customers are NOT verified** (DPDP Rules notified 14 Nov 2025 with an 18-month phased period; the detail is for a lawyer — Open Decision 56).

### 28.D.3 Retention defaults (`tenant_data_settings`; every number is a configurable **proposal**, not legal advice)
| Setting | Default | Bounds (DB) |
|---|---|---|
| Audit log kept | 730 days | ≥ 365 |
| Payment webhook payloads | 30 days | 7–365 |
| Aggregator raw payloads | 90 days | 7–730 |
| Export file lifetime | 7 days | 1–30 |
| Owner may still download data after cancelling | 90 days | 0–730 |
| Tenant data deleted after cancelling | 365 days | ≥ the download window |
The **retention job** (nightly) is the only code allowed to delete audit rows and old webhook events (it sets `galla.retention_job = 'on'` in its transaction; the database triggers refuse deletes otherwise). Bills, payments and registers are **not** deleted by any default here (retention of tax records: CA checklist item 10). Replaces old Open Decision 13 (retention after cancellation): the **mechanism** is built, the **numbers** stay proposals (Open Decision 54).

### 28.D.4 Audit-log viewer and export
Settings → Audit (O; M read) lists audit rows with filters (date, user, action, entity) and **Export CSV** (`AUDIT_LOG` job). The table is **append-only** (UPDATE refused; DELETE only by the retention job) *(DB cases: 5)*. Viewing/exporting is itself audited. Columns: `time, user, action, entity_type, entity_id, detail`.

### 28.D.5 Backup and restore runbook additions (targets are proposals, Open Decision 59)
- Daily full backup + continuous WAL archiving; `backup_runs` records every backup, WAL-archive check and **restore test** (platform table, no tenant). A backup that was never restore-tested is shown amber in the platform console.
- **Proposed targets:** RPO ≤ 15 minutes (WAL archive), RTO ≤ 4 hours; **monthly restore test** into a scratch database followed by a smoke script (row counts, latest bill number per outlet, register reconciliation R6 on the latest day). Whether the chosen host/managed Postgres can meet these is **not verified**.
- Runbook checks: alert if no `OK` FULL in 26 h, no `OK` RESTORE_TEST in 35 days, WAL archive lag > 15 min. Procedure for "restore one tenant" (restore to scratch, export that tenant's tables, import into production inside a maintenance window) is a manual runbook step in v1.

### 28.D.6 Weekly summary e-mail
`scheduled_reports`: per outlet `WEEKLY_SUMMARY` (ISO weekday, send time, default 08:00 in the outlet's time zone) or `MONTHLY_SUMMARY` (day 1–28), 1–10 recipients, enabled flag, `last_sent_for` for de-duplication. Content is **computed by SQL, never by the LLM**: sales, bill count, average bill, tax total, payment-mode split, top 5 items, voids and discounts, unresolved payment attentions (27.B), online-order counts (27.A). It uses the existing outbox worker and templates (Section 10.1–10.2); recipients are validated e-mail addresses; no customer personal data appears. Period-end dedupe: the e-mail for a period is sent once even if the worker restarts.

---

### 28.E  API, SCREENS, SECURITY, TESTS, E2E, PHASES

### 28.E.1 API (tenant-scoped; roles O=Owner, M=Manager)
| Method | Path | Roles | Notes |
|---|---|---|---|
| GET / PUT | `/outlets/{id}/legal-profile` | O (GET: O,M) | validation errors per field; audit `LEGAL_PROFILE_CHANGED` |
| GET / PUT | `/tax-profile-pairs` | O | |
| PUT | `/menu-items/{id}/hsn` or part of item PUT | O,M | 2–8 digits |
| GET / PUT | `/menu-items/{id}/translations` | O,M | |
| PUT | `/me/language` | any signed-in | |
| POST | `/exports` `{kind, format, outletId, from, to, layout?}` | O,M (registers), O (tenant export) | 202 + job; `409 REGISTER_NOT_RECONCILED`; `422 MISSING_LEDGER_MAPPING`; `422 VALIDATION_ERROR` |
| GET | `/exports`, `/exports/{id}`, `/exports/{id}/download` | O,M (own tenant) | time-limited link; audit |
| GET / PUT | `/tally-ledger-mappings`, `/tally-tax-ledger-mappings` | O,M | |
| POST | `/data-export` | O | one running at a time (`409 EXPORT_ALREADY_RUNNING`) |
| GET / POST / PATCH | `/data-requests` | O,M | state machine; audit |
| GET / PUT | `/tenant-data-settings` | O | bounds enforced by DB and API |
| GET | `/audit-logs`, POST `/exports` kind `AUDIT_LOG` | O (M read) | |
| GET / PUT | `/scheduled-reports` | O,M | |
| GET | `/platform/backup-runs` | SUPER_ADMIN | read-only |
New error codes: `REGISTER_NOT_RECONCILED` (409), `MISSING_LEDGER_MAPPING` (422), `EXPORT_ALREADY_RUNNING` (409), `EXPORT_EXPIRED` (410), `INVALID_GSTIN_FORMAT`, `INVALID_FSSAI_NUMBER`, `INVALID_HSN_CODE` (422).

### 28.E.2 Screens
**S39** Compliance & exports (28.B.6). **S40 Data & privacy (O; M partial):** tabs *Export my data*, *Customer requests* (table with due-date colouring, *New request*, handler actions), *Retention* (the six settings with defaults and a note "These are proposals, not legal advice"), *Audit log*, *Weekly e-mail*. *Empty states:* "No requests", "No scheduled e-mails". *Error states:* retry panel; a failed job shows its message. Settings → Language holds the user language selector (all roles) and the outlet bill language (O) with the Devanagari raster notice.

### 28.E.3 Security
Exports contain business and customer data: Owner/Manager only, tenant-scoped query (cross-tenant → 404), **no secrets or hashes ever included**, files encrypted at rest in storage, signed time-limited URLs, deletion after `export_file_retention_days` (status `EXPIRED`), every download audited. Tenant export is Owner-only and rate-limited. CSV injection: cells beginning with `= + - @` are prefixed with `'` in CSV/XLSX text columns (money columns are numbers). Data-request handling never reveals another customer's data; phone matching uses E.164 (`^\+[1-9][0-9]{6,14}$`). Retention job runs with a dedicated flag and logs how many rows it removed.

### 28.E.4 Tests (prefix IG)
- **IG-R1…R6** — `reference/registers.py`: reconciliation over random bills (`bill_calculator.py`), VOID exclusion, known vectors for exclusive and inclusive prices, round-off column isolation, CGST+SGST grouped as one rate, payment split.
- **IG-T1…T4, TP1** — Tally vouchers (balance, unpaid → credit-customers ledger, missing mapping raises, escaping, random vouchers balance).
- **IG-I1, IP1** — Indian grouping.
- **IG-DB-C/D/E** — V015 cases for legal fields (19), HSN/customer/bill snapshots (12), Tally mappings (6), export jobs (11), languages (6), data management (30), audit append-only (5).
- **IG-SQL-1…6** — each register SQL against a fixture; R6 must return zero rows; a hand-corrupted bill makes the export refuse.
- **IG-API-23…40**, **IG-UI-10…20** — role matrices, cross-tenant 404, download link expiry, no secrets in the ZIP (grep the archive), data-request state machine, empty/error states.

### 28.E.5 E2E scenarios (extend Section 14.2)
56. **Legal fields and bill:** owner enters GSTIN (bad format rejected, good accepted, "format checked only" note), FSSAI (13 digits rejected), document title and HSN; a bill prints with the header lines; editing the outlet afterwards does not change the reprint of the old bill.
57. **Registers reconcile:** create 20 bills (mixed exclusive/inclusive, discount, service charge, one VOID, split payments); generate sales, by-rate, HSN, tax and payment-mode registers; the sums equal the bill totals to the paisa; the VOID bill is absent; corrupting one bill by SQL makes the export fail with `REGISTER_NOT_RECONCILED`.
58. **Accounting exports:** generic CSVs have the stable columns; Tally export refused with the missing ledger names, then succeeds after mapping; vouchers balance; the owner is shown the "not tested against your Tally" notice.
59. **Hindi:** user switches UI to `hi`, a missing key shows English; outlet bill language `hi` prints a raster bill matching the golden image; amounts on screen show `1,00,000.00` grouping.
60. **Data management:** Owner exports tenant data (ZIP contains manifest, no secrets); a customer erasure request anonymises the customer but leaves the bill amounts; a deletion attempt on audit rows fails; the weekly e-mail is sent once per period.

### 28.E.6 Phases
- **Phase 2 amendment:** legal fields, bill snapshot, HSN field, Indian number grouping, `en/hi` UI (Hindi text after review) — small and early, because every later bill carries them.
- **Phase 2R (new, ≈ 2 weeks, after Stream B's credit notes and Stream C's purchases exist, otherwise those two registers are delivered later):** registers, generic CSV/XLSX, Tally XML (marked best effort), Hindi raster bills, export jobs.
- **Phase 4 amendment:** data management (tenant export, data requests, retention job, audit viewer, backup runbook, weekly e-mail). Retention numbers and data-request wording wait for Open Decisions 54–56.
- **Phase 6:** aggregator reports (partner reconciliation, 27.A) reuse export jobs.

### 28.E.7 Not verified (summary)
GSTIN checksum and validity; HSN digit rules; e-invoice thresholds; composition rules; mandatory invoice content; credit-note and retention rules; Tally import behaviour (structure read from Tally's sample page only); DPDP duties and deadlines beyond the notification date and the existence of an 18-month phased period; printer support for raster Devanagari; font licences; hosting's ability to meet RPO/RTO.

### 28.F Database — Migration V015 *(verified on PostgreSQL 16 on top of V001–V011: 193 accept/reject cases, 193 as expected)*
Covers sections 27 and 28. It depends on V001–V011 only; references to other streams' tables (devices, credit notes, purchases) are plain `uuid` columns without foreign keys (**FKs are added in V016**). It adds the shared guard functions `galla_block_mutation`, `galla_webhook_event_guard`, `galla_audit_guard` and the tables: `integration_accounts`, `external_item_mappings`, `external_orders`, `external_status_events`, `integration_sync_jobs`, `partner_payouts`, `payment_intents`, `provider_settlements`, `provider_settlement_lines`, `tax_profile_pairs`, `tally_ledger_mappings`, `tally_tax_ledger_mappings`, `export_jobs`, `menu_item_translations`, `tenant_data_settings`, `data_subject_requests`, `scheduled_reports`, `backup_runs`; and alters `payment_webhook_events`, `outlets`, `menu_items`, `customers`, `bills`, `bill_lines`, `users`, `audit_logs`.
```sql
-- V015 — online-order aggregators, payment-gateway intents & settlements, compliance fields, exports, i18n, data management
-- Depends on V001–V011 only. References to tables of streams A/B/C (devices, credit_notes, purchases ...) are plain uuid columns; FKs are added in V016.

-- ============================================================ shared guard functions
CREATE FUNCTION galla_block_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% on % is not allowed (append-only table)', TG_OP, TG_TABLE_NAME USING ERRCODE = 'restrict_violation';
END $$;

-- ============================================================ A. AGGREGATOR INTEGRATION FRAMEWORK
CREATE TABLE integration_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  provider text NOT NULL CHECK (provider ~ '^[a-z][a-z0-9_]{1,30}$'),        -- adapter code, e.g. a provider or middleware code; no provider is hard-coded in the schema
  kind text NOT NULL DEFAULT 'AGGREGATOR' CHECK (kind IN ('AGGREGATOR','MIDDLEWARE')),
  display_name text NOT NULL,
  external_store_id text NOT NULL,                  -- the provider's id for this outlet
  credentials_encrypted text NOT NULL,              -- AES-GCM (INTEGRATION_ENCRYPTION_KEY); never returned by any API
  webhook_secret_encrypted text,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','CONNECTED','ERROR','DISABLED')),
  auto_accept boolean NOT NULL DEFAULT false,       -- accept without staff when every line is mapped (23/27.4 rules)
  accept_sla_seconds int NOT NULL DEFAULT 180 CHECK (accept_sla_seconds BETWEEN 30 AND 3600),  -- placeholder: the real deadline comes from the provider's documentation
  store_open boolean NOT NULL DEFAULT true,
  last_error text,
  last_sync_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (outlet_id, provider, external_store_id)
);
CREATE UNIQUE INDEX ux_integration_store_per_provider ON integration_accounts(provider, external_store_id) WHERE status <> 'DISABLED';

CREATE TABLE external_item_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  integration_account_id uuid NOT NULL REFERENCES integration_accounts(id) ON DELETE CASCADE,
  external_item_id text NOT NULL,
  external_variant_id text NOT NULL DEFAULT '',     -- '' = the item has no variant (avoids NULL in the unique key)
  external_name text,
  status text NOT NULL DEFAULT 'MAPPED' CHECK (status IN ('MAPPED','IGNORED')),   -- IGNORED = not a food line (e.g. a fee) — skipped, never billed as an item
  menu_item_id uuid REFERENCES menu_items(id),
  item_variant_id uuid REFERENCES item_variants(id),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (integration_account_id, external_item_id, external_variant_id),
  CHECK (status <> 'MAPPED' OR menu_item_id IS NOT NULL),
  CHECK (status <> 'IGNORED' OR (menu_item_id IS NULL AND item_variant_id IS NULL)),
  CHECK (item_variant_id IS NULL OR menu_item_id IS NOT NULL)
);

CREATE TABLE external_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  integration_account_id uuid NOT NULL REFERENCES integration_accounts(id),
  provider text NOT NULL,
  external_order_id text NOT NULL,                  -- the provider's order id (idempotency key of the inbox)
  status text NOT NULL DEFAULT 'RECEIVED' CHECK (status IN
    ('RECEIVED','NEEDS_MAPPING','MAPPED','ACCEPTED','REJECTED','PREPARING','READY','HANDED_OVER','CANCELLED','EXPIRED')),
  payload jsonb NOT NULL,                           -- raw provider payload, kept for support; purged by the retention job (28.D)
  received_at timestamptz NOT NULL DEFAULT now(),
  accept_by timestamptz NOT NULL,                   -- SLA deadline = received_at + account.accept_sla_seconds
  accepted_at timestamptz,
  accepted_by uuid REFERENCES users(id),            -- NULL when auto-accepted
  auto_accepted boolean NOT NULL DEFAULT false,
  reject_reason text,
  cancel_reason text,
  order_id uuid REFERENCES orders(id),              -- the internal order (order_source = 'PARTNER', Section 20.3)
  payment_mode text NOT NULL DEFAULT 'UNKNOWN' CHECK (payment_mode IN ('PREPAID','COD','UNKNOWN')),
  provider_order_total numeric(12,2) CHECK (provider_order_total IS NULL OR provider_order_total >= 0),   -- as reported by the provider
  commission_percent numeric(5,2) CHECK (commission_percent IS NULL OR commission_percent BETWEEN 0 AND 100),  -- recorded as given / typed, never interpreted
  commission_amount numeric(12,2) CHECK (commission_amount IS NULL OR commission_amount >= 0),
  settlement_amount numeric(12,2) CHECK (settlement_amount IS NULL OR settlement_amount >= 0),
  settlement_entered_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (integration_account_id, external_order_id),
  CHECK (accept_by > received_at),
  CHECK (status NOT IN ('ACCEPTED','PREPARING','READY','HANDED_OVER') OR (order_id IS NOT NULL AND accepted_at IS NOT NULL)),
  CHECK (status <> 'REJECTED' OR (reject_reason IS NOT NULL AND length(btrim(reject_reason)) > 0)),
  CHECK (accepted_by IS NOT NULL OR auto_accepted = true OR accepted_at IS NULL)  -- an acceptance is either a user's or the auto-accept rule's
);
CREATE UNIQUE INDEX ux_external_orders_internal_order ON external_orders(order_id) WHERE order_id IS NOT NULL;
CREATE INDEX ix_external_orders_open ON external_orders(outlet_id, status, accept_by) WHERE status IN ('RECEIVED','NEEDS_MAPPING','MAPPED');

CREATE TABLE external_status_events (               -- append-only history of every inbound/outbound status change
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  external_order_id uuid NOT NULL REFERENCES external_orders(id),
  direction text NOT NULL CHECK (direction IN ('INBOUND','OUTBOUND','INTERNAL')),
  status text NOT NULL,
  provider_event_id text,                           -- dedupes the provider's retries of the same event
  detail jsonb,
  actor_user_id uuid REFERENCES users(id),
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_ext_events_provider_event ON external_status_events(external_order_id, provider_event_id) WHERE provider_event_id IS NOT NULL;
CREATE TRIGGER trg_ext_events_append_only BEFORE UPDATE OR DELETE ON external_status_events FOR EACH ROW EXECUTE FUNCTION galla_block_mutation();

CREATE TABLE integration_sync_jobs (                -- outbound work (acknowledgements, status pushes, menu/availability/store-open pushes), same retry rules as the outbox
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  integration_account_id uuid NOT NULL REFERENCES integration_accounts(id),
  job_type text NOT NULL CHECK (job_type IN
    ('POLL_ORDERS','ACCEPT','REJECT','MARK_PREPARING','MARK_READY','HANDOVER','ACK_CANCEL','MENU_PUSH','AVAILABILITY_PUSH','STORE_OPEN','STORE_CLOSE')),
  external_order_id uuid REFERENCES external_orders(id),
  payload jsonb,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','SENDING','SENT','FAILED')),
  attempts int NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_error text,
  dedupe_key text UNIQUE,                            -- e.g. "ext:<id>:ACCEPT"
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  CHECK (job_type NOT IN ('ACCEPT','REJECT','MARK_PREPARING','MARK_READY','HANDOVER','ACK_CANCEL') OR external_order_id IS NOT NULL),
  CHECK (status <> 'SENT' OR sent_at IS NOT NULL)
);
CREATE INDEX ix_sync_jobs_due ON integration_sync_jobs(next_attempt_at) WHERE status = 'PENDING';

CREATE TABLE partner_payouts (                      -- payouts the restaurant received from a partner, typed in by staff, for the reconciliation report
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  integration_account_id uuid NOT NULL REFERENCES integration_accounts(id),
  period_from date NOT NULL,
  period_to date NOT NULL,
  amount_received numeric(12,2) NOT NULL CHECK (amount_received >= 0),
  reference text,
  notes text,
  entered_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (period_to >= period_from)
);

-- ============================================================ B. PAYMENT-GATEWAY (MODE B) INTENTS, EVENTS, SETTLEMENTS
CREATE TABLE payment_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  bill_id uuid NOT NULL REFERENCES bills(id),
  payment_id uuid REFERENCES payments(id),          -- the PENDING payment row created with the intent (Section 9.3 step 1)
  provider text NOT NULL CHECK (provider ~ '^[a-z][a-z0-9_]{1,30}$'),
  provider_ref text,                                 -- provider's order / transaction reference
  amount numeric(12,2) NOT NULL CHECK (amount > 0),  -- locked at creation = remaining balance of the bill
  currency_code char(3) NOT NULL,
  qr_payload text,
  status text NOT NULL DEFAULT 'CREATED' CHECK (status IN ('CREATED','PENDING','SUCCESS','FAILED','EXPIRED')),
  attention text CHECK (attention IN ('AMOUNT_MISMATCH','LATE_SUCCESS','DUPLICATE_PAYMENT','BILL_NOT_PAYABLE')),   -- needs a human; never silently fixed
  attention_resolved_at timestamptz,
  attention_resolved_by uuid REFERENCES users(id),
  received_amount numeric(12,2) CHECK (received_amount IS NULL OR received_amount > 0),
  expires_at timestamptz NOT NULL,
  success_at timestamptz,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0,
  CHECK (expires_at > created_at),
  CHECK (status <> 'SUCCESS' OR (success_at IS NOT NULL AND received_amount IS NOT NULL AND received_amount = amount)),  -- a SUCCESS always has the exact locked amount
  CHECK (attention_resolved_at IS NULL OR attention IS NOT NULL),
  CHECK (attention_resolved_at IS NULL OR attention_resolved_by IS NOT NULL)
);
CREATE UNIQUE INDEX ux_intent_one_active_per_bill ON payment_intents(bill_id) WHERE status IN ('CREATED','PENDING');   -- never two live QRs for one bill
CREATE UNIQUE INDEX ux_intent_provider_ref ON payment_intents(provider, provider_ref) WHERE provider_ref IS NOT NULL;
CREATE INDEX ix_intent_attention ON payment_intents(outlet_id) WHERE attention IS NOT NULL AND attention_resolved_at IS NULL;

-- The existing table from V004 is the provider event log; it gains the fields the resolver needs.
ALTER TABLE payment_webhook_events
  ADD COLUMN tenant_id uuid REFERENCES tenants(id),
  ADD COLUMN intent_id uuid REFERENCES payment_intents(id),
  ADD COLUMN event_kind text NOT NULL DEFAULT 'OTHER' CHECK (event_kind IN ('SUCCESS','FAILED','OTHER')),
  ADD COLUMN amount numeric(12,2) CHECK (amount IS NULL OR amount >= 0),
  ADD COLUMN occurred_at timestamptz,                -- the provider's own event time (used to judge "paid before expiry")
  ADD COLUMN outcome text CHECK (outcome IN ('APPLIED','DUPLICATE_PAYMENT','AMOUNT_MISMATCH','LATE_SUCCESS','FAILED_RECORDED','UNKNOWN_INTENT','IGNORED'));
CREATE FUNCTION galla_webhook_event_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF coalesce(current_setting('galla.retention_job', true), '') = 'on' AND OLD.received_at < now() - interval '1 day' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'DELETE on payment_webhook_events is only allowed for the retention job' USING ERRCODE = 'restrict_violation';
  END IF;
  IF NEW.provider IS DISTINCT FROM OLD.provider OR NEW.event_id IS DISTINCT FROM OLD.event_id
     OR NEW.payload IS DISTINCT FROM OLD.payload OR NEW.received_at IS DISTINCT FROM OLD.received_at
     OR NEW.event_kind IS DISTINCT FROM OLD.event_kind OR NEW.amount IS DISTINCT FROM OLD.amount
     OR NEW.occurred_at IS DISTINCT FROM OLD.occurred_at THEN
    RAISE EXCEPTION 'payment_webhook_events: only processed_at, outcome, intent_id and tenant_id may change' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_webhook_event_guard BEFORE UPDATE OR DELETE ON payment_webhook_events FOR EACH ROW EXECUTE FUNCTION galla_webhook_event_guard();

CREATE TABLE provider_settlements (                 -- one imported settlement report (CSV the owner downloads from the provider and uploads)
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  provider text NOT NULL,
  settlement_ref text NOT NULL,
  settlement_date date NOT NULL,
  gross_amount numeric(12,2) NOT NULL CHECK (gross_amount >= 0),
  fee_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),     -- all fees and taxes on fees as one reported figure; not interpreted
  net_amount numeric(12,2) NOT NULL CHECK (net_amount >= 0),
  imported_by uuid NOT NULL REFERENCES users(id),
  imported_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, provider, settlement_ref),
  CHECK (net_amount = gross_amount - fee_amount)
);
CREATE TABLE provider_settlement_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id uuid NOT NULL REFERENCES provider_settlements(id) ON DELETE CASCADE,
  provider_txn_id text NOT NULL,
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  intent_id uuid REFERENCES payment_intents(id),
  match_status text NOT NULL CHECK (match_status IN ('MATCHED','UNMATCHED','AMOUNT_DIFF')),
  note text,
  UNIQUE (settlement_id, provider_txn_id),
  CHECK (match_status <> 'MATCHED' OR intent_id IS NOT NULL)
);

-- ============================================================ C. COMPLIANCE FIELDS (structure only — rules are NOT asserted, Section 28.A)
ALTER TABLE outlets
  ADD COLUMN legal_name text,
  ADD COLUMN gstin text CHECK (gstin IS NULL OR gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),      -- FORMAT only; checksum and existence are not verified
  ADD COLUMN state_code char(2) CHECK (state_code IS NULL OR state_code ~ '^[0-9]{2}$'),
  ADD COLUMN pan text CHECK (pan IS NULL OR pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'),
  ADD COLUMN registration_type text NOT NULL DEFAULT 'UNREGISTERED' CHECK (registration_type IN ('REGULAR','COMPOSITION','UNREGISTERED')),
  ADD COLUMN fssai_licence_no text CHECK (fssai_licence_no IS NULL OR fssai_licence_no ~ '^[0-9]{14}$'),            -- 14 digits per FSSAI order of 2021 (see 28.A)
  ADD COLUMN document_title text NOT NULL DEFAULT 'BILL' CHECK (document_title IN ('TAX_INVOICE','BILL_OF_SUPPLY','INVOICE','BILL')),
  ADD COLUMN place_of_supply_mode text NOT NULL DEFAULT 'OUTLET_STATE' CHECK (place_of_supply_mode IN ('OUTLET_STATE','DESTINATION_STATE')),
  ADD COLUMN print_hsn boolean NOT NULL DEFAULT false,
  ADD COLUMN bill_language text NOT NULL DEFAULT 'en' CHECK (bill_language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$'),
  ADD CONSTRAINT outlets_gstin_state_matches CHECK (gstin IS NULL OR state_code IS NULL OR substr(gstin,1,2) = state_code),
  ADD CONSTRAINT outlets_gstin_pan_matches CHECK (gstin IS NULL OR pan IS NULL OR substr(gstin,3,10) = pan);

ALTER TABLE menu_items
  ADD CONSTRAINT menu_items_hsn_format CHECK (hsn_sac_code IS NULL OR hsn_sac_code ~ '^[0-9]{2,8}$');               -- digits only; how many digits are required is a CA question

ALTER TABLE customers
  ADD COLUMN legal_name text,
  ADD COLUMN gstin text CHECK (gstin IS NULL OR gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

-- document-level snapshots (what was actually printed), so a later edit of the outlet never rewrites an old bill
ALTER TABLE bills
  ADD COLUMN document_title text,
  ADD COLUMN seller_legal_name text,
  ADD COLUMN seller_gstin text,
  ADD COLUMN seller_state_code char(2),
  ADD COLUMN seller_fssai_licence_no text,
  ADD COLUMN place_of_supply_state_code char(2) CHECK (place_of_supply_state_code IS NULL OR place_of_supply_state_code ~ '^[0-9]{2}$'),
  ADD COLUMN buyer_legal_name text,
  ADD COLUMN buyer_gstin text CHECK (buyer_gstin IS NULL OR buyer_gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
  ADD COLUMN bill_language text;
ALTER TABLE bill_lines ADD COLUMN hsn_sac_code text;

CREATE TABLE tax_profile_pairs (                    -- "if the place of supply is another state, use THIS profile instead of THAT one" (configuration; the owner/CA decides the pairs)
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  intra_profile_id uuid NOT NULL REFERENCES tax_profiles(id),
  inter_profile_id uuid NOT NULL REFERENCES tax_profiles(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (intra_profile_id),
  CHECK (intra_profile_id <> inter_profile_id)
);

CREATE TABLE tally_ledger_mappings (                -- names of the ledgers in the restaurant's own Tally company (Section 28.B)
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  purpose text NOT NULL CHECK (purpose IN ('SALES','SERVICE_CHARGE','DELIVERY_CHARGE','PACKAGING_CHARGE','ROUND_OFF',
                                           'CASH','CARD','UPI','OTHER_PAYMENT','CREDIT_CUSTOMERS','PURCHASES','TIP')),
  tally_ledger_name text NOT NULL CHECK (length(btrim(tally_ledger_name)) > 0),
  UNIQUE (outlet_id, purpose)
);
CREATE TABLE tally_tax_ledger_mappings (            -- one row per tax component name used in the restaurant's tax profiles
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  component_name text NOT NULL,
  tally_ledger_name text NOT NULL CHECK (length(btrim(tally_ledger_name)) > 0),
  UNIQUE (outlet_id, component_name)
);

-- ============================================================ EXPORT JOBS (registers, accounting exports, tenant data export, audit export)
CREATE TABLE export_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  kind text NOT NULL CHECK (kind IN ('SALES_REGISTER','HSN_SUMMARY','TAX_SUMMARY','PAYMENT_MODE_SUMMARY','CREDIT_NOTE_REGISTER','PURCHASE_REGISTER',
                                     'ACCOUNTING_SALES','ACCOUNTING_RECEIPTS','ACCOUNTING_PURCHASES','ACCOUNTING_PARTY_LEDGER','TALLY_VOUCHERS',
                                     'TENANT_DATA_EXPORT','CUSTOMER_DATA_EXPORT','AUDIT_LOG','PARTNER_RECONCILIATION','SETTLEMENT_RECONCILIATION')),
  format text NOT NULL CHECK (format IN ('CSV','XLSX','XML','ZIP','JSON')),
  params jsonb NOT NULL DEFAULT '{}',                -- date range, filters
  status text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','RUNNING','DONE','FAILED','EXPIRED')),
  file_key text,
  file_sha256 text CHECK (file_sha256 IS NULL OR file_sha256 ~ '^[0-9a-f]{64}$'),
  row_count int CHECK (row_count IS NULL OR row_count >= 0),
  error text,
  requested_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  expires_at timestamptz,                            -- download link lifetime (files are deleted after it)
  CHECK (status <> 'DONE' OR (file_key IS NOT NULL AND file_sha256 IS NOT NULL AND row_count IS NOT NULL AND finished_at IS NOT NULL)),
  CHECK (kind <> 'TALLY_VOUCHERS' OR format = 'XML'),
  CHECK (kind NOT IN ('TENANT_DATA_EXPORT','CUSTOMER_DATA_EXPORT') OR format IN ('ZIP','JSON'))
);
CREATE INDEX ix_export_jobs_tenant ON export_jobs(tenant_id, created_at DESC);

-- ============================================================ D. LANGUAGES
ALTER TABLE users ADD COLUMN ui_language text NOT NULL DEFAULT 'en' CHECK (ui_language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$');
CREATE TABLE menu_item_translations (               -- item names printed on bills/KOTs in the outlet's bill language
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  menu_item_id uuid NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  language text NOT NULL CHECK (language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$' AND language <> 'en'),   -- English is the item's own name
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  UNIQUE (menu_item_id, language)
);

-- ============================================================ E. DATA MANAGEMENT
CREATE TABLE tenant_data_settings (                 -- retention proposals (Section 28.D); every number is a configurable default, not legal advice
  tenant_id uuid PRIMARY KEY REFERENCES tenants(id),
  audit_log_retention_days int NOT NULL DEFAULT 730 CHECK (audit_log_retention_days >= 365),
  webhook_payload_retention_days int NOT NULL DEFAULT 30 CHECK (webhook_payload_retention_days BETWEEN 7 AND 365),
  external_order_payload_retention_days int NOT NULL DEFAULT 90 CHECK (external_order_payload_retention_days BETWEEN 7 AND 730),
  export_file_retention_days int NOT NULL DEFAULT 7 CHECK (export_file_retention_days BETWEEN 1 AND 30),
  after_cancel_export_days int NOT NULL DEFAULT 90 CHECK (after_cancel_export_days BETWEEN 0 AND 730),     -- how long the owner may still download data after cancelling
  after_cancel_delete_days int NOT NULL DEFAULT 365 CHECK (after_cancel_delete_days >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (after_cancel_delete_days >= after_cancel_export_days)
);
CREATE TABLE data_subject_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  customer_id uuid REFERENCES customers(id),             -- no ON DELETE action: erasure ANONYMISES the customer row (28.D); a hard delete of a customer with a request is refused
  phone_e164 text CHECK (phone_e164 IS NULL OR phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  request_type text NOT NULL CHECK (request_type IN ('ACCESS_EXPORT','ERASURE','CORRECTION')),
  status text NOT NULL DEFAULT 'RECEIVED' CHECK (status IN ('RECEIVED','IN_PROGRESS','COMPLETED','REJECTED')),
  received_at timestamptz NOT NULL DEFAULT now(),
  due_at timestamptz NOT NULL,                       -- configurable default; the legal deadline is NOT asserted
  completed_at timestamptz,
  handled_by uuid REFERENCES users(id),
  outcome_note text,
  legal_hold_reason text,                            -- e.g. bills that must be kept: the person is anonymised, the bills stay
  CHECK (customer_id IS NOT NULL OR phone_e164 IS NOT NULL),
  CHECK (due_at > received_at),
  CHECK (status NOT IN ('COMPLETED','REJECTED') OR (completed_at IS NOT NULL AND handled_by IS NOT NULL)),
  CHECK (status <> 'REJECTED' OR (outcome_note IS NOT NULL AND length(btrim(outcome_note)) > 0))
);
CREATE TABLE scheduled_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  kind text NOT NULL CHECK (kind IN ('WEEKLY_SUMMARY','MONTHLY_SUMMARY')),
  weekday smallint CHECK (weekday BETWEEN 1 AND 7),               -- ISO: 1 = Monday
  day_of_month smallint CHECK (day_of_month BETWEEN 1 AND 28),
  send_time time NOT NULL DEFAULT '08:00',
  recipients text[] NOT NULL CHECK (cardinality(recipients) BETWEEN 1 AND 10),
  enabled boolean NOT NULL DEFAULT true,
  last_sent_for date,                                -- the period end the last e-mail covered (dedupe)
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, kind),
  CHECK (kind <> 'WEEKLY_SUMMARY' OR weekday IS NOT NULL),
  CHECK (kind <> 'MONTHLY_SUMMARY' OR day_of_month IS NOT NULL)
);
CREATE TABLE backup_runs (                          -- platform-level (no tenant): proof that backups ran AND that a restore was tested
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('FULL','WAL_ARCHIVE_CHECK','RESTORE_TEST')),
  status text NOT NULL CHECK (status IN ('RUNNING','OK','FAILED')),
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  size_bytes bigint CHECK (size_bytes IS NULL OR size_bytes >= 0),
  location text,
  notes text,
  CHECK (status = 'RUNNING' OR finished_at IS NOT NULL),
  CHECK (finished_at IS NULL OR finished_at >= started_at)
);

-- audit log: append-only (retention job is the only deleter)
CREATE FUNCTION galla_audit_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN RAISE EXCEPTION 'audit_logs rows cannot be changed' USING ERRCODE = 'restrict_violation'; END IF;
  IF coalesce(current_setting('galla.retention_job', true), '') = 'on' THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'audit_logs rows can only be deleted by the retention job' USING ERRCODE = 'restrict_violation';
END $$;
CREATE TRIGGER trg_audit_guard BEFORE UPDATE OR DELETE ON audit_logs FOR EACH ROW EXECUTE FUNCTION galla_audit_guard();
```

---

## 29. CROSS-VERIFICATION — every requirement, where it lives, how it is checked

### 29.1 Traceability matrix
| # | You asked for | Where in this plan | Checked by |
|---|---|---|---|
| 1 | A clear product name | **Galla** (title; `app.brand.name` config) | — |
| 2 | Web billing app that generates the bill/slip like the existing tools | 5, 8, S3–S4 | vectors V1–V11, golden ESC/POS files, E2E 2 |
| 3 | Menu with items, variants, modifiers, tax | 4.3, S13, `/catalog/pos` | integration tests, E2E 2, CSV import tests |
| 4 | Billing that "should not create any problem" | 5.3–5.9 | 11 vectors, 10 000-case property tests, concurrency tests, DB constraints |
| 5 | Login functionality | 13.1, 22.1 | E2E 1, 23; auth tests 401/403/404 |
| 6 | Roles and rules in the restaurant | Appendix A, 22.2–22.3 | per-endpoint role tests |
| 7 | Super admin who gives access to any restaurant | 18.1–18.2, 18.7 | E2E 15, 19 |
| 8 | Restaurant admin creates cashier/inventory/etc. roles | 18.1, 18.3, R2 | E2E 18 |
| 9 | Plans that cap how many roles a restaurant can create | 18.3 | S6 vectors, E2E 18 |
| 10 | Receive money monthly or yearly | 18.4–18.5 | S3–S5 vectors, E2E 17 |
| 11 | One month free trial | 18.2, 18.4, 18.6 | S1, S2, S8, S10, E2E 16 |
| 12 | Activate/deactivate users (and restaurants) | 18.7 | E2E 19 (token rejected ≤ 1 s) |
| 13 | Select a role and then log in | 22.1 | E2E 23 |
| 14 | Feedback and support | 19 | E2E 20, internal-note API test |
| 15 | Map and delivery tracking, notifications | 11 | E2E 10 |
| 16 | Delivery charges for far deliveries | 20.1–20.2 | D1–D10, V10–V11, E2E 21 |
| 17 | Orders from partners | 20.3 | DB constraint test, E2E 21 |
| 18 | Restaurant uploads its own UPI ID/QR; cashier confirms | 21 | E2E 22, ZXing decode tests with sample QR images |
| 19 | End-of-day email with totals (and inventory) | 10.3–10.4, 26.10 | E2E 11, 50. `inventory` is `null` only when the outlet has not started inventory (flag off or no opening stock) |
| 20 | Dynamic QR with the amount after discount | 9.4, 21.3 | E2E 3, 8, 22 |
| 21 | React, Spring Boot, Docker, Kubernetes, Spring AI | 2, 10.5, 15 | CI pipeline |
| 22 | App must not be blank / must work properly | 12.2, 22.4 | E2E 24, 12 |
| 23 | Customers' ordering app ignored | 1.2 | — |
| 25 | Bill is sent on WhatsApp if the number is on WhatsApp | 23 (try → webhook status → fallback; no official pre-check exists) | W1–W12, E2E 25–27, fake-Meta integration tests. **Real delivery untested** |
| 26 | Check the domain is available | 17.20 — **not verified** (tools could not reach registrars); owner must check | — |
| 24 | Zero bugs | 14 — **cannot be guaranteed**; risk is cut by tests, constraints and idempotency | CI gates |
| 27 | "Make it work offline" | 24 | golden vectors (443 checks), OF1–OF20, 71 DB cases, E2E 28–33. **Real-device behaviour untested** |
| 28 | Calculation identical online and offline | 24.5 | golden_bill_vectors.json in JS (now), Java and Vitest (to write) |
| 29 | Combos / bundles | 25.3 | BX01–BX08 (property: exact sums), E2E 34 |
| 30 | Coupons with limits | 25.4 | BX10–BX19, DB cases (limits, release), E2E 35 |
| 31 | Happy-hour pricing | 25.5 | BX30–BX39, E2E 36 |
| 32 | Packaging charge | 25.6 | X1–X4 (existing), DB cases, E2E 37 |
| 33 | Open items | 25.7 | DB cases, E2E 38 |
| 34 | Complimentary bills | 25.8 | BX45–BX48, DB cases, E2E 39 |
| 35 | Tips | 25.9 | DB cases, E2E 40 |
| 36 | Shifts / cash drawer | 25.10 | BX60–BX66, DB cases, E2E 40. **Drawer hardware untested** |
| 37 | Credit sales / dues | 25.11 | BX70–BX75, DB cases, E2E 41 |
| 38 | Refunds / credit notes | 25.12 | BX80–BX91 (property), DB cases, E2E 42 |
| 39 | Kitchen display | 25.13 | BX50–BX55, DB cases, E2E 43 |
| 40 | Barcode, customer display, central menu | 25.14–25.16 | DB cases, E2E 44. **Scanner timing untested** |
| 41 | Know my food cost and stock | 26 | IN1–IN22, P1–P8 (30 tests), 217 DB cases, E2E 45–50 |
| 42 | Billing never blocked by stock | 26.7 | savepoint design, fault-injection test (to write) |
| 43 | End-of-day email with inventory | 10.3, 26.10 | IN22 invariant; E2E 50 |
| 44 | Aggregator orders arrive idempotently | 27.A.1, V015 `external_orders` unique | IG-A8, IG-AP2, DB cases, E2E 51 |
| 45 | Unmapped items block auto-accept | 27.A.3–4 | IG-A2, A3, E2E 52 |
| 46 | SLA / expiry / cancel handling | 27.A.1, 27.A.3 | IG-A5, A7, A11, E2E 53 |
| 47 | Reconciliation without interpretation | 27.A.8 | IG-A12, E2E 55 |
| 48 | Gateway auto-confirm, amount locked | 27.B.1–3 | IG-P1–P19, DB intent cases, E2E 54 |
| 49 | Any order/duplication of events → same state | 27.B.3 | IG-PP1–PP3 |
| 50 | Manual vs provider duplicate guard | 27.B.4, 5.9 | IG-P10, P17, E2E 54 |
| 51 | Settlement import & matching | 27.B.7 | IG-P19, DB cases, E2E 55 |
| 52 | Registers reconcile to bill totals | 28.B | IG-R1–R6, IG-SQL, E2E 57 |
| 53 | Tally voucher balances, no guessed ledgers | 28.B.5 | IG-T1–T4, TP1, E2E 58 |
| 54 | Legal fields format-checked, snapshot on bill | 28.A | DB cases, E2E 56 |
| 55 | Hindi bills, Indian grouping | 28.C | IG-I1–I6, E2E 59 |
| 56 | Data export / erasure / retention / audit | 28.D | DB cases, E2E 60 |
| 57 | Reports catalogue; every report reconciles to bills | 30.2 | RP1–RP9 SQL checks (14), E2E 66 |
| 58 | Loyalty earn / redeem / expire / refund | 30.3 | L1–L14, P1–P4, DB cases, E2E 61–63 |
| 59 | Payment-mode labels | 30.4 | DB cases, E2E 64 |
| 60 | Table reservations, no double-booking | 30.5 | DB cases, E2E 65 |
| 61 | Token numbers and ready display | 30.6 | DB cases, E2E 66 |
| 62 | Explicit out-of-scope list with reasons | 30.8 | review |

### 29.2 What has actually been verified so far, and what has not
**Verified (executed 23–27 Nov 2026, all from the final `Galla_Package`):**
- All seventeen migrations **V001–V017 apply in order to an empty PostgreSQL 16** (132 tables); an existing outlet's UPI ID migrates into `outlet_payment_accounts`.
- **848 database accept/reject cases pass** (`db_tests/run_db_tests.sh`): 9 core billing/payment · 27 Part II (V008–V010) · 27 WhatsApp (V011) · 71 offline (V012) · 231 billing extras (V013) · 217 inventory (V014) · 193 integrations/compliance (V015) · 5 cross-stream links (V016) · 68 loyalty, payment modes, reservations, tokens (V017) = **848**. The V012–V015 suites were also re-run **on the full V001–V016 chain** and give the same results; every FAIL case was checked to fail for its intended reason.
- Bill counter: 100 parallel connections → numbers `1…100`, no gaps, no duplicates (run earlier on V001–V007; the counter design did not change after that). **Not re-run for the V012 device-series counters under real concurrency.**
- **230 Python reference tests pass** (212 earlier + 18 loyalty) (`reference/`): billing vectors, property tests, extra charges, delivery charge, subscription, WhatsApp (W1–W12), offline (OF1–OF20), billing extras (BX), inventory (IN1–IN22 + properties), integrations/compliance (IG). **443 Node checks pass**: the JavaScript bill calculator reproduces all 424 golden bill vectors plus 18 device-rule cases exactly.
- UI colours: all 26 text/background pairs and control borders in 12.1 pass the WCAG contrast thresholds (`reference/contrast.py`).
- Count corrections made while merging: the WhatsApp migration has **27** cases (an earlier draft said 29); the stream sections below keep their own per-stream counts.
**Problems that testing found in my own earlier drafts, now fixed:** (1) "line order never changes totals" was false — fixed by canonical sorting (5.3 Step 0); (2) muted text and input borders failed contrast — tokens changed; (3) a subscription paid in advance during the trial was mishandled — fixed, tests S11/S12; (4) `must_change_password` missing from `users`, `bill_lines` unable to hold a delivery-charge line, outlet UPI fields unable to support several accounts — fixed in V008/V010; (5) a WhatsApp test wrongly assumed `1234567890` is an invalid Indian number — libphonenumber accepts it as a valid *non-mobile* number, so the design now warns ("not a mobile number") and asks the cashier to confirm instead of rejecting.
**Not verified (no code exists yet, or needs the real world):** the Java and React applications themselves; screen visuals; thermal printers; real UPI apps with a pre-filled amount; e-mail/SMS delivery; any payment gateway; GST/e-invoicing rules (Open Decision 1); performance targets; phone location behaviour; full axe audit. **WhatsApp specifically:** whether any official "is this number on WhatsApp" check exists (I found none; re-check Meta's docs), the webhook signature header name/format, the exact JSON for a document-header template message, how long uploaded media stays available, template approval and category outcome, India message rates and free-window rules, messaging-limit tiers, Embedded Signup requirements, DPDP/consent legal duties. **Domain/trademark:** availability of any "Galla" domain and trademark clearance were **not checked** (Open Decisions 17.20–17.21). Effort estimates in Section 16 are rough guesses, not measurements.
- **Final audit addendum (27 Nov 2026).** *Verified (executed 27 Nov 2026):* V017 applies after V001–V016 (132 tables); **68 accept/reject cases** as expected, each FAIL checked for its intended reason (balance −10 after a reversal, counter 1→2); **18 Python tests** (loyalty); **14 report checks** (RP1–RP9 figures, VOID excluded, filters, gate fires on a tampered line). *Not verified:* the Java/React implementation; the daily expiry job and the credit-note hooks (specified, not coded); concurrency of two terminals redeeming at once (the row lock is tested sequentially only); accounting treatment of the loyalty liability; WhatsApp reservation templates; report performance on large data (no indexes were tuned beyond the existing ones); offline token letters beyond the format check.
- **Offline mode (stream A, 23–26 Nov 2026).** *Verified (executed 24 Nov 2026):* V012 applies on PostgreSQL 16 after V001–V011 and over a database that already holds orders/bills (67 tables); **71 database accept/reject cases**; **20 Python reference tests OF1–OF20** incl. a hypothesis property test (300 random multi-terminal streams: any order/duplication → same final state, no gaps, nothing waiting), mutation-checked; **golden vectors: 424 bill cases + 18 device-rule cases, JS port reproduces all (443 checks, 0 failures)**; 418 order-independence checks. *Not verified:* any browser behaviour (IndexedDB eviction, `storage.persist()`, service-worker updates, background sync — **not relied upon**), loopback printing from an HTTPS page, real thermal printers offline, performance of Dexie with large queues, the TypeScript (not JS) build of the calculator and the Java port (only the JS port is tested), legal acceptability of one bill series per terminal, PBKDF2 parameters, whether `btree_gist` can be enabled on the chosen managed Postgres.
- **Everyday billing features (stream B, 23–26 Nov 2026).** *Verified (executed 25 Nov 2026):* V013 applies on PostgreSQL 16 after V001–V011 (and a fixture with an outlet pair); **231 accept/reject cases** each producing the intended error (the first run had 5 mismatches and 31 FAIL cases that failed for a wrong reason — missing ids in the test inserts — all fixed); **60 Python tests BX01–BX91** incl. hypothesis properties (combo sums, credit-note refund-everything = original, shift running sum, ledger balance/aging, KDS random walk); the 52 existing reference tests still pass. *Not verified:* legal rules for credit notes, NC tax, tips (Decisions 30–32); ESC/POS drawer kick on real drawers; barcode scanner timing (35 ms, 4 chars); browser sound autoplay; second-monitor behaviour of the customer display; concurrency behaviour under real load (modelled sequentially in SQL cases, to be tested with Testcontainers); the Java ports; UPI QR with tip amount in real UPI apps.
- **Inventory (stream C, 23–26 Nov 2026).** *Verified (executed 26 Nov 2026):* V014 applies on PostgreSQL 16 after V001–V011 (with `btree_gist`); **217 database accept/reject cases**, every FAIL case checked for its intended error message; **30 Python tests** (IN1–IN22 + 8 hypothesis properties: ledger sum = on-hand, weighted average within purchase range, consumption/reversal exactness, idempotent replay, exact unit round-trips, cycle detector vs brute force); the no-divergence query returns zero rows after all DB scenarios. *Not verified:* the Java implementation; consumption triggering from the real billing code (the DB provides only idempotency anchors; the savepoint design is untested); behaviour under 50+ concurrent bills; Postgres performance at scale; whether `btree_gist` is available on the chosen managed Postgres; stock count behaviour with movements during counting (documented limitation); any accounting/tax treatment of stock valuation, vendor GST or freight (deliberately not interpreted); interface with combos/credit notes (not yet built); e-mail/PDF rendering of the Stock block.
- **Integrations & compliance (stream D, 23–26 Nov 2026).** **Verified:** aggregator inbox state machine and rules (15 python tests); payment-intent resolver incl. property tests (22 tests); register reconciliation (6 tests, random bills) and register SQL on PostgreSQL 16; Tally voucher balancing (5 tests); Indian grouping (2 tests); V015 (193 DB cases, all as expected). Python total for stream D: 50 tests. **Read from official sources (applicability not verified):** FSSAI 14-digit licence number on bills (order of 8 June 2021, enforcement from 1 Jan 2022); DPDP Rules notification date 14 Nov 2025 with 18-month phased compliance; Tally XML structure (sample page). **Not verified:** every aggregator and gateway API/approval/fee/deadline; Tally import on a real installation; GSTIN checksum; HSN digits; e-invoice thresholds; composition rules; mandatory invoice fields; retention periods; DPDP duties; Devanagari raster on real printers; font licences; RPO/RTO feasibility.

### 29.3 Assumptions I made (change any of them)
1. "Revenue partner" = delivery/order partner (Section 20) — please confirm.
2. Trial = 30 × 24 hours from onboarding; grace = 7 days; both configurable.
3. Restaurants are onboarded by invite (no self-signup in v1).
4. After grace, a subscription goes **read-only + settle**, not lock-out.
5. `INVENTORY` role has the rights listed in Appendix A2 (menu availability plus the inventory module of Section 26, no billing, no count approvals, no settings).
6. Subscription fees are collected and recorded manually in v1.
7. Ticket auto-close/reopen windows (7 days) and the 5-tickets/hour limit are my defaults.
8. Distance = straight line × configurable factor; no road routing in v1.
9. WhatsApp: each restaurant brings its **own** WhatsApp Business number and pays Meta directly (17.17); consent is captured by the cashier at the counter; messages are template-based utility messages, never promotions.
10. "If the number is linked to WhatsApp" is implemented as try-send → webhook status → fallback, because no official pre-check is known (23.1).
11. Offline billing is per terminal; no LAN sync in v1.
12. Each billing terminal is registered and has its own bill series.
13. Offline sessions last up to 72 hours (configurable).
14. One discount per bill (manual, coupon or NC).
15. A refund after the sale is a credit note; void is for mistakes.
16. Catalog is per outlet; the central menu copies and syncs.
17. Tips are outside the bill and untaxed.
18. `payments.shift_id` is NULL for payments created offline unless the terminal had a local shift (open point for the implementer; Section 25 interface note in 4.8).
19. Costing is moving weighted average, operational not statutory.
20. No expiry/batch tracking in v1.
21. Billing never waits for inventory.
22. Galla's menu price and tax profile always win over an aggregator's reported totals.
23. `accept_sla_seconds = 180`, `INTENT_DEFAULT_EXPIRY_MINUTES = 10`, export-link TTL, retention numbers and the 30-day data-request due date are placeholders to be replaced from provider documentation and legal advice.
24. Erasure means anonymising the customer record while keeping bills.
25. A bill's rate for registers = sum of its tax-component rates on that line.

### 29.4 Handing this to an AI coding agent
Give the agent: this file, the `reference/` folder (executable spec for billing, delivery charge, subscription rules) and the `migrations/` folder (V001–V017, verified). First instruction: *"Read the whole plan. Implement Phase 0, then Phase 1S, then Phase 1 in the order of Section 16 (later phases only when asked; WhatsApp is Phase 2W). Write each rule's tests from the reference vectors before the code. Do not invent features; record questions in `docs/OPEN_QUESTIONS.md`. Stop at the end of each phase and show the acceptance results."* Build one phase at a time — a single prompt for the whole product will not produce a reliable result.

### 29.5 Migration V016 — cross-stream links *(verified: 5 cases, plus every suite re-run on the full chain)*
V012–V015 were designed in parallel, so references between their tables were left as plain `uuid` columns. After applying all of them, a catalogue query listed every `*_id` uuid column without a foreign key: only **`cashier_shifts.device_id` → `devices`** needed a real key; the rest are polymorphic by design (explained in the SQL comments).
```sql
-- V016 — cross-stream links that could not be declared while V012–V015 were written independently
-- Only one real soft reference remained: cashier_shifts.device_id (V013) -> devices (V012).
-- The remaining uuid columns without a foreign key are polymorphic by design and stay that way:
--   audit_logs.entity ids, print_jobs.ref_id, stock_movements.ref_id (+ ref_type), recipes.target_id (+ target kind),
--   sync_commands.aggregate_id / command_id / depends_on_command_id, sync_conflicts.command_id (client-generated ids),
--   stock_adjustments.movement_id (written in the same transaction as the movement), idempotency_keys.user_id, *.family_id (token families).
ALTER TABLE cashier_shifts
  ADD CONSTRAINT cashier_shifts_device_id_fkey FOREIGN KEY (device_id) REFERENCES devices(id);

CREATE FUNCTION fn_shift_device_same_outlet() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d_outlet uuid;
BEGIN
  IF NEW.device_id IS NOT NULL THEN
    SELECT outlet_id INTO d_outlet FROM devices WHERE id = NEW.device_id;
    IF d_outlet <> NEW.outlet_id THEN
      RAISE EXCEPTION 'SHIFT_DEVICE_OTHER_OUTLET' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_shift_device_same_outlet BEFORE INSERT OR UPDATE OF device_id, outlet_id ON cashier_shifts
  FOR EACH ROW EXECUTE FUNCTION fn_shift_device_same_outlet();
```
Constraint cases that passed: shift on an existing device of the same outlet; shift on a device that does not exist (foreign key); device of another outlet (`SHIFT_DEVICE_OTHER_OUTLET`); deleting a device that still has a shift (rejected); shift without a device for an online-only terminal.

---

## 30. FINAL AUDIT ADDENDUM — reports catalogue, loyalty, payment-mode labels, reservations, token numbers, and what is deliberately NOT built *(added in v1.4)*

### 30.1 Why this section exists, and how the audit was done
The owner asked for a last, careful check that no major feature of a restaurant billing product is missing. The check was done by listing what a restaurant does in a day (open, take orders, bill, collect money, close, report, buy stock, serve customers, follow the law) and what Petpooja-class products advertise, then looking up each item in Sections 1–29 and the traceability matrix (29.1). **Result: the core was complete; six gaps were found and are closed here; seven things are consciously left out, with reasons (30.8).**

| # | Gap found | Closed by |
|---|---|---|
| G1 | Only a few reports existed (daily, items, payments, discounts, voids, hourly) — no category-wise, order-type-wise, cashier-wise, table-wise, customer, multi-outlet or trend report, and no single list of all reports | 30.2 (RP1–RP9, SQL tested) |
| G2 | Loyalty/CRM was "later" although repeat-customer rewards are a standard counter feature | 30.3 (V017) |
| G3 | Payment modes were fixed (CASH/CARD/UPI/OTHER); restaurants want "Paytm", "PhonePe", "Sodexo" in reports | 30.4 (V017) |
| G4 | No table reservations | 30.5 (V017) |
| G5 | No token numbers for counter/takeaway orders and no "order ready" display | 30.6 (V017) |
| G6 | Out-of-scope list was scattered and partly contradictory (loyalty and reservations were listed as out of scope) | 30.8 and edits to 1.2 / 17 |

Nothing in this section changes an existing rule. Money rules (strings, `BigDecimal`, largest-remainder), tenant scoping (404 on cross-tenant), idempotency keys, audit logging, optimistic locking and the error model apply unchanged.

### 30.2 Reports catalogue
All reports: filters date range (business date, restaurant time zone) + outlet (OWNER may choose *All outlets*); every report has **Export CSV** and prints on A4; **VOID bills are excluded everywhere**; "net sales" = sum of `bill_lines.taxable_amount` (after discount, before tax). **Every report must reconcile to the bills it is drawn from**; the export is refused with `REPORT_NOT_RECONCILED` (500, logged, alerts the developer) if the gate query RP9 returns a row. Roles: O = Owner, M = Manager, A = Accountant (read-only), C = Cashier (own shift only where marked).

| Group | Report | Roles | Defined in |
|---|---|---|---|
| Sales | Daily summary · Hourly sales · Items sold · Discounts given · Voids & cancellations | O M A | 5.10, 6, S11 (existing) |
| Sales | **RP1 Category-wise** (open items shown as "Open items", lines without a category as "Uncategorised"; nothing is dropped) | O M A | 30.2 |
| Sales | **RP2 Order-type / source-wise** (dine-in, takeaway, delivery; partner orders split by partner name) | O M A | 30.2 |
| Sales | **RP3 Cashier-wise** (bills, discount, grand total by the user who generated the bill) | O M | 30.2 |
| Sales | **RP4 Table-wise** (bills, covers, average bill) | O M | 30.2 |
| Sales | **RP6 Consolidated multi-outlet** (per outlet and day with an *ALL* total row) | O A | 30.2 |
| Sales | **RP7 Monthly trend** with growth % over the previous month (first month shows "—") | O A | 30.2 |
| Money | Payments by method · **RP8 Payments by mode label** · Tips · Shift report · Cash in/out · Day closing | O M A (C own shift) | 5.8, 25, 30.2 |
| Money | Credit sales, dues and aging · Coupon usage · Credit notes · NC (complimentary) bills | O M A | 25 |
| Delivery | Delivery report, partner payouts, orders vs payouts reconciliation, gateway settlements | O M A | 11, 27 |
| Customers | **RP5 Customer insights** (visits, spend, average bill, last visit) · Loyalty balances and liability (30.3) · WhatsApp usage | O M | 23, 30.2, 30.3 |
| Stock | Stock on hand, movements, valuation, low stock, consumption vs sales, wastage, variance, payables aging | O M A | 26.10 |
| Compliance | GST/tax register, HSN summary, bill & credit-note registers, Tally/CSV export, audit log | O A | 28.B |
| Platform (Super admin) | Restaurants, plans, trials, MRR, support, feedback | S | 18 |
| Control | **RP9 Reconciliation gate** (not shown to users) | system | 30.2 |

**Report SQL (verified).** The nine queries are in `reference/reports.sql`. They were run on PostgreSQL 16 after V001–V017 on a fixture with two outlets, two cashiers, a VOID bill, a partner order, a December bill (for growth), a customer, a table and a payment-mode label. Result: **14 of 14 checks pass** — each report equals the hand-calculated figures; the VOID bill never appears; date and outlet filters isolate correctly; RP9 returns zero rows on good data and exactly one row after a bill line was altered by 1.00 (and zero again after restoring it).
The rules the queries embody (an implementer must keep them when porting to JPA/jOOQ):
1. Join `bills → orders` for `business_date`, `order_type`, `order_source`, `table_id`, `customer_id`; filter `bills.status <> 'VOID'`.
2. Count only `bill_lines.active` rows; item totals use `line_type = 'ITEM'`; charges (service, packaging, delivery, tip lines) are separate and **never inside a category**.
3. RP9 recomputes `grand_total = Σ(ITEM taxable+tax) + Σ(non-ITEM taxable+tax) + Σ round_off` and compares it with `Σ bills.grand_total` for the same filter.
4. Rows are sorted by amount (largest first) then by name, so the output is stable between runs.
5. RP6 uses `GROUP BY ROLLUP (outlet, business_date)`; RP7 uses `lag()` and returns NULL growth when the previous month is 0 or missing.
6. RP8 shows `payment_modes.label` when the payment has one, otherwise the base method; only `payments.status = 'SUCCESS'`.

**API.** `GET /reports/{key}?from=&to=&outlet_id=&format=json|csv` with `key ∈ category, order-type, cashier, table, customers, consolidated, trend, payment-modes` (plus the existing keys). Error codes: `REPORT_RANGE_TOO_LARGE` (400, more than 366 days), `REPORT_NOT_RECONCILED` (500), `NOT_FOUND` (an outlet of another tenant). Screen: S11 gets a left list grouped as in the table above, with the filter bar and the *Export CSV* button; **empty state** "No sales in this period — change the dates" (never a blank screen).

### 30.3 Loyalty points and customer list (CRM-lite)
**Scope.** Points earned on paid bills and spent on later bills. Not built: marketing campaigns, SMS blasts, tiers, birthday offers, referral schemes (30.8). Off by default (`loyalty_programs.enabled = false`); Owner enables it in *Settings → Loyalty* (S45).

**Settings (per restaurant, table `loyalty_programs`):** `spend_per_point` (default ₹100 → 1 point), `earn_on` (`GRAND_TOTAL` or `TAXABLE_VALUE`), `rupees_per_point` (default ₹1), `min_redeem_points` (default 100), `max_redeem_percent` of the bill (default 50), `expiry_days` (30–3650 or none).

**Rules (executable in `reference/loyalty.py`; 18 tests pass, incl. properties):**
1. **Earn** = `floor(amount ÷ spend_per_point)` where `amount` is the bill's `grand_total` (or taxable value). Earned once per bill, when the bill becomes PAID and has a customer. A bill without a customer earns nothing (the cashier may attach a customer later only before payment).
2. **Redeem** is a **tender**, not a discount: `payments.method = 'LOYALTY'`, `loyalty_points = n`, `amount = n × rupees_per_point` (2 decimals, half-up). Because it is a payment, taxes and the bill total are untouched and the GST register still shows the full taxable value. One redemption per bill.
3. **Limits:** points ≤ spendable balance; amount ≤ `max_redeem_percent` × bill total; amount never above the bill; at least `min_redeem_points` (else not allowed). The screen offers the largest allowed number and the cashier may lower it.
4. **Spendable = balance − points that have expired and are unspent.** The daily job writes an `EXPIRE` entry for those. Spending is FIFO (batches that expire first are used first) and a batch already expired at that moment cannot be spent.
5. **Refunds follow credit notes:** earned points are reversed so that *earned − reversed = what the remaining net amount would earn* (never below 0, never more than earned); redeemed points are restored in proportion to the loyalty-paid amount refunded, exactly all on a full refund. Each credit note writes each kind of entry at most once.
6. **The ledger is append-only.** Balance = `SUM(points)`. The database trigger locks the customer row and rejects a `REDEEM`/`EXPIRE` that would take the balance below 0 (`LOYALTY_INSUFFICIENT_POINTS`), so two terminals cannot spend the same points. A `REVERSE_EARN` (refund) may take the balance below 0 when the customer already spent the points; later earnings repay it. Manual `ADJUST` needs a reason and a user (Manager PIN above 500 points, decision 61).
7. **Offline:** loyalty is **online only** — a terminal that is offline shows "Points need internet" and bills normally; earn is credited when the bill syncs (the earn is idempotent per bill). Redemption is not offered offline, so points can never be spent twice.
8. **Customer list:** search by phone or name, merged duplicates are not supported in v1; shows visits, spend, last visit, balance and dues. WhatsApp is sent only with the consent already defined in Section 23; **no promotional messages**.

**API** (roles: O/M manage; C read balance and redeem): `GET/PUT /loyalty/program`; `GET /customers/{id}/loyalty` (balance, spendable, expiring in 30 days, last 50 entries); `POST /bills/{id}/loyalty/redeem {points}` (idempotent; creates the LOYALTY payment); `POST /customers/{id}/loyalty/adjust {points, reason}`; `GET /reports/loyalty` (balances and the liability = Σ spendable × `rupees_per_point`). Errors: `LOYALTY_DISABLED` 409, `LOYALTY_INSUFFICIENT_POINTS` 409, `LOYALTY_BELOW_MINIMUM` 422, `LOYALTY_OVER_CAP` 422, `LOYALTY_CUSTOMER_REQUIRED` 422, `LOYALTY_OFFLINE` 409.

### 30.4 Payment-mode labels
A restaurant may define labels such as "Paytm", "PhonePe", "Sodexo", "Zomato Pay" in *Settings → Payment modes*. Each label has a **base method** (CASH, CARD, UPI, OTHER), an optional outlet (none = all outlets), a sort order and an active flag. A payment stores `payment_mode_id` next to its base method, so **all money rules stay on the base method** (cash drawer = CASH only; UPI QR rules = UPI) and only the reports (RP8) and the bill print show the label. Database rules: same tenant/outlet (`PAYMENT_MODE_OTHER_OUTLET`), label's base method equals the payment's (`PAYMENT_MODE_METHOD_MISMATCH`), inactive labels cannot be used (`PAYMENT_MODE_INACTIVE`), labels are unique per tenant+outlet ignoring case and spaces. Deactivating a label never changes old payments. `LOYALTY` and `ON_ACCOUNT` cannot have labels. API: `GET/POST/PATCH /payment-modes` (O/M).

### 30.5 Table reservations
**Scope.** A booking list for dine-in tables: guest name, phone, party size, date-time, duration (default 90 min), optional table, notes, source (staff, phone, walk-in waitlist). Not built: customer-facing online booking (30.8).
**Rules.** Statuses `BOOKED → CONFIRMED → SEATED → COMPLETED`, or `CANCELLED` (reason required) or `NO_SHOW`. **A table cannot be promised to two parties at overlapping times** — enforced by an exclusion constraint on `(table_id, time range)` for BOOKED/CONFIRMED/SEATED (`RESERVATION_OVERLAP`, 409). Touching times (one ends when the next starts) are allowed. The table must belong to the same outlet. Reservations without a table are allowed (the manager assigns one later). **Seat** = create or open the table's order, link `seated_order_id`, set `seated_at`; if the table already has an open order it is refused with `TABLE_BUSY`. A booking is shown on the floor plan (S2) as a clock badge from 30 minutes before its time. After 30 minutes past the time (setting) the manager is prompted "Mark no-show?" — never automatic. A WhatsApp confirmation or reminder is sent only when the guest consented (Section 23 consent rules) and only as a **transactional** template (decision 62: template approval is not verified). Reservations are **online only** (offline terminals can see the last synced list read-only).
**API** (O/M/C): `GET /reservations?date=&status=`; `POST /reservations`; `PATCH /reservations/{id}` (with `version`); `POST /reservations/{id}/seat | cancel | no-show | complete`. Errors: `RESERVATION_OVERLAP` 409, `RESERVATION_TABLE_OTHER_OUTLET` 422, `RESERVATION_IN_PAST` 422 (staff may override with a reason), `RESERVATION_INVALID_STATE` 409.

### 30.6 Token numbers and the "order ready" display
Counter outlets give each takeaway/delivery order a short **token** (`outlets.token_mode`: `OFF`, `TAKEAWAY_DELIVERY`, `ALL`). Token = numeric counter per outlet per business date (1…99999, restarts every day, row-locked counter `token_counters`) shown on the KOT and the bill; unique per outlet per day. **Offline terminals** use their device letter + local counter (e.g. `A14`), so tokens never clash with online ones. The kitchen display (S24) gets *Ready*; the customer display (Section 25) can show *Now ready: 14, 15, A3* (updated through the existing SSE stream). Not built: SMS/voice calling of tokens, hardware token displays (30.8).

### 30.7 Screens, security, permissions
New screens: **S41** Reservations (day list + floor plan overlay) · **S42** Customers & loyalty (list, detail, ledger, adjust) · **S43** Payment modes (settings) · **S44** Reports hub (extends S11) · **S45** Loyalty settings. All have loading, empty ("No reservations today"), error (retry) and offline states, follow Section 12.2 tokens (contrast ≥ 4.5:1 checked by `contrast.py`) and the never-blank-screen rule of Section 22.
Permissions (add to Appendix A2): Owner — all; Manager — all except changing the loyalty rates; Cashier — see/seat/create reservations, read customer balance, redeem; Accountant — read reports and the loyalty liability; Kitchen — token/ready only. Every state change is audit-logged (`LOYALTY_*`, `RESERVATION_*`, `PAYMENT_MODE_*`). The loyalty ledger and the report SQL are tenant-scoped (cross-tenant access returns 404; DB case `LOYALTY_CROSS_TENANT`).

### 30.8 Deliberately NOT built (with reasons) — so nobody has to wonder
| Not built | Reason | If the owner later wants it |
|---|---|---|
| Customer scan-and-order (QR menu ordering), website/app builder, self-service kiosk | Needs a public ordering surface, online payment at order time, abuse protection and a menu-availability guarantee; a separate product risk. Aggregator orders **are** received (Section 27.A). | New phase after launch; reuse the order API with a public, rate-limited channel |
| Marketing campaigns, bulk SMS/WhatsApp promotions, birthday offers, tiers, referrals | Promotional WhatsApp is excluded by design (Section 23: consent/ban risk); SMS needs DLT registration in India (not verified) | Add after the DLT/Meta rules are checked |
| Gift cards and stored-value wallet | Stored value is a liability with possible regulatory rules (not verified) | Needs legal advice first |
| Payroll, attendance, staff scheduling | Different domain; a restaurant already has payroll tools | Export shift data (exists) |
| Caller-ID / calling device integration | Needs hardware per restaurant | Generic webhook can post an order |
| 150+ marketplace integrations | Impossible to verify; each has its own API and approval | **Generic inbound/outbound webhooks** (Section 27) plus CSV; add named integrations one by one |
| Native mobile apps (customer or captain) | The PWA covers phones; native wrapper listed as later (Section 16) | Wrap the PWA |
Other existing exclusions stay as stated in 1.2 and Section 29.2 (e-invoicing, GST return filing, automatic gateway refunds, on-premise LAN relay).

### 30.9 Tests added
- **Database:** 68 accept/reject cases on the full chain V001–V017 (`db_tests/t017.sql`): loyalty program limits; earn once per bill; redeem/expire cannot take the balance below 0 (and the balance is not changed by the failed attempt); append-only ledger (UPDATE/DELETE rejected); cross-tenant customer rejected; one credit-note entry per kind; LOYALTY tender shape (needs customer and points, no tender/change/tip); payment-mode tenant/outlet/method/inactive/unique rules; reservation overlap, touching times allowed, cancelled booking frees the table, `reserved_until` must equal start + duration, table of another outlet rejected, phone format; token format, uniqueness per outlet and day, counter bounds. Every FAIL case was checked to fail for its intended reason.
- **Python reference:** `reference/loyalty.py` with 18 tests L1–L14 and properties P1–P4 (redemption never exceeds bill or cap; cumulative refunds keep earned = net; restore never exceeds redeemed and a full refund restores all; expiring never exceeds balance).
- **Reports:** `reference/reports.sql`, `reference/reports_fx.sql`, `reference/run_reports_test.py`: 14 checks (above).
- **Java/TypeScript:** implementers port `loyalty.py` and write the same cases; CI must fail if the gate RP9 is not called by every export.

**New end-to-end scenarios**
61. Enable loyalty; bill ₹1,250 with a customer → 12 points earned; next bill ₹300 → redeem 100 points (₹100 tender, taxes unchanged), pay the rest in cash; balances correct.
62. Full credit note on a bill that earned and redeemed points → earned reversed, redeemed restored; balance equals the starting balance.
63. Two terminals redeem the same points at once → exactly one succeeds, the other shows `LOYALTY_INSUFFICIENT_POINTS`.
64. Create the label "Paytm" (UPI); pay a bill with it → RP8 shows "Paytm"; the drawer total is unchanged; trying a CASH payment with it is refused.
65. Book table T5 at 20:00 for 90 min; a second booking at 20:30 is refused; at 21:30 it is accepted; seat the first → order linked; cancel without a reason is refused.
66. Token mode on: three takeaway orders get 1, 2, 3; the next day restarts at 1; an offline terminal issues `A1`; the ready display shows the order when the kitchen marks it Ready; every report in 30.2 exports and RP9 returns nothing.

### 30.10 Build phase
**Phase 5 (later, after launch, ≈ 2 weeks):** V017 → RP1–RP9 + gate + CSV → payment-mode labels → loyalty (settings, earn, redeem tender, credit-note hooks, daily expiry job, S42/S45) → reservations (S41) → token numbers + ready display → permission rows, audit, E2E 61–66. *Phase 2 may already add RP1–RP9 and payment-mode labels because they need no new product decisions.* **Accept when:** all 68 database cases and the 18 reference tests pass in CI, every report reconciles (RP9 empty), E2E 61–66 pass.

### 30.11 Open decisions raised here
60. Is the loyalty liability (unspent points) an accounting item for the restaurant? *(Ask an accountant; the report gives the number only.)*
61. Manager-PIN threshold for manual loyalty adjustment (proposal 500 points).
62. Whether reservation confirmations may be sent as WhatsApp utility templates (Meta approval not verified).
63. Whether several bill series, per-terminal tokens and loyalty on the same bill are acceptable to the restaurant's tax adviser (Decision list 29.3 already holds the series question).
64. Token reset time: at business-date change (default) or at a fixed hour.

### 30.12 Migration V017 *(verified on PostgreSQL 16 on top of V001–V016: 132 tables, 68 accept/reject cases as expected)*
```sql
-- V017 — final-audit additions: loyalty points, payment-mode labels, table reservations, token labels
-- Applies on top of V001..V016 (needs btree_gist, created in V012).

-- ===== 1. Loyalty =====
CREATE TABLE loyalty_programs (
  tenant_id uuid PRIMARY KEY REFERENCES tenants(id),
  enabled boolean NOT NULL DEFAULT false,
  spend_per_point numeric(12,2) NOT NULL DEFAULT 100 CHECK (spend_per_point > 0),      -- earn 1 point per this many rupees
  earn_on text NOT NULL DEFAULT 'GRAND_TOTAL' CHECK (earn_on IN ('GRAND_TOTAL','TAXABLE_VALUE')),
  rupees_per_point numeric(12,4) NOT NULL DEFAULT 1 CHECK (rupees_per_point > 0),      -- value of one point when redeemed
  min_redeem_points int NOT NULL DEFAULT 100 CHECK (min_redeem_points >= 0),
  max_redeem_percent numeric(5,2) NOT NULL DEFAULT 50 CHECK (max_redeem_percent BETWEEN 1 AND 100),
  expiry_days int CHECK (expiry_days IS NULL OR expiry_days BETWEEN 30 AND 3650),      -- NULL = points never expire
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);

CREATE TABLE loyalty_ledger (                      -- append-only; balance = SUM(points) per customer
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  customer_id uuid NOT NULL REFERENCES customers(id),
  outlet_id uuid REFERENCES outlets(id),
  entry_type text NOT NULL CHECK (entry_type IN ('EARN','REDEEM','REVERSE_EARN','RESTORE_REDEEM','ADJUST','EXPIRE')),
  points int NOT NULL CHECK (points <> 0),
  bill_id uuid REFERENCES bills(id),
  credit_note_id uuid REFERENCES credit_notes(id),
  expires_at timestamptz,                          -- only on EARN
  reason text,
  created_by uuid REFERENCES users(id),            -- NULL for system entries (earn, expire)
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((entry_type IN ('EARN','RESTORE_REDEEM') AND points > 0)
      OR (entry_type IN ('REDEEM','REVERSE_EARN','EXPIRE') AND points < 0)
      OR entry_type = 'ADJUST'),
  CHECK (entry_type NOT IN ('EARN','REDEEM') OR bill_id IS NOT NULL),
  CHECK (entry_type NOT IN ('REVERSE_EARN','RESTORE_REDEEM') OR credit_note_id IS NOT NULL OR bill_id IS NOT NULL),
  CHECK (entry_type <> 'ADJUST' OR (reason IS NOT NULL AND length(btrim(reason)) > 0 AND created_by IS NOT NULL)),
  CHECK (expires_at IS NULL OR entry_type = 'EARN')
);
CREATE UNIQUE INDEX ux_loyalty_one_earn_per_bill   ON loyalty_ledger(bill_id) WHERE entry_type = 'EARN';
CREATE UNIQUE INDEX ux_loyalty_one_redeem_per_bill ON loyalty_ledger(bill_id) WHERE entry_type = 'REDEEM';
CREATE UNIQUE INDEX ux_loyalty_cn_once ON loyalty_ledger(credit_note_id, entry_type) WHERE credit_note_id IS NOT NULL;
CREATE INDEX ix_loyalty_customer ON loyalty_ledger(customer_id, created_at);

CREATE FUNCTION fn_loyalty_ledger_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE bal bigint; c_tenant uuid;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN
    RAISE EXCEPTION 'LOYALTY_LEDGER_APPEND_ONLY' USING ERRCODE = '23514';
  END IF;
  -- lock the customer row so two terminals cannot spend the same points
  SELECT tenant_id INTO c_tenant FROM customers WHERE id = NEW.customer_id FOR UPDATE;
  IF c_tenant <> NEW.tenant_id THEN RAISE EXCEPTION 'LOYALTY_CROSS_TENANT' USING ERRCODE = '23514'; END IF;
  IF NEW.entry_type IN ('REDEEM','EXPIRE') THEN
    SELECT COALESCE(SUM(points),0) INTO bal FROM loyalty_ledger WHERE customer_id = NEW.customer_id;
    IF bal + NEW.points < 0 THEN RAISE EXCEPTION 'LOYALTY_INSUFFICIENT_POINTS' USING ERRCODE = '23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_loyalty_ledger_guard BEFORE INSERT OR UPDATE OR DELETE ON loyalty_ledger
  FOR EACH ROW EXECUTE FUNCTION fn_loyalty_ledger_guard();

-- redemption is a tender (not a discount): payments.method = 'LOYALTY' with the points that were spent
ALTER TABLE payments DROP CONSTRAINT payments_method_check;
ALTER TABLE payments ADD CONSTRAINT payments_method_check CHECK (method IN ('CASH','CARD','UPI','OTHER','ON_ACCOUNT','LOYALTY'));
ALTER TABLE payments ADD COLUMN loyalty_points int CHECK (loyalty_points IS NULL OR loyalty_points > 0);
ALTER TABLE payments ADD CONSTRAINT payments_loyalty_shape CHECK (
  (method = 'LOYALTY') = (loyalty_points IS NOT NULL)
  AND (method <> 'LOYALTY' OR (customer_id IS NOT NULL AND tendered_amount IS NULL AND change_amount IS NULL AND tip_amount = 0)));

-- ===== 2. Payment-mode labels (Paytm, PhonePe, Zomato Pay, Sodexo ... chosen by the restaurant) =====
CREATE TABLE payment_modes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),           -- NULL = every outlet of the tenant
  label text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 40),
  base_method text NOT NULL CHECK (base_method IN ('CASH','CARD','UPI','OTHER')),
  sort_order int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_payment_modes_label ON payment_modes(tenant_id, COALESCE(outlet_id,'00000000-0000-0000-0000-000000000000'::uuid), lower(btrim(label)));
ALTER TABLE payments ADD COLUMN payment_mode_id uuid REFERENCES payment_modes(id);
CREATE FUNCTION fn_payment_mode_matches() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pm payment_modes%ROWTYPE;
BEGIN
  IF NEW.payment_mode_id IS NOT NULL THEN
    SELECT * INTO pm FROM payment_modes WHERE id = NEW.payment_mode_id;
    IF pm.tenant_id <> NEW.tenant_id OR (pm.outlet_id IS NOT NULL AND pm.outlet_id <> NEW.outlet_id) THEN
      RAISE EXCEPTION 'PAYMENT_MODE_OTHER_OUTLET' USING ERRCODE = '23514'; END IF;
    IF pm.base_method <> NEW.method THEN RAISE EXCEPTION 'PAYMENT_MODE_METHOD_MISMATCH' USING ERRCODE = '23514'; END IF;
    IF NOT pm.active THEN RAISE EXCEPTION 'PAYMENT_MODE_INACTIVE' USING ERRCODE = '23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_payment_mode_matches BEFORE INSERT ON payments FOR EACH ROW EXECUTE FUNCTION fn_payment_mode_matches();

-- ===== 3. Table reservations =====
CREATE TABLE reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  customer_id uuid REFERENCES customers(id),
  guest_name text NOT NULL CHECK (length(btrim(guest_name)) > 0),
  guest_phone text CHECK (guest_phone IS NULL OR guest_phone ~ '^\+?[0-9]{7,15}$'),
  party_size int NOT NULL CHECK (party_size BETWEEN 1 AND 100),
  table_id uuid REFERENCES dining_tables(id),
  reserved_for timestamptz NOT NULL,
  duration_minutes int NOT NULL DEFAULT 90 CHECK (duration_minutes BETWEEN 15 AND 480),
  reserved_until timestamptz NOT NULL,             -- = reserved_for + duration; stored so the overlap rule can be an index (timestamptz arithmetic is not immutable)
  status text NOT NULL DEFAULT 'BOOKED' CHECK (status IN ('BOOKED','CONFIRMED','SEATED','COMPLETED','CANCELLED','NO_SHOW')),
  source text NOT NULL DEFAULT 'STAFF' CHECK (source IN ('STAFF','PHONE','WALK_IN_WAITLIST')),
  notes text,
  seated_at timestamptz,
  seated_order_id uuid REFERENCES orders(id),
  cancel_reason text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0,
  CHECK (reserved_until = reserved_for + make_interval(mins => duration_minutes)),
  CHECK (status NOT IN ('SEATED','COMPLETED') OR seated_at IS NOT NULL),
  CHECK (status <> 'CANCELLED' OR (cancel_reason IS NOT NULL AND length(btrim(cancel_reason)) > 0)),
  -- a table cannot be promised to two parties at overlapping times
  EXCLUDE USING gist (table_id WITH =, tstzrange(reserved_for, reserved_until) WITH &&)
    WHERE (table_id IS NOT NULL AND status IN ('BOOKED','CONFIRMED','SEATED'))
);
CREATE INDEX ix_reservations_outlet_time ON reservations(outlet_id, reserved_for);
CREATE FUNCTION fn_reservation_table_outlet() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t_outlet uuid;
BEGIN
  IF NEW.table_id IS NOT NULL THEN
    SELECT outlet_id INTO t_outlet FROM dining_tables WHERE id = NEW.table_id;
    IF t_outlet <> NEW.outlet_id THEN RAISE EXCEPTION 'RESERVATION_TABLE_OTHER_OUTLET' USING ERRCODE = '23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_reservation_table_outlet BEFORE INSERT OR UPDATE OF table_id, outlet_id ON reservations
  FOR EACH ROW EXECUTE FUNCTION fn_reservation_table_outlet();

-- ===== 4. Token labels for counter orders (takeaway / delivery); offline terminals use their device letter, e.g. 'A14' =====
ALTER TABLE outlets ADD COLUMN token_mode text NOT NULL DEFAULT 'OFF' CHECK (token_mode IN ('OFF','TAKEAWAY_DELIVERY','ALL'));
ALTER TABLE orders ADD COLUMN token_label text CHECK (token_label IS NULL OR token_label ~ '^[A-Z]{0,3}[0-9]{1,5}$');
CREATE UNIQUE INDEX ux_orders_token_per_day ON orders(outlet_id, business_date, token_label) WHERE token_label IS NOT NULL;
CREATE TABLE token_counters (
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  business_date date NOT NULL,
  last_no int NOT NULL DEFAULT 0 CHECK (last_no >= 0 AND last_no <= 99999),
  PRIMARY KEY (outlet_id, business_date)
);
```
