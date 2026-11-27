INSERT INTO outlets(id,tenant_id,code,name,country_code,timezone,currency_code,currency_symbol,prices_include_tax,fiscal_year_start_month)
 VALUES ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000001','O2','Out2','IN','Asia/Kolkata','INR','Rs',false,4) ON CONFLICT DO NOTHING;
INSERT INTO users(id,tenant_id,email,password_hash,full_name,role) VALUES ('00000000-0000-0000-0000-0000000000f6','00000000-0000-0000-0000-000000000001','v16@x.io','x','V','OWNER') ON CONFLICT DO NOTHING;
INSERT INTO devices(id,tenant_id,outlet_id,name,series_code,status,pairing_code_hash,pairing_expires_at,created_by)
 VALUES ('00000000-0000-0000-0000-00000000d016','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','T1','A','PENDING','h',now()+interval '1 hour','00000000-0000-0000-0000-0000000000f6');
\echo '--- OK expected: shift on an existing device of the same outlet'
INSERT INTO cashier_shifts(tenant_id,outlet_id,device_id,cashier_id,business_date) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000d016','00000000-0000-0000-0000-0000000000f6',current_date);
UPDATE cashier_shifts SET status='CLOSED',closed_at=now(),counted_cash=0,expected_cash=0,variance=0,closed_by='00000000-0000-0000-0000-0000000000f6';
\echo '--- FAIL expected: shift pointing at a device that does not exist'
INSERT INTO cashier_shifts(tenant_id,outlet_id,device_id,cashier_id,business_date) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dead','00000000-0000-0000-0000-0000000000f6',current_date);
\echo '--- FAIL expected: shift at outlet 2 using a device of outlet 1'
INSERT INTO cashier_shifts(tenant_id,outlet_id,device_id,cashier_id,business_date) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-00000000d016','00000000-0000-0000-0000-0000000000f6',current_date);
\echo '--- FAIL expected: deleting a device that still has a shift'
DELETE FROM devices WHERE id='00000000-0000-0000-0000-00000000d016';
\echo '--- OK expected: shift without a device (online-only terminal)'
INSERT INTO cashier_shifts(tenant_id,outlet_id,cashier_id,business_date) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000f6',current_date);
