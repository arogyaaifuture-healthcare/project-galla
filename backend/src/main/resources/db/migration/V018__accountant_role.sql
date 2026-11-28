-- Plan Section 30.7 gives the Accountant read-only report access; the schema had no such role.
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('OWNER','MANAGER','CASHIER','CAPTAIN','KITCHEN','RIDER','INVENTORY','ACCOUNTANT'));
