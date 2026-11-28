ALTER TABLE outlets ADD COLUMN cashier_discount_limit_percent numeric(5,2) NOT NULL DEFAULT 0
  CHECK (cashier_discount_limit_percent BETWEEN 0 AND 100);
