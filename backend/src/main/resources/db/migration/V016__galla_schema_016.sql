-- V016 — cross-stream links that could not be declared while V012–V015 were written independently
-- Only one real soft reference remained: cashier_shifts.device_id (V013) -> devices (V012).
-- The remaining uuid columns without a foreign key are polymorphic by design and stay that way:
--   audit_logs.entity ids, print_jobs.ref_id, stock_movements.ref_id (+ ref_type), recipes.target_id (+ target kind),
--   sync_commands.aggregate_id / command_id / depends_on_command_id, sync_conflicts.command_id (client-generated ids),
--   stock_adjustments.movement_id (written in the same transaction as the movement), idempotency_keys.user_id, *.family_id (token families).
ALTER TABLE cashier_shifts
  ADD CONSTRAINT cashier_shifts_device_id_fkey FOREIGN KEY (device_id) REFERENCES devices(id);

CREATE FUNCTION fn_shift_device_same_outlet() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d_outlet uuid;
BEGIN
  IF NEW.device_id IS NOT NULL THEN
    SELECT outlet_id INTO d_outlet FROM devices WHERE id = NEW.device_id;
    IF d_outlet <> NEW.outlet_id THEN
      RAISE EXCEPTION 'SHIFT_DEVICE_OTHER_OUTLET' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_shift_device_same_outlet BEFORE INSERT OR UPDATE OF device_id, outlet_id ON cashier_shifts
  FOR EACH ROW EXECUTE FUNCTION fn_shift_device_same_outlet();
