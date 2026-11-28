\set T '''00000000-0000-0000-0000-000000000001'''
\set O '''00000000-0000-0000-0000-0000000000a1'''
\set P '''00000000-0000-0000-0000-0000000000aa'''
\set U '''00000000-0000-0000-0000-0000000000f1'''
INSERT INTO platform_users(id,email,password_hash,full_name,role) VALUES (:P,'root@tt.io','x','Root','SUPER_ADMIN');
INSERT INTO users(id,tenant_id,email,password_hash,full_name,role) VALUES (:U,:T,'inv@x.io','x','Inv','INVENTORY');
INSERT INTO plans(id,code,name,currency_code,price_monthly,price_yearly,max_outlets,max_users) VALUES ('00000000-0000-0000-0000-0000000000b0','STARTER','Starter','INR',999,9990,1,5);
\echo '--- OK expected: TRIALING subscription with trial_ends_at'
INSERT INTO subscriptions(tenant_id,plan_id,billing_cycle,status,price_snapshot,currency_code,trial_ends_at) VALUES (:T,'00000000-0000-0000-0000-0000000000b0','MONTHLY','TRIALING',999,'INR',now()+interval '30 days');
\echo '--- FAIL expected: second subscription for same tenant'
INSERT INTO subscriptions(tenant_id,plan_id,billing_cycle,status,price_snapshot,currency_code,trial_ends_at) VALUES (:T,'00000000-0000-0000-0000-0000000000b0','MONTHLY','TRIALING',999,'INR',now());
\echo '--- FAIL expected: TRIALING without trial_ends_at (new tenant)'
INSERT INTO tenants(id,name) VALUES ('00000000-0000-0000-0000-000000000002','T2');
INSERT INTO subscriptions(tenant_id,plan_id,billing_cycle,status,price_snapshot,currency_code) VALUES ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000b0','MONTHLY','TRIALING',999,'INR');
\echo '--- FAIL expected: ACTIVE without period/anchor'
INSERT INTO subscriptions(tenant_id,plan_id,billing_cycle,status,price_snapshot,currency_code) VALUES ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000b0','MONTHLY','ACTIVE',999,'INR');
\echo '--- FAIL expected: invoice total != before tax + tax'
INSERT INTO subscription_invoices(tenant_id,subscription_id,invoice_number,plan_name,billing_cycle,period_start,period_end,amount_before_tax,tax_amount,total_amount,currency_code,due_at)
 SELECT :T,id,'TT-INV-000001','Starter','MONTHLY',now(),now()+interval '1 month',100,18,119,'INR',now() FROM subscriptions WHERE tenant_id=:T;
\echo '--- OK expected: correct invoice'
INSERT INTO subscription_invoices(tenant_id,subscription_id,invoice_number,plan_name,billing_cycle,period_start,period_end,amount_before_tax,tax_amount,total_amount,currency_code,due_at)
 SELECT :T,id,'TT-INV-000001','Starter','MONTHLY','2027-01-01','2027-02-01',100,18,118,'INR',now() FROM subscriptions WHERE tenant_id=:T;
\echo '--- FAIL expected: duplicate non-void invoice for same period'
INSERT INTO subscription_invoices(tenant_id,subscription_id,invoice_number,plan_name,billing_cycle,period_start,period_end,amount_before_tax,tax_amount,total_amount,currency_code,due_at)
 SELECT :T,id,'TT-INV-000002','Starter','MONTHLY','2027-01-01','2027-02-01',100,18,118,'INR',now() FROM subscriptions WHERE tenant_id=:T;
\echo '--- OK expected: payment accounts (one default) '
INSERT INTO outlet_payment_accounts(tenant_id,outlet_id,label,vpa,is_default) VALUES (:T,:O,'Second','b@bank',false);
\echo '--- FAIL expected: second default account'
INSERT INTO outlet_payment_accounts(tenant_id,outlet_id,label,vpa,is_default) VALUES (:T,:O,'Third','c@bank',true);
\echo '--- FAIL expected: GENERATED mode without vpa'
INSERT INTO outlet_payment_accounts(tenant_id,outlet_id,label,qr_image_key,qr_mode) VALUES (:T,:O,'Img','k/1.png','GENERATED');
\echo '--- OK expected: STATIC_IMAGE with image only'
INSERT INTO outlet_payment_accounts(tenant_id,outlet_id,label,qr_image_key,qr_mode) VALUES (:T,:O,'Img','k/1.png','STATIC_IMAGE');
\echo '--- OK expected: slabs (0,3] (3,6]'
INSERT INTO delivery_charge_slabs(tenant_id,outlet_id,from_km,to_km,charge) VALUES (:T,:O,0,3,30),(:T,:O,3,6,50);
\echo '--- FAIL expected: overlapping slab (2,4]'
INSERT INTO delivery_charge_slabs(tenant_id,outlet_id,from_km,to_km,charge) VALUES (:T,:O,2,4,40);
\echo '--- FAIL expected: to_km <= from_km'
INSERT INTO delivery_charge_slabs(tenant_id,outlet_id,from_km,to_km,charge) VALUES (:T,:O,8,8,40);
\echo '--- OK expected: adjacent slab (6,10]'
INSERT INTO delivery_charge_slabs(tenant_id,outlet_id,from_km,to_km,charge) VALUES (:T,:O,6,10,80);
\echo '--- FAIL expected: PARTNER order without partner_name'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,order_source) VALUES ('00000000-0000-0000-0000-0000000000e1',:T,:O,1,current_date,'TAKEAWAY',:U,'PARTNER');
\echo '--- OK expected: PARTNER order with partner_name + external_ref'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,order_source,partner_name,external_ref) VALUES ('00000000-0000-0000-0000-0000000000e1',:T,:O,1,current_date,'DELIVERY',:U,'PARTNER','SomePartner','X-1001');
\echo '--- FAIL expected: delivery charge on two active bills of one order'
INSERT INTO bills(id,tenant_id,outlet_id,order_id,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,delivery_charge_total,generated_by)
 VALUES ('00000000-0000-0000-0000-000000000b11',:T,:O,'00000000-0000-0000-0000-0000000000e1','2026-27',1,'B-1',false,'INR',100,0,150,150,50,:U);
INSERT INTO bills(id,tenant_id,outlet_id,order_id,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,delivery_charge_total,generated_by)
 VALUES ('00000000-0000-0000-0000-000000000b12',:T,:O,'00000000-0000-0000-0000-0000000000e1','2026-27',2,'B-2',false,'INR',100,0,150,150,50,:U);
\echo '--- OK expected: second bill without delivery charge; void first then another with charge'
INSERT INTO bills(id,tenant_id,outlet_id,order_id,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by)
 VALUES ('00000000-0000-0000-0000-000000000b13',:T,:O,'00000000-0000-0000-0000-0000000000e1','2026-27',3,'B-3',false,'INR',100,0,100,100,:U);
UPDATE bills SET status='VOID' WHERE id='00000000-0000-0000-0000-000000000b11';
INSERT INTO bills(id,tenant_id,outlet_id,order_id,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,delivery_charge_total,generated_by)
 VALUES ('00000000-0000-0000-0000-000000000b14',:T,:O,'00000000-0000-0000-0000-0000000000e1','2026-27',4,'B-4',false,'INR',100,0,150,150,50,:U);
\echo '--- OK expected: DELIVERY_CHARGE bill line type'
INSERT INTO bill_lines(tenant_id,bill_id,line_no,line_type,name,quantity,unit_price,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-000000000b14',1,'DELIVERY_CHARGE','Delivery charge',1,50,50,50,0,50);
\echo '--- FAIL expected: unknown line type'
INSERT INTO bill_lines(tenant_id,bill_id,line_no,line_type,name,quantity,unit_price,line_gross,taxable_amount,tax_amount,line_total) VALUES (:T,'00000000-0000-0000-0000-000000000b14',2,'TIP','x',1,5,5,5,0,5);
\echo '--- FAIL expected: charge override without reason'
INSERT INTO deliveries(tenant_id,outlet_id,order_id,customer_name,customer_phone,address_text,tracking_token,charge_override) VALUES (:T,:O,'00000000-0000-0000-0000-0000000000e1','C','1','A','tok1',0);
\echo '--- OK expected: override with reason and user'
INSERT INTO deliveries(tenant_id,outlet_id,order_id,customer_name,customer_phone,address_text,tracking_token,charge_override,charge_override_reason,charge_override_by) VALUES (:T,:O,'00000000-0000-0000-0000-0000000000e1','C','1','A','tok2',0,'VIP customer',:U);
\echo '--- FAIL expected: internal note authored by tenant user'
INSERT INTO support_tickets(id,tenant_id,ticket_number,created_by,subject) VALUES ('00000000-0000-0000-0000-0000000000d1',:T,'TT-TKT-000001',:U,'Help');
INSERT INTO support_ticket_messages(ticket_id,tenant_id,author_type,author_id,body,internal_note) VALUES ('00000000-0000-0000-0000-0000000000d1',:T,'TENANT_USER',:U,'hi',true);
\echo '--- FAIL expected: blank message body'
INSERT INTO support_ticket_messages(ticket_id,tenant_id,author_type,author_id,body) VALUES ('00000000-0000-0000-0000-0000000000d1',:T,'TENANT_USER',:U,'   ');
\echo '--- OK expected: platform internal note and feedback rating 5'
INSERT INTO support_ticket_messages(ticket_id,tenant_id,author_type,author_id,body,internal_note) VALUES ('00000000-0000-0000-0000-0000000000d1',:T,'PLATFORM_USER',:P,'check logs',true);
INSERT INTO feedback(tenant_id,user_id,rating) VALUES (:T,:U,5);
\echo '--- FAIL expected: feedback rating 6'
INSERT INTO feedback(tenant_id,user_id,rating) VALUES (:T,:U,6);
