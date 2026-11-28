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
