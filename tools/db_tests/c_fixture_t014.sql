-- fixture for t014.sql (test-only rows and one test helper function; not part of the migration)
INSERT INTO tenants(id,name) VALUES ('00000000-0000-0000-0000-000000000002','T2');
INSERT INTO outlets(id,tenant_id,code,name,country_code,timezone,currency_code,currency_symbol,prices_include_tax,fiscal_year_start_month)
 VALUES ('00000000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-000000000002','X1','Other','IN','Asia/Kolkata','INR','Rs',false,4);
INSERT INTO users(id,tenant_id,email,password_hash,full_name,role) VALUES
 ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','o@x.io','x','Owner','OWNER'),
 ('00000000-0000-0000-0000-0000000000f2','00000000-0000-0000-0000-000000000001','i@x.io','x','Inv','INVENTORY'),
 ('00000000-0000-0000-0000-0000000000f3','00000000-0000-0000-0000-000000000001','m@x.io','x','Mgr','MANAGER');
INSERT INTO menu_categories(id,tenant_id,outlet_id,name) VALUES
 ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','Starters'),
 ('00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a2','Starters');
INSERT INTO menu_items(id,tenant_id,outlet_id,category_id,name,base_price) VALUES
 ('00000000-0000-0000-0000-000000000a11','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000c1','Paneer Tikka',200),
 ('00000000-0000-0000-0000-000000000a12','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000c1','Cola',50),
 ('00000000-0000-0000-0000-000000000a21','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000c2','Paneer Tikka O2',200);
INSERT INTO item_variants(id,tenant_id,menu_item_id,name,price) VALUES
 ('00000000-0000-0000-0000-000000000b01','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000a11','Half',120);
INSERT INTO modifier_groups(id,tenant_id,outlet_id,name) VALUES ('00000000-0000-0000-0000-000000000e01','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','Extras');
INSERT INTO modifiers(id,tenant_id,group_id,name,price) VALUES ('00000000-0000-0000-0000-000000000e02','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000e01','Extra cheese',30);
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by) VALUES
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',1,'2026-11-23','TAKEAWAY','00000000-0000-0000-0000-0000000000f1'),
 ('00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',2,'2026-11-23','TAKEAWAY','00000000-0000-0000-0000-0000000000f1');
INSERT INTO bills(id,tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,status)
 VALUES ('00000000-0000-0000-0000-000000000b11','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1','B','2026-27',1,'B-2026-27-000001',false,'INR',100,0,100,100,'00000000-0000-0000-0000-0000000000f1','PAID'),
        ('00000000-0000-0000-0000-000000000b12','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e2','B','2026-27',2,'B-2026-27-000002',false,'INR',100,0,100,100,'00000000-0000-0000-0000-0000000000f1','PAID');

-- stock items (tenant 1): s1 paneer g/kg, s2 milk ml/l, s3 cola pcs/crate(24), s4 gravy PREP g/kg, s5 salt g/kg
INSERT INTO stock_items(id,tenant_id,name,item_kind,base_unit_code,purchase_unit_code,purchase_to_base,reorder_level,par_level) VALUES
 ('00000000-0000-0000-0000-0000000005e1','00000000-0000-0000-0000-000000000001','Paneer','RAW','g','kg',1000,2000,10000),
 ('00000000-0000-0000-0000-0000000005e2','00000000-0000-0000-0000-000000000001','Milk','RAW','ml','l',1000,5000,NULL),
 ('00000000-0000-0000-0000-0000000005e3','00000000-0000-0000-0000-000000000001','Cola 300ml','RETAIL','pcs','crate',24,24,NULL),
 ('00000000-0000-0000-0000-0000000005e4','00000000-0000-0000-0000-000000000001','Gravy base','PREP','g','kg',1000,0,NULL),
 ('00000000-0000-0000-0000-0000000005e5','00000000-0000-0000-0000-000000000001','Salt','RAW','g','kg',1000,0,NULL);
INSERT INTO stock_items(id,tenant_id,name,base_unit_code,purchase_unit_code,purchase_to_base) VALUES
 ('00000000-0000-0000-0000-0000000005f1','00000000-0000-0000-0000-000000000002','Other tenant item','g','kg',1000);
INSERT INTO vendors(id,tenant_id,name) VALUES
 ('00000000-0000-0000-0000-000000000da1','00000000-0000-0000-0000-000000000001','Fresh Dairy'),
 ('00000000-0000-0000-0000-000000000da2','00000000-0000-0000-0000-000000000001','Spice Mart');

-- test helper (what the application service does): determine the outflow cost from the locked level, then insert
CREATE FUNCTION t_mov(p_outlet uuid, p_item uuid, p_kind text, p_qty numeric, p_key text,
                      p_reason text DEFAULT NULL, p_cons uuid DEFAULT NULL, p_cost numeric DEFAULT NULL,
                      p_basis text DEFAULT NULL, p_date date DEFAULT '2026-11-23', p_ref_type text DEFAULT NULL, p_ref_id uuid DEFAULT NULL,
                      p_rev uuid DEFAULT NULL, p_at timestamptz DEFAULT '2026-11-23 10:00+05:30') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE lv stock_levels%ROWTYPE; b text; c numeric; new_id uuid; tn uuid;
BEGIN
  SELECT tenant_id INTO tn FROM outlets WHERE id = p_outlet;
  INSERT INTO stock_levels(outlet_id, stock_item_id, tenant_id) VALUES (p_outlet, p_item, tn) ON CONFLICT DO NOTHING;
  SELECT * INTO lv FROM stock_levels WHERE outlet_id = p_outlet AND stock_item_id = p_item FOR UPDATE;
  IF p_basis IS NOT NULL THEN b := p_basis; c := p_cost;
  ELSIF p_qty < 0 THEN
    IF lv.on_hand > 0 AND lv.avg_cost_known THEN b := 'AVERAGE'; c := lv.avg_cost;
    ELSIF lv.last_purchase_cost IS NOT NULL THEN b := 'LAST_PURCHASE'; c := lv.last_purchase_cost;
    ELSE b := 'UNKNOWN'; c := 0; END IF;
  ELSE b := 'ACTUAL'; c := p_cost; END IF;
  INSERT INTO stock_movements(tenant_id,outlet_id,stock_item_id,kind,quantity_base,unit_cost,cost_basis,occurred_at,business_date,reason_code,
                              ref_type,ref_id,consumption_id,reverses_movement_id,dedupe_key)
  VALUES (tn,p_outlet,p_item,p_kind,p_qty,c,b,p_at,p_date,p_reason,p_ref_type,p_ref_id,p_cons,p_rev,p_key) RETURNING id INTO new_id;
  RETURN new_id;
END $$;
