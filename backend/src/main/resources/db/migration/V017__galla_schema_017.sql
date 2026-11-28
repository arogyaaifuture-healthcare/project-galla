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
