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
