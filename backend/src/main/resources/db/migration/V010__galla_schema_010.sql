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
