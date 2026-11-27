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
