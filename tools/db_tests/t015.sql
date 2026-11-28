\set T '''00000000-0000-0000-0000-000000000001'''
\set O '''00000000-0000-0000-0000-0000000000a1'''
\set O2 '''00000000-0000-0000-0000-0000000000a2'''
\set U '''00000000-0000-0000-0000-0000000000f1'''
\set E1 '''00000000-0000-0000-0000-0000000000e1'''
\set E2 '''00000000-0000-0000-0000-0000000000e2'''
\set E3 '''00000000-0000-0000-0000-0000000000e3'''
\set B1 '''00000000-0000-0000-0000-000000000b11'''
\set B2 '''00000000-0000-0000-0000-000000000b12'''
\set MI '''00000000-0000-0000-0000-0000000000c1'''
\set VA '''00000000-0000-0000-0000-0000000000d1'''
\set IA1 '''00000000-0000-0000-0000-00000000aa01'''
\set IA2 '''00000000-0000-0000-0000-00000000aa02'''
\set EO1 '''00000000-0000-0000-0000-00000000ee01'''
\set EO2 '''00000000-0000-0000-0000-00000000ee02'''
\set I1 '''00000000-0000-0000-0000-00000000f001'''
\set I2 '''00000000-0000-0000-0000-00000000f002'''
-- ---------- fixtures (any ERROR before the first case label is reported as SETUP ERROR)
INSERT INTO tenants(id,name) VALUES ('00000000-0000-0000-0000-000000000001','T');
INSERT INTO outlets(id,tenant_id,code,name,country_code,timezone,currency_code,currency_symbol,prices_include_tax,fiscal_year_start_month) VALUES ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000001','O1','Out','IN','Asia/Kolkata','INR','Rs',false,4),('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000001','O2','Out2','IN','Asia/Kolkata','INR','Rs',false,4);
INSERT INTO users(id,tenant_id,email,password_hash,full_name,role) VALUES (:U,:T,'d@x.io','x','D','OWNER');
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by) VALUES (:E1,:T,:O,1,current_date,'TAKEAWAY',:U),(:E2,:T,:O,2,current_date,'TAKEAWAY',:U),(:E3,:T,:O,3,current_date,'TAKEAWAY',:U);
INSERT INTO bills(id,tenant_id,outlet_id,order_id,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by)
 VALUES (:B1,:T,:O,:E1,'2026-27',1,'GL-1',false,'INR',100,0,100,100,:U),(:B2,:T,:O,:E2,'2026-27',2,'GL-2',false,'INR',100,0,100,100,:U);
INSERT INTO menu_categories(id,tenant_id,outlet_id,name) VALUES ('00000000-0000-0000-0000-0000000000b0',:T,:O,'Cat');
INSERT INTO menu_items(id,tenant_id,outlet_id,category_id,name,base_price) VALUES (:MI,:T,:O,'00000000-0000-0000-0000-0000000000b0','Paneer',100);
INSERT INTO item_variants(id,tenant_id,menu_item_id,name,price) VALUES (:VA,:T,:MI,'Large',150);
INSERT INTO tax_profiles(id,tenant_id,name) VALUES ('00000000-0000-0000-0000-0000000000a9',:T,'Intra'),('00000000-0000-0000-0000-0000000000aa',:T,'Inter');
INSERT INTO customers(id,tenant_id,name,phone) VALUES ('00000000-0000-0000-0000-0000000000cc',:T,'Cust','+919876500000');

-- ================================================== A. integration accounts
\echo '--- OK expected: integration account'
INSERT INTO integration_accounts(id,tenant_id,outlet_id,provider,display_name,external_store_id,credentials_encrypted) VALUES (:IA1,:T,:O,'provx','Provider X','S1','enc');
\echo '--- FAIL expected: same outlet+provider+store twice (unique)'
INSERT INTO integration_accounts(tenant_id,outlet_id,provider,display_name,external_store_id,credentials_encrypted) VALUES (:T,:O,'provx','Dup','S1','enc');
\echo '--- FAIL expected: same provider store id on another outlet while the first is active (ux_integration_store_per_provider)'
INSERT INTO integration_accounts(tenant_id,outlet_id,provider,display_name,external_store_id,credentials_encrypted) VALUES (:T,:O2,'provx','Dup','S1','enc');
\echo '--- FAIL expected: provider code with upper case / punctuation'
INSERT INTO integration_accounts(tenant_id,outlet_id,provider,display_name,external_store_id,credentials_encrypted) VALUES (:T,:O,'Prov-X','Bad','S9','enc');
\echo '--- FAIL expected: accept SLA below 30 seconds'
INSERT INTO integration_accounts(tenant_id,outlet_id,provider,display_name,external_store_id,credentials_encrypted,accept_sla_seconds) VALUES (:T,:O,'provy','Bad','S9','enc',10);
\echo '--- FAIL expected: accept SLA above 3600 seconds'
INSERT INTO integration_accounts(tenant_id,outlet_id,provider,display_name,external_store_id,credentials_encrypted,accept_sla_seconds) VALUES (:T,:O,'provy','Bad','S9','enc',4000);
\echo '--- FAIL expected: invalid account status'
UPDATE integration_accounts SET status='LIVE' WHERE id=:IA1;
\echo '--- FAIL expected: invalid account kind'
INSERT INTO integration_accounts(tenant_id,outlet_id,provider,kind,display_name,external_store_id,credentials_encrypted) VALUES (:T,:O,'provy','DIRECT','Bad','S9','enc');
\echo '--- FAIL expected: credentials missing'
INSERT INTO integration_accounts(tenant_id,outlet_id,provider,display_name,external_store_id) VALUES (:T,:O,'provy','Bad','S9');
\echo '--- OK expected: a second account for the same provider on the same outlet with another store id'
INSERT INTO integration_accounts(id,tenant_id,outlet_id,provider,display_name,external_store_id,credentials_encrypted,auto_accept) VALUES (:IA2,:T,:O,'provx','Provider X second','S2','enc',true);
\echo '--- OK expected: after DISABLED the store id can be connected on another outlet'
UPDATE integration_accounts SET status='DISABLED' WHERE id=:IA1;
INSERT INTO integration_accounts(tenant_id,outlet_id,provider,display_name,external_store_id,credentials_encrypted) VALUES (:T,:O2,'provx','Moved','S1','enc');

-- ================================================== A. item mappings
\echo '--- OK expected: item mapping (no variant)'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,menu_item_id) VALUES (:T,:IA2,'X1',:MI);
\echo '--- FAIL expected: same external item + variant twice (unique)'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,menu_item_id) VALUES (:T,:IA2,'X1',:MI);
\echo '--- OK expected: same external item with a variant is its own row'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,external_variant_id,menu_item_id,item_variant_id) VALUES (:T,:IA2,'X1','L',:MI,:VA);
\echo '--- FAIL expected: same external variant twice (unique)'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,external_variant_id,menu_item_id) VALUES (:T,:IA2,'X1','L',:MI);
\echo '--- OK expected: same external ids on another account'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,menu_item_id) VALUES (:T,:IA1,'X1',:MI);
\echo '--- FAIL expected: MAPPED row without an internal item'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,status) VALUES (:T,:IA2,'X2','MAPPED');
\echo '--- FAIL expected: IGNORED row that also points to an item'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,status,menu_item_id) VALUES (:T,:IA2,'X3','IGNORED',:MI);
\echo '--- OK expected: IGNORED row (a fee line, not a food item)'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,status) VALUES (:T,:IA2,'FEE1','IGNORED');
\echo '--- FAIL expected: variant without an item (caught by the MAPPED rule; the third CHECK is belt and braces)'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,item_variant_id) VALUES (:T,:IA2,'X4',:VA);
\echo '--- FAIL expected: invalid mapping status'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,status,menu_item_id) VALUES (:T,:IA2,'X5','PENDING',:MI);
\echo '--- FAIL expected: mapping to an item that does not exist'
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,menu_item_id) VALUES (:T,:IA2,'X6','00000000-0000-0000-0000-00000000dead');
\echo '--- OK expected: deleting an account removes its mappings (cascade) - checked by count below'
INSERT INTO integration_accounts(id,tenant_id,outlet_id,provider,display_name,external_store_id,credentials_encrypted) VALUES ('00000000-0000-0000-0000-00000000aa09',:T,:O,'provz','Tmp','T1','enc');
INSERT INTO external_item_mappings(tenant_id,integration_account_id,external_item_id,menu_item_id) VALUES (:T,'00000000-0000-0000-0000-00000000aa09','Y1',:MI);
DELETE FROM integration_accounts WHERE id='00000000-0000-0000-0000-00000000aa09';
SELECT count(*) AS mappings_left_must_be_0 FROM external_item_mappings WHERE integration_account_id='00000000-0000-0000-0000-00000000aa09';

-- ================================================== A. external orders inbox
\echo '--- OK expected: inbound order RECEIVED'
INSERT INTO external_orders(id,tenant_id,outlet_id,integration_account_id,provider,external_order_id,payload,accept_by) VALUES (:EO1,:T,:O,:IA2,'provx','ORD-1','{"k":1}',now()+interval '3 minutes');
\echo '--- FAIL expected: the same provider order delivered again (unique account+order id)'
INSERT INTO external_orders(tenant_id,outlet_id,integration_account_id,provider,external_order_id,payload,accept_by) VALUES (:T,:O,:IA2,'provx','ORD-1','{"k":1}',now()+interval '3 minutes');
\echo '--- OK expected: same external order id on another account is a different order'
INSERT INTO external_orders(id,tenant_id,outlet_id,integration_account_id,provider,external_order_id,payload,accept_by) VALUES (:EO2,:T,:O,:IA1,'provx','ORD-1','{"k":2}',now()+interval '3 minutes');
\echo '--- FAIL expected: payload missing'
INSERT INTO external_orders(tenant_id,outlet_id,integration_account_id,provider,external_order_id,accept_by) VALUES (:T,:O,:IA2,'provx','ORD-N',now()+interval '3 minutes');
\echo '--- FAIL expected: accept_by not after received_at'
INSERT INTO external_orders(tenant_id,outlet_id,integration_account_id,provider,external_order_id,payload,accept_by) VALUES (:T,:O,:IA2,'provx','ORD-2','{}',now()-interval '1 minute');
\echo '--- FAIL expected: invalid inbox status'
INSERT INTO external_orders(tenant_id,outlet_id,integration_account_id,provider,external_order_id,payload,accept_by,status) VALUES (:T,:O,:IA2,'provx','ORD-3','{}',now()+interval '1 minute','DONE');
\echo '--- FAIL expected: ACCEPTED without an internal order'
UPDATE external_orders SET status='ACCEPTED', accepted_at=now(), auto_accepted=true WHERE id=:EO1;
\echo '--- FAIL expected: REJECTED without a reason'
UPDATE external_orders SET status='REJECTED' WHERE id=:EO1;
\echo '--- FAIL expected: REJECTED with a blank reason'
UPDATE external_orders SET status='REJECTED', reject_reason='   ' WHERE id=:EO1;
\echo '--- FAIL expected: an acceptance with neither a user nor the auto-accept flag'
UPDATE external_orders SET accepted_at=now() WHERE id=:EO1;
\echo '--- OK expected: auto-accepted with internal order'
UPDATE external_orders SET status='ACCEPTED', accepted_at=now(), auto_accepted=true, order_id=:E3 WHERE id=:EO1;
\echo '--- FAIL expected: a second inbox row pointing at the same internal order'
UPDATE external_orders SET order_id=:E3 WHERE id=:EO2;
\echo '--- OK expected: rejected with reason by a user'
UPDATE external_orders SET status='REJECTED', reject_reason='Item out of stock', accepted_by=:U, accepted_at=now() WHERE id=:EO2;
\echo '--- FAIL expected: commission percent above 100'
UPDATE external_orders SET commission_percent=100.01 WHERE id=:EO1;
\echo '--- FAIL expected: negative settlement amount'
UPDATE external_orders SET settlement_amount=-1 WHERE id=:EO1;
\echo '--- FAIL expected: negative provider total'
UPDATE external_orders SET provider_order_total=-5 WHERE id=:EO1;
\echo '--- FAIL expected: invalid payment mode'
UPDATE external_orders SET payment_mode='CARD' WHERE id=:EO1;
\echo '--- OK expected: commission and settlement recorded as given'
UPDATE external_orders SET commission_percent=22.50, commission_amount=45.00, settlement_amount=155.00, provider_order_total=200.00, payment_mode='PREPAID' WHERE id=:EO1;

-- ================================================== A. status events (append-only)
\echo '--- OK expected: status event with provider event id'
INSERT INTO external_status_events(tenant_id,external_order_id,direction,status,provider_event_id) VALUES (:T,:EO1,'INBOUND','CREATED','pe1');
\echo '--- FAIL expected: the same provider event id again for the same order'
INSERT INTO external_status_events(tenant_id,external_order_id,direction,status,provider_event_id) VALUES (:T,:EO1,'INBOUND','CREATED','pe1');
\echo '--- OK expected: same provider event id for a different order'
INSERT INTO external_status_events(tenant_id,external_order_id,direction,status,provider_event_id) VALUES (:T,:EO2,'INBOUND','CREATED','pe1');
\echo '--- OK expected: events without a provider event id may repeat'
INSERT INTO external_status_events(tenant_id,external_order_id,direction,status) VALUES (:T,:EO1,'INTERNAL','ACCEPTED');
INSERT INTO external_status_events(tenant_id,external_order_id,direction,status) VALUES (:T,:EO1,'INTERNAL','ACCEPTED');
\echo '--- FAIL expected: invalid direction'
INSERT INTO external_status_events(tenant_id,external_order_id,direction,status) VALUES (:T,:EO1,'SIDEWAYS','X');
\echo '--- FAIL expected: UPDATE of an event row (append-only)'
UPDATE external_status_events SET status='CHANGED' WHERE provider_event_id='pe1';
\echo '--- FAIL expected: DELETE of an event row (append-only)'
DELETE FROM external_status_events WHERE provider_event_id='pe1';

-- ================================================== A. sync jobs
\echo '--- OK expected: poll job needs no order'
INSERT INTO integration_sync_jobs(tenant_id,integration_account_id,job_type) VALUES (:T,:IA2,'POLL_ORDERS');
\echo '--- FAIL expected: ACCEPT job without an external order'
INSERT INTO integration_sync_jobs(tenant_id,integration_account_id,job_type) VALUES (:T,:IA2,'ACCEPT');
\echo '--- OK expected: ACCEPT job with order and dedupe key'
INSERT INTO integration_sync_jobs(tenant_id,integration_account_id,job_type,external_order_id,dedupe_key) VALUES (:T,:IA2,'ACCEPT',:EO1,'ext:ORD-1:ACCEPT');
\echo '--- FAIL expected: same dedupe key twice'
INSERT INTO integration_sync_jobs(tenant_id,integration_account_id,job_type,external_order_id,dedupe_key) VALUES (:T,:IA2,'ACCEPT',:EO1,'ext:ORD-1:ACCEPT');
\echo '--- FAIL expected: unknown job type'
INSERT INTO integration_sync_jobs(tenant_id,integration_account_id,job_type) VALUES (:T,:IA2,'DELETE_EVERYTHING');
\echo '--- FAIL expected: SENT without sent_at'
INSERT INTO integration_sync_jobs(tenant_id,integration_account_id,job_type,status) VALUES (:T,:IA2,'MENU_PUSH','SENT');
\echo '--- FAIL expected: negative attempts'
INSERT INTO integration_sync_jobs(tenant_id,integration_account_id,job_type,attempts) VALUES (:T,:IA2,'MENU_PUSH',-1);

-- ================================================== A. partner payouts
\echo '--- OK expected: typed payout'
INSERT INTO partner_payouts(tenant_id,outlet_id,integration_account_id,period_from,period_to,amount_received,entered_by) VALUES (:T,:O,:IA2,'2026-11-01','2026-11-07',1234.50,:U);
\echo '--- FAIL expected: period end before start'
INSERT INTO partner_payouts(tenant_id,outlet_id,integration_account_id,period_from,period_to,amount_received,entered_by) VALUES (:T,:O,:IA2,'2026-11-08','2026-11-07',1,:U);
\echo '--- FAIL expected: negative payout'
INSERT INTO partner_payouts(tenant_id,outlet_id,integration_account_id,period_from,period_to,amount_received,entered_by) VALUES (:T,:O,:IA2,'2026-11-01','2026-11-07',-1,:U);

-- ================================================== B. payment intents
\echo '--- OK expected: intent CREATED for bill 1'
INSERT INTO payment_intents(id,tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by) VALUES (:I1,:T,:O,:B1,'provx',100.00,'INR',now()+interval '10 minutes',:U);
\echo '--- FAIL expected: a second live intent for the same bill (ux_intent_one_active_per_bill)'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by) VALUES (:T,:O,:B1,'provx',100.00,'INR',now()+interval '10 minutes',:U);
\echo '--- FAIL expected: amount zero'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by) VALUES (:T,:O,:B2,'provx',0,'INR',now()+interval '10 minutes',:U);
\echo '--- FAIL expected: negative amount'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by) VALUES (:T,:O,:B2,'provx',-5,'INR',now()+interval '10 minutes',:U);
\echo '--- FAIL expected: expiry not after creation'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by) VALUES (:T,:O,:B2,'provx',100,'INR',now()-interval '1 minute',:U);
\echo '--- FAIL expected: invalid intent status'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by,status) VALUES (:T,:O,:B2,'provx',100,'INR',now()+interval '10 minutes',:U,'PAID');
\echo '--- FAIL expected: provider code format'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by) VALUES (:T,:O,:B2,'Prov X',100,'INR',now()+interval '10 minutes',:U);
\echo '--- FAIL expected: bill does not exist'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by) VALUES (:T,:O,'00000000-0000-0000-0000-00000000dead','provx',100,'INR',now()+interval '10 minutes',:U);
\echo '--- OK expected: CREATED -> PENDING'
UPDATE payment_intents SET status='PENDING', provider_ref='R1' WHERE id=:I1;
\echo '--- FAIL expected: SUCCESS without success_at'
UPDATE payment_intents SET status='SUCCESS', received_amount=100.00 WHERE id=:I1;
\echo '--- FAIL expected: SUCCESS with a received amount different from the locked amount'
UPDATE payment_intents SET status='SUCCESS', success_at=now(), received_amount=99.00 WHERE id=:I1;
\echo '--- FAIL expected: SUCCESS without a received amount'
UPDATE payment_intents SET status='SUCCESS', success_at=now() WHERE id=:I1;
\echo '--- FAIL expected: received amount zero'
UPDATE payment_intents SET received_amount=0 WHERE id=:I1;
\echo '--- FAIL expected: invalid attention value'
UPDATE payment_intents SET attention='WEIRD' WHERE id=:I1;
\echo '--- FAIL expected: attention resolved but never raised'
UPDATE payment_intents SET attention_resolved_at=now(), attention_resolved_by=:U WHERE id=:I1;
\echo '--- FAIL expected: attention resolved without saying who'
UPDATE payment_intents SET attention='LATE_SUCCESS', attention_resolved_at=now() WHERE id=:I1;
\echo '--- OK expected: attention raised, then resolved by a user'
UPDATE payment_intents SET attention='DUPLICATE_PAYMENT' WHERE id=:I1;
UPDATE payment_intents SET attention_resolved_at=now(), attention_resolved_by=:U WHERE id=:I1;
\echo '--- OK expected: PENDING -> SUCCESS with the exact locked amount'
UPDATE payment_intents SET status='SUCCESS', success_at=now(), received_amount=100.00 WHERE id=:I1;
\echo '--- OK expected: provider reference unique per provider; an expired intent on bill 2'
INSERT INTO payment_intents(id,tenant_id,outlet_id,bill_id,provider,provider_ref,amount,currency_code,expires_at,created_by,status) VALUES (:I2,:T,:O,:B2,'provx','R2',100.00,'INR',now()+interval '10 minutes',:U,'EXPIRED');
\echo '--- OK expected: after EXPIRED a new live intent for the same bill is allowed'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by) VALUES (:T,:O,:B2,'provx',100.00,'INR',now()+interval '10 minutes',:U);
\echo '--- FAIL expected: provider reference reused by the same provider'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,provider_ref,amount,currency_code,expires_at,created_by,status) VALUES (:T,:O,:B2,'provx','R2',100.00,'INR',now()+interval '10 minutes',:U,'FAILED');
\echo '--- OK expected: same reference text under another provider; several intents without a reference'
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,provider_ref,amount,currency_code,expires_at,created_by,status) VALUES (:T,:O,:B2,'provy','R2',100.00,'INR',now()+interval '10 minutes',:U,'FAILED');
INSERT INTO payment_intents(tenant_id,outlet_id,bill_id,provider,amount,currency_code,expires_at,created_by,status) VALUES (:T,:O,:B2,'provx',100.00,'INR',now()+interval '10 minutes',:U,'FAILED');

-- ================================================== B. provider events (V004 table, extended)
\echo '--- OK expected: provider event for intent 1'
INSERT INTO payment_webhook_events(id,provider,event_id,payload,tenant_id,intent_id,event_kind,amount,occurred_at) VALUES ('00000000-0000-0000-0000-00000000ab01','provx','evt1','{"x":1}',:T,:I1,'SUCCESS',100.00,now());
\echo '--- FAIL expected: the same provider event id again (unique provider+event_id)'
INSERT INTO payment_webhook_events(provider,event_id,payload) VALUES ('provx','evt1','{"x":1}');
\echo '--- OK expected: same event id from another provider'
INSERT INTO payment_webhook_events(provider,event_id,payload) VALUES ('provy','evt1','{"x":1}');
\echo '--- FAIL expected: invalid event kind'
INSERT INTO payment_webhook_events(provider,event_id,payload,event_kind) VALUES ('provx','evt2','{}','REFUND');
\echo '--- FAIL expected: negative event amount'
INSERT INTO payment_webhook_events(provider,event_id,payload,amount) VALUES ('provx','evt3','{}',-1);
\echo '--- FAIL expected: invalid outcome label'
INSERT INTO payment_webhook_events(provider,event_id,payload,outcome) VALUES ('provx','evt4','{}','MAYBE');
\echo '--- FAIL expected: event for an intent that does not exist'
INSERT INTO payment_webhook_events(provider,event_id,payload,intent_id) VALUES ('provx','evt5','{}','00000000-0000-0000-0000-00000000dead');
\echo '--- OK expected: processing result may be written (processed_at, outcome)'
UPDATE payment_webhook_events SET processed_at=now(), outcome='APPLIED' WHERE event_id='evt1' AND provider='provx';
\echo '--- FAIL expected: the stored payload cannot be edited'
UPDATE payment_webhook_events SET payload='{"x":2}' WHERE event_id='evt1' AND provider='provx';
\echo '--- FAIL expected: the stored amount cannot be edited'
UPDATE payment_webhook_events SET amount=1 WHERE event_id='evt1' AND provider='provx';
\echo '--- FAIL expected: the provider event id cannot be edited'
UPDATE payment_webhook_events SET event_id='evt9' WHERE event_id='evt1' AND provider='provx';
\echo '--- FAIL expected: DELETE without the retention job flag'
DELETE FROM payment_webhook_events WHERE event_id='evt1' AND provider='provx';
\echo '--- FAIL expected: DELETE with the retention flag but the event is younger than one day'
SET galla.retention_job = 'on';
DELETE FROM payment_webhook_events WHERE event_id='evt1' AND provider='provx';
RESET galla.retention_job;
\echo '--- OK expected: retention job deletes an old event'
INSERT INTO payment_webhook_events(provider,event_id,payload,received_at) VALUES ('provx','old1','{}',now()-interval '40 days');
SET galla.retention_job = 'on';
DELETE FROM payment_webhook_events WHERE event_id='old1';
RESET galla.retention_job;

-- ================================================== B. settlements
\echo '--- OK expected: settlement report gross 100 fee 2 net 98'
INSERT INTO provider_settlements(id,tenant_id,outlet_id,provider,settlement_ref,settlement_date,gross_amount,fee_amount,net_amount,imported_by) VALUES ('00000000-0000-0000-0000-00000000a501',:T,:O,'provx','SET-1','2026-11-10',100.00,2.00,98.00,:U);
\echo '--- FAIL expected: the same settlement imported twice'
INSERT INTO provider_settlements(tenant_id,provider,settlement_ref,settlement_date,gross_amount,fee_amount,net_amount,imported_by) VALUES (:T,'provx','SET-1','2026-11-10',100.00,2.00,98.00,:U);
\echo '--- FAIL expected: net is not gross minus fee'
INSERT INTO provider_settlements(tenant_id,provider,settlement_ref,settlement_date,gross_amount,fee_amount,net_amount,imported_by) VALUES (:T,'provx','SET-2','2026-11-10',100.00,2.00,99.00,:U);
\echo '--- FAIL expected: negative gross'
INSERT INTO provider_settlements(tenant_id,provider,settlement_ref,settlement_date,gross_amount,fee_amount,net_amount,imported_by) VALUES (:T,'provx','SET-3','2026-11-10',-1,0,-1,:U);
\echo '--- OK expected: matched line'
INSERT INTO provider_settlement_lines(settlement_id,provider_txn_id,amount,intent_id,match_status) VALUES ('00000000-0000-0000-0000-00000000a501','TX1',100.00,:I1,'MATCHED');
\echo '--- FAIL expected: same transaction twice in one report'
INSERT INTO provider_settlement_lines(settlement_id,provider_txn_id,amount,match_status) VALUES ('00000000-0000-0000-0000-00000000a501','TX1',100.00,'UNMATCHED');
\echo '--- FAIL expected: MATCHED line without an intent'
INSERT INTO provider_settlement_lines(settlement_id,provider_txn_id,amount,match_status) VALUES ('00000000-0000-0000-0000-00000000a501','TX2',100.00,'MATCHED');
\echo '--- OK expected: unmatched line and amount-difference line'
INSERT INTO provider_settlement_lines(settlement_id,provider_txn_id,amount,match_status) VALUES ('00000000-0000-0000-0000-00000000a501','TX3',55.00,'UNMATCHED');
INSERT INTO provider_settlement_lines(settlement_id,provider_txn_id,amount,intent_id,match_status,note) VALUES ('00000000-0000-0000-0000-00000000a501','TX4',90.00,:I2,'AMOUNT_DIFF','settled 90 vs intent 100');
\echo '--- FAIL expected: invalid match status'
INSERT INTO provider_settlement_lines(settlement_id,provider_txn_id,amount,match_status) VALUES ('00000000-0000-0000-0000-00000000a501','TX5',1,'GUESSED');
\echo '--- FAIL expected: line for an unknown settlement'
INSERT INTO provider_settlement_lines(settlement_id,provider_txn_id,amount,match_status) VALUES ('00000000-0000-0000-0000-00000000dead','TX6',1,'UNMATCHED');

-- ================================================== C. legal fields on the outlet
\echo '--- OK expected: legal fields (GSTIN, matching state code and PAN, FSSAI 14 digits)'
UPDATE outlets SET legal_name='Cafe Z Pvt', gstin='27ABCDE1234F1Z5', state_code='27', pan='ABCDE1234F', fssai_licence_no='12345678901234', registration_type='REGULAR', document_title='TAX_INVOICE', print_hsn=true WHERE id=:O2;
\echo '--- FAIL expected: GSTIN in lower case'
UPDATE outlets SET gstin='27abcde1234f1z5' WHERE id=:O;
\echo '--- FAIL expected: GSTIN too short (14 characters)'
UPDATE outlets SET gstin='27ABCDE1234F1Z' WHERE id=:O;
\echo '--- FAIL expected: GSTIN whose 14th character is not Z'
UPDATE outlets SET gstin='27ABCDE1234F1X5' WHERE id=:O;
\echo '--- FAIL expected: GSTIN with letters where the state digits belong'
UPDATE outlets SET gstin='AAABCDE1234F1Z5' WHERE id=:O;
\echo '--- FAIL expected: state code with letters'
UPDATE outlets SET state_code='MH' WHERE id=:O;
\echo '--- FAIL expected: state code does not match the first two GSTIN digits'
UPDATE outlets SET state_code='29' WHERE id=:O2;
\echo '--- FAIL expected: PAN does not match GSTIN characters 3-12'
UPDATE outlets SET pan='ABCDE1234G' WHERE id=:O2;
\echo '--- FAIL expected: PAN in a wrong format'
UPDATE outlets SET pan='12345ABCDE' WHERE id=:O;
\echo '--- FAIL expected: FSSAI licence with 13 digits'
UPDATE outlets SET fssai_licence_no='1234567890123' WHERE id=:O;
\echo '--- FAIL expected: FSSAI licence with a letter'
UPDATE outlets SET fssai_licence_no='1234567890123A' WHERE id=:O;
\echo '--- FAIL expected: FSSAI licence with spaces'
UPDATE outlets SET fssai_licence_no='1234 5678 9012 34' WHERE id=:O;
\echo '--- OK expected: GSTIN alone (no state code, no PAN) is accepted'
UPDATE outlets SET gstin='29ABCDE1234F1Z5' WHERE id=:O;
\echo '--- FAIL expected: invalid registration type'
UPDATE outlets SET registration_type='GST_REGISTERED' WHERE id=:O;
\echo '--- FAIL expected: invalid document title'
UPDATE outlets SET document_title='RECEIPT' WHERE id=:O;
\echo '--- FAIL expected: invalid place-of-supply mode'
UPDATE outlets SET place_of_supply_mode='CUSTOMER_STATE' WHERE id=:O;
\echo '--- FAIL expected: bill language in upper case'
UPDATE outlets SET bill_language='EN' WHERE id=:O;
\echo '--- FAIL expected: bill language as a word'
UPDATE outlets SET bill_language='english' WHERE id=:O;
\echo '--- OK expected: bill language hi and pt-BR'
UPDATE outlets SET bill_language='hi' WHERE id=:O;
UPDATE outlets SET bill_language='pt-BR' WHERE id=:O2;

-- ================================================== C. HSN / customers / bill snapshots
\echo '--- FAIL expected: HSN with letters'
UPDATE menu_items SET hsn_sac_code='AB12' WHERE id=:MI;
\echo '--- FAIL expected: HSN with one digit'
UPDATE menu_items SET hsn_sac_code='9' WHERE id=:MI;
\echo '--- FAIL expected: HSN with nine digits'
UPDATE menu_items SET hsn_sac_code='123456789' WHERE id=:MI;
\echo '--- OK expected: HSN/SAC of 4 and 8 digits'
UPDATE menu_items SET hsn_sac_code='9963' WHERE id=:MI;
UPDATE menu_items SET hsn_sac_code='99633110' WHERE id=:MI;
\echo '--- FAIL expected: customer GSTIN in a wrong format'
UPDATE customers SET gstin='27ABCDE1234F1' WHERE phone='+919876500000';
\echo '--- OK expected: customer legal name and GSTIN'
UPDATE customers SET legal_name='Buyer Ltd', gstin='27AAAAA0000A1Z5' WHERE phone='+919876500000';
\echo '--- FAIL expected: bill buyer GSTIN in a wrong format'
UPDATE bills SET buyer_gstin='nope' WHERE id=:B1;
\echo '--- FAIL expected: bill place-of-supply code with letters'
UPDATE bills SET place_of_supply_state_code='MH' WHERE id=:B1;
\echo '--- OK expected: document snapshot on the bill'
UPDATE bills SET document_title='TAX_INVOICE', seller_legal_name='Cafe Z Pvt', seller_gstin='27ABCDE1234F1Z5', seller_state_code='27', seller_fssai_licence_no='12345678901234', place_of_supply_state_code='27', buyer_legal_name='Buyer Ltd', buyer_gstin='27AAAAA0000A1Z5', bill_language='hi' WHERE id=:B1;
\echo '--- OK expected: tax-profile pair (intra -> inter)'
INSERT INTO tax_profile_pairs(tenant_id,intra_profile_id,inter_profile_id) VALUES (:T,'00000000-0000-0000-0000-0000000000a9','00000000-0000-0000-0000-0000000000aa');
\echo '--- FAIL expected: the same intra profile paired twice'
INSERT INTO tax_profile_pairs(tenant_id,intra_profile_id,inter_profile_id) VALUES (:T,'00000000-0000-0000-0000-0000000000a9','00000000-0000-0000-0000-0000000000aa');
\echo '--- FAIL expected: a profile paired with itself'
INSERT INTO tax_profile_pairs(tenant_id,intra_profile_id,inter_profile_id) VALUES (:T,'00000000-0000-0000-0000-0000000000aa','00000000-0000-0000-0000-0000000000aa');

-- ================================================== C. Tally ledger mappings
\echo '--- OK expected: ledger mapping'
INSERT INTO tally_ledger_mappings(tenant_id,outlet_id,purpose,tally_ledger_name) VALUES (:T,:O,'SALES','Sales - Restaurant');
\echo '--- FAIL expected: same purpose twice for an outlet'
INSERT INTO tally_ledger_mappings(tenant_id,outlet_id,purpose,tally_ledger_name) VALUES (:T,:O,'SALES','Other');
\echo '--- FAIL expected: unknown purpose'
INSERT INTO tally_ledger_mappings(tenant_id,outlet_id,purpose,tally_ledger_name) VALUES (:T,:O,'DISCOUNT','D');
\echo '--- FAIL expected: blank ledger name'
INSERT INTO tally_ledger_mappings(tenant_id,outlet_id,purpose,tally_ledger_name) VALUES (:T,:O,'CASH','   ');
\echo '--- OK expected: tax ledger mapping'
INSERT INTO tally_tax_ledger_mappings(tenant_id,outlet_id,component_name,tally_ledger_name) VALUES (:T,:O,'CGST','Output CGST');
\echo '--- FAIL expected: same tax component twice for an outlet'
INSERT INTO tally_tax_ledger_mappings(tenant_id,outlet_id,component_name,tally_ledger_name) VALUES (:T,:O,'CGST','Other');

-- ================================================== exports
\echo '--- OK expected: queued register export'
INSERT INTO export_jobs(id,tenant_id,outlet_id,kind,format,requested_by) VALUES ('00000000-0000-0000-0000-00000000e501',:T,:O,'SALES_REGISTER','CSV',:U);
\echo '--- FAIL expected: DONE without file details'
UPDATE export_jobs SET status='DONE' WHERE id='00000000-0000-0000-0000-00000000e501';
\echo '--- FAIL expected: file checksum that is not 64 hex characters'
UPDATE export_jobs SET file_sha256='abc' WHERE id='00000000-0000-0000-0000-00000000e501';
\echo '--- OK expected: DONE with file, checksum, row count and finish time'
UPDATE export_jobs SET status='DONE', file_key='exports/1.csv', file_sha256=repeat('a',64), row_count=12, finished_at=now() WHERE id='00000000-0000-0000-0000-00000000e501';
\echo '--- FAIL expected: negative row count'
UPDATE export_jobs SET row_count=-1 WHERE id='00000000-0000-0000-0000-00000000e501';
\echo '--- FAIL expected: Tally vouchers in CSV format'
INSERT INTO export_jobs(tenant_id,outlet_id,kind,format,requested_by) VALUES (:T,:O,'TALLY_VOUCHERS','CSV',:U);
\echo '--- OK expected: Tally vouchers as XML'
INSERT INTO export_jobs(tenant_id,outlet_id,kind,format,requested_by) VALUES (:T,:O,'TALLY_VOUCHERS','XML',:U);
\echo '--- FAIL expected: tenant data export as CSV'
INSERT INTO export_jobs(tenant_id,kind,format,requested_by) VALUES (:T,'TENANT_DATA_EXPORT','CSV',:U);
\echo '--- OK expected: tenant data export as ZIP'
INSERT INTO export_jobs(tenant_id,kind,format,requested_by) VALUES (:T,'TENANT_DATA_EXPORT','ZIP',:U);
\echo '--- FAIL expected: unknown export kind'
INSERT INTO export_jobs(tenant_id,kind,format,requested_by) VALUES (:T,'EVERYTHING','CSV',:U);
\echo '--- FAIL expected: unknown export status'
UPDATE export_jobs SET status='PAUSED' WHERE id='00000000-0000-0000-0000-00000000e501';

-- ================================================== D. languages
\echo '--- FAIL expected: user UI language as a word'
UPDATE users SET ui_language='Hindi' WHERE id=:U;
\echo '--- OK expected: user UI language hi'
UPDATE users SET ui_language='hi' WHERE id=:U;
\echo '--- OK expected: item translation'
INSERT INTO menu_item_translations(tenant_id,menu_item_id,language,name) VALUES (:T,:MI,'hi','पनीर');
\echo '--- FAIL expected: same item and language twice'
INSERT INTO menu_item_translations(tenant_id,menu_item_id,language,name) VALUES (:T,:MI,'hi','दूसरा');
\echo '--- FAIL expected: translation into en (English is the item name)'
INSERT INTO menu_item_translations(tenant_id,menu_item_id,language,name) VALUES (:T,:MI,'en','Paneer');
\echo '--- FAIL expected: blank translated name'
INSERT INTO menu_item_translations(tenant_id,menu_item_id,language,name) VALUES (:T,:MI,'mr','  ');

-- ================================================== E. data management
\echo '--- OK expected: tenant data settings with defaults'
INSERT INTO tenant_data_settings(tenant_id) VALUES (:T);
\echo '--- FAIL expected: audit retention below 365 days'
UPDATE tenant_data_settings SET audit_log_retention_days=100 WHERE tenant_id=:T;
\echo '--- FAIL expected: webhook payload retention below 7 days'
UPDATE tenant_data_settings SET webhook_payload_retention_days=3 WHERE tenant_id=:T;
\echo '--- FAIL expected: export file retention of 0 days'
UPDATE tenant_data_settings SET export_file_retention_days=0 WHERE tenant_id=:T;
\echo '--- FAIL expected: deletion before the export window ends'
UPDATE tenant_data_settings SET after_cancel_delete_days=10 WHERE tenant_id=:T;
\echo '--- OK expected: both windows changed together'
UPDATE tenant_data_settings SET after_cancel_export_days=30, after_cancel_delete_days=180 WHERE tenant_id=:T;
\echo '--- FAIL expected: a second settings row for the same tenant'
INSERT INTO tenant_data_settings(tenant_id) VALUES (:T);
\echo '--- OK expected: erasure request by customer id'
INSERT INTO data_subject_requests(id,tenant_id,customer_id,request_type,due_at) VALUES ('00000000-0000-0000-0000-00000000d501',:T,'00000000-0000-0000-0000-0000000000cc','ERASURE',now()+interval '30 days');
\echo '--- OK expected: access request by phone only'
INSERT INTO data_subject_requests(tenant_id,phone_e164,request_type,due_at) VALUES (:T,'+919876543210','ACCESS_EXPORT',now()+interval '30 days');
\echo '--- FAIL expected: request with neither customer nor phone'
INSERT INTO data_subject_requests(tenant_id,request_type,due_at) VALUES (:T,'ERASURE',now()+interval '30 days');
\echo '--- FAIL expected: phone without + country code'
INSERT INTO data_subject_requests(tenant_id,phone_e164,request_type,due_at) VALUES (:T,'9876543210','ERASURE',now()+interval '30 days');
\echo '--- FAIL expected: due date not after receipt'
INSERT INTO data_subject_requests(tenant_id,phone_e164,request_type,due_at) VALUES (:T,'+919876543210','ERASURE',now()-interval '1 day');
\echo '--- FAIL expected: unknown request type'
INSERT INTO data_subject_requests(tenant_id,phone_e164,request_type,due_at) VALUES (:T,'+919876543210','SELL',now()+interval '30 days');
\echo '--- FAIL expected: COMPLETED without handler and completion time'
UPDATE data_subject_requests SET status='COMPLETED' WHERE id='00000000-0000-0000-0000-00000000d501';
\echo '--- FAIL expected: REJECTED without an outcome note'
UPDATE data_subject_requests SET status='REJECTED', completed_at=now(), handled_by=:U WHERE id='00000000-0000-0000-0000-00000000d501';
\echo '--- OK expected: REJECTED with note, handler and time'
UPDATE data_subject_requests SET status='REJECTED', completed_at=now(), handled_by=:U, outcome_note='Identity not verified' WHERE id='00000000-0000-0000-0000-00000000d501';
\echo '--- FAIL expected: hard delete of a customer that has a request (erasure anonymises instead)'
DELETE FROM customers WHERE id='00000000-0000-0000-0000-0000000000cc';
\echo '--- OK expected: weekly summary schedule'
INSERT INTO scheduled_reports(tenant_id,outlet_id,kind,weekday,recipients) VALUES (:T,:O,'WEEKLY_SUMMARY',1,ARRAY['owner@x.io']);
\echo '--- FAIL expected: second weekly schedule for the same outlet'
INSERT INTO scheduled_reports(tenant_id,outlet_id,kind,weekday,recipients) VALUES (:T,:O,'WEEKLY_SUMMARY',2,ARRAY['owner@x.io']);
\echo '--- FAIL expected: weekly schedule without a weekday'
INSERT INTO scheduled_reports(tenant_id,outlet_id,kind,recipients) VALUES (:T,:O2,'WEEKLY_SUMMARY',ARRAY['owner@x.io']);
\echo '--- FAIL expected: monthly schedule without a day of month'
INSERT INTO scheduled_reports(tenant_id,outlet_id,kind,recipients) VALUES (:T,:O2,'MONTHLY_SUMMARY',ARRAY['owner@x.io']);
\echo '--- FAIL expected: monthly day 29'
INSERT INTO scheduled_reports(tenant_id,outlet_id,kind,day_of_month,recipients) VALUES (:T,:O2,'MONTHLY_SUMMARY',29,ARRAY['owner@x.io']);
\echo '--- FAIL expected: weekday 8'
INSERT INTO scheduled_reports(tenant_id,outlet_id,kind,weekday,recipients) VALUES (:T,:O2,'WEEKLY_SUMMARY',8,ARRAY['owner@x.io']);
\echo '--- FAIL expected: no recipients'
INSERT INTO scheduled_reports(tenant_id,outlet_id,kind,weekday,recipients) VALUES (:T,:O2,'WEEKLY_SUMMARY',1,ARRAY[]::text[]);
\echo '--- FAIL expected: eleven recipients'
INSERT INTO scheduled_reports(tenant_id,outlet_id,kind,weekday,recipients) VALUES (:T,:O2,'WEEKLY_SUMMARY',1,ARRAY['a@x.io','b@x.io','c@x.io','d@x.io','e@x.io','f@x.io','g@x.io','h@x.io','i@x.io','j@x.io','k@x.io']);
\echo '--- OK expected: backup run and a tested restore'
INSERT INTO backup_runs(kind,status) VALUES ('FULL','RUNNING');
INSERT INTO backup_runs(kind,status,finished_at,size_bytes,notes) VALUES ('RESTORE_TEST','OK',now(),123456,'restored to scratch, row counts matched');
\echo '--- FAIL expected: finished backup run without finish time'
INSERT INTO backup_runs(kind,status) VALUES ('FULL','OK');
\echo '--- FAIL expected: finish time before start'
INSERT INTO backup_runs(kind,status,started_at,finished_at) VALUES ('FULL','OK',now(),now()-interval '1 hour');
\echo '--- FAIL expected: unknown backup kind'
INSERT INTO backup_runs(kind,status) VALUES ('SNAPSHOT','RUNNING');
\echo '--- FAIL expected: negative backup size'
INSERT INTO backup_runs(kind,status,finished_at,size_bytes) VALUES ('FULL','OK',now(),-1);

-- ================================================== audit log append-only
\echo '--- OK expected: audit row written'
INSERT INTO audit_logs(tenant_id,user_id,action,entity_type,entity_id) VALUES (:T,:U,'TEST','x','1');
\echo '--- FAIL expected: audit row cannot be changed'
UPDATE audit_logs SET action='EDITED' WHERE entity_id='1';
\echo '--- FAIL expected: audit row cannot be deleted by the application'
DELETE FROM audit_logs WHERE entity_id='1';
\echo '--- OK expected: the retention job (flag on) may delete audit rows'
SET galla.retention_job = 'on';
DELETE FROM audit_logs WHERE entity_id='1';
RESET galla.retention_job;
\echo '--- FAIL expected: the flag does not allow changing audit rows'
INSERT INTO audit_logs(tenant_id,user_id,action,entity_type,entity_id) VALUES (:T,:U,'TEST','x','2');
SET galla.retention_job = 'on';
UPDATE audit_logs SET action='EDITED' WHERE entity_id='2';
RESET galla.retention_job;
