\echo '--- OK expected: pending device with a pairing code'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,pairing_code_hash,pairing_expires_at,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','C','PENDING','h',now()+interval '1 hour','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: series code 'B' is reserved for the server default series'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,pairing_code_hash,pairing_expires_at,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','B','PENDING','h',now()+interval '1 hour','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: series code must be upper-case'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,pairing_code_hash,pairing_expires_at,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','a1','PENDING','h',now()+interval '1 hour','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: series code max 3 characters'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,pairing_code_hash,pairing_expires_at,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','ABCD','PENDING','h',now()+interval '1 hour','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: series code must start with a letter'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,pairing_code_hash,pairing_expires_at,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','1A','PENDING','h',now()+interval '1 hour','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: duplicate series code in the same outlet'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,pairing_code_hash,pairing_expires_at,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','A','PENDING','h',now()+interval '1 hour','00000000-0000-0000-0000-0000000000f1');
\echo '--- OK expected: same series code in another outlet'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,pairing_code_hash,pairing_expires_at,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a2','X','A','PENDING','h',now()+interval '1 hour','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: ACTIVE device without a device key'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,registered_at,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','D','ACTIVE',now(),'00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: REVOKED device without revoked_by'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,revoked_at,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','E','REVOKED',now(),'00000000-0000-0000-0000-0000000000f1');
\echo '--- OK expected: REVOKED device with revoked_by'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,revoked_at,revoked_by,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','F','REVOKED',now(),'00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: PENDING device without a pairing code'
INSERT INTO devices(tenant_id,outlet_id,name,series_code,status,created_by) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','X','G','PENDING','00000000-0000-0000-0000-0000000000f1');
\echo '--- FAIL expected: reported local seq without fiscal year'
UPDATE devices SET last_reported_seq=5 WHERE id='00000000-0000-0000-0000-00000000dd01';
\echo '--- OK expected: reported local seq with fiscal year'
UPDATE devices SET last_reported_seq=5,last_reported_fiscal_year='2026-27',pending_count=3 WHERE id='00000000-0000-0000-0000-00000000dd01';
\echo '--- FAIL expected: negative pending count'
UPDATE devices SET pending_count=-1 WHERE id='00000000-0000-0000-0000-00000000dd01';
\echo '--- OK expected: sync command recorded'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0001',1,'BILL_GENERATE',1,'BILL',gen_random_uuid(),'{}','h','RECEIVED',now());
\echo '--- FAIL expected: same command_id pushed twice is a duplicate (idempotency)'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0001',2,'BILL_GENERATE',1,'BILL',gen_random_uuid(),'{}','h','RECEIVED',now());
\echo '--- FAIL expected: same device sequence number used twice'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0002',1,'BILL_GENERATE',1,'BILL',gen_random_uuid(),'{}','h','RECEIVED',now());
\echo '--- FAIL expected: APPLIED command without applied_at'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0003',3,'BILL_GENERATE',1,'BILL',gen_random_uuid(),'{}','h','APPLIED',now());
\echo '--- OK expected: APPLIED command with applied_at'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at,applied_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0004',4,'BILL_GENERATE',1,'BILL',gen_random_uuid(),'{}','h','APPLIED',now(),now());
\echo '--- FAIL expected: REJECTED command without an error code'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0005',5,'BILL_GENERATE',1,'BILL',gen_random_uuid(),'{}','h','REJECTED',now());
\echo '--- FAIL expected: WAITING_DEPENDENCY without the command it waits for'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0006',6,'BILL_GENERATE',1,'BILL',gen_random_uuid(),'{}','h','WAITING_DEPENDENCY',now());
\echo '--- OK expected: payment waits for its bill command'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,depends_on_command_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0007',7,'PAYMENT_ADD',1,'PAYMENT',gen_random_uuid(),'00000000-0000-0000-0000-0000000c0001','{}','h','WAITING_DEPENDENCY',now());
\echo '--- FAIL expected: command cannot depend on itself'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at,depends_on_command_id) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0008',8,'BILL_GENERATE',1,'BILL',gen_random_uuid(),'{}','h','WAITING_DEPENDENCY',now(),'00000000-0000-0000-0000-0000000c0008');
\echo '--- FAIL expected: unknown aggregate type'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c0009',9,'BILL_GENERATE',1,'WIDGET',gen_random_uuid(),'{}','h','RECEIVED',now());
\echo '--- FAIL expected: command type must be UPPER_SNAKE'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','00000000-0000-0000-0000-0000000c000a',10,'billGenerate',1,'BILL',gen_random_uuid(),'{}','h','RECEIVED',now());
\echo '--- OK expected: open gap 5..7'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',5,7,'OPEN');
\echo '--- FAIL expected: overlapping open gap 6..9 in the same series/year'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',6,9,'OPEN');
\echo '--- OK expected: adjacent open gap 8..9'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',8,9,'OPEN');
\echo '--- OK expected: same range in another fiscal year'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2027-28',5,7,'OPEN');
\echo '--- OK expected: same range in another series'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','C','2026-27',5,7,'OPEN');
\echo '--- FAIL expected: gap with to_seq < from_seq'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',12,11,'OPEN');
\echo '--- FAIL expected: EXPLAINED gap without an explanation'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',20,21,'EXPLAINED');
\echo '--- FAIL expected: EXPLAINED gap with a too-short explanation'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status,explanation,explained_by,explained_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',20,21,'EXPLAINED','x','00000000-0000-0000-0000-0000000000f1',now());
\echo '--- OK expected: EXPLAINED gap with explanation, user and time'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status,explanation,explained_by,explained_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',20,21,'EXPLAINED','Pad of bills torn and burnt in a kitchen fire','00000000-0000-0000-0000-0000000000f1',now());
\echo '--- FAIL expected: FILLED gap without filled_at'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',30,31,'FILLED');
\echo '--- OK expected: FILLED gap with filled_at'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status,filled_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',30,31,'FILLED',now());
\echo '--- OK expected: a new open gap may reuse the range of a FILLED gap (history is kept)'
INSERT INTO bill_number_gaps(tenant_id,outlet_id,device_id,series,fiscal_year,from_seq,to_seq,status) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','A','2026-27',30,31,'OPEN');
\echo '--- OK expected: CALC_MISMATCH with bill and CRITICAL'
INSERT INTO sync_conflicts(tenant_id,outlet_id,device_id,conflict_type,severity,bill_id,details) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','CALC_MISMATCH','CRITICAL','00000000-0000-0000-0000-000000000b11','{"clientTotal":"100.00","serverTotal":"100.01"}');
\echo '--- FAIL expected: CALC_MISMATCH must be CRITICAL'
INSERT INTO sync_conflicts(tenant_id,outlet_id,device_id,conflict_type,severity,bill_id) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','CALC_MISMATCH','WARN','00000000-0000-0000-0000-000000000b11');
\echo '--- FAIL expected: CALC_MISMATCH must name the bill'
INSERT INTO sync_conflicts(tenant_id,outlet_id,device_id,conflict_type,severity) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','CALC_MISMATCH','CRITICAL');
\echo '--- FAIL expected: TABLE_CONFLICT must name the order'
INSERT INTO sync_conflicts(tenant_id,outlet_id,device_id,conflict_type,severity) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','TABLE_CONFLICT','WARN');
\echo '--- OK expected: TABLE_CONFLICT with order'
INSERT INTO sync_conflicts(tenant_id,outlet_id,device_id,conflict_type,severity,order_id) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','TABLE_CONFLICT','WARN','00000000-0000-0000-0000-0000000000e1');
\echo '--- FAIL expected: NUMBER_GAP must name the device'
INSERT INTO sync_conflicts(tenant_id,outlet_id,conflict_type,severity) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','NUMBER_GAP','WARN');
\echo '--- FAIL expected: unknown conflict type'
INSERT INTO sync_conflicts(tenant_id,outlet_id,device_id,conflict_type,severity) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','SOMETHING','WARN');
\echo '--- FAIL expected: unknown severity'
INSERT INTO sync_conflicts(tenant_id,outlet_id,device_id,conflict_type,severity) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','CLOCK_SKEW','LOW');
\echo '--- FAIL expected: RESOLVED conflict without a note'
INSERT INTO sync_conflicts(tenant_id,outlet_id,device_id,conflict_type,severity,status,resolved_by,resolved_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','CLOCK_SKEW','INFO','RESOLVED','00000000-0000-0000-0000-0000000000f1',now());
\echo '--- OK expected: RESOLVED conflict with note, user and time'
INSERT INTO sync_conflicts(tenant_id,outlet_id,device_id,conflict_type,severity,status,resolved_by,resolved_at,resolution_note) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000dd01','CLOCK_SKEW','INFO','RESOLVED','00000000-0000-0000-0000-0000000000f1',now(),'Clock on the terminal was reset');
\echo '--- OK expected: offline order carries device, client time and device order number'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,origin_device_id,offline_created,client_created_at,device_order_no) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',10,'2026-11-24','TAKEAWAY','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now(),12);
\echo '--- FAIL expected: offline order without a device'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,offline_created) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',11,'2026-11-24','TAKEAWAY','00000000-0000-0000-0000-0000000000f1',true);
\echo '--- FAIL expected: offline order without a device order number'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,origin_device_id,offline_created,client_created_at) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',11,'2026-11-24','TAKEAWAY','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now());
\echo '--- FAIL expected: same device order number twice on one business date'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,origin_device_id,offline_created,client_created_at,device_order_no) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',13,'2026-11-24','TAKEAWAY','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now(),12);
\echo '--- OK expected: same device order number on another business date'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,origin_device_id,offline_created,client_created_at,device_order_no) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',14,'2026-11-25','TAKEAWAY','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now(),12);
\echo '--- FAIL expected: device order number must be positive'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,origin_device_id,offline_created,client_created_at,device_order_no) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',15,'2026-11-26','TAKEAWAY','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now(),0);
\echo '--- FAIL expected: needs_attention without a reason'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,origin_device_id,offline_created,client_created_at,device_order_no,needs_attention) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',16,'2026-11-24','TAKEAWAY','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now(),20,true);
\echo '--- OK expected: needs_attention with a reason'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,opened_by,origin_device_id,offline_created,client_created_at,device_order_no,needs_attention,attention_reason) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',17,'2026-11-24','TAKEAWAY','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now(),21,true,'Second offline order on table T1');
\echo '--- OK expected: the database allows two OPEN orders on one table (the later one is flagged, never dropped)'
INSERT INTO orders(id,tenant_id,outlet_id,order_no,business_date,order_type,table_id,opened_by) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',30,'2026-11-27','DINE_IN','00000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-0000000000f1'),(gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',31,'2026-11-27','DINE_IN','00000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-0000000000f1');
\echo '--- OK expected: offline bill in the device series'
INSERT INTO bills(id,tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,origin_device_id,offline_created,client_created_at) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1','A','2026-27',1,'A-2026-27-000001',false,'INR',50,0,50,50,'00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now());
\echo '--- FAIL expected: offline bill without client_created_at'
INSERT INTO bills(id,tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,origin_device_id,offline_created) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1','A','2026-27',2,'A-2026-27-000002',false,'INR',50,0,50,50,'00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true);
\echo '--- FAIL expected: duplicate sequence in the same series/year (already-synced bill pushed again)'
INSERT INTO bills(id,tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,origin_device_id,offline_created,client_created_at) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1','A','2026-27',1,'A-dup',false,'INR',50,0,50,50,'00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now());
\echo '--- FAIL expected: duplicate bill number'
INSERT INTO bills(id,tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1','A','2026-27',3,'A-2026-27-000001',false,'INR',50,0,50,50,'00000000-0000-0000-0000-0000000000f1');
\echo '--- OK expected: another sequence in the device series'
INSERT INTO bills(id,tenant_id,outlet_id,order_id,series,fiscal_year,bill_seq,bill_number,prices_include_tax,currency_code,subtotal,tax_total,total_before_round_off,grand_total,generated_by,origin_device_id,offline_created,client_created_at) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1','A','2026-27',3,'A-2026-27-000003',false,'INR',50,0,50,50,'00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now());
\echo '--- OK expected: offline payment with device'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,origin_device_id,offline_created,client_created_at) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000b11','CASH',50,'SUCCESS','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now());
\echo '--- FAIL expected: offline payment without a device'
INSERT INTO payments(id,tenant_id,outlet_id,bill_id,method,amount,status,created_by,offline_created) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000b11','CASH',50,'SUCCESS','00000000-0000-0000-0000-0000000000f1',true);
\echo '--- OK expected: offline KOT with device KOT number'
INSERT INTO kots(id,tenant_id,outlet_id,order_id,kot_no,business_date,created_by,origin_device_id,offline_created,client_created_at,device_kot_no) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1',50,'2026-11-23','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now(),7);
\echo '--- FAIL expected: offline KOT without a device KOT number'
INSERT INTO kots(id,tenant_id,outlet_id,order_id,kot_no,business_date,created_by,origin_device_id,offline_created,client_created_at) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1',51,'2026-11-23','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now());
\echo '--- FAIL expected: same device KOT number twice on one date'
INSERT INTO kots(id,tenant_id,outlet_id,order_id,kot_no,business_date,created_by,origin_device_id,offline_created,client_created_at,device_kot_no) VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1',52,'2026-11-23','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000dd01',true,now(),7);
\echo '--- OK expected: outlet defaults: offline enabled, 72 hours'
SELECT offline_enabled, offline_max_hours FROM outlets WHERE id='00000000-0000-0000-0000-0000000000a1';
\echo '--- FAIL expected: offline_max_hours = 0'
UPDATE outlets SET offline_max_hours=0 WHERE id='00000000-0000-0000-0000-0000000000a1';
\echo '--- FAIL expected: offline_max_hours = 721'
UPDATE outlets SET offline_max_hours=721 WHERE id='00000000-0000-0000-0000-0000000000a1';
\echo '--- OK expected: offline_max_hours = 720'
UPDATE outlets SET offline_max_hours=720 WHERE id='00000000-0000-0000-0000-0000000000a1';
\echo '--- FAIL expected: FK: sync command for an unknown device'
INSERT INTO sync_commands(tenant_id,outlet_id,device_id,command_id,device_seq,command_type,schema_version,aggregate_type,aggregate_id,payload,payload_hash,status,client_created_at) VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000ee99','00000000-0000-0000-0000-0000000cffff',99,'BILL_GENERATE',1,'BILL',gen_random_uuid(),'{}','h','RECEIVED',now());
