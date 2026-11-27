-- V009 — feedback and support tickets
CREATE TABLE feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  user_id uuid NOT NULL REFERENCES users(id),
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  category text NOT NULL DEFAULT 'GENERAL' CHECK (category IN ('GENERAL','BILLING','MENU','PRINTING','DELIVERY','PERFORMANCE','TRIAL','OTHER')),
  message text,
  context text,                                  -- e.g. 'TRIAL_DAY_20', 'TRIAL_ENDED', 'MANUAL'
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_feedback_created ON feedback(created_at DESC);

CREATE TABLE support_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  ticket_number text NOT NULL UNIQUE,            -- GL-TKT-000045
  created_by uuid NOT NULL REFERENCES users(id),
  subject text NOT NULL,
  category text NOT NULL DEFAULT 'GENERAL' CHECK (category IN ('GENERAL','BILLING','MENU','PRINTING','DELIVERY','SUBSCRIPTION','BUG','OTHER')),
  priority text NOT NULL DEFAULT 'NORMAL' CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','IN_PROGRESS','WAITING_CUSTOMER','RESOLVED','CLOSED')),
  assigned_to uuid REFERENCES platform_users(id),
  context jsonb,                                 -- auto-attached diagnostics: app version, browser, route, last traceId
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  version bigint NOT NULL DEFAULT 0
);
CREATE INDEX ix_tickets_tenant ON support_tickets(tenant_id, created_at DESC);
CREATE INDEX ix_tickets_open ON support_tickets(status, priority) WHERE status IN ('OPEN','IN_PROGRESS','WAITING_CUSTOMER');

CREATE TABLE support_ticket_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  author_type text NOT NULL CHECK (author_type IN ('TENANT_USER','PLATFORM_USER')),
  author_id uuid NOT NULL,
  body text NOT NULL CHECK (length(btrim(body)) > 0),
  internal_note boolean NOT NULL DEFAULT false,  -- visible to platform staff only
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT internal_note OR author_type = 'PLATFORM_USER')
);
CREATE INDEX ix_ticket_messages ON support_ticket_messages(ticket_id, created_at);
