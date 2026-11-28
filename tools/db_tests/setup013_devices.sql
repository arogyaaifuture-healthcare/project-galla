-- only for the full-chain run (V016 turns cashier_shifts.device_id into a real foreign key)
INSERT INTO devices(id,tenant_id,outlet_id,name,series_code,status,pairing_code_hash,pairing_expires_at,created_by)
SELECT d.id,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1',d.name,d.code,'PENDING','h',now()+interval '1 day',(SELECT id FROM users ORDER BY id LIMIT 1)
FROM (VALUES ('00000000-0000-0000-0000-00000000dd01'::uuid,'D1','A'),('00000000-0000-0000-0000-00000000dd02'::uuid,'D2','C')) d(id,name,code);
