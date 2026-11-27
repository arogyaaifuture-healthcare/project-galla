-- V008 — platform (SaaS) layer: platform users, plans, subscriptions, invoices, support access
CREATE TABLE platform_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  password_hash text NOT NULL,
  full_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('SUPER_ADMIN','SUPPORT')),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DISABLED')),
  failed_login_attempts int NOT NULL DEFAULT 0,
  locked_until timestamptz,
  last_login_at timestamptz,
  totp_secret_encrypted text,                   -- AES-GCM encrypted with TOTP_ENCRYPTION_KEY; 2FA is mandatory for platform users before production (Phase 4)
  totp_enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX ux_platform_users_email ON platform_users (lower(email));

CREATE TABLE platform_refresh_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  platform_user_id uuid NOT NULL REFERENCES platform_users(id) ON DELETE CASCADE,
  family_id uuid NOT NULL,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  replaced_by uuid,
  user_agent text, ip text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,
  currency_code char(3) NOT NULL,
  price_monthly numeric(12,2) NOT NULL CHECK (price_monthly >= 0),
  price_yearly numeric(12,2) NOT NULL CHECK (price_yearly >= 0),
  trial_days int NOT NULL DEFAULT 30 CHECK (trial_days BETWEEN 0 AND 365),
  max_outlets int NOT NULL CHECK (max_outlets >= 1),
  max_users int NOT NULL CHECK (max_users >= 1),
  role_limits jsonb NOT NULL DEFAULT '{}',      -- e.g. {"CASHIER":3,"CAPTAIN":10}; role absent = only max_users applies
  features jsonb NOT NULL DEFAULT '{}',         -- e.g. {"delivery":true,"ai_summary":false,"whatsapp_bills":true}
  active boolean NOT NULL DEFAULT true,         -- inactive plans cannot be newly chosen; existing subscribers keep them
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);

ALTER TABLE tenants
  ADD COLUMN contact_name text,
  ADD COLUMN contact_email text,
  ADD COLUMN contact_phone text,
  ADD COLUMN created_by uuid REFERENCES platform_users(id),
  ADD COLUMN deactivated_at timestamptz,
  ADD COLUMN deactivated_reason text,
  ADD COLUMN deactivated_by uuid REFERENCES platform_users(id);

CREATE TABLE subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL UNIQUE REFERENCES tenants(id),
  plan_id uuid NOT NULL REFERENCES plans(id),
  billing_cycle text NOT NULL CHECK (billing_cycle IN ('MONTHLY','YEARLY')),
  status text NOT NULL CHECK (status IN ('TRIALING','ACTIVE','PAST_DUE','SUSPENDED','CANCELLED')),
  price_snapshot numeric(12,2) NOT NULL CHECK (price_snapshot >= 0),   -- price locked at subscribe/renew time
  currency_code char(3) NOT NULL,
  trial_ends_at timestamptz,
  billing_anchor_at timestamptz,                -- periods are anchor + k cycles (no month-end drift)
  period_number int NOT NULL DEFAULT 0,
  current_period_start timestamptz,
  current_period_end timestamptz,
  grace_days int NOT NULL DEFAULT 7 CHECK (grace_days BETWEEN 0 AND 60),
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  pending_plan_id uuid REFERENCES plans(id),    -- plan/cycle change takes effect at next renewal
  pending_billing_cycle text CHECK (pending_billing_cycle IN ('MONTHLY','YEARLY')),
  suspended_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0,
  CHECK (status <> 'TRIALING' OR trial_ends_at IS NOT NULL),
  CHECK (status NOT IN ('ACTIVE','PAST_DUE') OR (current_period_start IS NOT NULL AND current_period_end IS NOT NULL AND billing_anchor_at IS NOT NULL))
);
CREATE INDEX ix_subscriptions_status ON subscriptions(status);

CREATE TABLE platform_counters (
  name text PRIMARY KEY,                        -- 'invoice', 'ticket'
  last_no int NOT NULL
);

CREATE TABLE subscription_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  subscription_id uuid NOT NULL REFERENCES subscriptions(id),
  invoice_number text NOT NULL UNIQUE,          -- GL-INV-000001
  plan_name text NOT NULL,
  billing_cycle text NOT NULL CHECK (billing_cycle IN ('MONTHLY','YEARLY')),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  amount_before_tax numeric(12,2) NOT NULL CHECK (amount_before_tax >= 0),
  tax_label text,
  tax_percent numeric(5,2) NOT NULL DEFAULT 0 CHECK (tax_percent BETWEEN 0 AND 100),
  tax_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  total_amount numeric(12,2) NOT NULL CHECK (total_amount >= 0),
  currency_code char(3) NOT NULL,
  status text NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE','PAID','VOID')),
  due_at timestamptz NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  void_reason text,
  created_by uuid REFERENCES platform_users(id),
  CHECK (period_end > period_start),
  CHECK (total_amount = amount_before_tax + tax_amount)
);
CREATE UNIQUE INDEX ux_invoice_period ON subscription_invoices(subscription_id, period_start) WHERE status <> 'VOID';
CREATE INDEX ix_invoices_tenant ON subscription_invoices(tenant_id, issued_at DESC);

CREATE TABLE subscription_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  invoice_id uuid NOT NULL REFERENCES subscription_invoices(id),
  method text NOT NULL CHECK (method IN ('BANK_TRANSFER','UPI','CARD','CASH','OTHER')),
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  reference text,
  received_at timestamptz NOT NULL,
  recorded_by uuid NOT NULL REFERENCES platform_users(id),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE platform_settings (
  key text PRIMARY KEY,                         -- default_grace_days, default_trial_days, invoice_tax_label, invoice_tax_percent, support_email
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE support_access_grants (            -- restaurant admin lets platform staff view their data, read-only, time-boxed
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  granted_by uuid NOT NULL REFERENCES users(id),
  platform_user_id uuid REFERENCES platform_users(id),   -- NULL = any support user
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- existing tables
ALTER TABLE audit_logs ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE audit_logs ADD COLUMN actor_type text NOT NULL DEFAULT 'TENANT_USER' CHECK (actor_type IN ('TENANT_USER','PLATFORM_USER','SYSTEM'));
ALTER TABLE users ADD COLUMN must_change_password boolean NOT NULL DEFAULT false;
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('OWNER','MANAGER','CASHIER','CAPTAIN','KITCHEN','RIDER','INVENTORY'));
