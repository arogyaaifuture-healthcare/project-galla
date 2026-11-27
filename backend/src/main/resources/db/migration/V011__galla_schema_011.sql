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
