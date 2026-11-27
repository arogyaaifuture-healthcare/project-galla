\set T '''00000000-0000-0000-0000-000000000001'''
\set T2 '''00000000-0000-0000-0000-000000000002'''
\set O '''00000000-0000-0000-0000-0000000000a1'''
\set O2 '''00000000-0000-0000-0000-0000000000a2'''
\set U '''00000000-0000-0000-0000-0000000000f7'''
\set C1 '''00000000-0000-0000-0000-00000000c701'''
\set C2 '''00000000-0000-0000-0000-00000000c702'''
\set B1 '''00000000-0000-0000-0000-000000000801'''
\set B2 '''00000000-0000-0000-0000-000000000802'''
\set B3 '''00000000-0000-0000-0000-000000000803'''
\set B4 '''00000000-0000-0000-0000-000000000804'''
\set T1 '''00000000-0000-0000-0000-00000000b701'''
\set TB2 '''00000000-0000-0000-0000-00000000b702'''
\set TX '''00000000-0000-0000-0000-00000000b703'''
\echo '--- OK expected: loyalty program with defaults'
INSERT INTO loyalty_programs(tenant_id,enabled) VALUES (:T,true);
\echo '--- FAIL expected: spend_per_point 0'
UPDATE loyalty_programs SET spend_per_point=0;
\echo '--- FAIL expected: max_redeem_percent 101'
UPDATE loyalty_programs SET max_redeem_percent=101;
\echo '--- FAIL expected: expiry below 30 days'
UPDATE loyalty_programs SET expiry_days=10;
\echo '--- OK expected: earn 50 points on bill 1'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C1,'EARN',50,:B1);
\echo '--- FAIL expected: second earn on the same bill'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C1,'EARN',10,:B1);
\echo '--- FAIL expected: negative earn'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C1,'EARN',-5,:B2);
\echo '--- FAIL expected: earn without a bill'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points) VALUES (:T,:C1,'EARN',5);
\echo '--- FAIL expected: zero points'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C1,'EARN',0,:B2);
\echo '--- OK expected: redeem 20 points on bill 1 (balance 50)'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C1,'REDEEM',-20,:B1);
\echo '--- FAIL expected: second redeem on the same bill'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C1,'REDEEM',-5,:B1);
\echo '--- FAIL expected: redeem more than the balance (30 left)'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C1,'REDEEM',-31,:B2);
\echo '--- OK expected: redeem exactly the remaining 30'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C1,'REDEEM',-30,:B2);
\echo '--- FAIL expected: positive redeem'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C2,'REDEEM',5,:B3);
\echo '--- FAIL expected: adjustment without a reason'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,created_by) VALUES (:T,:C2,'ADJUST',10,:U);
\echo '--- FAIL expected: adjustment without the staff user'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,reason) VALUES (:T,:C2,'ADJUST',10,'goodwill');
\echo '--- OK expected: adjustment with reason and user'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,reason,created_by) VALUES (:T,:C2,'ADJUST',40,'goodwill',:U);
\echo '--- FAIL expected: expires_at on a non-earn entry'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,reason,created_by,expires_at) VALUES (:T,:C2,'ADJUST',5,'x',:U,now());
\echo '--- OK expected: earn with an expiry date'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id,expires_at) VALUES (:T,:C2,'EARN',10,:B3,now()+interval '365 days');
\echo '--- OK expected: expire 5 of 50'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,reason) VALUES (:T,:C2,'EXPIRE',-5,'batch expiry');
\echo '--- FAIL expected: expire more than the balance'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,reason) VALUES (:T,:C2,'EXPIRE',-500,'batch expiry');
\echo '--- OK expected: reversal of an earn may take the balance below zero (customer already spent the points)'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,bill_id) VALUES (:T,:C1,'REVERSE_EARN',-10,:B1);
\echo '--- FAIL expected: restore without a bill or credit note'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points) VALUES (:T,:C1,'RESTORE_REDEEM',10);
\echo '--- FAIL expected: ledger row of another tenant for this customer'
INSERT INTO loyalty_ledger(tenant_id,customer_id,entry_type,points,reason,created_by) VALUES (:T2,:C1,'ADJUST',5,'x',:U);
\echo '--- FAIL expected: ledger rows cannot be updated'
UPDATE loyalty_ledger SET points=999 WHERE entry_type='EARN';
\echo '--- FAIL expected: ledger rows cannot be deleted'
DELETE FROM loyalty_ledger;
\echo '--- OK expected: balance of customer 1 = 50-20-30-10 = -10'
SELECT SUM(points) AS balance FROM loyalty_ledger WHERE customer_id=:C1;
\echo '--- OK expected: loyalty payment with customer and points'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,customer_id,loyalty_points) VALUES ('00000000-0000-0000-0000-00000000e701',:T,:O,:B1,'LOYALTY',20,'SUCCESS',:U,:C1,20);
\echo '--- FAIL expected: LOYALTY payment without points'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,customer_id) VALUES ('00000000-0000-0000-0000-00000000e702',:T,:O,:B1,'LOYALTY',5,'SUCCESS',:U,:C1);
\echo '--- FAIL expected: points on a CASH payment'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,loyalty_points) VALUES ('00000000-0000-0000-0000-00000000e703',:T,:O,:B1,'CASH',5,'SUCCESS',:U,5);
\echo '--- FAIL expected: LOYALTY payment without a customer'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,loyalty_points) VALUES ('00000000-0000-0000-0000-00000000e704',:T,:O,:B1,'LOYALTY',5,'SUCCESS',:U,5);
\echo '--- FAIL expected: LOYALTY payment with a tip'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,customer_id,loyalty_points,tip_amount) VALUES ('00000000-0000-0000-0000-00000000e705',:T,:O,:B1,'LOYALTY',5,'SUCCESS',:U,:C1,5,2);
\echo '--- OK expected: payment mode Paytm (UPI) for all outlets'
INSERT INTO payment_modes(id,tenant_id,label,base_method) VALUES ('00000000-0000-0000-0000-00000000d701',:T,'Paytm','UPI');
\echo '--- FAIL expected: same label in other case'
INSERT INTO payment_modes(tenant_id,label,base_method) VALUES (:T,' paytm ','UPI');
\echo '--- FAIL expected: blank label'
INSERT INTO payment_modes(tenant_id,label,base_method) VALUES (:T,'  ','UPI');
\echo '--- FAIL expected: unknown base method'
INSERT INTO payment_modes(tenant_id,label,base_method) VALUES (:T,'Wallet X','WALLET');
\echo '--- OK expected: UPI payment tagged Paytm'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,payment_mode_id) VALUES ('00000000-0000-0000-0000-00000000e706',:T,:O,:B2,'UPI',10,'SUCCESS',:U,'00000000-0000-0000-0000-00000000d701');
\echo '--- FAIL expected: CASH payment tagged with a UPI mode'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,payment_mode_id) VALUES ('00000000-0000-0000-0000-00000000e707',:T,:O,:B2,'CASH',10,'SUCCESS',:U,'00000000-0000-0000-0000-00000000d701');
\echo '--- OK expected: mode that belongs to outlet 2 only'
INSERT INTO payment_modes(id,tenant_id,outlet_id,label,base_method) VALUES ('00000000-0000-0000-0000-00000000d702',:T,:O2,'Sodexo','OTHER');
\echo '--- FAIL expected: outlet-2 mode used at outlet 1'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,payment_mode_id) VALUES ('00000000-0000-0000-0000-00000000e708',:T,:O,:B2,'OTHER',10,'SUCCESS',:U,'00000000-0000-0000-0000-00000000d702');
\echo '--- OK expected: deactivate a mode'
INSERT INTO payment_modes(id,tenant_id,label,base_method,active) VALUES ('00000000-0000-0000-0000-00000000d703',:T,'Old wallet','OTHER',false);
\echo '--- FAIL expected: inactive mode used for a new payment'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,payment_mode_id) VALUES ('00000000-0000-0000-0000-00000000e709',:T,:O,:B2,'OTHER',10,'SUCCESS',:U,'00000000-0000-0000-0000-00000000d703');
\echo '--- OK expected: reservation of table T1 from 19:00 for 90 minutes'
INSERT INTO reservations(id,tenant_id,outlet_id,guest_name,guest_phone,party_size,table_id,reserved_for,duration_minutes,reserved_until,created_by) VALUES ('00000000-0000-0000-0000-00000000f701',:T,:O,'Mehta','+919811111111',4,:T1,'2026-12-01 19:00+05:30',90,'2026-12-01 20:30+05:30',:U);
\echo '--- FAIL expected: overlapping reservation for the same table (20:00)'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,table_id,reserved_for,duration_minutes,reserved_until,created_by) VALUES (:T,:O,'Shah',2,:T1,'2026-12-01 20:00+05:30',60,'2026-12-01 21:00+05:30',:U);
\echo '--- OK expected: back-to-back reservation starting at 20:30'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,table_id,reserved_for,duration_minutes,reserved_until,created_by) VALUES (:T,:O,'Shah',2,:T1,'2026-12-01 20:30+05:30',60,'2026-12-01 21:30+05:30',:U);
\echo '--- OK expected: same time on another table'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,table_id,reserved_for,duration_minutes,reserved_until,created_by) VALUES (:T,:O,'Iyer',3,:TB2,'2026-12-01 19:00+05:30',90,'2026-12-01 20:30+05:30',:U);
\echo '--- OK expected: a cancelled reservation frees its slot'
UPDATE reservations SET status='CANCELLED', cancel_reason='guest called' WHERE id='00000000-0000-0000-0000-00000000f701';
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,table_id,reserved_for,duration_minutes,reserved_until,created_by) VALUES (:T,:O,'Nair',2,:T1,'2026-12-01 19:15+05:30',60,'2026-12-01 20:15+05:30',:U);
\echo '--- FAIL expected: cancel without a reason'
UPDATE reservations SET status='CANCELLED', cancel_reason=NULL WHERE guest_name='Nair';
\echo '--- FAIL expected: seated without seated_at'
UPDATE reservations SET status='SEATED' WHERE guest_name='Nair';
\echo '--- OK expected: seated with time and order'
UPDATE reservations SET status='SEATED', seated_at=now(), seated_order_id='00000000-0000-0000-0000-000000000705' WHERE guest_name='Nair';
\echo '--- FAIL expected: party size 0'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,reserved_for,duration_minutes,reserved_until,created_by) VALUES (:T,:O,'Z',0,'2026-12-02 19:00+05:30',90,'2026-12-02 20:30+05:30',:U);
\echo '--- FAIL expected: duration 5 minutes'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,reserved_for,duration_minutes,reserved_until,created_by) VALUES (:T,:O,'Z',2,'2026-12-02 19:00+05:30',5,'2026-12-02 19:05+05:30',:U);
\echo '--- FAIL expected: reserved_until does not match the duration'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,reserved_for,duration_minutes,reserved_until,created_by) VALUES (:T,:O,'Z',2,'2026-12-02 19:00+05:30',90,'2026-12-02 19:30+05:30',:U);
\echo '--- FAIL expected: table of another outlet'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,table_id,reserved_for,duration_minutes,reserved_until,created_by) VALUES (:T,:O,'Z',2,:TX,'2026-12-02 19:00+05:30',90,'2026-12-02 20:30+05:30',:U);
\echo '--- FAIL expected: invalid phone'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,guest_phone,party_size,reserved_for,duration_minutes,reserved_until,created_by) VALUES (:T,:O,'Z','98-ab',2,'2026-12-02 19:00+05:30',90,'2026-12-02 20:30+05:30',:U);
\echo '--- FAIL expected: unknown status'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,reserved_for,duration_minutes,reserved_until,created_by,status) VALUES (:T,:O,'Z',2,'2026-12-02 19:00+05:30',90,'2026-12-02 20:30+05:30',:U,'LATE');
\echo '--- OK expected: waitlist entry without a table may overlap anything'
INSERT INTO reservations(tenant_id,outlet_id,guest_name,party_size,reserved_for,duration_minutes,reserved_until,created_by,source) VALUES (:T,:O,'Walk',2,'2026-12-01 19:15+05:30',60,'2026-12-01 20:15+05:30',:U,'WALK_IN_WAITLIST');
\echo '--- OK expected: token label A14 on order 1'
UPDATE orders SET token_label='A14' WHERE order_no=1;
\echo '--- FAIL expected: same token label on the same day and outlet'
UPDATE orders SET token_label='A14' WHERE order_no=2;
\echo '--- OK expected: same label on another business date'
UPDATE orders SET token_label='A14', business_date='2026-11-02' WHERE order_no=2;
\echo '--- FAIL expected: lower-case token label'
UPDATE orders SET token_label='a15' WHERE order_no=3;
\echo '--- FAIL expected: token label with 6 digits'
UPDATE orders SET token_label='123456' WHERE order_no=3;
\echo '--- OK expected: plain numeric token'
UPDATE orders SET token_label='15' WHERE order_no=3;
\echo '--- FAIL expected: unknown token mode'
UPDATE outlets SET token_mode='SOMETIMES' WHERE id=:O;
\echo '--- OK expected: token mode TAKEAWAY_DELIVERY'
UPDATE outlets SET token_mode='TAKEAWAY_DELIVERY' WHERE id=:O;
\echo '--- OK expected: counter upsert gives 1'
INSERT INTO token_counters(outlet_id,business_date,last_no) VALUES (:O,'2026-11-01',1) ON CONFLICT (outlet_id,business_date) DO UPDATE SET last_no = token_counters.last_no + 1 RETURNING last_no;
\echo '--- OK expected: counter upsert gives 2'
INSERT INTO token_counters(outlet_id,business_date,last_no) VALUES (:O,'2026-11-01',1) ON CONFLICT (outlet_id,business_date) DO UPDATE SET last_no = token_counters.last_no + 1 RETURNING last_no;
\echo '--- FAIL expected: counter above 99999'
UPDATE token_counters SET last_no = 100000;
