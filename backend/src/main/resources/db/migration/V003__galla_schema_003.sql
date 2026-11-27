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
