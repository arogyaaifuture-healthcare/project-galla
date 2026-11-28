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
