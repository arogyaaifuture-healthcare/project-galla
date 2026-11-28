\set T '''00000000-0000-0000-0000-000000000001'''
\set T2 '''00000000-0000-0000-0000-000000000002'''
\set O '''00000000-0000-0000-0000-0000000000a1'''
\set O2 '''00000000-0000-0000-0000-0000000000a2'''
\set O3 '''00000000-0000-0000-0000-0000000000a3'''
\set U '''00000000-0000-0000-0000-0000000000f1'''
\set UI '''00000000-0000-0000-0000-0000000000f2'''
\set UM '''00000000-0000-0000-0000-0000000000f3'''
\set S1 '''00000000-0000-0000-0000-0000000005e1'''
\set S2 '''00000000-0000-0000-0000-0000000005e2'''
\set S3 '''00000000-0000-0000-0000-0000000005e3'''
\set S4 '''00000000-0000-0000-0000-0000000005e4'''
\set S5 '''00000000-0000-0000-0000-0000000005e5'''
\set SX '''00000000-0000-0000-0000-0000000005f1'''
\set B1 '''00000000-0000-0000-0000-000000000b11'''
\set B2 '''00000000-0000-0000-0000-000000000b12'''
\set M1 '''00000000-0000-0000-0000-000000000a11'''
\set M2 '''00000000-0000-0000-0000-000000000a12'''
\set M21 '''00000000-0000-0000-0000-000000000a21'''
\set V1 '''00000000-0000-0000-0000-000000000b01'''
\set MD '''00000000-0000-0000-0000-000000000e02'''
\set VD1 '''00000000-0000-0000-0000-000000000da1'''
\set VD2 '''00000000-0000-0000-0000-000000000da2'''
\set C1 '''00000000-0000-0000-0000-00000000c001'''
\set C2 '''00000000-0000-0000-0000-00000000c002'''

-- ============================== UNITS
\echo '--- OK expected: seeded units exist (6 convertible + 7 pack)'
DO $$ BEGIN ASSERT (SELECT count(*) FROM inventory_units) = 13; ASSERT (SELECT factor_to_base FROM inventory_units WHERE code='dozen') = 12; END $$;
\echo '--- FAIL expected: PACK unit with a factor'
INSERT INTO inventory_units(code,name,family,factor_to_base,base_code) VALUES ('sack','sack','PACK',50,'g');
\echo '--- FAIL expected: MASS unit without factor'
INSERT INTO inventory_units(code,name,family) VALUES ('mg','milligram','MASS');
\echo '--- FAIL expected: zero factor'
INSERT INTO inventory_units(code,name,family,factor_to_base,base_code) VALUES ('mg','milligram','MASS',0,'g');
\echo '--- FAIL expected: invalid family'
INSERT INTO inventory_units(code,name,family) VALUES ('x','x','AREA');

-- ============================== MASTERS
\echo '--- OK expected: category'
INSERT INTO stock_categories(tenant_id,name) VALUES (:T,'Dairy');
\echo '--- FAIL expected: duplicate category name'
INSERT INTO stock_categories(tenant_id,name) VALUES (:T,'Dairy');
\echo '--- FAIL expected: blank category name'
INSERT INTO stock_categories(tenant_id,name) VALUES (:T,'  ');
\echo '--- OK expected: vendor GSTIN stored as text, NOT validated'
UPDATE vendors SET gstin='not-a-real-gstin' WHERE id=:VD1;
\echo '--- FAIL expected: GSTIN longer than 20 characters'
UPDATE vendors SET gstin='123456789012345678901' WHERE id=:VD1;
\echo '--- FAIL expected: duplicate vendor name (case-insensitive)'
INSERT INTO vendors(tenant_id,name) VALUES (:T,'FRESH DAIRY');
\echo '--- FAIL expected: payment terms 400 days'
UPDATE vendors SET payment_terms_days=400 WHERE id=:VD1;
\echo '--- OK expected: same vendor name in another tenant'
INSERT INTO vendors(tenant_id,name) VALUES (:T2,'Fresh Dairy');
\echo '--- OK expected: item with PACK purchase unit (crate of 24)'
SELECT purchase_to_base FROM stock_items WHERE id=:S3;
\echo '--- FAIL expected: base unit kg (must be g, ml or pcs)'
INSERT INTO stock_items(tenant_id,name,base_unit_code,purchase_unit_code,purchase_to_base) VALUES (:T,'A','kg','kg',1);
\echo '--- FAIL expected: purchase unit litre for a gram item'
INSERT INTO stock_items(tenant_id,name,base_unit_code,purchase_unit_code,purchase_to_base) VALUES (:T,'B','g','l',1000);
\echo '--- FAIL expected: purchase unit kg with factor 100'
INSERT INTO stock_items(tenant_id,name,base_unit_code,purchase_unit_code,purchase_to_base) VALUES (:T,'C','g','kg',100);
\echo '--- OK expected: purchase unit dozen for a piece item with factor 12'
INSERT INTO stock_items(tenant_id,name,base_unit_code,purchase_unit_code,purchase_to_base) VALUES (:T,'Eggs','pcs','dozen',12);
\echo '--- FAIL expected: zero purchase_to_base for a PACK unit'
INSERT INTO stock_items(tenant_id,name,base_unit_code,purchase_unit_code,purchase_to_base) VALUES (:T,'D','pcs','box',0);
\echo '--- FAIL expected: duplicate item name (case-insensitive)'
INSERT INTO stock_items(tenant_id,name,base_unit_code,purchase_unit_code,purchase_to_base) VALUES (:T,'PANEER','g','kg',1000);
\echo '--- OK expected: item with SKU'
UPDATE stock_items SET sku='PN-01', barcode='8901234567890' WHERE id=:S1;
\echo '--- FAIL expected: duplicate SKU (case-insensitive)'
UPDATE stock_items SET sku='pn-01' WHERE id=:S2;
\echo '--- FAIL expected: duplicate barcode'
UPDATE stock_items SET barcode='8901234567890' WHERE id=:S2;
\echo '--- FAIL expected: par level below reorder level'
UPDATE stock_items SET par_level=100 WHERE id=:S1;
\echo '--- FAIL expected: negative reorder level'
UPDATE stock_items SET reorder_level=-1 WHERE id=:S1;
\echo '--- FAIL expected: invalid item kind'
UPDATE stock_items SET item_kind='SERVICE' WHERE id=:S1;
\echo '--- FAIL expected: changing the purchase unit to a mismatching factor later'
UPDATE stock_items SET purchase_to_base=999 WHERE id=:S1;
\echo '--- OK expected: outlet settings row'
INSERT INTO inventory_settings(outlet_id,tenant_id) VALUES (:O,:T);
\echo '--- FAIL expected: invalid negative-stock policy'
UPDATE inventory_settings SET negative_stock_policy='DENY' WHERE outlet_id=:O;
\echo '--- FAIL expected: dead-stock days below 7'
UPDATE inventory_settings SET dead_stock_days=3 WHERE outlet_id=:O;
\echo '--- FAIL expected: counter kind not in list'
INSERT INTO inventory_counters(outlet_id,kind) VALUES (:O,'XYZ');
\echo '--- OK expected: counter'
INSERT INTO inventory_counters(outlet_id,kind,last_value) VALUES (:O,'PO',0);

-- ============================== STOCK LEVELS ARE LEDGER-ONLY
\echo '--- FAIL expected: direct insert of a level with stock'
INSERT INTO stock_levels(outlet_id,stock_item_id,tenant_id,on_hand) VALUES (:O,:S1,:T,5);
\echo '--- OK expected: ledger entry creates the level (OPENING 2000 g at 0.30)'
SELECT t_mov(:O,:S5,'OPENING',2000,'t-open-s5',p_cost=>0.30);
\echo '--- FAIL expected: direct update of on_hand'
UPDATE stock_levels SET on_hand=1 WHERE outlet_id=:O AND stock_item_id=:S5;
\echo '--- FAIL expected: direct update of avg_cost'
UPDATE stock_levels SET avg_cost=9 WHERE outlet_id=:O AND stock_item_id=:S5;
\echo '--- FAIL expected: delete of a level'
DELETE FROM stock_levels WHERE outlet_id=:O AND stock_item_id=:S5;
\echo '--- OK expected: reorder override is allowed to change directly'
UPDATE stock_levels SET reorder_level_override=500 WHERE outlet_id=:O AND stock_item_id=:S5;
\echo '--- FAIL expected: negative reorder override'
UPDATE stock_levels SET reorder_level_override=-5 WHERE outlet_id=:O AND stock_item_id=:S5;

-- ============================== GRN + PURCHASE LEDGER
\echo '--- OK expected: draft GRN g1 with a line, then posted'
INSERT INTO goods_receipts(id,tenant_id,outlet_id,vendor_id,grn_number,invoice_number,invoice_date,subtotal,tax_total,total_amount,created_by)
 VALUES ('00000000-0000-0000-0000-0000000009a1',:T,:O,:VD1,'GRN-000001','INV-1','2026-11-20',4000,200,4200,:UI);
INSERT INTO goods_receipt_lines(grn_id,stock_item_id,qty_purchase,purchase_unit_code,purchase_to_base,qty_base,unit_price,unit_cost_base,line_amount,tax_amount)
 VALUES ('00000000-0000-0000-0000-0000000009a1',:S1,10,'kg',1000,10000,400,0.4,4000,200);
UPDATE goods_receipts SET status='POSTED',posted_by=:UI,posted_at=now() WHERE id='00000000-0000-0000-0000-0000000009a1';
\echo '--- FAIL expected: GRN total does not equal subtotal+tax+other+round_off'
INSERT INTO goods_receipts(tenant_id,outlet_id,vendor_id,grn_number,subtotal,tax_total,total_amount,created_by) VALUES (:T,:O,:VD1,'GRN-X1',100,5,100,:UI);
\echo '--- FAIL expected: posting without invoice number'
INSERT INTO goods_receipts(tenant_id,outlet_id,vendor_id,grn_number,status,subtotal,total_amount,created_by,posted_by,posted_at) VALUES (:T,:O,:VD1,'GRN-X2','POSTED',100,100,:UI,:UI,now());
\echo '--- FAIL expected: duplicate invoice for the same vendor (case and spaces ignored)'
INSERT INTO goods_receipts(tenant_id,outlet_id,vendor_id,grn_number,invoice_number,invoice_date,subtotal,total_amount,created_by) VALUES (:T,:O,:VD1,'GRN-X3',' inv-1 ','2026-11-21',100,100,:UI);
\echo '--- FAIL expected: duplicate invoice for the same vendor at another outlet'
INSERT INTO goods_receipts(tenant_id,outlet_id,vendor_id,grn_number,invoice_number,invoice_date,subtotal,total_amount,created_by) VALUES (:T,:O2,:VD1,'GRN-X3','INV-1','2026-11-21',100,100,:UI);
\echo '--- OK expected: same invoice number from another vendor'
INSERT INTO goods_receipts(id,tenant_id,outlet_id,vendor_id,grn_number,invoice_number,invoice_date,subtotal,total_amount,created_by) VALUES ('00000000-0000-0000-0000-0000000009a3',:T,:O,:VD2,'GRN-000003','INV-1','2026-11-21',100,100,:UI);
\echo '--- FAIL expected: duplicate GRN number at the outlet'
INSERT INTO goods_receipts(tenant_id,outlet_id,vendor_id,grn_number,subtotal,total_amount,created_by) VALUES (:T,:O,:VD1,'GRN-000001',1,1,:UI);
\echo '--- FAIL expected: attachment of an unsupported type'
UPDATE goods_receipts SET attachment_key='k/a.exe',attachment_content_type='application/x-msdownload',attachment_size_bytes=100 WHERE id='00000000-0000-0000-0000-0000000009a3';
\echo '--- FAIL expected: attachment bigger than 5 MB'
UPDATE goods_receipts SET attachment_key='k/a.pdf',attachment_content_type='application/pdf',attachment_size_bytes=5242881 WHERE id='00000000-0000-0000-0000-0000000009a3';
\echo '--- FAIL expected: attachment key without content type'
UPDATE goods_receipts SET attachment_key='k/a.pdf' WHERE id='00000000-0000-0000-0000-0000000009a3';
\echo '--- OK expected: PDF attachment'
UPDATE goods_receipts SET attachment_key='k/a.pdf',attachment_content_type='application/pdf',attachment_size_bytes=120000 WHERE id='00000000-0000-0000-0000-0000000009a3';
\echo '--- FAIL expected: GRN line qty_base inconsistent with purchase_to_base'
INSERT INTO goods_receipt_lines(grn_id,stock_item_id,qty_purchase,purchase_unit_code,purchase_to_base,qty_base,unit_price,unit_cost_base,line_amount) VALUES ('00000000-0000-0000-0000-0000000009a3',:S2,2,'l',1000,1999,50,0.05,100);
\echo '--- FAIL expected: GRN line unit_cost_base inconsistent with price'
INSERT INTO goods_receipt_lines(grn_id,stock_item_id,qty_purchase,purchase_unit_code,purchase_to_base,qty_base,unit_price,unit_cost_base,line_amount) VALUES ('00000000-0000-0000-0000-0000000009a3',:S2,2,'l',1000,2000,50,0.06,100);
\echo '--- FAIL expected: GRN line amount inconsistent with qty x price'
INSERT INTO goods_receipt_lines(grn_id,stock_item_id,qty_purchase,purchase_unit_code,purchase_to_base,qty_base,unit_price,unit_cost_base,line_amount) VALUES ('00000000-0000-0000-0000-0000000009a3',:S2,2,'l',1000,2000,50,0.05,99);
\echo '--- OK expected: valid line on a draft GRN'
INSERT INTO goods_receipt_lines(grn_id,stock_item_id,qty_purchase,purchase_unit_code,purchase_to_base,qty_base,unit_price,unit_cost_base,line_amount) VALUES ('00000000-0000-0000-0000-0000000009a3',:S2,2,'l',1000,2000,50,0.05,100);
\echo '--- FAIL expected: same item twice on one GRN'
INSERT INTO goods_receipt_lines(grn_id,stock_item_id,qty_purchase,purchase_unit_code,purchase_to_base,qty_base,unit_price,unit_cost_base,line_amount) VALUES ('00000000-0000-0000-0000-0000000009a3',:S2,1,'l',1000,1000,50,0.05,50);
\echo '--- FAIL expected: line added to a posted GRN'
INSERT INTO goods_receipt_lines(grn_id,stock_item_id,qty_purchase,purchase_unit_code,purchase_to_base,qty_base,unit_price,unit_cost_base,line_amount) VALUES ('00000000-0000-0000-0000-0000000009a1',:S2,1,'l',1000,1000,50,0.05,50);
\echo '--- FAIL expected: line of a posted GRN edited'
UPDATE goods_receipt_lines SET unit_price=1,unit_cost_base=0.001,line_amount=10 WHERE grn_id='00000000-0000-0000-0000-0000000009a1';
\echo '--- FAIL expected: posted GRN total edited'
UPDATE goods_receipts SET subtotal=1,total_amount=1+tax_total WHERE id='00000000-0000-0000-0000-0000000009a1';
\echo '--- FAIL expected: posted GRN deleted'
DELETE FROM goods_receipts WHERE id='00000000-0000-0000-0000-0000000009a1';
\echo '--- OK expected: PURCHASE movement 10 kg at 0.4 per g'
SELECT t_mov(:O,:S1,'PURCHASE',10000,'t-p1',p_cost=>0.4,p_ref_type=>'GRN',p_ref_id=>'00000000-0000-0000-0000-0000000009a1');
\echo '--- FAIL expected: PURCHASE without GRN reference'
SELECT t_mov(:O,:S1,'PURCHASE',100,'t-p-noref',p_cost=>0.4);
\echo '--- FAIL expected: PURCHASE with cost basis other than ACTUAL'
SELECT t_mov(:O,:S1,'PURCHASE',100,'t-p-avg',p_cost=>0.4,p_basis=>'AVERAGE',p_ref_type=>'GRN',p_ref_id=>gen_random_uuid());
\echo '--- OK expected: second purchase 5000 g at 0.50 gives average 0.433333 and 15000 on hand'
SELECT t_mov(:O,:S1,'PURCHASE',5000,'t-p2',p_cost=>0.5,p_ref_type=>'GRN',p_ref_id=>gen_random_uuid());
DO $$ DECLARE l stock_levels%ROWTYPE; BEGIN
  SELECT * INTO l FROM stock_levels WHERE outlet_id='00000000-0000-0000-0000-0000000000a1' AND stock_item_id='00000000-0000-0000-0000-0000000005e1';
  ASSERT l.on_hand = 15000, 'on_hand'; ASSERT l.avg_cost = 0.433333, 'avg'; ASSERT l.avg_cost_known; ASSERT l.last_purchase_cost = 0.5; END $$;
\echo '--- FAIL expected: negative price'
SELECT t_mov(:O,:S1,'PURCHASE',100,'t-p-neg',p_cost=>-1,p_ref_type=>'GRN',p_ref_id=>gen_random_uuid());
\echo '--- OK expected: older back-dated purchase (at the current average) does not replace last_purchase_cost'
SELECT t_mov(:O,:S1,'PURCHASE',1000,'t-p3',p_cost=>0.433333,p_ref_type=>'GRN',p_ref_id=>gen_random_uuid(),p_at=>'2026-11-01 10:00+05:30');
DO $$ BEGIN ASSERT (SELECT last_purchase_cost FROM stock_levels WHERE outlet_id='00000000-0000-0000-0000-0000000000a1' AND stock_item_id='00000000-0000-0000-0000-0000000005e1') = 0.5; END $$;

-- ============================== LEDGER RULES
\echo '--- FAIL expected: zero quantity'
INSERT INTO stock_movements(tenant_id,outlet_id,stock_item_id,kind,quantity_base,unit_cost,cost_basis,occurred_at,business_date,reason_code,dedupe_key) VALUES (:T,:O,:S1,'ADJUSTMENT',0,0,'UNKNOWN',now(),current_date,'OTHER','z');
\echo '--- FAIL expected: OPENING with negative quantity'
SELECT t_mov(:O,:S2,'OPENING',-5,'t-neg-open',p_cost=>0,p_basis=>'UNKNOWN');
\echo '--- FAIL expected: SALE with positive quantity'
SELECT t_mov(:O,:S5,'SALE',5,'t-pos-sale',p_cons=>:C1,p_cost=>0.3,p_basis=>'AVERAGE');
\echo '--- FAIL expected: WASTAGE without reason'
SELECT t_mov(:O,:S1,'WASTAGE',-5,'t-w-noreason');
\echo '--- FAIL expected: SALE without consumption'
SELECT t_mov(:O,:S1,'SALE',-5,'t-sale-nocons');
\echo '--- OK expected: consumption anchor for bill 1'
INSERT INTO stock_consumptions(id,tenant_id,outlet_id,bill_id,business_date,source,covered_net_amount,uncovered_net_amount) VALUES (:C1,:T,:O,:B1,'2026-11-23','BILL_PAID',80,20);
\echo '--- FAIL expected: second consumption for the same bill'
INSERT INTO stock_consumptions(tenant_id,outlet_id,bill_id,business_date,source) VALUES (:T,:O,:B1,'2026-11-23','OFFLINE_SYNC');
\echo '--- FAIL expected: consumption with invalid status'
UPDATE stock_consumptions SET status='DONE' WHERE id=:C1;
\echo '--- FAIL expected: consumption with invalid source'
INSERT INTO stock_consumptions(tenant_id,outlet_id,bill_id,business_date,source) VALUES (:T,:O,:B2,'2026-11-23','MANUAL');
\echo '--- OK expected: skip row (no recipe) recorded'
INSERT INTO stock_consumption_skips(consumption_id,menu_item_id,quantity,line_net_amount,reason) VALUES (:C1,:M2,1,20,'NO_RECIPE');
\echo '--- FAIL expected: skip row with invalid reason'
INSERT INTO stock_consumption_skips(consumption_id,menu_item_id,quantity,line_net_amount,reason) VALUES (:C1,:M2,1,20,'FORGOT');
\echo '--- FAIL expected: outflow with a caller-supplied wrong cost'
SELECT t_mov(:O,:S1,'SALE',-1500,'t-sale-bad',p_cons=>:C1,p_cost=>0.1,p_basis=>'AVERAGE');
\echo '--- OK expected: SALE 1500 g at the average 0.433333 (value -650.00)'
SELECT t_mov(:O,:S1,'SALE',-1500,'t-sale1',p_cons=>:C1,p_ref_type=>'BILL',p_ref_id=>:B1);
DO $$ DECLARE m stock_movements%ROWTYPE; BEGIN
  SELECT * INTO m FROM stock_movements WHERE dedupe_key='t-sale1';
  ASSERT m.unit_cost = 0.433333 AND m.cost_basis='AVERAGE' AND NOT m.cost_estimated; ASSERT m.line_value = -650.00, 'line_value ' || m.line_value;
  ASSERT (SELECT on_hand FROM stock_levels WHERE outlet_id='00000000-0000-0000-0000-0000000000a1' AND stock_item_id='00000000-0000-0000-0000-0000000005e1') = 14500 + 1000 - 1000 + 0 ,'on_hand after sale'; END $$;
\echo '--- FAIL expected: duplicate dedupe key (same sale applied twice)'
SELECT t_mov(:O,:S1,'SALE',-1500,'t-sale1',p_cons=>:C1);
\echo '--- FAIL expected: reversal larger than the original sale'
SELECT t_mov(:O,:S1,'SALE_REVERSAL',1501,'t-rev-big',p_cost=>0.433333,p_basis=>'REVERSAL',p_rev=>(SELECT id FROM stock_movements WHERE dedupe_key='t-sale1'));
\echo '--- FAIL expected: reversal at a cost other than the original sale cost'
SELECT t_mov(:O,:S1,'SALE_REVERSAL',10,'t-rev-cost',p_cost=>0.5,p_basis=>'REVERSAL',p_rev=>(SELECT id FROM stock_movements WHERE dedupe_key='t-sale1'));
\echo '--- FAIL expected: reversal pointing at a PURCHASE'
SELECT t_mov(:O,:S1,'SALE_REVERSAL',10,'t-rev-bad',p_cost=>0.4,p_basis=>'REVERSAL',p_rev=>(SELECT id FROM stock_movements WHERE dedupe_key='t-p1'));
\echo '--- FAIL expected: reversal without a target'
SELECT t_mov(:O,:S1,'SALE_REVERSAL',10,'t-rev-none',p_cost=>0.433333,p_basis=>'REVERSAL');
\echo '--- OK expected: proportional reversal of 40 percent (600 g) at the original unit cost'
SELECT t_mov(:O,:S1,'SALE_REVERSAL',600,'t-rev1',p_cost=>0.433333,p_basis=>'REVERSAL',p_ref_type=>'BILL_VOID',p_ref_id=>:B1,p_rev=>(SELECT id FROM stock_movements WHERE dedupe_key='t-sale1'));
\echo '--- OK expected: reversal of the remaining 900 g reaches exactly the original quantity and value'
SELECT t_mov(:O,:S1,'SALE_REVERSAL',900,'t-rev2',p_cost=>0.433333,p_basis=>'REVERSAL',p_ref_type=>'BILL_VOID',p_ref_id=>:B1,p_rev=>(SELECT id FROM stock_movements WHERE dedupe_key='t-sale1'));
DO $$ DECLARE l stock_levels%ROWTYPE; BEGIN
  SELECT * INTO l FROM stock_levels WHERE outlet_id='00000000-0000-0000-0000-0000000000a1' AND stock_item_id='00000000-0000-0000-0000-0000000005e1';
  ASSERT l.on_hand = 16000, 'on_hand ' || l.on_hand; ASSERT l.avg_cost = 0.433333, 'avg ' || l.avg_cost; END $$;
\echo '--- FAIL expected: a further reversal after full reversal'
SELECT t_mov(:O,:S1,'SALE_REVERSAL',1,'t-rev3',p_cost=>0.433333,p_basis=>'REVERSAL',p_rev=>(SELECT id FROM stock_movements WHERE dedupe_key='t-sale1'));
\echo '--- FAIL expected: SALE_REVERSAL for another stock item than the original'
SELECT t_mov(:O,:S5,'SALE_REVERSAL',1,'t-rev-item',p_cost=>0.3,p_basis=>'REVERSAL',p_rev=>(SELECT id FROM stock_movements WHERE dedupe_key='t-sale1'));
\echo '--- FAIL expected: positive ADJUSTMENT at an invented cost'
SELECT t_mov(:O,:S1,'ADJUSTMENT',10,'t-adj-actual',p_reason=>'FOUND_STOCK',p_cost=>9,p_basis=>'ACTUAL');
\echo '--- FAIL expected: AVERAGE inflow at a cost other than the current average'
SELECT t_mov(:O,:S1,'ADJUSTMENT',10,'t-adj-wrongavg',p_reason=>'FOUND_STOCK',p_cost=>0.9,p_basis=>'AVERAGE');
\echo '--- OK expected: positive ADJUSTMENT at the current average does not move the average'
SELECT t_mov(:O,:S1,'ADJUSTMENT',100,'t-adj1',p_reason=>'FOUND_STOCK',p_cost=>0.433333,p_basis=>'AVERAGE');
DO $$ BEGIN ASSERT (SELECT avg_cost FROM stock_levels WHERE outlet_id='00000000-0000-0000-0000-0000000000a1' AND stock_item_id='00000000-0000-0000-0000-0000000005e1') = 0.433333; END $$;
\echo '--- FAIL expected: ADJUSTMENT with unknown reason missing'
SELECT t_mov(:O,:S1,'ADJUSTMENT',-1,'t-adj-noreason');
\echo '--- FAIL expected: UNKNOWN cost basis with a non-zero cost (cost rule)'
INSERT INTO stock_movements(tenant_id,outlet_id,stock_item_id,kind,quantity_base,unit_cost,cost_basis,occurred_at,business_date,reason_code,dedupe_key) VALUES (:T,:O,:S2,'WASTAGE',-1,5,'UNKNOWN',now(),current_date,'SPILL','t-unk');
\echo '--- FAIL expected: invalid movement kind'
SELECT t_mov(:O,:S2,'GIFT',-1,'t-gift');
\echo '--- FAIL expected: invalid ref type'
INSERT INTO stock_movements(tenant_id,outlet_id,stock_item_id,kind,quantity_base,unit_cost,cost_basis,occurred_at,business_date,reason_code,ref_type,dedupe_key) VALUES (:T,:O,:S1,'WASTAGE',-1,0.433333,'AVERAGE',now(),current_date,'SPILL','EMAIL','t-ref');
\echo '--- FAIL expected: stock item of another tenant'
SELECT t_mov(:O,:SX,'OPENING',10,'t-xt',p_cost=>1);
\echo '--- FAIL expected: outlet of another tenant'
INSERT INTO stock_movements(tenant_id,outlet_id,stock_item_id,kind,quantity_base,unit_cost,cost_basis,occurred_at,business_date,dedupe_key) VALUES (:T,:O3,:S1,'OPENING',10,1,'ACTUAL',now(),current_date,'t-xo');
\echo '--- FAIL expected: movement for an item that is not tracked'
UPDATE stock_items SET track_stock=false WHERE id=:S2;
SELECT t_mov(:O,:S2,'OPENING',10,'t-nt',p_cost=>1);
UPDATE stock_items SET track_stock=true WHERE id=:S2;
\echo '--- OK expected: sale of an item never purchased: UNKNOWN cost at 0, flagged estimated, stock goes negative (policy ALLOW)'
SELECT t_mov(:O,:S2,'SALE',-200,'t-sale-unknown',p_cons=>:C1);
DO $$ DECLARE m stock_movements%ROWTYPE; BEGIN SELECT * INTO m FROM stock_movements WHERE dedupe_key='t-sale-unknown';
  ASSERT m.cost_basis='UNKNOWN' AND m.cost_estimated AND m.unit_cost=0; ASSERT (SELECT on_hand FROM stock_levels WHERE outlet_id='00000000-0000-0000-0000-0000000000a1' AND stock_item_id='00000000-0000-0000-0000-0000000005e2') = -200; END $$;
\echo '--- OK expected: purchase after negative stock restarts the average at the purchase cost'
SELECT t_mov(:O,:S2,'PURCHASE',1000,'t-milk-p',p_cost=>0.06,p_ref_type=>'GRN',p_ref_id=>gen_random_uuid());
DO $$ DECLARE l stock_levels%ROWTYPE; BEGIN SELECT * INTO l FROM stock_levels WHERE outlet_id='00000000-0000-0000-0000-0000000000a1' AND stock_item_id='00000000-0000-0000-0000-0000000005e2';
  ASSERT l.on_hand = 800; ASSERT l.avg_cost = 0.06; END $$;
\echo '--- OK expected: sale when nothing on hand uses LAST_PURCHASE cost, flagged estimated'
SELECT t_mov(:O,:S2,'SALE',-900,'t-milk-s1',p_cons=>:C1);
SELECT t_mov(:O,:S2,'SALE',-100,'t-milk-s2',p_cons=>:C1);
DO $$ DECLARE m stock_movements%ROWTYPE; BEGIN SELECT * INTO m FROM stock_movements WHERE dedupe_key='t-milk-s2';
  ASSERT m.cost_basis='LAST_PURCHASE' AND m.cost_estimated AND m.unit_cost=0.06; END $$;
\echo '--- OK expected: BLOCK_MANUAL policy set'
UPDATE inventory_settings SET negative_stock_policy='BLOCK_MANUAL' WHERE outlet_id=:O;
\echo '--- FAIL expected: wastage that would take stock below zero under BLOCK_MANUAL'
SELECT t_mov(:O,:S5,'WASTAGE',-2001,'t-w-big',p_reason=>'SPILL');
\echo '--- OK expected: wastage within stock under BLOCK_MANUAL'
SELECT t_mov(:O,:S5,'WASTAGE',-100,'t-w-ok',p_reason=>'SPILL');
\echo '--- OK expected: a SALE can still drive stock negative under BLOCK_MANUAL (billing is never blocked)'
SELECT t_mov(:O,:S5,'SALE',-5000,'t-sale-neg',p_cons=>:C1);
UPDATE inventory_settings SET negative_stock_policy='ALLOW' WHERE outlet_id=:O;
\echo '--- FAIL expected: UPDATE on the ledger'
UPDATE stock_movements SET note='x' WHERE dedupe_key='t-sale1';
\echo '--- FAIL expected: UPDATE of quantity on the ledger'
UPDATE stock_movements SET quantity_base=-1 WHERE dedupe_key='t-sale1';
\echo '--- FAIL expected: DELETE on the ledger'
DELETE FROM stock_movements WHERE dedupe_key='t-sale1';
\echo '--- FAIL expected: TRUNCATE on the ledger'
TRUNCATE stock_movements;
\echo '--- OK expected: the ledger sum equals on_hand for every level (no divergence)'
DO $$ BEGIN ASSERT NOT EXISTS (
  SELECT 1 FROM stock_levels l LEFT JOIN (SELECT outlet_id, stock_item_id, sum(quantity_base) q FROM stock_movements GROUP BY 1,2) m
    ON m.outlet_id=l.outlet_id AND m.stock_item_id=l.stock_item_id WHERE l.on_hand IS DISTINCT FROM COALESCE(m.q,0)), 'ledger and levels diverge'; END $$;

-- ============================== RECIPES
\echo '--- OK expected: draft recipe for a menu item'
INSERT INTO recipes(id,tenant_id,outlet_id,target_type,menu_item_id,version,effective_from) VALUES ('00000000-0000-0000-0000-00000000f001',:T,:O,'MENU_ITEM',:M1,1,'2026-01-01');
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base,wastage_percent) VALUES ('00000000-0000-0000-0000-00000000f001',1,:S1,0.15,'kg',150,5);
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f001',2,:S5,2,'g',2);
\echo '--- FAIL expected: recipe line unit of the wrong family (litre for grams)'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f001',3,:S2,1,'g',1) ;
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f001',3,:S1,1,'l',1000);
\echo '--- FAIL expected: recipe line in a pack unit'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f001',3,:S3,1,'crate',24);
\echo '--- FAIL expected: quantity_base not equal to quantity x unit factor'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f001',3,:S3,2,'pcs',3);
\echo '--- FAIL expected: wastage 100 percent'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base,wastage_percent) VALUES ('00000000-0000-0000-0000-00000000f001',3,:S3,1,'pcs',1,100);
\echo '--- FAIL expected: zero quantity'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f001',3,:S3,0,'pcs',0);
\echo '--- FAIL expected: same ingredient twice in a recipe'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f001',3,:S1,1,'g',1);
\echo '--- FAIL expected: ingredient of another tenant'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f001',3,:SX,1,'g',1);
\echo '--- FAIL expected: EXPAND on a non-prep ingredient'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base,consume_mode) VALUES ('00000000-0000-0000-0000-00000000f001',3,:S2,100,'ml',100,'EXPAND');
\echo '--- OK expected: prep item used as a sub-recipe ingredient (EXPAND)'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base,consume_mode) VALUES ('00000000-0000-0000-0000-00000000f001',3,:S4,100,'g',100,'EXPAND');
\echo '--- FAIL expected: recipe for a menu item of another outlet'
INSERT INTO recipes(tenant_id,outlet_id,target_type,menu_item_id,version,effective_from) VALUES (:T,:O,'MENU_ITEM',:M21,1,'2026-01-01');
\echo '--- FAIL expected: recipe with two targets'
INSERT INTO recipes(tenant_id,outlet_id,target_type,menu_item_id,variant_id,version,effective_from) VALUES (:T,:O,'MENU_ITEM',:M1,:V1,9,'2026-01-01');
\echo '--- FAIL expected: target type does not match the target column'
INSERT INTO recipes(tenant_id,outlet_id,target_type,variant_id,version,effective_from) VALUES (:T,:O,'MENU_ITEM',:V1,9,'2026-01-01');
\echo '--- FAIL expected: inherit flag on a menu-item recipe'
INSERT INTO recipes(tenant_id,outlet_id,target_type,menu_item_id,version,effective_from,inherit_item_recipe) VALUES (:T,:O,'MENU_ITEM',:M1,9,'2026-01-01',true);
\echo '--- FAIL expected: effective_to not after effective_from'
INSERT INTO recipes(tenant_id,outlet_id,target_type,menu_item_id,version,effective_from,effective_to) VALUES (:T,:O,'MENU_ITEM',:M1,9,'2026-01-01','2026-01-01');
\echo '--- FAIL expected: outlet-less recipe for a menu item'
INSERT INTO recipes(tenant_id,target_type,menu_item_id,version,effective_from) VALUES (:T,'MENU_ITEM',:M1,9,'2026-01-01');
\echo '--- FAIL expected: portion factor zero'
INSERT INTO recipes(tenant_id,outlet_id,target_type,variant_id,version,effective_from,portion_factor,inherit_item_recipe) VALUES (:T,:O,'VARIANT',:V1,1,'2026-01-01',0,true);
\echo '--- OK expected: variant recipe inheriting the item recipe at 0.6 portion'
INSERT INTO recipes(id,tenant_id,outlet_id,target_type,variant_id,version,effective_from,portion_factor,inherit_item_recipe) VALUES ('00000000-0000-0000-0000-00000000f002',:T,:O,'VARIANT',:V1,1,'2026-01-01',0.6,true);
\echo '--- FAIL expected: lines on an inheriting variant recipe'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f002',1,:S5,1,'g',1);
\echo '--- OK expected: modifier recipe (extra cheese)'
INSERT INTO recipes(id,tenant_id,outlet_id,target_type,modifier_id,version,effective_from) VALUES ('00000000-0000-0000-0000-00000000f003',:T,:O,'MODIFIER',:MD,1,'2026-01-01');
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f003',1,:S5,5,'g',5);
\echo '--- OK expected: prep recipe (gravy base, yields 1000 g per batch, shared by outlets)'
INSERT INTO recipes(id,tenant_id,target_type,prep_stock_item_id,version,effective_from,yield_qty_base) VALUES ('00000000-0000-0000-0000-00000000f004',:T,'PREP_ITEM',:S4,1,'2026-01-01',1000);
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f004',1,:S1,300,'g',300);
\echo '--- FAIL expected: prep recipe using another prep item (no nesting beyond one level)'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f004',2,:S4,100,'g',100);
\echo '--- FAIL expected: prep recipe whose target is not a PREP item'
INSERT INTO recipes(id,tenant_id,target_type,prep_stock_item_id,version,effective_from,yield_qty_base) VALUES ('00000000-0000-0000-0000-00000000f005',:T,'PREP_ITEM',:S5,1,'2026-01-01',1000);
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f005',1,:S1,300,'g',300);
\echo '--- FAIL expected: prep recipe without yield'
INSERT INTO recipes(tenant_id,target_type,prep_stock_item_id,version,effective_from) VALUES (:T,'PREP_ITEM',:S4,7,'2026-01-01');
\echo '--- FAIL expected: prep recipe bound to one outlet'
INSERT INTO recipes(tenant_id,outlet_id,target_type,prep_stock_item_id,version,effective_from,yield_qty_base) VALUES (:T,:O,'PREP_ITEM',:S4,7,'2026-01-01',1000);
\echo '--- FAIL expected: duplicate version number for the same target'
INSERT INTO recipes(tenant_id,outlet_id,target_type,menu_item_id,version,effective_from) VALUES (:T,:O,'MENU_ITEM',:M1,1,'2027-01-01');
\echo '--- OK expected: draft recipes are deletable'
INSERT INTO recipes(id,tenant_id,outlet_id,target_type,menu_item_id,version,effective_from) VALUES ('00000000-0000-0000-0000-00000000f0ff',:T,:O,'MENU_ITEM',:M2,1,'2026-01-01');
DELETE FROM recipes WHERE id='00000000-0000-0000-0000-00000000f0ff';
\echo '--- OK expected: activate version 1 (open ended)'
UPDATE recipes SET status='ACTIVE' WHERE id='00000000-0000-0000-0000-00000000f001';
\echo '--- FAIL expected: a second ACTIVE version overlapping in time'
INSERT INTO recipes(tenant_id,outlet_id,target_type,menu_item_id,version,effective_from,status) VALUES (:T,:O,'MENU_ITEM',:M1,2,'2026-06-01','ACTIVE');
\echo '--- FAIL expected: line added to an active recipe'
INSERT INTO recipe_lines(recipe_id,line_no,stock_item_id,quantity,unit_code,quantity_base) VALUES ('00000000-0000-0000-0000-00000000f001',9,:S2,1,'ml',1);
\echo '--- FAIL expected: line of an active recipe edited'
UPDATE recipe_lines SET quantity=1,quantity_base=1000 WHERE recipe_id='00000000-0000-0000-0000-00000000f001' AND line_no=1;
\echo '--- FAIL expected: line of an active recipe deleted'
DELETE FROM recipe_lines WHERE recipe_id='00000000-0000-0000-0000-00000000f001' AND line_no=2;
\echo '--- FAIL expected: effective_from of an active recipe changed'
UPDATE recipes SET effective_from='2026-02-01' WHERE id='00000000-0000-0000-0000-00000000f001';
\echo '--- FAIL expected: active recipe deleted'
DELETE FROM recipes WHERE id='00000000-0000-0000-0000-00000000f001';
\echo '--- FAIL expected: active recipe sent back to draft'
UPDATE recipes SET status='DRAFT' WHERE id='00000000-0000-0000-0000-00000000f001';
\echo '--- OK expected: end date set on the active recipe'
UPDATE recipes SET effective_to='2026-06-01' WHERE id='00000000-0000-0000-0000-00000000f001';
\echo '--- OK expected: version 2 starts exactly when version 1 ends (no overlap, no gap)'
INSERT INTO recipes(id,tenant_id,outlet_id,target_type,menu_item_id,version,effective_from,status) VALUES ('00000000-0000-0000-0000-00000000f006',:T,:O,'MENU_ITEM',:M1,2,'2026-06-01','ACTIVE');
\echo '--- OK expected: the version effective at a given instant is unique'
DO $$ BEGIN
  ASSERT (SELECT version FROM recipes WHERE menu_item_id='00000000-0000-0000-0000-000000000a11' AND status='ACTIVE' AND tstzrange(effective_from,effective_to) @> '2026-03-01 12:00+05:30'::timestamptz) = 1;
  ASSERT (SELECT version FROM recipes WHERE menu_item_id='00000000-0000-0000-0000-000000000a11' AND status='ACTIVE' AND tstzrange(effective_from,effective_to) @> '2026-06-01 00:00+00'::timestamptz) = 2;
END $$;
\echo '--- OK expected: archive an active recipe'
UPDATE recipes SET status='ARCHIVED' WHERE id='00000000-0000-0000-0000-00000000f001';
\echo '--- FAIL expected: archived recipe reactivated'
UPDATE recipes SET status='ACTIVE' WHERE id='00000000-0000-0000-0000-00000000f001';

-- ============================== PURCHASE ORDERS
\echo '--- OK expected: PO draft with a line'
INSERT INTO purchase_orders(id,tenant_id,outlet_id,vendor_id,po_number,created_by) VALUES ('00000000-0000-0000-0000-0000000008a1',:T,:O,:VD1,'PO-000001',:UI);
INSERT INTO purchase_order_lines(po_id,stock_item_id,ordered_qty,unit_price) VALUES ('00000000-0000-0000-0000-0000000008a1',:S1,20,400);
\echo '--- FAIL expected: PO line with zero quantity'
INSERT INTO purchase_order_lines(po_id,stock_item_id,ordered_qty,unit_price) VALUES ('00000000-0000-0000-0000-0000000008a1',:S2,0,50);
\echo '--- FAIL expected: same item twice on a PO'
INSERT INTO purchase_order_lines(po_id,stock_item_id,ordered_qty,unit_price) VALUES ('00000000-0000-0000-0000-0000000008a1',:S1,1,400);
\echo '--- FAIL expected: duplicate PO number at the outlet'
INSERT INTO purchase_orders(tenant_id,outlet_id,vendor_id,po_number,created_by) VALUES (:T,:O,:VD1,'PO-000001',:UI);
\echo '--- FAIL expected: SENT without sent_at'
UPDATE purchase_orders SET status='SENT' WHERE id='00000000-0000-0000-0000-0000000008a1';
\echo '--- OK expected: SENT with sent_at'
UPDATE purchase_orders SET status='SENT', sent_at=now() WHERE id='00000000-0000-0000-0000-0000000008a1';
\echo '--- FAIL expected: CANCELLED without a reason'
UPDATE purchase_orders SET status='CANCELLED' WHERE id='00000000-0000-0000-0000-0000000008a1';
\echo '--- FAIL expected: invalid PO status'
UPDATE purchase_orders SET status='CLOSED' WHERE id='00000000-0000-0000-0000-0000000008a1';
\echo '--- OK expected: CANCELLED with a reason'
UPDATE purchase_orders SET status='CANCELLED', cancelled_reason='Vendor out of stock' WHERE id='00000000-0000-0000-0000-0000000008a1';
\echo '--- FAIL expected: negative received quantity'
UPDATE purchase_order_lines SET received_qty=-1 WHERE po_id='00000000-0000-0000-0000-0000000008a1';

-- ============================== GRN VOID, DUPLICATE-INVOICE RELEASE
\echo '--- FAIL expected: VOID without a reason'
UPDATE goods_receipts SET status='VOID' WHERE id='00000000-0000-0000-0000-0000000009a1';
\echo '--- OK expected: posted GRN voided with reason'
UPDATE goods_receipts SET status='VOID', voided_by=:UM, void_reason='Wrong vendor' WHERE id='00000000-0000-0000-0000-0000000009a1';
\echo '--- FAIL expected: void GRN changed again'
UPDATE goods_receipts SET status='POSTED' WHERE id='00000000-0000-0000-0000-0000000009a1';
\echo '--- OK expected: invoice number becomes usable again after the receipt is void'
INSERT INTO goods_receipts(tenant_id,outlet_id,vendor_id,grn_number,invoice_number,invoice_date,subtotal,total_amount,created_by) VALUES (:T,:O,:VD1,'GRN-000010','INV-1','2026-11-22',10,10,:UI);

-- ============================== VENDOR PAYMENTS
\echo '--- OK expected: two more posted GRNs for payment tests'
INSERT INTO goods_receipts(id,tenant_id,outlet_id,vendor_id,grn_number,invoice_number,invoice_date,subtotal,total_amount,status,created_by,posted_by,posted_at) VALUES
 ('00000000-0000-0000-0000-0000000009b1',:T,:O,:VD1,'GRN-000011','INV-P1','2026-11-01',4200,4200,'POSTED',:UI,:UI,now()),
 ('00000000-0000-0000-0000-0000000009b2',:T,:O,:VD1,'GRN-000012','INV-P2','2026-11-02',1000,1000,'POSTED',:UI,:UI,now()),
 ('00000000-0000-0000-0000-0000000009b3',:T,:O,:VD2,'GRN-000013','INV-P3','2026-11-02',100,100,'POSTED',:UI,:UI,now());
INSERT INTO vendor_payments(id,tenant_id,vendor_id,paid_on,amount,method,recorded_by) VALUES ('00000000-0000-0000-0000-0000000007a1',:T,:VD1,'2026-11-10',5000,'UPI',:U);
\echo '--- FAIL expected: payment of zero'
INSERT INTO vendor_payments(tenant_id,vendor_id,paid_on,amount,method,recorded_by) VALUES (:T,:VD1,'2026-11-10',0,'UPI',:U);
\echo '--- FAIL expected: payment method not in list'
INSERT INTO vendor_payments(tenant_id,vendor_id,paid_on,amount,method,recorded_by) VALUES (:T,:VD1,'2026-11-10',5,'BITCOIN',:U);
\echo '--- OK expected: allocate 4200 to the first invoice'
INSERT INTO vendor_payment_allocations(payment_id,grn_id,amount) VALUES ('00000000-0000-0000-0000-0000000007a1','00000000-0000-0000-0000-0000000009b1',4200);
\echo '--- FAIL expected: allocations exceed the payment (4200 + 900 > 5000)'
INSERT INTO vendor_payment_allocations(payment_id,grn_id,amount) VALUES ('00000000-0000-0000-0000-0000000007a1','00000000-0000-0000-0000-0000000009b2',900);
\echo '--- OK expected: allocate the remaining 800'
INSERT INTO vendor_payment_allocations(payment_id,grn_id,amount) VALUES ('00000000-0000-0000-0000-0000000007a1','00000000-0000-0000-0000-0000000009b2',800);
\echo '--- FAIL expected: allocation to an invoice of another vendor'
INSERT INTO vendor_payments(id,tenant_id,vendor_id,paid_on,amount,method,recorded_by) VALUES ('00000000-0000-0000-0000-0000000007a2',:T,:VD1,'2026-11-11',100,'CASH',:U);
INSERT INTO vendor_payment_allocations(payment_id,grn_id,amount) VALUES ('00000000-0000-0000-0000-0000000007a2','00000000-0000-0000-0000-0000000009b3',100);
\echo '--- FAIL expected: allocation to a draft (unposted) receipt'
INSERT INTO vendor_payment_allocations(payment_id,grn_id,amount) VALUES ('00000000-0000-0000-0000-0000000007a2',(SELECT id FROM goods_receipts WHERE grn_number='GRN-000010'),10);
\echo '--- FAIL expected: allocation over the invoice total (4200 already paid)'
INSERT INTO vendor_payment_allocations(payment_id,grn_id,amount) VALUES ('00000000-0000-0000-0000-0000000007a2','00000000-0000-0000-0000-0000000009b1',100);
\echo '--- FAIL expected: duplicate allocation row for the same payment and invoice'
INSERT INTO vendor_payment_allocations(payment_id,grn_id,amount) VALUES ('00000000-0000-0000-0000-0000000007a1','00000000-0000-0000-0000-0000000009b1',1);
\echo '--- OK expected: voiding the first payment frees the invoice'
UPDATE vendor_payments SET voided_at=now() WHERE id='00000000-0000-0000-0000-0000000007a1';
INSERT INTO vendor_payment_allocations(payment_id,grn_id,amount) VALUES ('00000000-0000-0000-0000-0000000007a2','00000000-0000-0000-0000-0000000009b1',100);

-- ============================== ADJUSTMENTS, COUNTS, TRANSFERS, PRODUCTION
\echo '--- OK expected: wastage record'
INSERT INTO stock_adjustments(tenant_id,outlet_id,adjustment_number,kind,stock_item_id,quantity_base,reason_code,value_amount,created_by) VALUES (:T,:O,'ADJ-000001','WASTAGE',:S1,-500,'SPOILAGE',216.67,:UI);
\echo '--- FAIL expected: wastage with a positive quantity'
INSERT INTO stock_adjustments(tenant_id,outlet_id,adjustment_number,kind,stock_item_id,quantity_base,reason_code,value_amount,created_by) VALUES (:T,:O,'ADJ-000002','WASTAGE',:S1,500,'SPOILAGE',1,:UI);
\echo '--- FAIL expected: wastage reason code not in the list'
INSERT INTO stock_adjustments(tenant_id,outlet_id,adjustment_number,kind,stock_item_id,quantity_base,reason_code,value_amount,created_by) VALUES (:T,:O,'ADJ-000002','WASTAGE',:S1,-5,'FELT_LIKE_IT',1,:UI);
\echo '--- FAIL expected: reason OTHER without a note'
INSERT INTO stock_adjustments(tenant_id,outlet_id,adjustment_number,kind,stock_item_id,quantity_base,reason_code,value_amount,created_by) VALUES (:T,:O,'ADJ-000002','WASTAGE',:S1,-5,'OTHER',1,:UI);
\echo '--- FAIL expected: approval required but no approver'
INSERT INTO stock_adjustments(tenant_id,outlet_id,adjustment_number,kind,stock_item_id,quantity_base,reason_code,value_amount,requires_approval,created_by) VALUES (:T,:O,'ADJ-000002','WASTAGE',:S1,-5000,'SPOILAGE',2166,true,:UI);
\echo '--- OK expected: approval required and manager recorded'
INSERT INTO stock_adjustments(tenant_id,outlet_id,adjustment_number,kind,stock_item_id,quantity_base,reason_code,value_amount,requires_approval,approved_by,created_by) VALUES (:T,:O,'ADJ-000002','WASTAGE',:S1,-5000,'SPOILAGE',2166,true,:UM,:UI);
\echo '--- FAIL expected: duplicate adjustment number'
INSERT INTO stock_adjustments(tenant_id,outlet_id,adjustment_number,kind,stock_item_id,quantity_base,reason_code,value_amount,created_by) VALUES (:T,:O,'ADJ-000002','WASTAGE',:S1,-5,'SPILL',1,:UI);
\echo '--- FAIL expected: adjustment reason from the wastage list'
INSERT INTO stock_adjustments(tenant_id,outlet_id,adjustment_number,kind,stock_item_id,quantity_base,reason_code,value_amount,created_by) VALUES (:T,:O,'ADJ-000003','ADJUSTMENT',:S1,5,'SPILL',1,:UI);
\echo '--- OK expected: count sheet with lines and generated variance'
INSERT INTO stock_counts(id,tenant_id,outlet_id,count_number,created_by) VALUES ('00000000-0000-0000-0000-0000000006a1',:T,:O,'CNT-000001',:UI);
INSERT INTO stock_count_lines(count_id,stock_item_id,system_qty_base,avg_cost_snapshot,counted_qty_base) VALUES ('00000000-0000-0000-0000-0000000006a1',:S1,16100,0.433333,15800);
DO $$ DECLARE l stock_count_lines%ROWTYPE; BEGIN SELECT * INTO l FROM stock_count_lines WHERE counted_qty_base=15800;
  ASSERT l.variance_qty = -300; ASSERT l.variance_value = -130.00, 'variance ' || l.variance_value; END $$;
\echo '--- FAIL expected: negative counted quantity'
INSERT INTO stock_count_lines(count_id,stock_item_id,system_qty_base,avg_cost_snapshot,counted_qty_base) VALUES ('00000000-0000-0000-0000-0000000006a1',:S2,0,0.06,-1);
\echo '--- FAIL expected: same item twice on a count sheet'
INSERT INTO stock_count_lines(count_id,stock_item_id,system_qty_base,avg_cost_snapshot) VALUES ('00000000-0000-0000-0000-0000000006a1',:S1,1,1);
\echo '--- FAIL expected: category count without a category'
INSERT INTO stock_counts(tenant_id,outlet_id,count_number,scope,created_by) VALUES (:T,:O,'CNT-000002','CATEGORY',:UI);
\echo '--- FAIL expected: submitted count without submitter'
UPDATE stock_counts SET status='SUBMITTED' WHERE id='00000000-0000-0000-0000-0000000006a1';
\echo '--- FAIL expected: approver is the same person as the submitter (four eyes)'
UPDATE stock_counts SET status='APPROVED',submitted_by=:UI,submitted_at=now(),approved_by=:UI,approved_at=now() WHERE id='00000000-0000-0000-0000-0000000006a1';
\echo '--- FAIL expected: approved without approver'
UPDATE stock_counts SET status='APPROVED',submitted_by=:UI,submitted_at=now() WHERE id='00000000-0000-0000-0000-0000000006a1';
\echo '--- OK expected: submitted by inventory user and approved by manager'
UPDATE stock_counts SET status='APPROVED',submitted_by=:UI,submitted_at=now(),approved_by=:UM,approved_at=now() WHERE id='00000000-0000-0000-0000-0000000006a1';
\echo '--- FAIL expected: invalid count status'
UPDATE stock_counts SET status='DONE' WHERE id='00000000-0000-0000-0000-0000000006a1';
\echo '--- OK expected: COUNT_VARIANCE movement of the shortage'
SELECT t_mov(:O,:S1,'COUNT_VARIANCE',-300,'t-cv1',p_reason=>'COUNT',p_ref_type=>'COUNT',p_ref_id=>'00000000-0000-0000-0000-0000000006a1');
\echo '--- FAIL expected: transfer between the same outlet'
INSERT INTO stock_transfers(tenant_id,from_outlet_id,to_outlet_id,transfer_number,created_by) VALUES (:T,:O,:O,'TRF-000001',:UI);
\echo '--- FAIL expected: transfer to an outlet of another tenant'
INSERT INTO stock_transfers(tenant_id,from_outlet_id,to_outlet_id,transfer_number,created_by) VALUES (:T,:O,:O3,'TRF-000001',:UI);
\echo '--- OK expected: draft transfer with a line'
INSERT INTO stock_transfers(id,tenant_id,from_outlet_id,to_outlet_id,transfer_number,created_by) VALUES ('00000000-0000-0000-0000-0000000005a1',:T,:O,:O2,'TRF-000001',:UI);
INSERT INTO stock_transfer_lines(transfer_id,stock_item_id,qty_sent_base) VALUES ('00000000-0000-0000-0000-0000000005a1',:S1,2000);
\echo '--- FAIL expected: IN_TRANSIT without sender'
UPDATE stock_transfers SET status='IN_TRANSIT' WHERE id='00000000-0000-0000-0000-0000000005a1';
\echo '--- OK expected: sent'
UPDATE stock_transfers SET status='IN_TRANSIT',sent_by=:UI,sent_at=now() WHERE id='00000000-0000-0000-0000-0000000005a1';
UPDATE stock_transfer_lines SET unit_cost_sent=0.433333 WHERE transfer_id='00000000-0000-0000-0000-0000000005a1';
\echo '--- FAIL expected: received without receiver'
UPDATE stock_transfers SET status='RECEIVED' WHERE id='00000000-0000-0000-0000-0000000005a1';
\echo '--- FAIL expected: received more than sent'
UPDATE stock_transfer_lines SET qty_received_base=2001 WHERE transfer_id='00000000-0000-0000-0000-0000000005a1';
\echo '--- OK expected: received 1980 of 2000 (20 g short in transit)'
UPDATE stock_transfer_lines SET qty_received_base=1980 WHERE transfer_id='00000000-0000-0000-0000-0000000005a1';
UPDATE stock_transfers SET status='RECEIVED',received_by=:UI,received_at=now() WHERE id='00000000-0000-0000-0000-0000000005a1';
\echo '--- OK expected: TRANSFER_OUT at average, TRANSFER_IN at the sent cost into the other outlet'
SELECT t_mov(:O,:S1,'TRANSFER_OUT',-2000,'t-trf-out',p_ref_type=>'TRANSFER',p_ref_id=>'00000000-0000-0000-0000-0000000005a1');
SELECT t_mov(:O2,:S1,'TRANSFER_IN',1980,'t-trf-in',p_cost=>0.433333,p_ref_type=>'TRANSFER',p_ref_id=>'00000000-0000-0000-0000-0000000005a1');
\echo '--- FAIL expected: TRANSFER_IN at a cost basis other than ACTUAL'
SELECT t_mov(:O2,:S1,'TRANSFER_IN',10,'t-trf-in2',p_cost=>0.433333,p_basis=>'AVERAGE');
\echo '--- FAIL expected: duplicate transfer number from the same outlet'
INSERT INTO stock_transfers(tenant_id,from_outlet_id,to_outlet_id,transfer_number,created_by) VALUES (:T,:O,:O2,'TRF-000001',:UI);
\echo '--- OK expected: production run turns raw into prep stock'
SELECT t_mov(:O,:S1,'PRODUCTION_CONSUME',-300,'t-prd-c',p_ref_type=>'PRODUCTION',p_ref_id=>gen_random_uuid());
SELECT t_mov(:O,:S4,'PRODUCTION_OUTPUT',1000,'t-prd-o',p_cost=>0.13,p_ref_type=>'PRODUCTION',p_ref_id=>gen_random_uuid());
INSERT INTO production_runs(tenant_id,outlet_id,run_number,prep_stock_item_id,recipe_id,batches,output_qty_base,produced_at,business_date,created_by) VALUES (:T,:O,'PRD-000001',:S4,'00000000-0000-0000-0000-00000000f004',1,980,now(),'2026-11-23',:UI);
\echo '--- FAIL expected: production run with zero batches'
INSERT INTO production_runs(tenant_id,outlet_id,run_number,prep_stock_item_id,recipe_id,batches,output_qty_base,produced_at,business_date,created_by) VALUES (:T,:O,'PRD-000002',:S4,'00000000-0000-0000-0000-00000000f004',0,980,now(),'2026-11-23',:UI);
\echo '--- FAIL expected: production run with zero output'
INSERT INTO production_runs(tenant_id,outlet_id,run_number,prep_stock_item_id,recipe_id,batches,output_qty_base,produced_at,business_date,created_by) VALUES (:T,:O,'PRD-000002',:S4,'00000000-0000-0000-0000-00000000f004',1,0,now(),'2026-11-23',:UI);

-- ============================== SNAPSHOTS, IMPORT JOBS
\echo '--- OK expected: day-close snapshot with generated value'
INSERT INTO stock_snapshots(outlet_id,business_date,stock_item_id,tenant_id,on_hand,avg_cost) VALUES (:O,'2026-11-23',:S1,:T,1000,0.433333);
DO $$ BEGIN ASSERT (SELECT value_amount FROM stock_snapshots WHERE business_date='2026-11-23') = 433.33; END $$;
\echo '--- FAIL expected: second snapshot row for the same outlet, date and item'
INSERT INTO stock_snapshots(outlet_id,business_date,stock_item_id,tenant_id,on_hand,avg_cost) VALUES (:O,'2026-11-23',:S1,:T,1,1);
\echo '--- OK expected: validated import job with row errors'
INSERT INTO inventory_import_jobs(tenant_id,kind,file_key,file_sha256,total_rows,ok_rows,error_rows,errors,created_by)
 VALUES (:T,'STOCK_ITEMS','k/i.csv',repeat('a',64),10,8,2,'[{"row":3,"column":"unit","code":"UNIT_FAMILY_MISMATCH","message":"kg for a ml item"}]',:UI);
\echo '--- FAIL expected: counts do not add up'
INSERT INTO inventory_import_jobs(tenant_id,kind,file_key,file_sha256,total_rows,ok_rows,error_rows,created_by) VALUES (:T,'RECIPES','k/j.csv',repeat('b',64),10,8,1,:UI);
\echo '--- FAIL expected: committed with errors without the valid-only flag'
UPDATE inventory_import_jobs SET status='COMMITTED',committed_at=now() WHERE file_sha256=repeat('a',64);
\echo '--- OK expected: committed with valid-only flag'
UPDATE inventory_import_jobs SET status='COMMITTED',committed_at=now(),commit_valid_only=true WHERE file_sha256=repeat('a',64);
\echo '--- FAIL expected: the same file committed a second time'
INSERT INTO inventory_import_jobs(tenant_id,kind,file_key,file_sha256,status,total_rows,ok_rows,error_rows,created_by,committed_at,commit_valid_only)
 VALUES (:T,'STOCK_ITEMS','k/i2.csv',repeat('a',64),'COMMITTED',10,8,2,:UI,now(),true);
\echo '--- OK expected: the same file may be re-validated (not committed) again'
INSERT INTO inventory_import_jobs(tenant_id,kind,file_key,file_sha256,total_rows,ok_rows,error_rows,created_by) VALUES (:T,'STOCK_ITEMS','k/i3.csv',repeat('a',64),10,10,0,:UI);
\echo '--- FAIL expected: invalid import kind'
INSERT INTO inventory_import_jobs(tenant_id,kind,file_key,file_sha256,total_rows,ok_rows,error_rows,created_by) VALUES (:T,'MENU','k/i4.csv',repeat('c',64),1,1,0,:UI);

-- ============================== FINAL INVARIANTS
\echo '--- OK expected: ledger sum equals on_hand for every level after all scenarios'
DO $$ BEGIN ASSERT NOT EXISTS (
  SELECT 1 FROM stock_levels l LEFT JOIN (SELECT outlet_id, stock_item_id, sum(quantity_base) q FROM stock_movements GROUP BY 1,2) m
    ON m.outlet_id=l.outlet_id AND m.stock_item_id=l.stock_item_id WHERE l.on_hand IS DISTINCT FROM COALESCE(m.q,0)), 'ledger and levels diverge'; END $$;
\echo '--- OK expected: every level has at least one ledger row and vice versa'
DO $$ BEGIN ASSERT NOT EXISTS (SELECT 1 FROM stock_levels l WHERE NOT EXISTS (SELECT 1 FROM stock_movements m WHERE m.outlet_id=l.outlet_id AND m.stock_item_id=l.stock_item_id));
  ASSERT NOT EXISTS (SELECT 1 FROM stock_movements m WHERE NOT EXISTS (SELECT 1 FROM stock_levels l WHERE m.outlet_id=l.outlet_id AND m.stock_item_id=l.stock_item_id)); END $$;
