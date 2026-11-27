INSERT INTO tenants(id,name) VALUES ('00000000-0000-0000-0000-000000000001','T');
INSERT INTO outlets(id,tenant_id,code,name,country_code,timezone,currency_code,currency_symbol,prices_include_tax,fiscal_year_start_month)
 VALUES ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000001','O1','Out','IN','Asia/Kolkata','INR','Rs',false,4),
        ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000001','O2','Out2','IN','Asia/Kolkata','INR','Rs',false,4);
INSERT INTO users(id,tenant_id,email,password_hash,full_name,role) VALUES ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','o@x.io','x','Owner','OWNER');
INSERT INTO dining_areas(id,tenant_id,outlet_id,name) VALUES ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','Main');
INSERT INTO dining_tables(id,tenant_id,outlet_id,area_id,name) VALUES ('00000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000d1','T1');
INSERT INTO devices(id,tenant_id,outlet_id,name,series_code,status,device_key_hash,registered_at,created_by)
 VALUES ('00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','Counter 1','A','ACTIVE','h1',now(),'00000000-0000-0000-0000-0000000000f1');
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by)
 VALUES ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',1,'2026-11-23','TAKEAWAY','00000000-0000-0000-0000-0000000000f1');
INSERT INTO bills(id,tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by)
 VALUES ('00000000-0000-0000-0000-000000000b11','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1','B','2026-27',1,'B-2026-27-000001',false,'INR',100,0,100,100,'00000000-0000-0000-0000-0000000000f1');
