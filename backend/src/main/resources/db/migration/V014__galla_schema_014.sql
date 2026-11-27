-- V014 — Inventory, recipes, purchasing (plan Section 26). Applies on top of V001–V011.
-- Cross-stream references (credit notes, combo components) are plain uuid columns; their FKs are added in V016.
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- needed for the recipe-version exclusion constraint

-- ---------------------------------------------------------------- units
CREATE TABLE inventory_units (
  code text PRIMARY KEY,
  name text NOT NULL,
  family text NOT NULL CHECK (family IN ('MASS','VOLUME','COUNT','PACK')),
  factor_to_base numeric(18,6) CHECK (factor_to_base > 0),
  base_code text,
  CHECK ((family = 'PACK' AND factor_to_base IS NULL AND base_code IS NULL)
      OR (family <> 'PACK' AND factor_to_base IS NOT NULL AND base_code IS NOT NULL))
);
INSERT INTO inventory_units(code,name,family,factor_to_base,base_code) VALUES
 ('g','gram','MASS',1,'g'), ('kg','kilogram','MASS',1000,'g'),
 ('ml','millilitre','VOLUME',1,'ml'), ('l','litre','VOLUME',1000,'ml'),
 ('pcs','piece','COUNT',1,'pcs'), ('dozen','dozen','COUNT',12,'pcs');
INSERT INTO inventory_units(code,name,family) VALUES
 ('pack','pack','PACK'),('box','box','PACK'),('bottle','bottle','PACK'),('can','can','PACK'),
 ('tray','tray','PACK'),('bag','bag','PACK'),('crate','crate','PACK');
ALTER TABLE inventory_units ADD FOREIGN KEY (base_code) REFERENCES inventory_units(code);

-- ---------------------------------------------------------------- masters
CREATE TABLE stock_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  sort_order int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  UNIQUE (tenant_id, name)
);

CREATE TABLE vendors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  contact_person text, phone text, email text, address text,
  gstin text CHECK (gstin IS NULL OR length(btrim(gstin)) BETWEEN 1 AND 20),   -- stored as text; NOT validated against any registry
  payment_terms_days int NOT NULL DEFAULT 0 CHECK (payment_terms_days BETWEEN 0 AND 365),
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX ux_vendors_name ON vendors(tenant_id, lower(name));

CREATE TABLE stock_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  category_id uuid REFERENCES stock_categories(id),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  sku text,
  barcode text,
  item_kind text NOT NULL DEFAULT 'RAW' CHECK (item_kind IN ('RAW','PREP','RETAIL')),
  base_unit_code text NOT NULL REFERENCES inventory_units(code) CHECK (base_unit_code IN ('g','ml','pcs')),
  purchase_unit_code text NOT NULL REFERENCES inventory_units(code),
  purchase_to_base numeric(18,6) NOT NULL CHECK (purchase_to_base > 0),   -- base units in ONE purchase unit
  default_vendor_id uuid REFERENCES vendors(id),
  reorder_level numeric(14,4) NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),   -- base units; per-outlet override in stock_levels
  par_level numeric(14,4) CHECK (par_level IS NULL OR par_level >= reorder_level),
  track_stock boolean NOT NULL DEFAULT true,
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX ux_stock_items_name ON stock_items(tenant_id, lower(name));
CREATE UNIQUE INDEX ux_stock_items_sku ON stock_items(tenant_id, lower(sku)) WHERE sku IS NOT NULL;
CREATE UNIQUE INDEX ux_stock_items_barcode ON stock_items(tenant_id, barcode) WHERE barcode IS NOT NULL;

-- purchase unit must be a PACK unit, or a unit of the same family as the base unit with the exact table factor
CREATE FUNCTION trg_stock_item_units() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE bu inventory_units%ROWTYPE; pu inventory_units%ROWTYPE;
BEGIN
  SELECT * INTO bu FROM inventory_units WHERE code = NEW.base_unit_code;
  SELECT * INTO pu FROM inventory_units WHERE code = NEW.purchase_unit_code;
  IF pu.family <> 'PACK' THEN
    IF pu.family <> bu.family THEN
      RAISE EXCEPTION 'UNIT_FAMILY_MISMATCH: purchase unit % cannot convert to base unit %', pu.code, bu.code USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.purchase_to_base <> pu.factor_to_base THEN
      RAISE EXCEPTION 'UNIT_FACTOR_MISMATCH: % must be % base units', pu.code, pu.factor_to_base USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_items_units BEFORE INSERT OR UPDATE OF base_unit_code, purchase_unit_code, purchase_to_base
  ON stock_items FOR EACH ROW EXECUTE FUNCTION trg_stock_item_units();

CREATE TABLE inventory_settings (
  outlet_id uuid PRIMARY KEY REFERENCES outlets(id),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  negative_stock_policy text NOT NULL DEFAULT 'ALLOW' CHECK (negative_stock_policy IN ('ALLOW','BLOCK_MANUAL')),
  wastage_approval_threshold numeric(12,2) NOT NULL DEFAULT 500 CHECK (wastage_approval_threshold >= 0),
  price_change_alert_percent numeric(5,2) NOT NULL DEFAULT 10 CHECK (price_change_alert_percent > 0),
  low_stock_alerts_enabled boolean NOT NULL DEFAULT true,
  low_stock_recipients text[] NOT NULL DEFAULT '{}',
  dead_stock_days int NOT NULL DEFAULT 30 CHECK (dead_stock_days BETWEEN 7 AND 365),
  count_blind_default boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory_counters (                  -- gapless per outlet and kind: PO, GRN, RET, TRF, CNT, ADJ, PRD
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  kind text NOT NULL CHECK (kind IN ('PO','GRN','RET','TRF','CNT','ADJ','PRD')),
  last_value bigint NOT NULL DEFAULT 0 CHECK (last_value >= 0),
  PRIMARY KEY (outlet_id, kind)
);

-- ---------------------------------------------------------------- stock levels (trigger-maintained) and the ledger
CREATE TABLE stock_levels (
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  on_hand numeric(14,4) NOT NULL DEFAULT 0,                    -- may be negative (policy ALLOW)
  avg_cost numeric(16,6) NOT NULL DEFAULT 0 CHECK (avg_cost >= 0),   -- moving weighted average per base unit
  avg_cost_known boolean NOT NULL DEFAULT false,
  last_purchase_cost numeric(16,6) CHECK (last_purchase_cost IS NULL OR last_purchase_cost >= 0),
  last_purchase_at timestamptz,
  last_movement_at timestamptz,
  reorder_level_override numeric(14,4) CHECK (reorder_level_override IS NULL OR reorder_level_override >= 0),
  par_level_override numeric(14,4) CHECK (par_level_override IS NULL OR par_level_override >= 0),
  low_stock_alerted_on date,
  PRIMARY KEY (outlet_id, stock_item_id)
);

CREATE TABLE stock_consumptions (                  -- one row per bill that consumed stock (idempotency anchor)
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  bill_id uuid NOT NULL UNIQUE REFERENCES bills(id),         -- ONE consumption per bill
  business_date date NOT NULL,
  source text NOT NULL CHECK (source IN ('BILL_PAID','OFFLINE_SYNC')),
  status text NOT NULL DEFAULT 'APPLIED' CHECK (status IN ('APPLIED','PARTIALLY_REVERSED','REVERSED')),
  covered_net_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (covered_net_amount >= 0),     -- sales lines that had a recipe
  uncovered_net_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (uncovered_net_amount >= 0), -- sales lines skipped
  consumed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_consumptions_outlet_date ON stock_consumptions(outlet_id, business_date);

CREATE TABLE stock_consumption_skips (            -- the "no recipe" report: never blocks billing
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consumption_id uuid NOT NULL REFERENCES stock_consumptions(id) ON DELETE CASCADE,
  menu_item_id uuid NOT NULL REFERENCES menu_items(id),
  variant_id uuid REFERENCES item_variants(id),
  quantity numeric(10,3) NOT NULL CHECK (quantity > 0),
  line_net_amount numeric(12,2) NOT NULL CHECK (line_net_amount >= 0),
  reason text NOT NULL CHECK (reason IN ('NO_RECIPE','RECIPE_EMPTY','ITEM_NOT_TRACKED'))
);

CREATE TABLE stock_movements (                    -- APPEND-ONLY ledger
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  kind text NOT NULL CHECK (kind IN ('OPENING','PURCHASE','SALE','SALE_REVERSAL','WASTAGE','ADJUSTMENT','COUNT_VARIANCE',
                                      'TRANSFER_OUT','TRANSFER_IN','VENDOR_RETURN','PRODUCTION_CONSUME','PRODUCTION_OUTPUT')),
  quantity_base numeric(14,4) NOT NULL CHECK (quantity_base <> 0),   -- signed, base units
  unit_cost numeric(16,6) NOT NULL CHECK (unit_cost >= 0),
  cost_basis text NOT NULL CHECK (cost_basis IN ('ACTUAL','REVERSAL','AVERAGE','LAST_PURCHASE','UNKNOWN')),
  cost_estimated boolean GENERATED ALWAYS AS (cost_basis IN ('LAST_PURCHASE','UNKNOWN')) STORED,
  line_value numeric(14,2) GENERATED ALWAYS AS (round(quantity_base * unit_cost, 2)) STORED,
  occurred_at timestamptz NOT NULL,
  business_date date NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  actor_id uuid REFERENCES users(id),               -- NULL = system (bill-paid trigger)
  reason_code text,
  note text,
  ref_type text CHECK (ref_type IN ('BILL','BILL_VOID','CREDIT_NOTE','GRN','PURCHASE_RETURN','ADJUSTMENT','COUNT','TRANSFER','PRODUCTION','IMPORT')),
  ref_id uuid,
  consumption_id uuid REFERENCES stock_consumptions(id),
  reverses_movement_id uuid REFERENCES stock_movements(id),
  dedupe_key text NOT NULL UNIQUE,
  CHECK ((kind IN ('OPENING','PURCHASE','SALE_REVERSAL','TRANSFER_IN','PRODUCTION_OUTPUT') AND quantity_base > 0)
      OR (kind IN ('SALE','WASTAGE','VENDOR_RETURN','TRANSFER_OUT','PRODUCTION_CONSUME') AND quantity_base < 0)
      OR kind IN ('ADJUSTMENT','COUNT_VARIANCE')),
  CHECK ((quantity_base > 0 AND cost_basis IN ('ACTUAL','REVERSAL','AVERAGE'))
      OR (quantity_base < 0 AND cost_basis IN ('AVERAGE','LAST_PURCHASE','UNKNOWN'))),
  CHECK (cost_basis <> 'UNKNOWN' OR unit_cost = 0),
  CHECK (kind NOT IN ('OPENING','PURCHASE','TRANSFER_IN','PRODUCTION_OUTPUT') OR cost_basis = 'ACTUAL'),
  CHECK (kind <> 'SALE_REVERSAL' OR cost_basis IN ('REVERSAL','AVERAGE')),
  CHECK (kind NOT IN ('ADJUSTMENT','COUNT_VARIANCE') OR quantity_base < 0 OR cost_basis = 'AVERAGE'),   -- found stock enters at the current average
  CHECK (kind <> 'SALE' OR consumption_id IS NOT NULL),
  CHECK (kind <> 'SALE_REVERSAL' OR reverses_movement_id IS NOT NULL),
  CHECK (kind <> 'PURCHASE' OR (ref_type = 'GRN' AND ref_id IS NOT NULL)),
  CHECK (kind NOT IN ('WASTAGE','ADJUSTMENT','COUNT_VARIANCE') OR (reason_code IS NOT NULL AND length(btrim(reason_code)) > 0))
);
CREATE INDEX ix_movements_item_time ON stock_movements(outlet_id, stock_item_id, occurred_at);
CREATE INDEX ix_movements_date_kind ON stock_movements(outlet_id, business_date, kind);
CREATE INDEX ix_movements_consumption ON stock_movements(consumption_id) WHERE consumption_id IS NOT NULL;
CREATE INDEX ix_movements_reverses ON stock_movements(reverses_movement_id) WHERE reverses_movement_id IS NOT NULL;

-- ledger is append-only
CREATE FUNCTION trg_stock_movements_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'LEDGER_IMMUTABLE: stock_movements is append-only (% not allowed)', TG_OP USING ERRCODE = 'restrict_violation'; END $$;
CREATE TRIGGER stock_movements_no_update BEFORE UPDATE OR DELETE ON stock_movements FOR EACH ROW EXECUTE FUNCTION trg_stock_movements_immutable();
CREATE TRIGGER stock_movements_no_truncate BEFORE TRUNCATE ON stock_movements FOR EACH STATEMENT EXECUTE FUNCTION trg_stock_movements_immutable();

-- BEFORE INSERT: validate (cost rules, policy, reversal cap) under a row lock on the level
CREATE FUNCTION trg_stock_movements_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE lv stock_levels%ROWTYPE; pol text; orig stock_movements%ROWTYPE; already numeric;
        exp_basis text; exp_cost numeric; tracked boolean;
BEGIN
  SELECT track_stock INTO tracked FROM stock_items WHERE id = NEW.stock_item_id AND tenant_id = NEW.tenant_id;
  IF tracked IS NULL THEN RAISE EXCEPTION 'STOCK_ITEM_TENANT_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
  IF NOT tracked THEN RAISE EXCEPTION 'ITEM_NOT_TRACKED' USING ERRCODE = 'check_violation'; END IF;
  IF NOT EXISTS (SELECT 1 FROM outlets WHERE id = NEW.outlet_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'OUTLET_TENANT_MISMATCH' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO stock_levels(outlet_id, stock_item_id, tenant_id) VALUES (NEW.outlet_id, NEW.stock_item_id, NEW.tenant_id)
    ON CONFLICT DO NOTHING;
  SELECT * INTO lv FROM stock_levels WHERE outlet_id = NEW.outlet_id AND stock_item_id = NEW.stock_item_id FOR UPDATE;

  IF NEW.quantity_base < 0 THEN               -- outflow cost is DETERMINED by the level, never by the caller
    IF lv.on_hand > 0 AND lv.avg_cost_known THEN exp_basis := 'AVERAGE'; exp_cost := lv.avg_cost;
    ELSIF lv.last_purchase_cost IS NOT NULL THEN exp_basis := 'LAST_PURCHASE'; exp_cost := lv.last_purchase_cost;
    ELSE exp_basis := 'UNKNOWN'; exp_cost := 0; END IF;
    IF NEW.cost_basis <> exp_basis OR NEW.unit_cost <> exp_cost THEN
      RAISE EXCEPTION 'COST_BASIS_MISMATCH: expected % at %', exp_basis, exp_cost USING ERRCODE = 'check_violation';
    END IF;
    SELECT negative_stock_policy INTO pol FROM inventory_settings WHERE outlet_id = NEW.outlet_id;
    IF COALESCE(pol, 'ALLOW') = 'BLOCK_MANUAL' AND lv.on_hand + NEW.quantity_base < 0
       AND NEW.kind IN ('WASTAGE','ADJUSTMENT','TRANSFER_OUT','VENDOR_RETURN','PRODUCTION_CONSUME') THEN
      RAISE EXCEPTION 'NEGATIVE_STOCK_BLOCKED' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF NEW.cost_basis = 'AVERAGE' AND NEW.unit_cost <> lv.avg_cost THEN
    RAISE EXCEPTION 'COST_BASIS_MISMATCH: AVERAGE inflow must use the current average %', lv.avg_cost USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.kind = 'SALE_REVERSAL' THEN
    SELECT * INTO orig FROM stock_movements WHERE id = NEW.reverses_movement_id;
    IF NOT FOUND OR orig.kind <> 'SALE' OR orig.stock_item_id <> NEW.stock_item_id OR orig.outlet_id <> NEW.outlet_id THEN
      RAISE EXCEPTION 'REVERSAL_TARGET_INVALID' USING ERRCODE = 'check_violation';
    END IF;
    SELECT COALESCE(sum(quantity_base), 0) INTO already FROM stock_movements
      WHERE reverses_movement_id = NEW.reverses_movement_id AND kind = 'SALE_REVERSAL';
    IF already + NEW.quantity_base > -orig.quantity_base THEN
      RAISE EXCEPTION 'REVERSAL_EXCEEDS_ORIGINAL' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.unit_cost <> orig.unit_cost THEN       -- a reversal always returns stock at the ORIGINAL sale cost
      RAISE EXCEPTION 'REVERSAL_COST_MISMATCH: must equal the original unit cost %', orig.unit_cost USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_movements_before BEFORE INSERT ON stock_movements FOR EACH ROW EXECUTE FUNCTION trg_stock_movements_before();

-- AFTER INSERT: apply to the level (fires only for rows really inserted, so ON CONFLICT DO NOTHING cannot diverge)
CREATE FUNCTION trg_stock_movements_after() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE lv stock_levels%ROWTYPE; n_on numeric; n_avg numeric; n_known boolean; n_lp numeric; n_lpat timestamptz;
BEGIN
  PERFORM set_config('galla.stock_trigger', '1', true);
  SELECT * INTO lv FROM stock_levels WHERE outlet_id = NEW.outlet_id AND stock_item_id = NEW.stock_item_id FOR UPDATE;
  n_on := lv.on_hand + NEW.quantity_base;
  n_avg := lv.avg_cost; n_known := lv.avg_cost_known; n_lp := lv.last_purchase_cost; n_lpat := lv.last_purchase_at;
  IF NEW.quantity_base > 0 AND NEW.cost_basis IN ('ACTUAL','REVERSAL') THEN
    IF lv.on_hand <= 0 THEN n_avg := NEW.unit_cost;
    ELSE n_avg := round((lv.on_hand * lv.avg_cost + NEW.quantity_base * NEW.unit_cost) / (lv.on_hand + NEW.quantity_base), 6);
    END IF;
    IF NEW.cost_basis = 'ACTUAL' THEN n_known := true; END IF;
  END IF;
  IF NEW.kind = 'PURCHASE' AND (lv.last_purchase_at IS NULL OR NEW.occurred_at >= lv.last_purchase_at) THEN
    n_lp := NEW.unit_cost; n_lpat := NEW.occurred_at;
  END IF;
  UPDATE stock_levels SET on_hand = n_on, avg_cost = n_avg, avg_cost_known = n_known,
         last_purchase_cost = n_lp, last_purchase_at = n_lpat,
         last_movement_at = GREATEST(COALESCE(lv.last_movement_at, NEW.occurred_at), NEW.occurred_at)
   WHERE outlet_id = NEW.outlet_id AND stock_item_id = NEW.stock_item_id;
  PERFORM set_config('galla.stock_trigger', '0', true);
  RETURN NULL;
END $$;
CREATE TRIGGER stock_movements_after AFTER INSERT ON stock_movements FOR EACH ROW EXECUTE FUNCTION trg_stock_movements_after();

-- levels can only be changed through the ledger
CREATE FUNCTION trg_stock_levels_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF COALESCE(current_setting('galla.stock_trigger', true), '') = '1' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF; RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'STOCK_LEVEL_DIRECT_CHANGE' USING ERRCODE = 'restrict_violation'; END IF;
  IF TG_OP = 'INSERT' THEN       -- a level row starts empty; quantity and cost arrive only through the ledger
    IF NEW.on_hand <> 0 OR NEW.avg_cost <> 0 OR NEW.avg_cost_known OR NEW.last_purchase_cost IS NOT NULL
       OR NEW.last_purchase_at IS NOT NULL OR NEW.last_movement_at IS NOT NULL THEN
      RAISE EXCEPTION 'STOCK_LEVEL_DIRECT_CHANGE: a new level starts at zero' USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF (NEW.on_hand, NEW.avg_cost, NEW.avg_cost_known, NEW.last_purchase_cost, NEW.last_purchase_at, NEW.last_movement_at)
     IS DISTINCT FROM (OLD.on_hand, OLD.avg_cost, OLD.avg_cost_known, OLD.last_purchase_cost, OLD.last_purchase_at, OLD.last_movement_at) THEN
    RAISE EXCEPTION 'STOCK_LEVEL_DIRECT_CHANGE: on-hand and cost change only through stock_movements' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_levels_guard BEFORE INSERT OR UPDATE OR DELETE ON stock_levels FOR EACH ROW EXECUTE FUNCTION trg_stock_levels_guard();

CREATE TABLE stock_snapshots (                    -- written by day close; opening/closing valuation of the EOD e-mail
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  business_date date NOT NULL,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  on_hand numeric(14,4) NOT NULL,
  avg_cost numeric(16,6) NOT NULL CHECK (avg_cost >= 0),
  value_amount numeric(14,2) GENERATED ALWAYS AS (round(on_hand * avg_cost, 2)) STORED,
  PRIMARY KEY (outlet_id, business_date, stock_item_id)
);

-- ---------------------------------------------------------------- recipes (versioned, immutable once active)
CREATE TABLE recipes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),                       -- NULL only for PREP_ITEM recipes (shared by all outlets)
  target_type text NOT NULL CHECK (target_type IN ('MENU_ITEM','VARIANT','MODIFIER','PREP_ITEM')),
  menu_item_id uuid REFERENCES menu_items(id),
  variant_id uuid REFERENCES item_variants(id),
  modifier_id uuid REFERENCES modifiers(id),
  prep_stock_item_id uuid REFERENCES stock_items(id),
  target_id uuid GENERATED ALWAYS AS (COALESCE(prep_stock_item_id, modifier_id, variant_id, menu_item_id)) STORED,
  version int NOT NULL CHECK (version >= 1),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','ARCHIVED')),
  effective_from timestamptz NOT NULL,
  effective_to timestamptz,
  yield_qty_base numeric(14,4) CHECK (yield_qty_base IS NULL OR yield_qty_base > 0),   -- PREP only: output of ONE batch
  inherit_item_recipe boolean NOT NULL DEFAULT false,          -- VARIANT only: use the item's recipe x portion_factor
  portion_factor numeric(8,4) NOT NULL DEFAULT 1 CHECK (portion_factor > 0),
  note text,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (effective_to IS NULL OR effective_to > effective_from),
  CHECK ((target_type = 'MENU_ITEM' AND menu_item_id IS NOT NULL AND variant_id IS NULL AND modifier_id IS NULL AND prep_stock_item_id IS NULL)
      OR (target_type = 'VARIANT'   AND variant_id IS NOT NULL AND menu_item_id IS NULL AND modifier_id IS NULL AND prep_stock_item_id IS NULL)
      OR (target_type = 'MODIFIER'  AND modifier_id IS NOT NULL AND menu_item_id IS NULL AND variant_id IS NULL AND prep_stock_item_id IS NULL)
      OR (target_type = 'PREP_ITEM' AND prep_stock_item_id IS NOT NULL AND menu_item_id IS NULL AND variant_id IS NULL AND modifier_id IS NULL)),
  CHECK ((target_type = 'PREP_ITEM') = (yield_qty_base IS NOT NULL)),
  CHECK ((target_type = 'PREP_ITEM') = (outlet_id IS NULL)),
  CHECK (NOT inherit_item_recipe OR target_type = 'VARIANT'),
  UNIQUE (target_id, version),
  EXCLUDE USING gist (target_id WITH =, tstzrange(effective_from, effective_to) WITH &&) WHERE (status = 'ACTIVE')
);

CREATE TABLE recipe_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id uuid NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  line_no int NOT NULL CHECK (line_no >= 1),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  quantity numeric(14,4) NOT NULL CHECK (quantity > 0),              -- NET quantity per portion (or per batch for PREP), in unit_code
  unit_code text NOT NULL REFERENCES inventory_units(code),
  quantity_base numeric(14,4) NOT NULL CHECK (quantity_base > 0),    -- = round(quantity * unit factor, 4); validated by trigger
  wastage_percent numeric(5,2) NOT NULL DEFAULT 0 CHECK (wastage_percent >= 0 AND wastage_percent < 100),
  consume_mode text NOT NULL DEFAULT 'DIRECT' CHECK (consume_mode IN ('DIRECT','EXPAND')),   -- EXPAND: use the prep item's raw ingredients instead of its stock
  UNIQUE (recipe_id, line_no),
  UNIQUE (recipe_id, stock_item_id)
);

CREATE FUNCTION trg_recipe_lines_rules() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r recipes%ROWTYPE; si stock_items%ROWTYPE; u inventory_units%ROWTYPE; bu inventory_units%ROWTYPE; rid uuid; st text; prep stock_items%ROWTYPE;
BEGIN
  rid := CASE WHEN TG_OP = 'DELETE' THEN OLD.recipe_id ELSE NEW.recipe_id END;
  SELECT * INTO r FROM recipes WHERE id = rid;
  IF r.status <> 'DRAFT' THEN RAISE EXCEPTION 'RECIPE_IMMUTABLE: create a new version instead' USING ERRCODE = 'restrict_violation'; END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF r.inherit_item_recipe THEN RAISE EXCEPTION 'RECIPE_INHERITS: a variant that inherits the item recipe has no lines' USING ERRCODE = 'check_violation'; END IF;
  SELECT * INTO si FROM stock_items WHERE id = NEW.stock_item_id;
  IF si.tenant_id <> r.tenant_id THEN RAISE EXCEPTION 'STOCK_ITEM_TENANT_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
  SELECT * INTO u FROM inventory_units WHERE code = NEW.unit_code;
  SELECT * INTO bu FROM inventory_units WHERE code = si.base_unit_code;
  IF u.family = 'PACK' OR u.family <> bu.family THEN
    RAISE EXCEPTION 'UNIT_FAMILY_MISMATCH: % cannot be used for an item counted in %', u.code, bu.code USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.quantity_base <> round(NEW.quantity * u.factor_to_base, 4) THEN
    RAISE EXCEPTION 'QUANTITY_BASE_MISMATCH' USING ERRCODE = 'check_violation';
  END IF;
  IF r.target_type = 'PREP_ITEM' THEN
    IF si.item_kind = 'PREP' THEN RAISE EXCEPTION 'PREP_NESTING_NOT_ALLOWED: a prep recipe may only use raw/retail items' USING ERRCODE = 'check_violation'; END IF;
    SELECT * INTO prep FROM stock_items WHERE id = r.prep_stock_item_id;
    IF prep.item_kind <> 'PREP' THEN RAISE EXCEPTION 'PREP_TARGET_INVALID' USING ERRCODE = 'check_violation'; END IF;
  END IF;
  IF NEW.consume_mode = 'EXPAND' AND si.item_kind <> 'PREP' THEN
    RAISE EXCEPTION 'EXPAND_ONLY_FOR_PREP' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER recipe_lines_rules BEFORE INSERT OR UPDATE OR DELETE ON recipe_lines FOR EACH ROW EXECUTE FUNCTION trg_recipe_lines_rules();

CREATE FUNCTION trg_recipes_rules() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN RAISE EXCEPTION 'RECIPE_IMMUTABLE: only drafts can be deleted' USING ERRCODE = 'restrict_violation'; END IF;
    RETURN OLD;
  END IF;
  IF TG_OP = 'INSERT' THEN
    -- malformed target / outlet combinations are reported by the table CHECKs, so skip the cross-table lookups for them
    IF (NEW.target_type <> 'PREP_ITEM' AND NEW.outlet_id IS NULL)
       OR (NEW.target_type = 'MENU_ITEM' AND NEW.menu_item_id IS NULL) OR (NEW.target_type = 'VARIANT' AND NEW.variant_id IS NULL)
       OR (NEW.target_type = 'MODIFIER' AND NEW.modifier_id IS NULL) OR (NEW.target_type = 'PREP_ITEM' AND NEW.prep_stock_item_id IS NULL) THEN
      RETURN NEW;
    END IF;
    IF NEW.target_type = 'PREP_ITEM' THEN
      IF NOT EXISTS (SELECT 1 FROM stock_items WHERE id = NEW.prep_stock_item_id AND tenant_id = NEW.tenant_id) THEN
        RAISE EXCEPTION 'RECIPE_TARGET_TENANT_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
    ELSIF NEW.target_type = 'MENU_ITEM' THEN
      IF NOT EXISTS (SELECT 1 FROM menu_items WHERE id = NEW.menu_item_id AND tenant_id = NEW.tenant_id AND outlet_id = NEW.outlet_id) THEN
        RAISE EXCEPTION 'RECIPE_TARGET_OUTLET_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
    ELSIF NEW.target_type = 'VARIANT' THEN
      IF NOT EXISTS (SELECT 1 FROM item_variants v JOIN menu_items m ON m.id = v.menu_item_id
                      WHERE v.id = NEW.variant_id AND m.tenant_id = NEW.tenant_id AND m.outlet_id = NEW.outlet_id) THEN
        RAISE EXCEPTION 'RECIPE_TARGET_OUTLET_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
    ELSE
      IF NOT EXISTS (SELECT 1 FROM modifiers md JOIN modifier_groups g ON g.id = md.group_id
                      WHERE md.id = NEW.modifier_id AND md.tenant_id = NEW.tenant_id AND g.outlet_id = NEW.outlet_id) THEN
        RAISE EXCEPTION 'RECIPE_TARGET_OUTLET_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.status <> 'DRAFT' THEN
    IF (NEW.tenant_id, NEW.outlet_id, NEW.target_type, NEW.menu_item_id, NEW.variant_id, NEW.modifier_id, NEW.prep_stock_item_id, NEW.version, NEW.effective_from, NEW.yield_qty_base, NEW.inherit_item_recipe, NEW.portion_factor)
       IS DISTINCT FROM (OLD.tenant_id, OLD.outlet_id, OLD.target_type, OLD.menu_item_id, OLD.variant_id, OLD.modifier_id, OLD.prep_stock_item_id, OLD.version, OLD.effective_from, OLD.yield_qty_base, OLD.inherit_item_recipe, OLD.portion_factor)
       OR (OLD.status = 'ARCHIVED' AND NEW.status <> 'ARCHIVED') OR (OLD.status = 'ACTIVE' AND NEW.status = 'DRAFT') THEN
      RAISE EXCEPTION 'RECIPE_IMMUTABLE: an active recipe only gets an end date or is archived' USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER recipes_rules BEFORE INSERT OR UPDATE OR DELETE ON recipes FOR EACH ROW EXECUTE FUNCTION trg_recipes_rules();

-- ---------------------------------------------------------------- purchasing
CREATE TABLE purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  vendor_id uuid NOT NULL REFERENCES vendors(id),
  po_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SENT','PARTIALLY_RECEIVED','RECEIVED','CANCELLED')),
  expected_date date,
  notes text,
  total_estimate numeric(14,2) NOT NULL DEFAULT 0 CHECK (total_estimate >= 0),
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  cancelled_reason text,
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (outlet_id, po_number),
  CHECK (status <> 'CANCELLED' OR (cancelled_reason IS NOT NULL AND length(btrim(cancelled_reason)) > 0)),
  CHECK (status NOT IN ('SENT','PARTIALLY_RECEIVED','RECEIVED') OR sent_at IS NOT NULL)
);

CREATE TABLE purchase_order_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  po_id uuid NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  ordered_qty numeric(14,4) NOT NULL CHECK (ordered_qty > 0),        -- in the item's purchase unit
  unit_price numeric(16,6) NOT NULL CHECK (unit_price >= 0),         -- per purchase unit, before tax
  received_qty numeric(14,4) NOT NULL DEFAULT 0 CHECK (received_qty >= 0),
  UNIQUE (po_id, stock_item_id)
);

CREATE TABLE goods_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  vendor_id uuid NOT NULL REFERENCES vendors(id),
  po_id uuid REFERENCES purchase_orders(id),
  grn_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','POSTED','VOID')),
  invoice_number text,
  invoice_date date,
  due_date date,
  received_at timestamptz NOT NULL DEFAULT now(),
  subtotal numeric(14,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  tax_total numeric(14,2) NOT NULL DEFAULT 0 CHECK (tax_total >= 0),      -- recorded exactly as on the vendor invoice; NOT interpreted
  other_charges numeric(14,2) NOT NULL DEFAULT 0,                          -- freight etc.; NOT added to stock cost in v1
  round_off numeric(14,2) NOT NULL DEFAULT 0,
  total_amount numeric(14,2) NOT NULL CHECK (total_amount >= 0),
  attachment_key text,
  attachment_content_type text CHECK (attachment_content_type IN ('image/jpeg','image/png','application/pdf')),
  attachment_size_bytes int CHECK (attachment_size_bytes IS NULL OR attachment_size_bytes BETWEEN 1 AND 5242880),
  notes text,
  created_by uuid NOT NULL REFERENCES users(id),
  posted_by uuid REFERENCES users(id),
  posted_at timestamptz,
  voided_by uuid REFERENCES users(id),
  void_reason text,
  version bigint NOT NULL DEFAULT 0,
  UNIQUE (outlet_id, grn_number),
  CHECK (total_amount = subtotal + tax_total + other_charges + round_off),
  CHECK (status <> 'POSTED' OR (invoice_number IS NOT NULL AND length(btrim(invoice_number)) > 0 AND invoice_date IS NOT NULL AND posted_by IS NOT NULL AND posted_at IS NOT NULL)),
  CHECK (status <> 'VOID' OR (void_reason IS NOT NULL AND length(btrim(void_reason)) > 0)),
  CHECK ((attachment_key IS NULL) = (attachment_content_type IS NULL))
);
CREATE UNIQUE INDEX ux_grn_vendor_invoice ON goods_receipts(tenant_id, vendor_id, lower(btrim(invoice_number)))
  WHERE invoice_number IS NOT NULL AND status <> 'VOID';          -- duplicate-invoice guard

CREATE TABLE goods_receipt_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  grn_id uuid NOT NULL REFERENCES goods_receipts(id) ON DELETE CASCADE,
  po_line_id uuid REFERENCES purchase_order_lines(id),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  qty_purchase numeric(14,4) NOT NULL CHECK (qty_purchase > 0),
  purchase_unit_code text NOT NULL REFERENCES inventory_units(code),   -- snapshots, so later item edits never change history
  purchase_to_base numeric(18,6) NOT NULL CHECK (purchase_to_base > 0),
  qty_base numeric(14,4) NOT NULL CHECK (qty_base > 0),
  unit_price numeric(16,6) NOT NULL CHECK (unit_price >= 0),           -- per purchase unit, before tax
  unit_cost_base numeric(16,6) NOT NULL CHECK (unit_cost_base >= 0),   -- per base unit; this is the cost that enters the ledger
  line_amount numeric(14,2) NOT NULL CHECK (line_amount >= 0),
  tax_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  price_change_percent numeric(8,2),
  price_alert boolean NOT NULL DEFAULT false,
  UNIQUE (grn_id, stock_item_id),
  CHECK (qty_base = round(qty_purchase * purchase_to_base, 4)),
  CHECK (unit_cost_base = round(unit_price / purchase_to_base, 6)),
  CHECK (line_amount = round(qty_purchase * unit_price, 2))
);

-- a posted receipt is frozen: lines never change, the header can only be voided (the stock effect is reversed by new ledger rows)
CREATE FUNCTION trg_grn_lines_draft_only() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text;
BEGIN
  SELECT status INTO st FROM goods_receipts WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.grn_id ELSE NEW.grn_id END;
  IF st IS DISTINCT FROM 'DRAFT' THEN RAISE EXCEPTION 'GRN_NOT_DRAFT: lines of a posted or void receipt cannot change' USING ERRCODE = 'restrict_violation'; END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER grn_lines_draft_only BEFORE INSERT OR UPDATE OR DELETE ON goods_receipt_lines FOR EACH ROW EXECUTE FUNCTION trg_grn_lines_draft_only();

CREATE FUNCTION trg_grn_header_rules() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN RAISE EXCEPTION 'GRN_NOT_DRAFT: only a draft receipt can be deleted' USING ERRCODE = 'restrict_violation'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.status = 'VOID' THEN RAISE EXCEPTION 'GRN_VOID_IS_FINAL' USING ERRCODE = 'restrict_violation'; END IF;
  IF OLD.status = 'POSTED' THEN
    IF NEW.status NOT IN ('POSTED','VOID')
       OR (NEW.tenant_id, NEW.outlet_id, NEW.vendor_id, NEW.po_id, NEW.grn_number, NEW.invoice_number, NEW.invoice_date, NEW.subtotal,
           NEW.tax_total, NEW.other_charges, NEW.round_off, NEW.total_amount, NEW.posted_by, NEW.posted_at)
          IS DISTINCT FROM
          (OLD.tenant_id, OLD.outlet_id, OLD.vendor_id, OLD.po_id, OLD.grn_number, OLD.invoice_number, OLD.invoice_date, OLD.subtotal,
           OLD.tax_total, OLD.other_charges, OLD.round_off, OLD.total_amount, OLD.posted_by, OLD.posted_at) THEN
      RAISE EXCEPTION 'GRN_POSTED_IMMUTABLE: a posted receipt can only be voided' USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER grn_header_rules BEFORE UPDATE OR DELETE ON goods_receipts FOR EACH ROW EXECUTE FUNCTION trg_grn_header_rules();

CREATE TABLE purchase_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  vendor_id uuid NOT NULL REFERENCES vendors(id),
  grn_id uuid REFERENCES goods_receipts(id),
  return_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','POSTED','VOID')),
  reason text NOT NULL CHECK (length(btrim(reason)) > 0),
  credit_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (credit_amount >= 0),    -- what the vendor credits us (may differ from stock value)
  created_by uuid NOT NULL REFERENCES users(id),
  posted_by uuid REFERENCES users(id),
  posted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, return_number),
  CHECK (status <> 'POSTED' OR (posted_by IS NOT NULL AND posted_at IS NOT NULL))
);
CREATE TABLE purchase_return_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id uuid NOT NULL REFERENCES purchase_returns(id) ON DELETE CASCADE,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  qty_base numeric(14,4) NOT NULL CHECK (qty_base > 0),
  UNIQUE (return_id, stock_item_id)
);

CREATE TABLE vendor_payments (                     -- recorded manually; no gateway in v1
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  vendor_id uuid NOT NULL REFERENCES vendors(id),
  outlet_id uuid REFERENCES outlets(id),
  paid_on date NOT NULL,
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  method text NOT NULL CHECK (method IN ('CASH','UPI','BANK_TRANSFER','CHEQUE','CARD','OTHER')),
  reference text,
  recorded_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  voided_at timestamptz
);
CREATE TABLE vendor_payment_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES vendor_payments(id),
  grn_id uuid NOT NULL REFERENCES goods_receipts(id),
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  UNIQUE (payment_id, grn_id)
);
CREATE FUNCTION trg_vendor_alloc_limits() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pay numeric; used_pay numeric; grn_total numeric; used_grn numeric; v1 uuid; v2 uuid;
BEGIN
  SELECT amount, vendor_id INTO pay, v1 FROM vendor_payments WHERE id = NEW.payment_id;
  SELECT total_amount, vendor_id INTO grn_total, v2 FROM goods_receipts WHERE id = NEW.grn_id AND status = 'POSTED';
  IF v2 IS NULL THEN RAISE EXCEPTION 'ALLOCATION_GRN_NOT_POSTED' USING ERRCODE = 'check_violation'; END IF;
  IF v1 <> v2 THEN RAISE EXCEPTION 'ALLOCATION_VENDOR_MISMATCH' USING ERRCODE = 'check_violation'; END IF;
  SELECT COALESCE(sum(amount), 0) INTO used_pay FROM vendor_payment_allocations WHERE payment_id = NEW.payment_id;
  SELECT COALESCE(sum(a.amount), 0) INTO used_grn FROM vendor_payment_allocations a JOIN vendor_payments p ON p.id = a.payment_id
    WHERE a.grn_id = NEW.grn_id AND p.voided_at IS NULL;
  IF used_pay > pay THEN RAISE EXCEPTION 'ALLOCATION_EXCEEDS_PAYMENT' USING ERRCODE = 'check_violation'; END IF;
  IF used_grn > grn_total THEN RAISE EXCEPTION 'ALLOCATION_EXCEEDS_INVOICE' USING ERRCODE = 'check_violation'; END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER vendor_alloc_limits AFTER INSERT ON vendor_payment_allocations
  DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION trg_vendor_alloc_limits();

-- ---------------------------------------------------------------- adjustments, counts, transfers, production
CREATE TABLE stock_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  adjustment_number text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('WASTAGE','ADJUSTMENT')),
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  quantity_base numeric(14,4) NOT NULL CHECK (quantity_base <> 0),             -- signed; WASTAGE is negative
  reason_code text NOT NULL,
  note text,
  value_amount numeric(14,2) NOT NULL CHECK (value_amount >= 0),               -- |qty| x cost at the time
  requires_approval boolean NOT NULL DEFAULT false,                            -- value above outlet threshold (manager PIN)
  approved_by uuid REFERENCES users(id),
  movement_id uuid,                                                           -- stock_movements.id (no FK: movement is written in the same txn)
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, adjustment_number),
  CHECK (kind <> 'WASTAGE' OR quantity_base < 0),
  CHECK (kind <> 'WASTAGE' OR reason_code IN ('SPOILAGE','EXPIRED','SPILL','DAMAGED','RETURNED_BY_CUSTOMER','STAFF_MEAL','TRANSIT_LOSS','THEFT_SUSPECTED','OTHER')),
  CHECK (kind <> 'ADJUSTMENT' OR reason_code IN ('DATA_ENTRY_CORRECTION','FOUND_STOCK','DAMAGED','OTHER')),
  CHECK (reason_code <> 'OTHER' OR (note IS NOT NULL AND length(btrim(note)) > 0)),
  CHECK (NOT requires_approval OR approved_by IS NOT NULL)
);

CREATE TABLE stock_counts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  count_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','IN_PROGRESS','SUBMITTED','APPROVED','CANCELLED')),
  scope text NOT NULL DEFAULT 'FULL' CHECK (scope IN ('FULL','CATEGORY','SELECTED')),
  category_id uuid REFERENCES stock_categories(id),
  blind boolean NOT NULL DEFAULT true,
  started_by uuid REFERENCES users(id),
  started_at timestamptz,
  submitted_by uuid REFERENCES users(id),
  submitted_at timestamptz,
  approved_by uuid REFERENCES users(id),
  approved_at timestamptz,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, count_number),
  CHECK (scope <> 'CATEGORY' OR category_id IS NOT NULL),
  CHECK (status <> 'APPROVED' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL AND submitted_by IS NOT NULL)),
  CHECK (status NOT IN ('SUBMITTED','APPROVED') OR (submitted_by IS NOT NULL AND submitted_at IS NOT NULL)),
  CHECK (approved_by IS NULL OR submitted_by IS NULL OR approved_by <> submitted_by)    -- four-eyes: approver is not the submitter
);
CREATE TABLE stock_count_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  count_id uuid NOT NULL REFERENCES stock_counts(id) ON DELETE CASCADE,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  system_qty_base numeric(14,4) NOT NULL,                     -- frozen when the sheet is started; hidden from counters in blind mode
  avg_cost_snapshot numeric(16,6) NOT NULL CHECK (avg_cost_snapshot >= 0),
  counted_qty_base numeric(14,4) CHECK (counted_qty_base IS NULL OR counted_qty_base >= 0),
  variance_qty numeric(14,4) GENERATED ALWAYS AS (counted_qty_base - system_qty_base) STORED,
  variance_value numeric(14,2) GENERATED ALWAYS AS (round((counted_qty_base - system_qty_base) * avg_cost_snapshot, 2)) STORED,
  note text,
  UNIQUE (count_id, stock_item_id)
);

CREATE TABLE stock_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  from_outlet_id uuid NOT NULL REFERENCES outlets(id),
  to_outlet_id uuid NOT NULL REFERENCES outlets(id),
  transfer_number text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','IN_TRANSIT','RECEIVED','CANCELLED')),
  sent_by uuid REFERENCES users(id), sent_at timestamptz,
  received_by uuid REFERENCES users(id), received_at timestamptz,
  note text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (from_outlet_id, transfer_number),
  CHECK (from_outlet_id <> to_outlet_id),
  CHECK (status NOT IN ('IN_TRANSIT','RECEIVED') OR (sent_by IS NOT NULL AND sent_at IS NOT NULL)),
  CHECK (status <> 'RECEIVED' OR (received_by IS NOT NULL AND received_at IS NOT NULL))
);
CREATE FUNCTION trg_transfer_same_tenant() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.from_outlet_id = NEW.to_outlet_id THEN RETURN NEW; END IF;   -- the CHECK reports this case
  IF (SELECT count(*) FROM outlets WHERE id IN (NEW.from_outlet_id, NEW.to_outlet_id) AND tenant_id = NEW.tenant_id) <> 2 THEN
    RAISE EXCEPTION 'TRANSFER_CROSS_TENANT' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_transfers_same_tenant BEFORE INSERT OR UPDATE OF from_outlet_id, to_outlet_id, tenant_id ON stock_transfers
  FOR EACH ROW EXECUTE FUNCTION trg_transfer_same_tenant();
CREATE TABLE stock_transfer_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id uuid NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  qty_sent_base numeric(14,4) NOT NULL CHECK (qty_sent_base > 0),
  unit_cost_sent numeric(16,6) CHECK (unit_cost_sent IS NULL OR unit_cost_sent >= 0),   -- set when sent
  qty_received_base numeric(14,4) CHECK (qty_received_base IS NULL OR qty_received_base >= 0),
  UNIQUE (transfer_id, stock_item_id),
  CHECK (qty_received_base IS NULL OR qty_received_base <= qty_sent_base)
);

CREATE TABLE production_runs (                    -- turns raw items into a PREP item (gravy base, dough, ...)
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid NOT NULL REFERENCES outlets(id),
  run_number text NOT NULL,
  prep_stock_item_id uuid NOT NULL REFERENCES stock_items(id),
  recipe_id uuid NOT NULL REFERENCES recipes(id),
  batches numeric(10,3) NOT NULL CHECK (batches > 0),
  output_qty_base numeric(14,4) NOT NULL CHECK (output_qty_base > 0),     -- actual output (may differ from batches x yield)
  produced_at timestamptz NOT NULL,
  business_date date NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outlet_id, run_number)
);

-- ---------------------------------------------------------------- CSV import
CREATE TABLE inventory_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  outlet_id uuid REFERENCES outlets(id),
  kind text NOT NULL CHECK (kind IN ('STOCK_ITEMS','OPENING_STOCK','RECIPES')),
  file_key text NOT NULL,
  file_sha256 char(64) NOT NULL,
  status text NOT NULL DEFAULT 'VALIDATED' CHECK (status IN ('VALIDATED','COMMITTED','REJECTED')),
  total_rows int NOT NULL CHECK (total_rows >= 0),
  ok_rows int NOT NULL CHECK (ok_rows >= 0),
  error_rows int NOT NULL CHECK (error_rows >= 0),
  errors jsonb NOT NULL DEFAULT '[]',               -- [{"row":7,"column":"unit","code":"UNIT_FAMILY_MISMATCH","message":"..."}], max 500 stored
  commit_valid_only boolean NOT NULL DEFAULT false,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  committed_at timestamptz,
  CHECK (ok_rows + error_rows = total_rows),
  CHECK (status <> 'COMMITTED' OR (committed_at IS NOT NULL AND (error_rows = 0 OR commit_valid_only)))
);
CREATE UNIQUE INDEX ux_import_committed_file ON inventory_import_jobs(tenant_id, kind, file_sha256) WHERE status = 'COMMITTED';   -- re-uploading the same file cannot double-import
