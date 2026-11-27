\set T '''00000000-0000-0000-0000-000000000001'''
\set O '''00000000-0000-0000-0000-0000000000a1'''
\set O2 '''00000000-0000-0000-0000-0000000000a2'''
\set U '''00000000-0000-0000-0000-0000000000f1'''
\set B '''00000000-0000-0000-0000-000000000b11'''
INSERT INTO users(id,tenant_id,email,password_hash,full_name,role) VALUES (:U,:T,'wa@x.io','x','W','OWNER') ON CONFLICT DO NOTHING;
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by) VALUES ('00000000-0000-0000-0000-0000000000e1',:T,:O,1,current_date,'TAKEAWAY',:U) ON CONFLICT DO NOTHING;
INSERT INTO bills(id,tenant_id,outlet_id,order_id,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by)
 VALUES (:B,:T,:O,'00000000-0000-0000-0000-0000000000e1','2026-27',1,'GL-1',false,'INR',100,0,100,100,:U) ON CONFLICT DO NOTHING;
\echo '--- OK expected: whatsapp account'
INSERT INTO whatsapp_accounts(id,tenant_id,outlet_id,waba_id,phone_number_id,access_token_encrypted) VALUES ('00000000-0000-0000-0000-00000000aaa1'::uuid,:T,:O,'w1','p1','enc');

\echo '--- FAIL expected: second account for the same outlet'
INSERT INTO whatsapp_accounts(tenant_id,outlet_id,waba_id,phone_number_id,access_token_encrypted) VALUES (:T,:O,'w2','p2','enc');
\echo '--- FAIL expected: same phone_number_id on another outlet'
INSERT INTO whatsapp_accounts(tenant_id,outlet_id,waba_id,phone_number_id,access_token_encrypted) VALUES (:T,:O2,'w3','p1','enc');
\echo '--- FAIL expected: invalid account status'
UPDATE whatsapp_accounts SET status='READY' WHERE phone_number_id='p1';
\echo '--- FAIL expected: invalid template status'
UPDATE whatsapp_accounts SET bill_template_status='LIVE' WHERE phone_number_id='p1';
\echo '--- OK expected: opt-in recorded in person by staff'
INSERT INTO customer_consents(tenant_id,outlet_id,phone_e164,channel,status,method,statement_shown,recorded_by) VALUES (:T,:O,'+919876543210','WHATSAPP','OPTED_IN','IN_PERSON','I agree to receive my bill from Cafe Z on WhatsApp',:U);
\echo '--- FAIL expected: phone without +country code'
INSERT INTO customer_consents(tenant_id,phone_e164,channel,status,method,statement_shown,recorded_by) VALUES (:T,'9876543210','WHATSAPP','OPTED_IN','IN_PERSON','x',:U);
\echo '--- FAIL expected: phone with spaces'
INSERT INTO customer_consents(tenant_id,phone_e164,channel,status,method,statement_shown,recorded_by) VALUES (:T,'+91 98765 43210','WHATSAPP','OPTED_IN','IN_PERSON','x',:U);
\echo '--- FAIL expected: customer-message method cannot be an opt-in'
INSERT INTO customer_consents(tenant_id,phone_e164,channel,status,method,statement_shown) VALUES (:T,'+919876543210','WHATSAPP','OPTED_IN','CUSTOMER_MESSAGE','x');
\echo '--- OK expected: customer STOP reply recorded without a user'
INSERT INTO customer_consents(tenant_id,phone_e164,channel,status,method,statement_shown) VALUES (:T,'+919876543210','WHATSAPP','OPTED_OUT','CUSTOMER_MESSAGE','Customer replied STOP');
\echo '--- FAIL expected: staff-recorded consent without the staff user'
INSERT INTO customer_consents(tenant_id,phone_e164,channel,status,method,statement_shown) VALUES (:T,'+919876543210','WHATSAPP','OPTED_IN','IN_PERSON','x');
\echo '--- FAIL expected: blank statement'
INSERT INTO customer_consents(tenant_id,phone_e164,channel,status,method,statement_shown,recorded_by) VALUES (:T,'+919876543210','WHATSAPP','OPTED_IN','IN_PERSON','   ',:U);
\echo '--- OK expected: newest consent row is the OPTED_OUT one'
SELECT status FROM customer_consents WHERE phone_e164='+919876543210' AND channel='WHATSAPP' AND purpose='BILL' ORDER BY recorded_at DESC, id DESC LIMIT 1;
\echo '--- OK expected: bill message'
INSERT INTO whatsapp_messages(id,tenant_id,outlet_id,account_id,kind,bill_id,to_phone,template_name,provider_message_id) VALUES ('00000000-0000-0000-0000-00000000bb01',:T,:O,'00000000-0000-0000-0000-00000000aaa1','BILL',:B,'+919876543210','galla_bill_v1','wamid.AAA');
\echo '--- FAIL expected: duplicate provider message id'
INSERT INTO whatsapp_messages(tenant_id,outlet_id,account_id,kind,bill_id,to_phone,template_name,provider_message_id) VALUES (:T,:O,'00000000-0000-0000-0000-00000000aaa1','BILL',:B,'+919876543210','galla_bill_v1','wamid.AAA');
\echo '--- OK expected: several messages without a provider id yet (queued)'
INSERT INTO whatsapp_messages(tenant_id,outlet_id,account_id,kind,bill_id,to_phone,template_name) VALUES (:T,:O,'00000000-0000-0000-0000-00000000aaa1','BILL',:B,'+919876543210','galla_bill_v1'),(:T,:O,'00000000-0000-0000-0000-00000000aaa1','BILL',:B,'+919876543210','galla_bill_v1');
\echo '--- FAIL expected: BILL message without bill id'
INSERT INTO whatsapp_messages(tenant_id,outlet_id,account_id,kind,to_phone,template_name) VALUES (:T,:O,'00000000-0000-0000-0000-00000000aaa1','BILL','+919876543210','galla_bill_v1');
\echo '--- FAIL expected: DELIVERY_UPDATE without delivery id'
INSERT INTO whatsapp_messages(tenant_id,outlet_id,account_id,kind,to_phone,template_name) VALUES (:T,:O,'00000000-0000-0000-0000-00000000aaa1','DELIVERY_UPDATE','+919876543210','galla_delivery_picked_up_v1');
\echo '--- FAIL expected: bad message status'
UPDATE whatsapp_messages SET status='DONE' WHERE id='00000000-0000-0000-0000-00000000bb01';
\echo '--- FAIL expected: message phone not E.164'
INSERT INTO whatsapp_messages(tenant_id,outlet_id,account_id,kind,bill_id,to_phone,template_name) VALUES (:T,:O,'00000000-0000-0000-0000-00000000aaa1','BILL',:B,'098765','galla_bill_v1');
\echo '--- OK expected: webhook event once'
INSERT INTO whatsapp_webhook_events(event_key,payload) VALUES ('wamid.AAA:delivered:1700000000','{}');
\echo '--- FAIL expected: same webhook event again'
INSERT INTO whatsapp_webhook_events(event_key,payload) VALUES ('wamid.AAA:delivered:1700000000','{}');
\echo '--- OK expected: share link'
INSERT INTO bill_share_links(tenant_id,bill_id,token_hash,expires_at) VALUES (:T,:B,'hash1',now()+interval '90 days');
\echo '--- FAIL expected: duplicate token hash'
INSERT INTO bill_share_links(tenant_id,bill_id,token_hash,expires_at) VALUES (:T,:B,'hash1',now()+interval '90 days');
\echo '--- FAIL expected: negative view count'
UPDATE bill_share_links SET view_count=-1;
\echo '--- FAIL expected: share link days 0'
UPDATE outlets SET bill_share_link_days=0 WHERE id=:O;
\echo '--- OK expected: outlet defaults'
SELECT whatsapp_bill_prompt, bill_share_link_days FROM outlets WHERE id=:O;
