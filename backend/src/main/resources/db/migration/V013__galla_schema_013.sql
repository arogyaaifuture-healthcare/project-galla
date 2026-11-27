-- V013 — everyday billing features: combos, coupons, time-based prices, packaging, open items, NC bills, tips,
--        cashier shifts & cash drawer, customer credit (dues), credit notes, kitchen display, barcode, central menu.
-- Applies on top of V001..V011. Columns that point at tables owned by other streams (e.g. devices) are plain uuid; FK added in V016.

-- ============ 1. outlet settings ============
ALTER TABLE outlets
  ADD COLUMN packaging_mode text NOT NULL DEFAULT 'NONE' CHECK (packaging_mode IN ('NONE','FLAT_PER_ORDER','PER_ITEM')),
  ADD COLUMN packaging_flat_charge numeric(12,2) NOT NULL DEFAULT 0 CHECK (packaging_flat_charge >= 0),
  ADD COLUMN packaging_order_types text[] NOT NULL DEFAULT '{TAKEAWAY,DELIVERY}'
        CHECK (packaging_order_types <@ ARRAY['DINE_IN','TAKEAWAY','DELIVERY']::text[]),
  ADD COLUMN packaging_tax_profile_id uuid REFERENCES tax_profiles(id),
  ADD COLUMN nc_tax_mode text NOT NULL DEFAULT 'ZERO_TAX' CHECK (nc_tax_mode IN ('ZERO_TAX','TAX_ON_LIST_PRICE')),
  ADD COLUMN open_items_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN open_item_max_price numeric(12,2) NOT NULL DEFAULT 500 CHECK (open_item_max_price > 0),
  ADD COLUMN tips_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN shifts_required boolean NOT NULL DEFAULT false,
  ADD COLUMN credit_sales_enabled boolean NOT NULL DEFAULT false,
  ADD CONSTRAINT outlets_packaging_flat_needs_amount CHECK (packaging_mode <> 'FLAT_PER_ORDER' OR packaging_flat_charge > 0);

ALTER TABLE printers ADD COLUMN opens_cash_drawer boolean NOT NULL DEFAULT false;   -- ESC/POS drawer kick on cash payment / pay-out

ALTER TABLE kitchen_stations
  ADD COLUMN sla_warn_minutes int NOT NULL DEFAULT 10 CHECK (sla_warn_minutes BETWEEN 1 AND 240),
  ADD COLUMN sla_late_minutes int NOT NULL DEFAULT 20 CHECK (sla_late_minutes BETWEEN 1 AND 480),
  ADD CONSTRAINT stations_sla_order CHECK (sla_warn_minutes < sla_late_minutes);

-- ============ 2. reason codes & per-outlet role permissions ============
CREATE TABLE reason_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  kind text NOT NULL CHECK (kind IN ('NC','REFUND','CASH_MOVEMENT','CREDIT_ADJUSTMENT')),
  code text NOT NULL CHECK (code ~ '^[A-Z0-9_]{2,30}$'),
  label text NOT NULL CHECK (length(btrim(label)) > 0),
  active boolean NOT NULL DEFAULT true,
  UNIQUE (tenant_id, kind, code)
);

CREATE TABLE outlet_role_permissions (            -- a missing row = the built-in default (OPEN_ITEM: OWNER and MANAGER only)
  outlet_id uuid NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  role text NOT NULL CHECK (role IN ('OWNER','MANAGER','CASHIER','CAPTAIN','KITCHEN','RIDER','INVENTORY')),
  permission text NOT NULL CHECK (permission IN ('OPEN_ITEM')),
  allowed boolean NOT NULL,
  PRIMARY KEY (outlet_id, role, permission)
);

-- ============ 3. menu: barcode, packaging, combos, central-menu links ============
ALTER TABLE menu_items
  ADD COLUMN barcode text CHECK (barcode IS NULL OR barcode ~ '^[0-9A-Za-z-]{4,32}$'),
  ADD COLUMN packaging_charge numeric(12,2) NOT NULL DEFAULT 0 CHECK (packaging_charge >= 0),   -- per unit, used when outlet.packaging_mode = PER_ITEM
  ADD COLUMN item_kind text NOT NULL DEFAULT 'STANDARD' CHECK (item_kind IN ('STANDARD','COMBO')),
  ADD COLUMN source_item_id uuid REFERENCES menu_items(id),                 -- set on copies published from a master outlet's item
  ADD COLUMN overridden_fields text[] NOT NULL DEFAULT '{}'                  -- fields the outlet changed itself; re-publish skips them
        CHECK (overridden_fields <@ ARRAY['name','base_price','tax_profile_id','station_id','available','description','packaging_charge','variants']::text[]);
CREATE UNIQUE INDEX ux_menu_items_barcode ON menu_items(outlet_id, barcode) WHERE barcode IS NOT NULL AND active;
CREATE UNIQUE INDEX ux_menu_items_source ON menu_items(outlet_id, source_item_id) WHERE source_item_id IS NOT NULL;
ALTER TABLE menu_categories ADD COLUMN source_category_id uuid REFERENCES menu_categories(id);
CREATE UNIQUE INDEX ux_menu_categories_source ON menu_categories(outlet_id, source_category_id) WHERE source_category_id IS NOT NULL;
ALTER TABLE modifier_groups ADD COLUMN source_group_id uuid REFERENCES modifier_groups(id);
CREATE UNIQUE INDEX ux_modifier_groups_source ON modifier_groups(outlet_id, source_group_id) WHERE source_group_id IS NOT NULL;

CREATE TABLE combo_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  combo_item_id uuid NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  component_item_id uuid NOT NULL REFERENCES menu_items(id),
  component_variant_id uuid REFERENCES item_variants(id),
  quantity numeric(10,3) NOT NULL CHECK (quantity > 0),
  sort_order int NOT NULL DEFAULT 0,
  CHECK (combo_item_id <> component_item_id)
);
CREATE UNIQUE INDEX ux_combo_components ON combo_components(combo_item_id, component_item_id, COALESCE(component_variant_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE FUNCTION fn_combo_components_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k_combo text; k_comp text; o_combo uuid; o_comp uuid;
BEGIN
  SELECT item_kind, outlet_id INTO k_combo, o_combo FROM menu_items WHERE id = NEW.combo_item_id;
  SELECT item_kind, outlet_id INTO k_comp,  o_comp  FROM menu_items WHERE id = NEW.component_item_id;
  IF k_combo <> 'COMBO' THEN RAISE EXCEPTION 'COMBO_PARENT_NOT_COMBO' USING ERRCODE = '23514'; END IF;
  IF k_comp  <> 'STANDARD' THEN RAISE EXCEPTION 'COMBO_NESTING_NOT_ALLOWED' USING ERRCODE = '23514'; END IF;
  IF o_combo <> o_comp THEN RAISE EXCEPTION 'COMBO_COMPONENT_OTHER_OUTLET' USING ERRCODE = '23514'; END IF;
  IF NEW.component_variant_id IS NOT NULL AND NOT EXISTS
     (SELECT 1 FROM item_variants WHERE id = NEW.component_variant_id AND menu_item_id = NEW.component_item_id)
  THEN RAISE EXCEPTION 'COMBO_VARIANT_MISMATCH' USING ERRCODE = '23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_combo_components_guard BEFORE INSERT OR UPDATE ON combo_components FOR EACH ROW EXECUTE FUNCTION fn_combo_components_guard();

-- ============ 4. time-based price rules ============
CREATE TABLE price_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  scope_type text NOT NULL CHECK (scope_type IN ('ITEM','VARIANT','CATEGORY')),
  menu_item_id uuid REFERENCES menu_items(id),
  variant_id uuid REFERENCES item_variants(id),
  category_id uuid REFERENCES menu_categories(id),
  weekdays smallint[] NOT NULL DEFAULT '{1,2,3,4,5,6,7}'                  -- ISO: 1 = Monday .. 7 = Sunday; the weekday on which the WINDOW STARTS
        CHECK (cardinality(weekdays) >= 1 AND weekdays <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),
  start_time time NOT NULL,
  end_time time NOT NULL,                                                   -- end < start means the window crosses midnight; end = start is invalid
  valid_from date, valid_to date,
  order_types text[] NOT NULL DEFAULT '{DINE_IN,TAKEAWAY,DELIVERY}'
        CHECK (cardinality(order_types) >= 1 AND order_types <@ ARRAY['DINE_IN','TAKEAWAY','DELIVERY']::text[]),
  action text NOT NULL CHECK (action IN ('PRICE_OVERRIDE','PERCENT_OFF')),
  price numeric(12,2) CHECK (price IS NULL OR price >= 0),
  percent_off numeric(5,2) CHECK (percent_off IS NULL OR (percent_off > 0 AND percent_off <= 100)),
  priority int NOT NULL DEFAULT 0 CHECK (priority BETWEEN 0 AND 1000),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_time <> end_time),
  CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
  CHECK ((action = 'PRICE_OVERRIDE' AND price IS NOT NULL AND percent_off IS NULL)
      OR (action = 'PERCENT_OFF'    AND percent_off IS NOT NULL AND price IS NULL)),
  CHECK ((scope_type = 'ITEM'     AND menu_item_id IS NOT NULL AND variant_id IS NULL AND category_id IS NULL)
      OR (scope_type = 'VARIANT'  AND variant_id IS NOT NULL AND menu_item_id IS NULL AND category_id IS NULL)
      OR (scope_type = 'CATEGORY' AND category_id IS NOT NULL AND menu_item_id IS NULL AND variant_id IS NULL)),
  CHECK (scope_type <> 'CATEGORY' OR action = 'PERCENT_OFF')                -- a category has no single price to override
);
CREATE INDEX ix_price_rules_outlet ON price_rules(outlet_id) WHERE active;

-- ============ 5. order lines: open items, combos, price snapshot, kitchen status ============
ALTER TABLE order_items
  ALTER COLUMN menu_item_id DROP NOT NULL,
  ADD COLUMN is_open_item boolean NOT NULL DEFAULT false,
  ADD COLUMN price_source text NOT NULL DEFAULT 'LIST' CHECK (price_source IN ('LIST','PRICE_RULE','OPEN_ITEM','COMBO')),
  ADD COLUMN list_unit_price numeric(12,2) CHECK (list_unit_price IS NULL OR list_unit_price >= 0),  -- price before any rule (used by NC TAX_ON_LIST_PRICE reporting)
  ADD COLUMN price_rule_id uuid REFERENCES price_rules(id) ON DELETE SET NULL,
  ADD COLUMN price_rule_name text,
  ADD COLUMN combo_role text NOT NULL DEFAULT 'NONE' CHECK (combo_role IN ('NONE','HEADER','COMPONENT')),
  ADD COLUMN combo_parent_id uuid REFERENCES order_items(id) ON DELETE CASCADE,
  ADD COLUMN fixed_line_amount numeric(12,2) CHECK (fixed_line_amount IS NULL OR fixed_line_amount >= 0),  -- allocated combo amount for the WHOLE component line
  ADD COLUMN kitchen_status text NOT NULL DEFAULT 'NEW' CHECK (kitchen_status IN ('NEW','PREPARING','READY','SERVED')),
  ADD COLUMN preparing_at timestamptz, ADD COLUMN ready_at timestamptz, ADD COLUMN served_at timestamptz,
  ADD CONSTRAINT order_items_open_item_shape CHECK (is_open_item = (menu_item_id IS NULL)),
  ADD CONSTRAINT order_items_open_item_source CHECK (NOT is_open_item OR price_source = 'OPEN_ITEM'),
  ADD CONSTRAINT order_items_combo_shape CHECK (
        (combo_role = 'COMPONENT') = (combo_parent_id IS NOT NULL)
    AND (combo_role <> 'COMPONENT' OR fixed_line_amount IS NOT NULL)
    AND (combo_role = 'COMPONENT' OR fixed_line_amount IS NULL)),
  ADD CONSTRAINT order_items_kitchen_only_after_kot CHECK (kitchen_status = 'NEW' OR kot_id IS NOT NULL);
CREATE INDEX ix_order_items_kitchen ON order_items(kot_id, kitchen_status) WHERE kot_id IS NOT NULL AND status = 'ACTIVE';

-- the kitchen status machine (forward by one or skip, plus recall one step back)
CREATE FUNCTION fn_order_items_kitchen_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.kitchen_status IS DISTINCT FROM OLD.kitchen_status THEN
    IF NOT ((OLD.kitchen_status, NEW.kitchen_status) IN
        (('NEW','PREPARING'),('NEW','READY'),('PREPARING','READY'),('READY','SERVED'),
         ('PREPARING','NEW'),('READY','PREPARING'),('SERVED','READY'))) THEN
      RAISE EXCEPTION 'ILLEGAL_KITCHEN_TRANSITION % -> %', OLD.kitchen_status, NEW.kitchen_status USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_order_items_kitchen BEFORE UPDATE OF kitchen_status ON order_items FOR EACH ROW EXECUTE FUNCTION fn_order_items_kitchen_transition();

-- ============ 6. cashier shifts, cash movements ============
CREATE TABLE cashier_shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  device_id uuid,                                                           -- terminal; FK to devices added in V016
  cashier_id uuid NOT NULL REFERENCES users(id),
  business_date date NOT NULL,
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','CLOSED')),
  opened_at timestamptz NOT NULL DEFAULT now(),
  opening_float numeric(12,2) NOT NULL DEFAULT 0 CHECK (opening_float >= 0),
  closed_at timestamptz,
  counted_cash numeric(12,2) CHECK (counted_cash IS NULL OR counted_cash >= 0),
  expected_cash numeric(12,2),
  variance numeric(12,2),                                                   -- counted - expected
  closed_by uuid REFERENCES users(id),
  handover_to uuid REFERENCES users(id),
  note text,
  CHECK ((status = 'OPEN'   AND closed_at IS NULL AND counted_cash IS NULL AND expected_cash IS NULL AND variance IS NULL)
      OR (status = 'CLOSED' AND closed_at IS NOT NULL AND counted_cash IS NOT NULL AND expected_cash IS NOT NULL AND variance IS NOT NULL AND closed_by IS NOT NULL)),
  CHECK (variance IS NULL OR variance = counted_cash - expected_cash),
  CHECK (handover_to IS NULL OR handover_to <> cashier_id)
);
CREATE UNIQUE INDEX ux_shift_one_open_per_cashier ON cashier_shifts(cashier_id) WHERE status = 'OPEN';
CREATE UNIQUE INDEX ux_shift_one_open_per_device  ON cashier_shifts(device_id) WHERE status = 'OPEN' AND device_id IS NOT NULL;
CREATE INDEX ix_shifts_outlet_date ON cashier_shifts(outlet_id, business_date);

CREATE TABLE cash_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  shift_id uuid NOT NULL REFERENCES cashier_shifts(id),
  kind text NOT NULL CHECK (kind IN ('PAY_IN','PAY_OUT','DROP')),
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  reason_code text NOT NULL CHECK (length(btrim(reason_code)) > 0),
  note text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_cash_movements_shift ON cash_movements(shift_id);

CREATE FUNCTION fn_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'APPEND_ONLY_TABLE % cannot be %', TG_TABLE_NAME, TG_OP USING ERRCODE = '23514'; END $$;
CREATE TRIGGER trg_cash_movements_append_only BEFORE UPDATE OR DELETE ON cash_movements FOR EACH ROW EXECUTE FUNCTION fn_append_only();

-- day close needs every shift of the outlet closed
CREATE FUNCTION fn_day_close_needs_closed_shifts() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'CLOSED' AND OLD.status <> 'CLOSED'
     AND EXISTS (SELECT 1 FROM cashier_shifts WHERE outlet_id = NEW.outlet_id AND status = 'OPEN') THEN
    RAISE EXCEPTION 'OPEN_SHIFTS_EXIST' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_day_close_shifts BEFORE UPDATE OF status ON day_closings FOR EACH ROW EXECUTE FUNCTION fn_day_close_needs_closed_shifts();

-- ============ 7. customer credit (dues) ============
ALTER TABLE customers ADD COLUMN credit_limit numeric(12,2) NOT NULL DEFAULT 0 CHECK (credit_limit >= 0);   -- 0 = no credit allowed

CREATE TABLE customer_ledger (                                              -- append-only; balance = SUM(amount); positive = customer owes
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  customer_id uuid NOT NULL REFERENCES customers(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  entry_type text NOT NULL CHECK (entry_type IN ('CHARGE','PAYMENT','CREDIT_NOTE','ADJUSTMENT')),
  amount numeric(12,2) NOT NULL CHECK (amount <> 0),
  bill_id uuid REFERENCES bills(id),
  payment_id uuid REFERENCES payments(id),
  credit_note_id uuid,                                                      -- FK added below (credit_notes is defined later in this file)
  method text CHECK (method IN ('CASH','CARD','UPI','OTHER')),              -- how a settlement PAYMENT was made
  reference text,
  reason text,
  shift_id uuid REFERENCES cashier_shifts(id),                              -- a cash settlement lands in this shift's drawer
  business_date date NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (entry_type <> 'CHARGE'      OR (amount > 0 AND bill_id IS NOT NULL)),
  CHECK (entry_type <> 'PAYMENT'     OR (amount < 0 AND method IS NOT NULL)),
  CHECK (entry_type <> 'CREDIT_NOTE' OR (amount < 0 AND credit_note_id IS NOT NULL)),
  CHECK (entry_type <> 'ADJUSTMENT'  OR (reason IS NOT NULL AND length(btrim(reason)) >= 5)),
  CHECK (method IS NULL OR entry_type = 'PAYMENT')
);
CREATE INDEX ix_ledger_customer ON customer_ledger(tenant_id, customer_id, created_at);
CREATE TRIGGER trg_ledger_append_only BEFORE UPDATE OR DELETE ON customer_ledger FOR EACH ROW EXECUTE FUNCTION fn_append_only();

-- ============ 8. coupons ============
CREATE TABLE coupons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),                                    -- NULL = every outlet of the tenant
  code text NOT NULL CHECK (code ~ '^[A-Za-z0-9_-]{3,24}$'),
  description text,
  discount_type text NOT NULL CHECK (discount_type IN ('PERCENT','AMOUNT')),
  value numeric(12,2) NOT NULL CHECK (value > 0),
  max_discount numeric(12,2) CHECK (max_discount IS NULL OR max_discount > 0),
  min_bill numeric(12,2) NOT NULL DEFAULT 0 CHECK (min_bill >= 0),
  valid_from timestamptz, valid_to timestamptz,
  weekdays smallint[] NOT NULL DEFAULT '{1,2,3,4,5,6,7}' CHECK (cardinality(weekdays) >= 1 AND weekdays <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),
  order_types text[] NOT NULL DEFAULT '{DINE_IN,TAKEAWAY,DELIVERY}' CHECK (cardinality(order_types) >= 1 AND order_types <@ ARRAY['DINE_IN','TAKEAWAY','DELIVERY']::text[]),
  usage_limit_total int CHECK (usage_limit_total IS NULL OR usage_limit_total > 0),
  usage_limit_per_customer int CHECK (usage_limit_per_customer IS NULL OR usage_limit_per_customer > 0),
  usage_limit_per_day int CHECK (usage_limit_per_day IS NULL OR usage_limit_per_day > 0),
  stackable boolean NOT NULL DEFAULT false CHECK (stackable = false),       -- v1: one coupon per bill; the column exists so a later version can relax it
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (discount_type <> 'PERCENT' OR value <= 100),
  CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);
CREATE UNIQUE INDEX ux_coupons_code ON coupons(tenant_id, lower(code));

-- ============ 9. bills: NC, packaging, coupon ============
ALTER TABLE bills
  ADD COLUMN is_complimentary boolean NOT NULL DEFAULT false,
  ADD COLUMN nc_reason_code text,
  ADD COLUMN nc_tax_liability numeric(12,2) NOT NULL DEFAULT 0 CHECK (nc_tax_liability >= 0),   -- tax the restaurant bears when outlet.nc_tax_mode = TAX_ON_LIST_PRICE (informational; not payable by the guest)
  ADD COLUMN packaging_charge_total numeric(12,2) NOT NULL DEFAULT 0 CHECK (packaging_charge_total >= 0),
  ADD COLUMN packaging_kind text CHECK (packaging_kind IN ('FLAT','PER_ITEM')),                   -- how the packaging line was computed
  ADD COLUMN coupon_id uuid REFERENCES coupons(id),
  ADD COLUMN coupon_code text,
  ADD CONSTRAINT bills_nc_shape CHECK (NOT is_complimentary OR (grand_total = 0 AND nc_reason_code IS NOT NULL AND length(btrim(nc_reason_code)) > 0)),
  ADD CONSTRAINT bills_nc_no_extras CHECK (NOT is_complimentary OR (packaging_charge_total = 0 AND delivery_charge_total = 0 AND service_charge_total = 0 AND coupon_id IS NULL)),
  ADD CONSTRAINT bills_nc_liability_only_nc CHECK (is_complimentary OR nc_tax_liability = 0),
  ADD CONSTRAINT bills_packaging_kind_set CHECK ((packaging_charge_total = 0) = (packaging_kind IS NULL)),
  ADD CONSTRAINT bills_coupon_has_discount CHECK (coupon_id IS NULL OR (discount_total > 0 AND coupon_code IS NOT NULL));
-- a FLAT packaging charge is charged once per order (split bills); PER_ITEM follows the items, so each bill carries its own
CREATE UNIQUE INDEX ux_bills_packaging_flat_once ON bills(order_id) WHERE packaging_kind = 'FLAT' AND status <> 'VOID';
ALTER TABLE bill_lines DROP CONSTRAINT bill_lines_line_type_check;
ALTER TABLE bill_lines ADD CONSTRAINT bill_lines_line_type_check CHECK (line_type IN ('ITEM','SERVICE_CHARGE','DELIVERY_CHARGE','PACKAGING_CHARGE'));

CREATE TABLE coupon_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  coupon_id uuid NOT NULL REFERENCES coupons(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  bill_id uuid NOT NULL REFERENCES bills(id),
  customer_id uuid REFERENCES customers(id),
  business_date date NOT NULL,
  discount_amount numeric(12,2) NOT NULL CHECK (discount_amount > 0),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RELEASED')),
  released_at timestamptz, release_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((status = 'ACTIVE' AND released_at IS NULL) OR (status = 'RELEASED' AND released_at IS NOT NULL AND release_reason IS NOT NULL))
);
CREATE UNIQUE INDEX ux_coupon_one_active_per_bill ON coupon_redemptions(bill_id) WHERE status = 'ACTIVE';
CREATE INDEX ix_coupon_redemptions_coupon ON coupon_redemptions(coupon_id, status);

-- usage limits are enforced INSIDE the database under a row lock on the coupon, so parallel redemptions cannot overshoot a limit
CREATE FUNCTION fn_coupon_redemption_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c coupons%ROWTYPE; n int;
BEGIN
  SELECT * INTO c FROM coupons WHERE id = NEW.coupon_id FOR UPDATE;
  IF NEW.status = 'ACTIVE' THEN
    IF NOT c.active THEN RAISE EXCEPTION 'COUPON_INACTIVE' USING ERRCODE = '23514'; END IF;
    IF c.usage_limit_total IS NOT NULL THEN
      SELECT count(*) INTO n FROM coupon_redemptions WHERE coupon_id = c.id AND status = 'ACTIVE';
      IF n >= c.usage_limit_total THEN RAISE EXCEPTION 'COUPON_LIMIT_TOTAL' USING ERRCODE = '23514'; END IF;
    END IF;
    IF c.usage_limit_per_customer IS NOT NULL THEN
      IF NEW.customer_id IS NULL THEN RAISE EXCEPTION 'COUPON_CUSTOMER_REQUIRED' USING ERRCODE = '23514'; END IF;
      SELECT count(*) INTO n FROM coupon_redemptions WHERE coupon_id = c.id AND customer_id = NEW.customer_id AND status = 'ACTIVE';
      IF n >= c.usage_limit_per_customer THEN RAISE EXCEPTION 'COUPON_LIMIT_CUSTOMER' USING ERRCODE = '23514'; END IF;
    END IF;
    IF c.usage_limit_per_day IS NOT NULL THEN
      SELECT count(*) INTO n FROM coupon_redemptions WHERE coupon_id = c.id AND outlet_id = NEW.outlet_id AND business_date = NEW.business_date AND status = 'ACTIVE';
      IF n >= c.usage_limit_per_day THEN RAISE EXCEPTION 'COUPON_LIMIT_DAY' USING ERRCODE = '23514'; END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_coupon_redemption_guard BEFORE INSERT ON coupon_redemptions FOR EACH ROW EXECUTE FUNCTION fn_coupon_redemption_guard();

-- only ACTIVE -> RELEASED is allowed; nothing else about a redemption may change, and rows are never deleted
CREATE FUNCTION fn_coupon_redemption_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'APPEND_ONLY_TABLE coupon_redemptions cannot be DELETE' USING ERRCODE = '23514'; END IF;
  IF OLD.status = 'ACTIVE' AND NEW.status = 'RELEASED'
     AND (NEW.coupon_id, NEW.bill_id, NEW.outlet_id, NEW.discount_amount, NEW.business_date, NEW.tenant_id)
         IS NOT DISTINCT FROM (OLD.coupon_id, OLD.bill_id, OLD.outlet_id, OLD.discount_amount, OLD.business_date, OLD.tenant_id)
  THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'APPEND_ONLY_TABLE coupon_redemptions allows only ACTIVE -> RELEASED' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_coupon_redemption_immutable BEFORE UPDATE OR DELETE ON coupon_redemptions FOR EACH ROW EXECUTE FUNCTION fn_coupon_redemption_immutable();

-- ============ 10. payments: ON_ACCOUNT, tips, shift ============
ALTER TABLE payments
  ADD COLUMN tip_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (tip_amount >= 0),
  ADD COLUMN tip_staff_id uuid REFERENCES users(id),
  ADD COLUMN customer_id uuid REFERENCES customers(id),
  ADD COLUMN shift_id uuid REFERENCES cashier_shifts(id);
ALTER TABLE payments DROP CONSTRAINT payments_method_check;
ALTER TABLE payments ADD CONSTRAINT payments_method_check CHECK (method IN ('CASH','CARD','UPI','OTHER','ON_ACCOUNT'));
ALTER TABLE payments
  ADD CONSTRAINT payments_on_account_needs_customer CHECK (method <> 'ON_ACCOUNT' OR customer_id IS NOT NULL),
  ADD CONSTRAINT payments_on_account_no_tip CHECK (method <> 'ON_ACCOUNT' OR tip_amount = 0),
  ADD CONSTRAINT payments_on_account_no_tender CHECK (method <> 'ON_ACCOUNT' OR (tendered_amount IS NULL AND change_amount IS NULL));
CREATE INDEX ix_payments_shift ON payments(shift_id) WHERE shift_id IS NOT NULL;

CREATE FUNCTION fn_payments_shift_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE req boolean; sh_outlet uuid;
BEGIN
  SELECT shifts_required INTO req FROM outlets WHERE id = NEW.outlet_id;
  IF req AND NEW.shift_id IS NULL THEN RAISE EXCEPTION 'SHIFT_REQUIRED' USING ERRCODE = '23514'; END IF;
  IF NEW.shift_id IS NOT NULL THEN
    SELECT outlet_id INTO sh_outlet FROM cashier_shifts WHERE id = NEW.shift_id;
    IF sh_outlet <> NEW.outlet_id THEN RAISE EXCEPTION 'SHIFT_OTHER_OUTLET' USING ERRCODE = '23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_payments_shift_guard BEFORE INSERT ON payments FOR EACH ROW EXECUTE FUNCTION fn_payments_shift_guard();

-- ============ 11. credit notes (partial / full refunds on PAID bills) ============
-- numbering reuses bill_counters with series 'CN' (same atomic upsert as bills, Section 5.5)
CREATE TABLE credit_notes (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  bill_id uuid NOT NULL REFERENCES bills(id),
  series text NOT NULL DEFAULT 'CN',
  fiscal_year text NOT NULL,
  cn_seq int NOT NULL,
  cn_number text NOT NULL,
  business_date date NOT NULL,
  reason_code text NOT NULL CHECK (length(btrim(reason_code)) > 0),
  reason text NOT NULL CHECK (length(btrim(reason)) >= 5),
  refund_method text NOT NULL CHECK (refund_method IN ('CASH','CARD','UPI','OTHER','ON_ACCOUNT')),
  refund_reference text,
  customer_id uuid REFERENCES customers(id),
  shift_id uuid REFERENCES cashier_shifts(id),
  taxable_total numeric(12,2) NOT NULL CHECK (taxable_total >= 0),
  tax_total numeric(12,2) NOT NULL CHECK (tax_total >= 0),
  total_before_round_off numeric(12,2) NOT NULL CHECK (total_before_round_off >= 0),
  round_off numeric(12,2) NOT NULL DEFAULT 0,
  grand_total numeric(12,2) NOT NULL CHECK (grand_total > 0),               -- the money handed back
  approved_by uuid NOT NULL REFERENCES users(id),                           -- manager / owner who approved (PIN override)
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, series, fiscal_year, cn_seq),
  UNIQUE (outlet_id, cn_number),
  CHECK (series = 'CN'),
  CHECK (grand_total = total_before_round_off + round_off),
  CHECK (refund_method <> 'ON_ACCOUNT' OR customer_id IS NOT NULL)
);
CREATE INDEX ix_credit_notes_bill ON credit_notes(bill_id);

CREATE TABLE credit_note_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  credit_note_id uuid NOT NULL REFERENCES credit_notes(id),
  bill_line_id uuid NOT NULL REFERENCES bill_lines(id),
  quantity numeric(10,3) NOT NULL CHECK (quantity > 0),
  line_gross numeric(12,2) NOT NULL CHECK (line_gross >= 0),
  discount_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  taxable_amount numeric(12,2) NOT NULL CHECK (taxable_amount >= 0),
  tax_amount numeric(12,2) NOT NULL CHECK (tax_amount >= 0),
  line_total numeric(12,2) NOT NULL CHECK (line_total >= 0),
  restock boolean NOT NULL DEFAULT false,                                   -- hook for the inventory module: return the ingredients to stock
  CHECK (line_total = taxable_amount + tax_amount)
);
CREATE INDEX ix_credit_note_lines_bill_line ON credit_note_lines(bill_line_id);
CREATE TABLE credit_note_line_taxes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  credit_note_line_id uuid NOT NULL REFERENCES credit_note_lines(id),
  component_name text NOT NULL,
  rate_percent numeric(5,2) NOT NULL,
  taxable_amount numeric(12,2) NOT NULL CHECK (taxable_amount >= 0),
  tax_amount numeric(12,2) NOT NULL CHECK (tax_amount >= 0)
);
ALTER TABLE customer_ledger ADD CONSTRAINT fk_ledger_credit_note FOREIGN KEY (credit_note_id) REFERENCES credit_notes(id);
CREATE TRIGGER trg_credit_notes_immutable BEFORE UPDATE OR DELETE ON credit_notes FOR EACH ROW EXECUTE FUNCTION fn_append_only();
CREATE TRIGGER trg_credit_note_lines_immutable BEFORE UPDATE OR DELETE ON credit_note_lines FOR EACH ROW EXECUTE FUNCTION fn_append_only();
CREATE TRIGGER trg_credit_note_line_taxes_immutable BEFORE UPDATE OR DELETE ON credit_note_line_taxes FOR EACH ROW EXECUTE FUNCTION fn_append_only();

-- one bill line can never be refunded for more than it was sold for (quantity and every money column), even under parallel requests
CREATE FUNCTION fn_credit_note_line_cap() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE bl bill_lines%ROWTYPE; cn_bill uuid; q numeric; g numeric; tx numeric; t numeric; lt numeric;
BEGIN
  SELECT * INTO bl FROM bill_lines WHERE id = NEW.bill_line_id FOR UPDATE;
  SELECT bill_id INTO cn_bill FROM credit_notes WHERE id = NEW.credit_note_id;
  IF bl.bill_id <> cn_bill THEN RAISE EXCEPTION 'CREDIT_LINE_OTHER_BILL' USING ERRCODE = '23514'; END IF;
  SELECT COALESCE(sum(quantity),0), COALESCE(sum(taxable_amount),0), COALESCE(sum(tax_amount),0), COALESCE(sum(line_total),0), COALESCE(sum(line_gross),0)
    INTO q, tx, t, lt, g FROM credit_note_lines WHERE bill_line_id = NEW.bill_line_id;
  IF q  + NEW.quantity        > bl.quantity       THEN RAISE EXCEPTION 'REFUND_EXCEEDS_QUANTITY' USING ERRCODE = '23514'; END IF;
  IF lt + NEW.line_total      > bl.line_total     THEN RAISE EXCEPTION 'REFUND_EXCEEDS_AMOUNT' USING ERRCODE = '23514'; END IF;
  IF tx + NEW.taxable_amount  > bl.taxable_amount THEN RAISE EXCEPTION 'REFUND_EXCEEDS_TAXABLE' USING ERRCODE = '23514'; END IF;
  IF t  + NEW.tax_amount      > bl.tax_amount     THEN RAISE EXCEPTION 'REFUND_EXCEEDS_TAX' USING ERRCODE = '23514'; END IF;
  IF g  + NEW.line_gross      > bl.line_gross     THEN RAISE EXCEPTION 'REFUND_EXCEEDS_GROSS' USING ERRCODE = '23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_credit_note_line_cap BEFORE INSERT ON credit_note_lines FOR EACH ROW EXECUTE FUNCTION fn_credit_note_line_cap();

-- a bill that already has a credit note can no longer be voided (void = whole-bill cancellation for mistakes; credit note = return after the sale)
CREATE FUNCTION fn_bill_void_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'VOID' AND OLD.status <> 'VOID' AND EXISTS (SELECT 1 FROM credit_notes WHERE bill_id = NEW.id) THEN
    RAISE EXCEPTION 'BILL_HAS_CREDIT_NOTES' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_bill_void_guard BEFORE UPDATE OF status ON bills FOR EACH ROW EXECUTE FUNCTION fn_bill_void_guard();

-- a credit note needs a PAID bill, and all credit notes of a bill together can never hand back more than the bill's grand total
CREATE FUNCTION fn_credit_note_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b bills%ROWTYPE; refunded numeric;
BEGIN
  SELECT * INTO b FROM bills WHERE id = NEW.bill_id FOR UPDATE;
  IF b.status <> 'PAID' THEN RAISE EXCEPTION 'CREDIT_NOTE_NEEDS_PAID_BILL' USING ERRCODE = '23514'; END IF;
  IF b.outlet_id <> NEW.outlet_id THEN RAISE EXCEPTION 'CREDIT_NOTE_OTHER_OUTLET' USING ERRCODE = '23514'; END IF;
  SELECT COALESCE(sum(grand_total),0) INTO refunded FROM credit_notes WHERE bill_id = NEW.bill_id;
  IF refunded + NEW.grand_total > b.grand_total THEN RAISE EXCEPTION 'REFUND_EXCEEDS_BILL_TOTAL' USING ERRCODE = '23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_credit_note_guard BEFORE INSERT ON credit_notes FOR EACH ROW EXECUTE FUNCTION fn_credit_note_guard();

-- voiding a bill gives its coupon use back (the redemption row stays, marked RELEASED)
CREATE FUNCTION fn_bill_void_release_coupon() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'VOID' AND OLD.status <> 'VOID' THEN
    UPDATE coupon_redemptions SET status = 'RELEASED', released_at = now(), release_reason = 'BILL_VOIDED'
     WHERE bill_id = NEW.id AND status = 'ACTIVE';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_bill_void_release_coupon AFTER UPDATE OF status ON bills FOR EACH ROW EXECUTE FUNCTION fn_bill_void_release_coupon();

-- ============ 12. central menu: version counter and publish audit ============
CREATE TABLE outlet_menu_versions (                                         -- bumped in the same transaction as ANY change that affects /catalog/pos (items, variants, modifiers, combos, price rules, availability, outlet settings used by the POS)
  outlet_id uuid PRIMARY KEY REFERENCES outlets(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  version bigint NOT NULL DEFAULT 1 CHECK (version >= 1),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO outlet_menu_versions(outlet_id, tenant_id) SELECT id, tenant_id FROM outlets;

CREATE TABLE menu_publish_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  source_outlet_id uuid NOT NULL REFERENCES outlets(id),
  target_outlet_ids uuid[] NOT NULL CHECK (cardinality(target_outlet_ids) >= 1),
  mode text NOT NULL DEFAULT 'ADD_AND_UPDATE' CHECK (mode IN ('ADD_AND_UPDATE','ADD_ONLY')),
  started_by uuid NOT NULL REFERENCES users(id),
  summary jsonb NOT NULL DEFAULT '{}',                                     -- {created, updated, skippedOverridden, deactivated, errors[]}
  created_at timestamptz NOT NULL DEFAULT now()
);
