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
