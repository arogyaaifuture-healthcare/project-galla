\set T '''00000000-0000-0000-0000-000000000001'''
\set O '''00000000-0000-0000-0000-0000000000a1'''
INSERT INTO tenants(id,name) VALUES (:T,'T');
INSERT INTO outlets(id,tenant_id,code,name,country_code,timezone,currency_code,currency_symbol,prices_include_tax,fiscal_year_start_month) VALUES (:O,:T,'O1','Out','IN','Asia/Kolkata','INR','Rs',false,4);
INSERT INTO users(id,tenant_id,email,password_hash,full_name,role) VALUES ('00000000-0000-0000-0000-0000000000f1',:T,'a@b.c','x','A','OWNER');
INSERT INTO menu_categories(id,tenant_id,outlet_id,name) VALUES ('00000000-0000-0000-0000-0000000000c1',:T,:O,'Cat');
INSERT INTO menu_items(id,tenant_id,outlet_id,category_id,name,base_price) VALUES ('00000000-0000-0000-0000-0000000000d1',:T,:O,'00000000-0000-0000-0000-0000000000c1','Item',100);
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by) VALUES ('00000000-0000-0000-0000-0000000000e1',:T,:O,1,current_date,'TAKEAWAY','00000000-0000-0000-0000-0000000000f1');
INSERT INTO order_items(id,tenant_id,order_id,menu_item_id,name_snapshot,unit_price,quantity) VALUES ('00000000-0000-0000-0000-0000000000b1',:T,'00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000d1','Item',100,1);
INSERT INTO bills(id,tenant_id,outlet_id,order_id,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by) VALUES
 ('00000000-0000-0000-0000-000000000b11',:T,:O,'00000000-0000-0000-0000-0000000000e1','2026-27',1,'B1',false,'INR',100,0,100,100,'00000000-0000-0000-0000-0000000000f1'),
 ('00000000-0000-0000-0000-000000000b12',:T,:O,'00000000-0000-0000-0000-0000000000e1','2026-27',2,'B2',false,'INR',100,0,100,100,'00000000-0000-0000-0000-0000000000f1');
INSERT INTO bill_lines(tenant_id,bill_id,line_no,line_type,order_item_id,name,quantity,unit_price,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-000000000b11',1,'ITEM','00000000-0000-0000-0000-0000000000b1','Item',1,100,100,100,0,100);
\echo '--- FAIL expected: same order item on a second ACTIVE bill'
INSERT INTO bill_lines(tenant_id,bill_id,line_no,line_type,order_item_id,name,quantity,unit_price,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-000000000b12',1,'ITEM','00000000-0000-0000-0000-0000000000b1','Item',1,100,100,100,0,100);
\echo '--- OK expected: after the first bill lines go inactive'
UPDATE bill_lines SET active=false WHERE bill_id='00000000-0000-0000-0000-000000000b11';
INSERT INTO bill_lines(tenant_id,bill_id,line_no,line_type,order_item_id,name,quantity,unit_price,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-000000000b12',1,'ITEM','00000000-0000-0000-0000-0000000000b1','Item',1,100,100,100,0,100);
\echo '--- FAIL expected: DINE_IN without a table'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by) VALUES ('00000000-0000-0000-0000-0000000000e2',:T,:O,2,current_date,'DINE_IN','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: duplicate email, different case'
INSERT INTO users(tenant_id,email,password_hash,full_name,role) VALUES (:T,'A@B.C','x','B','CASHIER');
\echo '--- FAIL expected: duplicate order number same outlet/day'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by) VALUES ('00000000-0000-0000-0000-0000000000e3',:T,:O,1,current_date,'TAKEAWAY','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: negative price'
INSERT INTO menu_items(tenant_id,outlet_id,category_id,name,base_price) VALUES (:T,:O,'00000000-0000-0000-0000-0000000000c1','Bad',-1);
\echo '--- FAIL expected: payment amount 0'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by) VALUES ('00000000-0000-0000-0000-0000000000a9',:T,:O,'00000000-0000-0000-0000-000000000b12','CASH',0,'SUCCESS','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: invalid role'
INSERT INTO users(tenant_id,email,password_hash,full_name,role) VALUES (:T,'z@z.z','x','Z','ADMIN');
\echo '--- OK expected: INVENTORY role (added in V008)'
INSERT INTO users(tenant_id,email,password_hash,full_name,role) VALUES (:T,'inv@z.z','x','Inv','INVENTORY');
