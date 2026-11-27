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
