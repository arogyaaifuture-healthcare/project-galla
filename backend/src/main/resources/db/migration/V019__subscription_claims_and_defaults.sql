-- A restaurant says "I paid, UTR xxx"; the super admin confirms it against the bank/UPI credit.
CREATE TABLE payment_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  invoice_id uuid NOT NULL REFERENCES subscription_invoices(id),
  utr text NOT NULL CHECK (utr ~ '^[A-Za-z0-9]{10,30}$'),
  claimed_by uuid NOT NULL REFERENCES users(id),
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','CONFIRMED','REJECTED')),
  reviewed_by uuid REFERENCES platform_users(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((status = 'PENDING') = (reviewed_at IS NULL)),
  CHECK (status <> 'REJECTED' OR review_note IS NOT NULL)
);
CREATE UNIQUE INDEX ux_payment_claims_one_pending ON payment_claims(invoice_id) WHERE status = 'PENDING';
CREATE UNIQUE INDEX ux_payment_claims_utr ON payment_claims(upper(utr)) WHERE status <> 'REJECTED';
CREATE INDEX ix_payment_claims_status ON payment_claims(status, created_at);

-- Defaults. The plan below is a PLACEHOLDER: price 0 means "pricing not set"; the super admin must set real prices before launch.
INSERT INTO plans(code,name,description,currency_code,price_monthly,price_yearly,trial_days,max_outlets,max_users,sort_order)
VALUES ('STANDARD','Standard','Placeholder plan - set real prices in the platform console','INR',0,0,30,1,10,1);
INSERT INTO platform_settings(key,value) VALUES
  ('default_grace_days','7'), ('invoice_tax_label','GST'), ('invoice_tax_percent','0'),
  ('expired_access_mode','LOCKED'),   -- LOCKED: only the subscription page works; READ_ONLY: data can still be viewed
  ('invoice_lead_days','7');
