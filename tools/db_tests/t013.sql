\set T '''00000000-0000-0000-0000-000000000001'''
\set O '''00000000-0000-0000-0000-0000000000a1'''
\set O2 '''00000000-0000-0000-0000-0000000000a2'''
\set U '''00000000-0000-0000-0000-0000000000f1'''
\set M '''00000000-0000-0000-0000-0000000000f2'''
\set C '''00000000-0000-0000-0000-0000000000f3'''
\set C2 '''00000000-0000-0000-0000-0000000000f4'''
\set CAT '''00000000-0000-0000-0000-0000000000c1'''
\set I1 '''00000000-0000-0000-0000-0000000000d1'''
\set I2 '''00000000-0000-0000-0000-0000000000d2'''
\set COMBO '''00000000-0000-0000-0000-0000000000d3'''
\set I4 '''00000000-0000-0000-0000-0000000000d4'''
\set V1 '''00000000-0000-0000-0000-0000000000e9'''
\set V2 '''00000000-0000-0000-0000-0000000000ea'''
\set CA '''00000000-0000-0000-0000-0000000000b9'''
\set CB '''00000000-0000-0000-0000-0000000000ba'''
\set E1 '''00000000-0000-0000-0000-0000000000e1'''
\set E2 '''00000000-0000-0000-0000-0000000000e2'''
\set E3 '''00000000-0000-0000-0000-0000000000e3'''
\set K1 '''00000000-0000-0000-0000-0000000000a5'''
\set B1 '''00000000-0000-0000-0000-000000000b11'''
\set B2 '''00000000-0000-0000-0000-000000000b12'''
\set B3 '''00000000-0000-0000-0000-000000000b13'''
\set B4 '''00000000-0000-0000-0000-000000000b14'''
\set L1 '''00000000-0000-0000-0000-00000000c101'''
\set L2 '''00000000-0000-0000-0000-00000000c102'''
\set CP '''00000000-0000-0000-0000-00000000cc01'''

\echo '=== 1 outlet settings'
\echo '--- FAIL expected: invalid packaging mode'
UPDATE outlets SET packaging_mode='PER_BOX' WHERE id=:O;
\echo '--- FAIL expected: FLAT_PER_ORDER with zero flat charge'
UPDATE outlets SET packaging_mode='FLAT_PER_ORDER', packaging_flat_charge=0 WHERE id=:O;
\echo '--- FAIL expected: packaging order type not in the allowed list'
UPDATE outlets SET packaging_order_types='{ROOM_SERVICE}' WHERE id=:O;
\echo '--- FAIL expected: invalid nc tax mode'
UPDATE outlets SET nc_tax_mode='HALF_TAX' WHERE id=:O;
\echo '--- FAIL expected: open item max price 0'
UPDATE outlets SET open_item_max_price=0 WHERE id=:O;
\echo '--- FAIL expected: negative flat packaging charge'
UPDATE outlets SET packaging_flat_charge=-1 WHERE id=:O;
\echo '--- OK expected: valid packaging + NC + open-item settings'
UPDATE outlets SET packaging_mode='FLAT_PER_ORDER', packaging_flat_charge=10, nc_tax_mode='TAX_ON_LIST_PRICE', open_items_enabled=true, open_item_max_price=750 WHERE id=:O;
\echo '--- FAIL expected: station warn minutes not below late minutes'
INSERT INTO kitchen_stations(tenant_id,outlet_id,name,sla_warn_minutes,sla_late_minutes) VALUES (:T,:O,'S-bad',20,20);
\echo '--- FAIL expected: station warn minutes 0'
INSERT INTO kitchen_stations(tenant_id,outlet_id,name,sla_warn_minutes,sla_late_minutes) VALUES (:T,:O,'S-bad2',0,20);
\echo '--- OK expected: station with SLA 8/15'
INSERT INTO kitchen_stations(tenant_id,outlet_id,name,sla_warn_minutes,sla_late_minutes) VALUES (:T,:O,'S-ok',8,15);

\echo '=== 2 reason codes and role permissions'
\echo '--- OK expected: NC reason code'
INSERT INTO reason_codes(tenant_id,kind,code,label) VALUES (:T,'NC','OWNER_GUEST','Owner guest');
\echo '--- FAIL expected: duplicate reason code in the same kind'
INSERT INTO reason_codes(tenant_id,kind,code,label) VALUES (:T,'NC','OWNER_GUEST','Again');
\echo '--- OK expected: same code under another kind'
INSERT INTO reason_codes(tenant_id,kind,code,label) VALUES (:T,'REFUND','OWNER_GUEST','Refund variant');
\echo '--- FAIL expected: lowercase code'
INSERT INTO reason_codes(tenant_id,kind,code,label) VALUES (:T,'NC','owner','x');
\echo '--- FAIL expected: unknown kind'
INSERT INTO reason_codes(tenant_id,kind,code,label) VALUES (:T,'WASTAGE','SPOIL','x');
\echo '--- FAIL expected: blank label'
INSERT INTO reason_codes(tenant_id,kind,code,label) VALUES (:T,'NC','BLANK','   ');
\echo '--- OK expected: cashier may use open items at this outlet'
INSERT INTO outlet_role_permissions(outlet_id,tenant_id,role,permission,allowed) VALUES (:O,:T,'CASHIER','OPEN_ITEM',true);
\echo '--- FAIL expected: same role+permission twice'
INSERT INTO outlet_role_permissions(outlet_id,tenant_id,role,permission,allowed) VALUES (:O,:T,'CASHIER','OPEN_ITEM',false);
\echo '--- FAIL expected: unknown permission'
INSERT INTO outlet_role_permissions(outlet_id,tenant_id,role,permission,allowed) VALUES (:O,:T,'CAPTAIN','DELETE_ALL',true);
\echo '--- FAIL expected: unknown role'
INSERT INTO outlet_role_permissions(outlet_id,tenant_id,role,permission,allowed) VALUES (:O,:T,'SUPER_ADMIN','OPEN_ITEM',true);

\echo '=== 3 menu: barcode, packaging, kind'
\echo '--- OK expected: barcode on item 1'
UPDATE menu_items SET barcode='8901234567890' WHERE id=:I1;
\echo '--- FAIL expected: same barcode on another active item of the outlet'
UPDATE menu_items SET barcode='8901234567890' WHERE id=:I2;
\echo '--- OK expected: same barcode at another outlet'
UPDATE menu_items SET barcode='8901234567890' WHERE id=:I4;
\echo '--- FAIL expected: barcode with a space'
UPDATE menu_items SET barcode='89 01' WHERE id=:I2;
\echo '--- FAIL expected: barcode too short'
UPDATE menu_items SET barcode='123' WHERE id=:I2;
\echo '--- OK expected: inactive item does not hold the barcode'
UPDATE menu_items SET active=false WHERE id=:I4;
UPDATE menu_items SET barcode='8901234567890' WHERE id=:I4;
\echo '--- FAIL expected: negative packaging charge on item'
UPDATE menu_items SET packaging_charge=-1 WHERE id=:I2;
\echo '--- OK expected: packaging charge per unit'
UPDATE menu_items SET packaging_charge=5 WHERE id=:I2;
\echo '--- FAIL expected: unknown item kind'
UPDATE menu_items SET item_kind='BUNDLE' WHERE id=:I2;
\echo '--- FAIL expected: overridden_fields with unknown field'
UPDATE menu_items SET overridden_fields='{colour}' WHERE id=:I2;
\echo '--- OK expected: overridden_fields with known fields'
UPDATE menu_items SET overridden_fields='{base_price,name}' WHERE id=:I2;
\echo '--- OK expected: copy published from a master item'
INSERT INTO menu_items(tenant_id,outlet_id,category_id,name,base_price,source_item_id) VALUES (:T,:O2,'00000000-0000-0000-0000-0000000000c2','Copy of 1',100,:I1);
\echo '--- FAIL expected: a second copy of the same master item at the same outlet'
INSERT INTO menu_items(tenant_id,outlet_id,category_id,name,base_price,source_item_id) VALUES (:T,:O2,'00000000-0000-0000-0000-0000000000c2','Copy of 1 again',100,:I1);

\echo '=== 4 combo components'
\echo '--- OK expected: component 1 of the combo'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,quantity) VALUES (:T,:COMBO,:I1,1);
\echo '--- OK expected: component 2 with a variant'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,component_variant_id,quantity) VALUES (:T,:COMBO,:I2,:V2,2);
\echo '--- FAIL expected: same component and variant twice'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,component_variant_id,quantity) VALUES (:T,:COMBO,:I2,:V2,1);
\echo '--- FAIL expected: same component without variant twice'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,quantity) VALUES (:T,:COMBO,:I1,1);
\echo '--- FAIL expected: parent is not a combo'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,quantity) VALUES (:T,:I1,:I2,1);
\echo '--- FAIL expected: a combo inside a combo'
INSERT INTO menu_items(id,tenant_id,outlet_id,category_id,name,base_price,item_kind) VALUES ('00000000-0000-0000-0000-0000000000d5',:T,:O,:CAT,'Combo2',99,'COMBO');
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,quantity) VALUES (:T,'00000000-0000-0000-0000-0000000000d5',:COMBO,1);
\echo '--- FAIL expected: component from another outlet'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,quantity) VALUES (:T,'00000000-0000-0000-0000-0000000000d5',:I4,1);
\echo '--- FAIL expected: variant of a different item'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,component_variant_id,quantity) VALUES (:T,'00000000-0000-0000-0000-0000000000d5',:I1,:V2,1);
\echo '--- FAIL expected: quantity 0'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,quantity) VALUES (:T,'00000000-0000-0000-0000-0000000000d5',:I2,0);
\echo '--- FAIL expected: combo as its own component'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,quantity) VALUES (:T,:COMBO,:COMBO,1);
\echo '--- OK expected: fractional component quantity 0.5'
INSERT INTO combo_components(tenant_id,combo_item_id,component_item_id,quantity) VALUES (:T,'00000000-0000-0000-0000-0000000000d5',:I2,0.5);

\echo '=== 5 price rules'
\echo '--- OK expected: happy hour crossing midnight, price override on an item'
INSERT INTO price_rules(id,tenant_id,outlet_id,name,scope_type,menu_item_id,weekdays,start_time,end_time,action,price,priority) VALUES ('00000000-0000-0000-0000-00000000f001',:T,:O,'Late night','ITEM',:I1,'{5,6}','22:00','02:00','PRICE_OVERRIDE',80,10);
\echo '--- OK expected: category percent off on weekday lunch'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,category_id,start_time,end_time,action,percent_off) VALUES (:T,:O,'Lunch','CATEGORY',:CAT,'12:00','15:00','PERCENT_OFF',15);
\echo '--- OK expected: variant price override'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,variant_id,start_time,end_time,action,price) VALUES (:T,:O,'Half price','VARIANT',:V1,'10:00','11:00','PRICE_OVERRIDE',120);
\echo '--- FAIL expected: start = end'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,start_time,end_time,action,price) VALUES (:T,:O,'Bad','ITEM',:I1,'10:00','10:00','PRICE_OVERRIDE',80);
\echo '--- FAIL expected: empty weekdays'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,weekdays,start_time,end_time,action,price) VALUES (:T,:O,'Bad','ITEM',:I1,'{}','10:00','11:00','PRICE_OVERRIDE',80);
\echo '--- FAIL expected: weekday 8'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,weekdays,start_time,end_time,action,price) VALUES (:T,:O,'Bad','ITEM',:I1,'{8}','10:00','11:00','PRICE_OVERRIDE',80);
\echo '--- FAIL expected: weekday 0'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,weekdays,start_time,end_time,action,price) VALUES (:T,:O,'Bad','ITEM',:I1,'{0}','10:00','11:00','PRICE_OVERRIDE',80);
\echo '--- FAIL expected: PRICE_OVERRIDE carrying a percent'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,start_time,end_time,action,price,percent_off) VALUES (:T,:O,'Bad','ITEM',:I1,'10:00','11:00','PRICE_OVERRIDE',80,10);
\echo '--- FAIL expected: PRICE_OVERRIDE without price'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,start_time,end_time,action) VALUES (:T,:O,'Bad','ITEM',:I1,'10:00','11:00','PRICE_OVERRIDE');
\echo '--- FAIL expected: PERCENT_OFF with a price'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,start_time,end_time,action,price,percent_off) VALUES (:T,:O,'Bad','ITEM',:I1,'10:00','11:00','PERCENT_OFF',80,10);
\echo '--- FAIL expected: percent 0'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,start_time,end_time,action,percent_off) VALUES (:T,:O,'Bad','ITEM',:I1,'10:00','11:00','PERCENT_OFF',0);
\echo '--- FAIL expected: percent 101'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,start_time,end_time,action,percent_off) VALUES (:T,:O,'Bad','ITEM',:I1,'10:00','11:00','PERCENT_OFF',101);
\echo '--- FAIL expected: ITEM scope without an item'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,start_time,end_time,action,price) VALUES (:T,:O,'Bad','ITEM','10:00','11:00','PRICE_OVERRIDE',80);
\echo '--- FAIL expected: ITEM scope that also names a category'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,category_id,start_time,end_time,action,price) VALUES (:T,:O,'Bad','ITEM',:I1,:CAT,'10:00','11:00','PRICE_OVERRIDE',80);
\echo '--- FAIL expected: CATEGORY scope with a price override'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,category_id,start_time,end_time,action,price) VALUES (:T,:O,'Bad','CATEGORY',:CAT,'10:00','11:00','PRICE_OVERRIDE',80);
\echo '--- FAIL expected: valid_to before valid_from'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,valid_from,valid_to,start_time,end_time,action,price) VALUES (:T,:O,'Bad','ITEM',:I1,'2026-12-31','2026-12-01','10:00','11:00','PRICE_OVERRIDE',80);
\echo '--- FAIL expected: priority 1001'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,start_time,end_time,action,price,priority) VALUES (:T,:O,'Bad','ITEM',:I1,'10:00','11:00','PRICE_OVERRIDE',80,1001);
\echo '--- FAIL expected: unknown order type'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,order_types,start_time,end_time,action,price) VALUES (:T,:O,'Bad','ITEM',:I1,'{DRIVE_THRU}','10:00','11:00','PRICE_OVERRIDE',80);
\echo '--- FAIL expected: negative override price'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,start_time,end_time,action,price) VALUES (:T,:O,'Bad','ITEM',:I1,'10:00','11:00','PRICE_OVERRIDE',-1);
\echo '--- OK expected: override price 0 (free item during a promotion)'
INSERT INTO price_rules(tenant_id,outlet_id,name,scope_type,menu_item_id,start_time,end_time,action,price) VALUES (:T,:O,'Free','ITEM',:I2,'10:00','11:00','PRICE_OVERRIDE',0);

\echo '=== 6 order lines: open items, combos, kitchen status'
\echo '--- OK expected: open item (no menu item, source OPEN_ITEM)'
INSERT INTO order_items(id,tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,is_open_item,price_source) VALUES ('00000000-0000-0000-0000-0000000000b4',:T,:E1,NULL,'Special thali',350,1,true,'OPEN_ITEM');
\echo '--- FAIL expected: no menu item but not flagged open'
INSERT INTO order_items(tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity) VALUES (:T,:E1,NULL,'Ghost',10,1);
\echo '--- FAIL expected: open item that also points at a menu item'
INSERT INTO order_items(tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,is_open_item,price_source) VALUES (:T,:E1,:I1,'X',10,1,true,'OPEN_ITEM');
\echo '--- FAIL expected: open item with price source LIST'
INSERT INTO order_items(tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,is_open_item,price_source) VALUES (:T,:E1,NULL,'X',10,1,true,'LIST');
\echo '--- FAIL expected: unknown price source'
INSERT INTO order_items(tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,price_source) VALUES (:T,:E1,:I1,'X',10,1,'COUPON');
\echo '--- OK expected: combo header'
INSERT INTO order_items(id,tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,price_source,combo_role) VALUES ('00000000-0000-0000-0000-0000000000b5',:T,:E1,:COMBO,'Combo1',120,1,'COMBO','HEADER');
\echo '--- OK expected: combo component with allocated amount'
INSERT INTO order_items(id,tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,price_source,combo_role,combo_parent_id,fixed_line_amount) VALUES ('00000000-0000-0000-0000-0000000000b6',:T,:E1,:I1,'Item1 (Combo1)',0,1,'COMBO','COMPONENT','00000000-0000-0000-0000-0000000000b5',80.00);
\echo '--- FAIL expected: component without a parent'
INSERT INTO order_items(tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,price_source,combo_role,fixed_line_amount) VALUES (:T,:E1,:I1,'X',0,1,'COMBO','COMPONENT',80);
\echo '--- FAIL expected: component without an allocated amount'
INSERT INTO order_items(tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,price_source,combo_role,combo_parent_id) VALUES (:T,:E1,:I1,'X',0,1,'COMBO','COMPONENT','00000000-0000-0000-0000-0000000000b5');
\echo '--- FAIL expected: plain line carrying a parent'
INSERT INTO order_items(tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,combo_parent_id) VALUES (:T,:E1,:I1,'X',10,1,'00000000-0000-0000-0000-0000000000b5');
\echo '--- FAIL expected: header carrying a fixed amount'
INSERT INTO order_items(tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,combo_role,fixed_line_amount) VALUES (:T,:E1,:COMBO,'X',10,1,'HEADER',5);
\echo '--- FAIL expected: negative allocated amount'
INSERT INTO order_items(tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity,combo_role,combo_parent_id,fixed_line_amount) VALUES (:T,:E1,:I1,'X',0,1,'COMPONENT','00000000-0000-0000-0000-0000000000b5',-1);
\echo '--- FAIL expected: kitchen status PREPARING before any KOT'
UPDATE order_items SET kitchen_status='PREPARING' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- OK expected: attach the line to the KOT'
UPDATE order_items SET kot_id=:K1 WHERE id IN ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000b3');
\echo '--- FAIL expected: NEW -> SERVED skips the kitchen'
UPDATE order_items SET kitchen_status='SERVED' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- OK expected: NEW -> PREPARING'
UPDATE order_items SET kitchen_status='PREPARING', preparing_at=now() WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- OK expected: PREPARING -> NEW (recall)'
UPDATE order_items SET kitchen_status='NEW' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- OK expected: NEW -> READY (bump straight to ready)'
UPDATE order_items SET kitchen_status='READY', ready_at=now() WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- FAIL expected: READY -> NEW (only one step back)'
UPDATE order_items SET kitchen_status='NEW' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- OK expected: READY -> SERVED'
UPDATE order_items SET kitchen_status='SERVED', served_at=now() WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- FAIL expected: SERVED -> NEW'
UPDATE order_items SET kitchen_status='NEW' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- FAIL expected: SERVED -> PREPARING'
UPDATE order_items SET kitchen_status='PREPARING' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- OK expected: SERVED -> READY (recall)'
UPDATE order_items SET kitchen_status='READY' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- OK expected: READY -> PREPARING (recall)'
UPDATE order_items SET kitchen_status='PREPARING' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- FAIL expected: PREPARING -> SERVED'
UPDATE order_items SET kitchen_status='SERVED' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- FAIL expected: unknown kitchen status'
UPDATE order_items SET kitchen_status='COOKING' WHERE id='00000000-0000-0000-0000-0000000000b1';
\echo '--- OK expected: same status written again is not a transition'
UPDATE order_items SET kitchen_status='PREPARING' WHERE id='00000000-0000-0000-0000-0000000000b1';

\echo '=== 7 cashier shifts and cash movements'
\echo '--- OK expected: open shift for cashier 1 on device D1'
INSERT INTO cashier_shifts(id,tenant_id,outlet_id,device_id,cashier_id,business_date,opening_float) VALUES ('00000000-0000-0000-0000-0000000005a1',:T,:O,'00000000-0000-0000-0000-00000000dd01',:C,'2026-11-23',2000);
\echo '--- FAIL expected: same cashier opens a second shift'
INSERT INTO cashier_shifts(tenant_id,outlet_id,cashier_id,business_date,opening_float) VALUES (:T,:O,:C,'2026-11-23',0);
\echo '--- FAIL expected: another cashier on the same device'
INSERT INTO cashier_shifts(tenant_id,outlet_id,device_id,cashier_id,business_date) VALUES (:T,:O,'00000000-0000-0000-0000-00000000dd01',:C2,'2026-11-23');
\echo '--- OK expected: another cashier on another device'
INSERT INTO cashier_shifts(id,tenant_id,outlet_id,device_id,cashier_id,business_date) VALUES ('00000000-0000-0000-0000-0000000005a2',:T,:O,'00000000-0000-0000-0000-00000000dd02',:C2,'2026-11-23');
\echo '--- FAIL expected: negative opening float'
INSERT INTO cashier_shifts(tenant_id,outlet_id,cashier_id,business_date,opening_float) VALUES (:T,:O,:M,'2026-11-23',-1);
\echo '--- FAIL expected: OPEN shift already carrying a counted amount'
UPDATE cashier_shifts SET counted_cash=100 WHERE id='00000000-0000-0000-0000-0000000005a1';
\echo '--- FAIL expected: CLOSED without counted cash'
UPDATE cashier_shifts SET status='CLOSED', closed_at=now(), closed_by=:M WHERE id='00000000-0000-0000-0000-0000000005a1';
\echo '--- FAIL expected: variance not equal counted - expected'
UPDATE cashier_shifts SET status='CLOSED', closed_at=now(), closed_by=:M, counted_cash=2100, expected_cash=2000, variance=50 WHERE id='00000000-0000-0000-0000-0000000005a1';
\echo '--- FAIL expected: handover to the same cashier'
UPDATE cashier_shifts SET handover_to=:C WHERE id='00000000-0000-0000-0000-0000000005a1';
\echo '--- OK expected: cash movement PAY_IN'
INSERT INTO cash_movements(id,tenant_id,outlet_id,shift_id,kind,amount,reason_code,created_by) VALUES ('00000000-0000-0000-0000-0000000005b1',:T,:O,'00000000-0000-0000-0000-0000000005a1','PAY_IN',500,'FLOAT_TOPUP',:M);
\echo '--- OK expected: cash movement DROP'
INSERT INTO cash_movements(tenant_id,outlet_id,shift_id,kind,amount,reason_code,created_by) VALUES (:T,:O,'00000000-0000-0000-0000-0000000005a1','DROP',1000,'SAFE_DROP',:M);
\echo '--- FAIL expected: movement amount 0'
INSERT INTO cash_movements(tenant_id,outlet_id,shift_id,kind,amount,reason_code,created_by) VALUES (:T,:O,'00000000-0000-0000-0000-0000000005a1','PAY_OUT',0,'X',:M);
\echo '--- FAIL expected: movement kind REFUND'
INSERT INTO cash_movements(tenant_id,outlet_id,shift_id,kind,amount,reason_code,created_by) VALUES (:T,:O,'00000000-0000-0000-0000-0000000005a1','REFUND',10,'X',:M);
\echo '--- FAIL expected: movement without a reason'
INSERT INTO cash_movements(tenant_id,outlet_id,shift_id,kind,amount,reason_code,created_by) VALUES (:T,:O,'00000000-0000-0000-0000-0000000005a1','PAY_OUT',10,'  ',:M);
\echo '--- FAIL expected: cash movement edited'
UPDATE cash_movements SET amount=1 WHERE id='00000000-0000-0000-0000-0000000005b1';
\echo '--- FAIL expected: cash movement deleted'
DELETE FROM cash_movements WHERE id='00000000-0000-0000-0000-0000000005b1';
\echo '--- OK expected: day closing row opened'
INSERT INTO day_closings(tenant_id,outlet_id,business_date) VALUES (:T,:O,'2026-11-23');
\echo '--- FAIL expected: day close while shifts are open'
UPDATE day_closings SET status='CLOSED', closed_by=:M, closed_at=now() WHERE outlet_id=:O AND business_date='2026-11-23';
\echo '--- OK expected: close shift 1 (counted 1500, expected 1500)'
UPDATE cashier_shifts SET status='CLOSED', closed_at=now(), closed_by=:M, counted_cash=1500, expected_cash=1500, variance=0, handover_to=:C2 WHERE id='00000000-0000-0000-0000-0000000005a1';
\echo '--- FAIL expected: day close while shift 2 is still open'
UPDATE day_closings SET status='CLOSED', closed_by=:M, closed_at=now() WHERE outlet_id=:O AND business_date='2026-11-23';
\echo '--- OK expected: close shift 2 with a shortage'
UPDATE cashier_shifts SET status='CLOSED', closed_at=now(), closed_by=:M, counted_cash=95, expected_cash=100, variance=-5 WHERE id='00000000-0000-0000-0000-0000000005a2';
\echo '--- OK expected: day close once all shifts are closed'
UPDATE day_closings SET status='CLOSED', closed_by=:M, closed_at=now() WHERE outlet_id=:O AND business_date='2026-11-23';
\echo '--- OK expected: the cashier can open a new shift after closing'
INSERT INTO cashier_shifts(id,tenant_id,outlet_id,device_id,cashier_id,business_date,opening_float) VALUES ('00000000-0000-0000-0000-0000000005a3',:T,:O,'00000000-0000-0000-0000-00000000dd01',:C,'2026-11-24',500);

\echo '=== 8 customer ledger'
\echo '--- OK expected: CHARGE for an on-account bill'
INSERT INTO customer_ledger(id,tenant_id,customer_id,outlet_id,entry_type,amount,bill_id,business_date,created_by) VALUES ('00000000-0000-0000-0000-0000000001a1',:T,:CA,:O,'CHARGE',263,:B1,'2026-11-23',:C);
\echo '--- FAIL expected: CHARGE with a negative amount'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,bill_id,business_date,created_by) VALUES (:T,:CA,:O,'CHARGE',-5,:B1,'2026-11-23',:C);
\echo '--- FAIL expected: CHARGE without a bill'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,business_date,created_by) VALUES (:T,:CA,:O,'CHARGE',5,'2026-11-23',:C);
\echo '--- OK expected: PAYMENT settles part of the dues (cash, in shift 3)'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,method,shift_id,business_date,created_by) VALUES (:T,:CA,:O,'PAYMENT',-100,'CASH','00000000-0000-0000-0000-0000000005a3','2026-11-24',:C);
\echo '--- FAIL expected: PAYMENT with a positive amount'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,method,business_date,created_by) VALUES (:T,:CA,:O,'PAYMENT',100,'CASH','2026-11-24',:C);
\echo '--- FAIL expected: PAYMENT without a method'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,business_date,created_by) VALUES (:T,:CA,:O,'PAYMENT',-100,'2026-11-24',:C);
\echo '--- FAIL expected: PAYMENT with method ON_ACCOUNT'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,method,business_date,created_by) VALUES (:T,:CA,:O,'PAYMENT',-100,'ON_ACCOUNT','2026-11-24',:C);
\echo '--- FAIL expected: method on a CHARGE entry'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,bill_id,method,business_date,created_by) VALUES (:T,:CA,:O,'CHARGE',5,:B1,'CASH','2026-11-24',:C);
\echo '--- FAIL expected: CREDIT_NOTE entry without a credit note'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,business_date,created_by) VALUES (:T,:CA,:O,'CREDIT_NOTE',-10,'2026-11-24',:C);
\echo '--- FAIL expected: ADJUSTMENT with a 3-letter reason'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,reason,business_date,created_by) VALUES (:T,:CA,:O,'ADJUSTMENT',-10,'abc','2026-11-24',:M);
\echo '--- FAIL expected: ADJUSTMENT without a reason'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,business_date,created_by) VALUES (:T,:CA,:O,'ADJUSTMENT',-10,'2026-11-24',:M);
\echo '--- OK expected: ADJUSTMENT write-off with a reason'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,reason,business_date,created_by) VALUES (:T,:CA,:O,'ADJUSTMENT',-13,'Rounding write-off agreed with owner','2026-11-24',:M);
\echo '--- FAIL expected: ledger amount 0'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,reason,business_date,created_by) VALUES (:T,:CA,:O,'ADJUSTMENT',0,'zero adjustment','2026-11-24',:M);
\echo '--- FAIL expected: unknown entry type'
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,business_date,created_by) VALUES (:T,:CA,:O,'REFUND',-10,'2026-11-24',:M);
\echo '--- FAIL expected: ledger entry edited'
UPDATE customer_ledger SET amount=1 WHERE id='00000000-0000-0000-0000-0000000001a1';
\echo '--- FAIL expected: ledger entry deleted'
DELETE FROM customer_ledger WHERE id='00000000-0000-0000-0000-0000000001a1';
\echo '--- FAIL expected: negative credit limit'
UPDATE customers SET credit_limit=-1 WHERE id=:CA;
\echo '--- OK expected: balance of customer A is the sum of entries (263-100-13 = 150)'
DO $$ BEGIN IF (SELECT sum(amount) FROM customer_ledger WHERE customer_id='00000000-0000-0000-0000-0000000000b9') <> 150 THEN RAISE EXCEPTION 'balance mismatch'; END IF; END $$;

\echo '=== 9 coupons'
\echo '--- FAIL expected: code differing only in case'
INSERT INTO coupons(tenant_id,code,discount_type,value) VALUES (:T,'welcome10','PERCENT',5);
\echo '--- FAIL expected: code too short'
INSERT INTO coupons(tenant_id,code,discount_type,value) VALUES (:T,'AB','PERCENT',5);
\echo '--- FAIL expected: code with a space'
INSERT INTO coupons(tenant_id,code,discount_type,value) VALUES (:T,'SAVE 5','PERCENT',5);
\echo '--- FAIL expected: percent 101'
INSERT INTO coupons(tenant_id,code,discount_type,value) VALUES (:T,'OVER100','PERCENT',101);
\echo '--- FAIL expected: value 0'
INSERT INTO coupons(tenant_id,code,discount_type,value) VALUES (:T,'ZERO0','AMOUNT',0);
\echo '--- FAIL expected: unknown discount type'
INSERT INTO coupons(tenant_id,code,discount_type,value) VALUES (:T,'BOGO1','BOGO',1);
\echo '--- FAIL expected: stackable coupon (not in v1)'
INSERT INTO coupons(tenant_id,code,discount_type,value,stackable) VALUES (:T,'STACK5','PERCENT',5,true);
\echo '--- FAIL expected: valid_to not after valid_from'
INSERT INTO coupons(tenant_id,code,discount_type,value,valid_from,valid_to) VALUES (:T,'BADRANGE','PERCENT',5,'2026-12-02','2026-12-01');
\echo '--- FAIL expected: usage limit 0'
INSERT INTO coupons(tenant_id,code,discount_type,value,usage_limit_total) VALUES (:T,'LIM0','PERCENT',5,0);
\echo '--- FAIL expected: max discount 0'
INSERT INTO coupons(tenant_id,code,discount_type,value,max_discount) VALUES (:T,'CAP0','PERCENT',5,0);
\echo '--- FAIL expected: negative min bill'
INSERT INTO coupons(tenant_id,code,discount_type,value,min_bill) VALUES (:T,'MINNEG','PERCENT',5,-1);
\echo '--- FAIL expected: empty weekdays'
INSERT INTO coupons(tenant_id,code,discount_type,value,weekdays) VALUES (:T,'NODAYS','PERCENT',5,'{}');
\echo '--- OK expected: flat coupon with limits'
INSERT INTO coupons(id,tenant_id,code,discount_type,value,min_bill,usage_limit_total,usage_limit_per_customer,usage_limit_per_day) VALUES ('00000000-0000-0000-0000-00000000cc02',:T,'FLAT50','AMOUNT',50,200,2,1,1);
\echo '--- OK expected: coupon limited to one outlet'
INSERT INTO coupons(id,tenant_id,outlet_id,code,discount_type,value,max_discount) VALUES ('00000000-0000-0000-0000-00000000cc03',:T,:O2,'OUT2ONLY','PERCENT',20,100);

\echo '=== 10 bills: NC, packaging, coupon, line types'
\echo '--- OK expected: NC bill (grand 0, reason, liability recorded)'
INSERT INTO bills(id,tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,discount_type,discount_value,discount_total,tax_total,total_before_round_off,grand_total,generated_by,is_complimentary,nc_reason_code,nc_tax_liability)
 VALUES ('00000000-0000-0000-0000-000000000b21',:T,:O,:E2,'B','2026-27',21,'B-21',false,'INR',100,'PERCENT',100,100,0,0,0,:M,true,'OWNER_GUEST',5.00);
\echo '--- FAIL expected: NC bill with a payable grand total'
INSERT INTO bills(tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,is_complimentary,nc_reason_code)
 VALUES (:T,:O,:E2,'B','2026-27',22,'B-22',false,'INR',100,0,100,100,:M,true,'OWNER_GUEST');
\echo '--- FAIL expected: NC bill without a reason code'
INSERT INTO bills(tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,is_complimentary)
 VALUES (:T,:O,:E2,'B','2026-27',23,'B-23',false,'INR',100,0,0,0,:M,true);
\echo '--- FAIL expected: NC bill with blank reason code'
INSERT INTO bills(tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,is_complimentary,nc_reason_code)
 VALUES (:T,:O,:E2,'B','2026-27',24,'B-24',false,'INR',100,0,0,0,:M,true,'  ');
\echo '--- FAIL expected: NC bill carrying packaging charge'
INSERT INTO bills(tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,is_complimentary,nc_reason_code,packaging_charge_total,packaging_kind)
 VALUES (:T,:O,:E2,'B','2026-27',25,'B-25',false,'INR',100,0,0,0,:M,true,'OWNER_GUEST',10,'FLAT');
\echo '--- FAIL expected: NC bill carrying service charge'
INSERT INTO bills(tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,is_complimentary,nc_reason_code,service_charge_total)
 VALUES (:T,:O,:E2,'B','2026-27',26,'B-26',false,'INR',100,0,0,0,:M,true,'OWNER_GUEST',5);
\echo '--- FAIL expected: tax liability on a normal bill'
UPDATE bills SET nc_tax_liability=5 WHERE id=:B2;
\echo '--- FAIL expected: negative tax liability'
UPDATE bills SET nc_tax_liability=-1 WHERE id='00000000-0000-0000-0000-000000000b21';
\echo '--- FAIL expected: coupon on a bill without a discount'
UPDATE bills SET coupon_id=:CP, coupon_code='WELCOME10' WHERE id=:B2;
\echo '--- FAIL expected: coupon id without the code snapshot'
UPDATE bills SET coupon_id=:CP, discount_total=10 WHERE id=:B2;
\echo '--- OK expected: coupon with discount and code snapshot'
UPDATE bills SET coupon_id=:CP, coupon_code='WELCOME10', discount_total=10, discount_type='PERCENT', discount_value=10 WHERE id=:B2;
\echo '--- FAIL expected: packaging charge without a kind'
UPDATE bills SET packaging_charge_total=10 WHERE id=:B3;
\echo '--- FAIL expected: packaging kind without a charge'
UPDATE bills SET packaging_kind='FLAT' WHERE id=:B3;
\echo '--- FAIL expected: unknown packaging kind'
UPDATE bills SET packaging_charge_total=10, packaging_kind='PER_BOX' WHERE id=:B3;
\echo '--- OK expected: FLAT packaging on the first bill of order 3'
UPDATE bills SET packaging_charge_total=10, packaging_kind='FLAT' WHERE id=:B3;
\echo '--- FAIL expected: FLAT packaging charged again on a split bill of the same order'
UPDATE bills SET packaging_charge_total=10, packaging_kind='FLAT' WHERE id=:B4;
\echo '--- OK expected: PER_ITEM packaging on another bill of the same order'
UPDATE bills SET packaging_charge_total=15, packaging_kind='PER_ITEM' WHERE id=:B4;
\echo '--- OK expected: PACKAGING_CHARGE bill line'
INSERT INTO bill_lines(tenant_id,bill_id,line_no,line_type,name,quantity,unit_price,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,:B3,9,'PACKAGING_CHARGE','Packaging charge',1,10,10,10,0,10);
\echo '--- FAIL expected: unknown bill line type'
INSERT INTO bill_lines(tenant_id,bill_id,line_no,line_type,name,quantity,unit_price,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,:B3,10,'TIP','Tip',1,10,10,10,0,10);
\echo '--- OK expected: DELIVERY_CHARGE line type still accepted'
INSERT INTO bill_lines(tenant_id,bill_id,line_no,line_type,name,quantity,unit_price,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,:B3,11,'DELIVERY_CHARGE','Delivery',1,10,10,10,0,10);

\echo '=== 11 coupon redemptions'
\echo '--- OK expected: redemption of WELCOME10 on bill 2'
INSERT INTO coupon_redemptions(id,tenant_id,coupon_id,outlet_id,bill_id,customer_id,business_date,discount_amount) VALUES ('00000000-0000-0000-0000-0000000007a1',:T,:CP,:O,:B2,:CA,'2026-11-23',10);
\echo '--- FAIL expected: second ACTIVE redemption on the same bill'
INSERT INTO coupon_redemptions(tenant_id,coupon_id,outlet_id,bill_id,customer_id,business_date,discount_amount) VALUES (:T,'00000000-0000-0000-0000-00000000cc02',:O,:B2,:CA,'2026-11-23',50);
\echo '--- FAIL expected: redemption discount 0'
INSERT INTO coupon_redemptions(tenant_id,coupon_id,outlet_id,bill_id,business_date,discount_amount) VALUES (:T,:CP,:O,:B3,'2026-11-23',0);
\echo '--- FAIL expected: ACTIVE redemption carrying a release time'
INSERT INTO coupon_redemptions(tenant_id,coupon_id,outlet_id,bill_id,business_date,discount_amount,released_at) VALUES (:T,:CP,:O,:B3,'2026-11-23',5,now());
\echo '--- OK expected: FLAT50 first use (limits total 2, customer 1, day 1)'
INSERT INTO coupon_redemptions(id,tenant_id,coupon_id,outlet_id,bill_id,customer_id,business_date,discount_amount) VALUES ('00000000-0000-0000-0000-0000000007a2',:T,'00000000-0000-0000-0000-00000000cc02',:O,:B3,:CA,'2026-11-23',50);
\echo '--- FAIL expected: per-customer limit 1 reached'
INSERT INTO coupon_redemptions(tenant_id,coupon_id,outlet_id,bill_id,customer_id,business_date,discount_amount) VALUES (:T,'00000000-0000-0000-0000-00000000cc02',:O,:B4,:CA,'2026-11-24',50);
\echo '--- FAIL expected: per-day limit 1 reached (other customer, same day)'
INSERT INTO coupon_redemptions(tenant_id,coupon_id,outlet_id,bill_id,customer_id,business_date,discount_amount) VALUES (:T,'00000000-0000-0000-0000-00000000cc02',:O,:B4,:CB,'2026-11-23',50);
\echo '--- FAIL expected: coupon with a per-customer limit redeemed without a customer'
INSERT INTO coupon_redemptions(tenant_id,coupon_id,outlet_id,bill_id,business_date,discount_amount) VALUES (:T,'00000000-0000-0000-0000-00000000cc02',:O,:B4,'2026-11-24',50);
\echo '--- OK expected: other customer, next day (second of total 2)'
INSERT INTO coupon_redemptions(id,tenant_id,coupon_id,outlet_id,bill_id,customer_id,business_date,discount_amount) VALUES ('00000000-0000-0000-0000-0000000007a3',:T,'00000000-0000-0000-0000-00000000cc02',:O,:B4,:CB,'2026-11-24',50);
\echo '--- FAIL expected: total limit 2 reached'
INSERT INTO coupon_redemptions(tenant_id,coupon_id,outlet_id,bill_id,customer_id,business_date,discount_amount) VALUES (:T,'00000000-0000-0000-0000-00000000cc02',:O,:B1,'00000000-0000-0000-0000-0000000000b9','2026-11-25',50);
\echo '--- FAIL expected: release without a reason'
UPDATE coupon_redemptions SET status='RELEASED', released_at=now() WHERE id='00000000-0000-0000-0000-0000000007a2';
\echo '--- FAIL expected: changing the discount amount of a redemption'
UPDATE coupon_redemptions SET discount_amount=1 WHERE id='00000000-0000-0000-0000-0000000007a2';
\echo '--- FAIL expected: moving a redemption to another bill'
UPDATE coupon_redemptions SET bill_id=:B1 WHERE id='00000000-0000-0000-0000-0000000007a2';
\echo '--- FAIL expected: redemption deleted'
DELETE FROM coupon_redemptions WHERE id='00000000-0000-0000-0000-0000000007a2';
\echo '--- OK expected: release with a reason'
UPDATE coupon_redemptions SET status='RELEASED', released_at=now(), release_reason='REFUND_FULL' WHERE id='00000000-0000-0000-0000-0000000007a2';
\echo '--- FAIL expected: RELEASED back to ACTIVE'
UPDATE coupon_redemptions SET status='ACTIVE', released_at=NULL, release_reason=NULL WHERE id='00000000-0000-0000-0000-0000000007a2';
\echo '--- OK expected: the released use is free again (customer A, per-customer limit 1)'
INSERT INTO coupon_redemptions(id,tenant_id,coupon_id,outlet_id,bill_id,customer_id,business_date,discount_amount) VALUES ('00000000-0000-0000-0000-0000000007a4',:T,'00000000-0000-0000-0000-00000000cc02',:O,:B1,:CA,'2026-11-25',50);
\echo '--- FAIL expected: coupon switched off then redeemed'
UPDATE coupons SET active=false WHERE code='OUT2ONLY';
INSERT INTO coupon_redemptions(tenant_id,coupon_id,outlet_id,bill_id,business_date,discount_amount) VALUES (:T,'00000000-0000-0000-0000-00000000cc03',:O2,:B3,'2026-11-23',5);
\echo '--- OK expected: voiding bill 2 releases its coupon redemption automatically'
UPDATE bills SET status='VOID', voided_by=:M, voided_at=now(), void_reason='test void' WHERE id=:B2;
DO $$ BEGIN IF (SELECT status FROM coupon_redemptions WHERE id='00000000-0000-0000-0000-0000000007a1') <> 'RELEASED' THEN RAISE EXCEPTION 'not released'; END IF; END $$;

\echo '=== 12 payments: ON_ACCOUNT, tips, shifts'
\echo '--- FAIL expected: ON_ACCOUNT without a customer'
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by) VALUES (:T,:O,:B4,'ON_ACCOUNT',100,'SUCCESS',:C);
\echo '--- FAIL expected: ON_ACCOUNT with a tip'
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by,customer_id,tip_amount) VALUES (:T,:O,:B4,'ON_ACCOUNT',100,'SUCCESS',:C,:CA,10);
\echo '--- FAIL expected: ON_ACCOUNT with tendered cash'
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by,customer_id,tendered_amount) VALUES (:T,:O,:B4,'ON_ACCOUNT',100,'SUCCESS',:C,:CA,100);
\echo '--- OK expected: ON_ACCOUNT with a customer'
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by,customer_id) VALUES (:T,:O,:B4,'ON_ACCOUNT',100,'SUCCESS',:C,:CA);
\echo '--- OK expected: cash payment with tip and staff attribution in shift 3'
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by,tip_amount,tip_staff_id,shift_id) VALUES (:T,:O,:B3,'CASH',100,'SUCCESS',:C,20,:C2,'00000000-0000-0000-0000-0000000005a3');
\echo '--- FAIL expected: negative tip'
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by,tip_amount) VALUES (:T,:O,:B3,'CARD',10,'SUCCESS',:C,-1);
\echo '--- FAIL expected: unknown payment method'
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by) VALUES (:T,:O,:B3,'CRYPTO',10,'SUCCESS',:C);
\echo '--- OK expected: UPI payment without a shift while shifts are optional'
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by) VALUES (:T,:O,:B3,'UPI',10,'SUCCESS',:C);
\echo '--- FAIL expected: payment without a shift once the outlet requires shifts'
UPDATE outlets SET shifts_required=true WHERE id=:O;
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by) VALUES (:T,:O,:B3,'UPI',10,'SUCCESS',:C);
\echo '--- OK expected: payment with a shift when shifts are required'
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by,shift_id) VALUES (:T,:O,:B3,'UPI',10,'SUCCESS',:C,'00000000-0000-0000-0000-0000000005a3');
\echo '--- FAIL expected: payment pointing at a shift of another outlet'
INSERT INTO cashier_shifts(id,tenant_id,outlet_id,cashier_id,business_date) VALUES ('00000000-0000-0000-0000-0000000005a9',:T,:O2,:M,'2026-11-24');
INSERT INTO payments(tenant_id,outlet_id,bill_id,method,amount,status,created_by,shift_id) VALUES (:T,:O,:B3,'UPI',10,'SUCCESS',:C,'00000000-0000-0000-0000-0000000005a9');
UPDATE outlets SET shifts_required=false WHERE id=:O;

\echo '=== 13 credit notes'
\echo '--- FAIL expected: credit note on a bill that is not PAID (bill 2 is VOID)'
INSERT INTO credit_notes(id,tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES ('00000000-0000-0000-0000-0000000000c9',:T,:O,:B2,'2026-27',1,'CN-X1','2026-11-24','WRONG_ITEM','Wrong item served','CASH',100,0,100,0,100,:M,:C);
\echo '--- OK expected: credit note for 1 of 2 units of line 1 (taxable 100, tax 5)'
INSERT INTO credit_notes(id,tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES ('00000000-0000-0000-0000-0000000000c1',:T,:O,:B1,'2026-27',1,'CN-2026-27-000001','2026-11-24','WRONG_ITEM','Wrong item served','CASH',100,5,105,0,105,:M,:C);
INSERT INTO credit_note_lines(id,tenant_id,credit_note_id,bill_line_id,quantity,line_gross,discount_amount,taxable_amount,tax_amount,line_total) VALUES ('00000000-0000-0000-0000-0000000000d9',:T,'00000000-0000-0000-0000-0000000000c1',:L1,1,100,0,100,5,105);
INSERT INTO credit_note_line_taxes(credit_note_line_id,component_name,rate_percent,taxable_amount,tax_amount) VALUES ('00000000-0000-0000-0000-0000000000d9','CGST',2.5,100,2.5),('00000000-0000-0000-0000-0000000000d9','SGST',2.5,100,2.5);
\echo '--- FAIL expected: credit note number repeated'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O,:B1,'2026-27',2,'CN-2026-27-000001','2026-11-24','X','Another reason','CASH',1,0,1,0,1,:M,:C);
\echo '--- FAIL expected: credit note sequence repeated'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O,:B1,'2026-27',1,'CN-OTHER','2026-11-24','X','Another reason','CASH',1,0,1,0,1,:M,:C);
\echo '--- FAIL expected: series other than CN'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,series,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O,:B1,'B','2026-27',5,'CN-S','2026-11-24','X','Another reason','CASH',1,0,1,0,1,:M,:C);
\echo '--- FAIL expected: grand total not equal to total + round-off'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O,:B1,'2026-27',6,'CN-6','2026-11-24','X','Another reason','CASH',1,0,1,0.5,1,:M,:C);
\echo '--- FAIL expected: grand total 0'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O,:B1,'2026-27',7,'CN-7','2026-11-24','X','Another reason','CASH',0,0,0.4,-0.4,0,:M,:C);
\echo '--- FAIL expected: reason shorter than 5 characters'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O,:B1,'2026-27',8,'CN-8','2026-11-24','X','abc','CASH',1,0,1,0,1,:M,:C);
\echo '--- FAIL expected: ON_ACCOUNT refund without a customer'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O,:B1,'2026-27',9,'CN-9','2026-11-24','X','Another reason','ON_ACCOUNT',1,0,1,0,1,:M,:C);
\echo '--- FAIL expected: unknown refund method'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O,:B1,'2026-27',10,'CN-10','2026-11-24','X','Another reason','CHEQUE',1,0,1,0,1,:M,:C);
\echo '--- FAIL expected: credit note whose total exceeds what is left on the bill'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O,:B1,'2026-27',11,'CN-11','2026-11-24','X','Another reason','CASH',250,12.5,262.5,0.5,263,:M,:C);
\echo '--- FAIL expected: credit note on a bill of another outlet id'
INSERT INTO credit_notes(tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES (:T,:O2,:B1,'2026-27',12,'CN-12','2026-11-24','X','Another reason','CASH',1,0,1,0,1,:M,:C);
\echo '--- FAIL expected: refund line quantity beyond the sold quantity (1 left, ask 2)'
INSERT INTO credit_notes(id,tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES ('00000000-0000-0000-0000-0000000000c2',:T,:O,:B1,'2026-27',2,'CN-2026-27-000002','2026-11-24','X','Another reason','CASH',100,5,105,0,105,:M,:C);
INSERT INTO credit_note_lines(tenant_id,credit_note_id,bill_line_id,quantity,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-0000000000c2',:L1,2,100,100,5,105);
\echo '--- FAIL expected: refund amount beyond the line total (quantity fine, money too high)'
INSERT INTO credit_note_lines(tenant_id,credit_note_id,bill_line_id,quantity,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-0000000000c2',:L1,1,100,101,5,106);
\echo '--- FAIL expected: refund tax beyond the original tax of the line'
INSERT INTO credit_note_lines(tenant_id,credit_note_id,bill_line_id,quantity,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-0000000000c2',:L1,1,100,99,6,105);
\echo '--- FAIL expected: refund line whose total is not taxable + tax'
INSERT INTO credit_note_lines(tenant_id,credit_note_id,bill_line_id,quantity,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-0000000000c2',:L1,1,100,100,5,100);
\echo '--- FAIL expected: line of another bill on this credit note'
INSERT INTO credit_note_lines(tenant_id,credit_note_id,bill_line_id,quantity,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-00000000c301',1,100,100,0,100);
\echo '--- OK expected: remaining unit of line 1 refunded (cumulative equals the original line)'
INSERT INTO credit_note_lines(tenant_id,credit_note_id,bill_line_id,quantity,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-0000000000c2',:L1,1,100,100,5,105);
\echo '--- FAIL expected: line 1 already fully refunded, one more unit'
INSERT INTO credit_notes(id,tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES ('00000000-0000-0000-0000-0000000000c3',:T,:O,:B1,'2026-27',3,'CN-2026-27-000003','2026-11-24','X','Another reason','CASH',1,0,1,0,1,:M,:C);
INSERT INTO credit_note_lines(tenant_id,credit_note_id,bill_line_id,quantity,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-0000000000c3',:L1,0.001,0.01,0.01,0,0.01);
\echo '--- OK expected: ON_ACCOUNT refund with a customer and its ledger entry'
INSERT INTO credit_notes(id,tenant_id,outlet_id,bill_id,fiscal_year,cn_seq,cn_number,business_date,reason_code,reason,refund_method,customer_id,taxable_total,tax_total,total_before_round_off,round_off,grand_total,approved_by,created_by)
 VALUES ('00000000-0000-0000-0000-0000000000c4',:T,:O,:B1,'2026-27',4,'CN-2026-27-000004','2026-11-24','X','Another reason','ON_ACCOUNT',:CA,50,2.5,52.5,-0.5,52,:M,:C);
INSERT INTO customer_ledger(tenant_id,customer_id,outlet_id,entry_type,amount,credit_note_id,business_date,created_by) VALUES (:T,:CA,:O,'CREDIT_NOTE',-52,'00000000-0000-0000-0000-0000000000c4','2026-11-24',:C);
\echo '--- FAIL expected: credit note edited'
UPDATE credit_notes SET reason_code='OTHER' WHERE id='00000000-0000-0000-0000-0000000000c1';
\echo '--- FAIL expected: credit note deleted'
DELETE FROM credit_notes WHERE id='00000000-0000-0000-0000-0000000000c1';
\echo '--- FAIL expected: credit note line edited'
UPDATE credit_note_lines SET quantity=1 WHERE id='00000000-0000-0000-0000-0000000000d9';
\echo '--- FAIL expected: credit note line deleted'
DELETE FROM credit_note_lines WHERE id='00000000-0000-0000-0000-0000000000d9';
\echo '--- FAIL expected: credit note tax row deleted'
DELETE FROM credit_note_line_taxes;
\echo '--- FAIL expected: void a bill that already has a credit note'
UPDATE bills SET status='VOID', voided_by=:U, voided_at=now(), void_reason='too late' WHERE id=:B1;
\echo '--- OK expected: bill without credit notes can still be voided'
UPDATE bills SET status='VOID', voided_by=:U, voided_at=now(), void_reason='mistake entered' WHERE id=:B4;

\echo '=== 14 central menu'
\echo '--- OK expected: every outlet got a version row by the migration'
DO $$ BEGIN IF (SELECT count(*) FROM outlet_menu_versions) <> 2 THEN RAISE EXCEPTION 'missing version rows'; END IF; END $$;
\echo '--- FAIL expected: version 0'
UPDATE outlet_menu_versions SET version=0 WHERE outlet_id=:O;
\echo '--- OK expected: bump version'
UPDATE outlet_menu_versions SET version=version+1, updated_at=now() WHERE outlet_id=:O;
\echo '--- OK expected: publish run to one outlet'
INSERT INTO menu_publish_runs(tenant_id,source_outlet_id,target_outlet_ids,started_by,summary) VALUES (:T,:O,ARRAY['00000000-0000-0000-0000-0000000000a2']::uuid[],:U,'{"created":3,"updated":1,"skippedOverridden":2}');
\echo '--- FAIL expected: publish run without targets'
INSERT INTO menu_publish_runs(tenant_id,source_outlet_id,target_outlet_ids,started_by) VALUES (:T,:O,'{}',:U);
\echo '--- FAIL expected: unknown publish mode'
INSERT INTO menu_publish_runs(tenant_id,source_outlet_id,target_outlet_ids,mode,started_by) VALUES (:T,:O,ARRAY['00000000-0000-0000-0000-0000000000a2']::uuid[],'REPLACE_ALL',:U);
\echo '--- FAIL expected: category copied twice from the same master category'
INSERT INTO menu_categories(tenant_id,outlet_id,name,source_category_id) VALUES (:T,:O2,'MasterCopy',:CAT);
INSERT INTO menu_categories(tenant_id,outlet_id,name,source_category_id) VALUES (:T,:O2,'MasterCopy2',:CAT);
\echo '--- OK expected: printer drawer-kick flag'
INSERT INTO printers(tenant_id,outlet_id,name,purpose,paper_width_mm,connection,opens_cash_drawer) VALUES (:T,:O,'Counter printer','BILL',80,'AGENT',true);
