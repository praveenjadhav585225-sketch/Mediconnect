-- 008_triggers.sql : audit logging and rules that must hold even for ad-hoc SQL

-- Generic row audit. TG_ARGV[0] = name of the primary-key column. Passwords are never copied into the log.
-- The seed script sets mediconnect.skip_audit = on so synthetic loading does not flood the log.
CREATE OR REPLACE FUNCTION audit_row_change() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_old jsonb; v_new jsonb; v_actor uuid;
BEGIN
  IF current_setting('mediconnect.skip_audit', true) = 'on' THEN RETURN NULL; END IF;
  IF TG_OP IN ('UPDATE','DELETE') THEN v_old := to_jsonb(OLD) - 'password_hash'; END IF;
  IF TG_OP IN ('INSERT','UPDATE') THEN v_new := to_jsonb(NEW) - 'password_hash'; END IF;
  IF TG_OP = 'UPDATE' AND v_old = v_new THEN RETURN NULL; END IF;
  v_actor := NULLIF(current_setting('mediconnect.actor_user_id', true), '')::uuid;
  IF v_actor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users WHERE user_id = v_actor) THEN v_actor := NULL; END IF;
  INSERT INTO audit_log (actor_user_id, table_name, record_id, action, old_data, new_data)
  VALUES (v_actor, TG_TABLE_NAME, COALESCE(v_new, v_old) ->> TG_ARGV[0], TG_OP, v_old, v_new);
  RETURN NULL;
END $$;

CREATE TRIGGER trg_audit_appointments  AFTER INSERT OR UPDATE OR DELETE ON appointments
  FOR EACH ROW EXECUTE FUNCTION audit_row_change('appointment_id');
CREATE TRIGGER trg_audit_doctors       AFTER INSERT OR DELETE OR UPDATE OF verification_status ON doctors
  FOR EACH ROW EXECUTE FUNCTION audit_row_change('doctor_id');
CREATE TRIGGER trg_audit_users         AFTER INSERT OR DELETE OR UPDATE OF is_active, role ON users
  FOR EACH ROW EXECUTE FUNCTION audit_row_change('user_id');
CREATE TRIGGER trg_audit_cases         AFTER INSERT OR DELETE OR UPDATE OF status, consent_for_matching ON medical_cases
  FOR EACH ROW EXECUTE FUNCTION audit_row_change('case_id');
CREATE TRIGGER trg_audit_consultations AFTER INSERT OR UPDATE OR DELETE ON consultations
  FOR EACH ROW EXECUTE FUNCTION audit_row_change('consultation_id');
CREATE TRIGGER trg_audit_reviews       AFTER INSERT ON reviews
  FOR EACH ROW EXECUTE FUNCTION audit_row_change('review_id');

-- Keeps time_slots.status in step with appointments: active booking = BOOKED, cancelled/deleted = AVAILABLE.
CREATE OR REPLACE FUNCTION sync_slot_status() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'CANCELLED' THEN UPDATE time_slots SET status = 'BOOKED' WHERE slot_id = NEW.slot_id; END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.slot_id <> NEW.slot_id THEN
      IF OLD.status <> 'CANCELLED' THEN UPDATE time_slots SET status = 'AVAILABLE' WHERE slot_id = OLD.slot_id; END IF;
      IF NEW.status <> 'CANCELLED' THEN UPDATE time_slots SET status = 'BOOKED'    WHERE slot_id = NEW.slot_id; END IF;
    ELSIF OLD.status <> 'CANCELLED' AND NEW.status = 'CANCELLED' THEN
      UPDATE time_slots SET status = 'AVAILABLE' WHERE slot_id = NEW.slot_id;
    ELSIF OLD.status = 'CANCELLED' AND NEW.status <> 'CANCELLED' THEN
      UPDATE time_slots SET status = 'BOOKED' WHERE slot_id = NEW.slot_id;
    END IF;
  ELSE  -- DELETE
    IF OLD.status <> 'CANCELLED' THEN UPDATE time_slots SET status = 'AVAILABLE' WHERE slot_id = OLD.slot_id; END IF;
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_appt_sync_slot AFTER INSERT OR DELETE OR UPDATE OF status, slot_id ON appointments
  FOR EACH ROW EXECUTE FUNCTION sync_slot_status();

-- Legal status changes only. COMPLETED / CANCELLED / NO_SHOW are final (a completed visit can never be cancelled).
CREATE OR REPLACE FUNCTION enforce_appt_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('BOOKED','CONFIRMED','IN_PROGRESS','COMPLETED','CANCELLED','NO_SHOW') THEN
    RETURN NEW;                                   -- unknown value: the CHECK constraint reports it
  END IF;
  IF NOT ((OLD.status = 'BOOKED'      AND NEW.status IN ('CONFIRMED','IN_PROGRESS','CANCELLED','NO_SHOW'))
       OR (OLD.status = 'CONFIRMED'   AND NEW.status IN ('IN_PROGRESS','CANCELLED','NO_SHOW'))
       OR (OLD.status = 'IN_PROGRESS' AND NEW.status = 'COMPLETED')) THEN
    RAISE EXCEPTION 'Illegal appointment status change: % -> %', OLD.status, NEW.status USING ERRCODE = 'MC004';
  END IF;
  IF NEW.status = 'CONFIRMED' AND NEW.confirmed_at IS NULL THEN NEW.confirmed_at := now(); END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_appt_transition BEFORE UPDATE OF status ON appointments
  FOR EACH ROW EXECUTE FUNCTION enforce_appt_transition();

-- Even a direct INSERT cannot book an unverified doctor.
CREATE OR REPLACE FUNCTION enforce_doctor_verified() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status <> 'CANCELLED'
     AND (SELECT verification_status FROM doctors WHERE doctor_id = NEW.doctor_id) IS DISTINCT FROM 'VERIFIED' THEN
    RAISE EXCEPTION 'Doctor is not verified' USING ERRCODE = 'MC002';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_appt_doctor_verified BEFORE INSERT ON appointments
  FOR EACH ROW EXECUTE FUNCTION enforce_doctor_verified();

-- A review needs a COMPLETED consultation (a missing consultation is left to the foreign key to report).
CREATE OR REPLACE FUNCTION enforce_review_after_completion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM consultations WHERE consultation_id = NEW.consultation_id;
  IF FOUND AND v_status <> 'COMPLETED' THEN
    RAISE EXCEPTION 'Reviews are only allowed after the consultation is completed' USING ERRCODE = 'MC009';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_review_completed BEFORE INSERT ON reviews
  FOR EACH ROW EXECUTE FUNCTION enforce_review_after_completion();

CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_cases_touch BEFORE UPDATE ON medical_cases
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
