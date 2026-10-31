-- 007_functions_procedures.sql : business rules inside the database (transactions + row locking)
-- Custom error codes (SQLSTATE) so the API can map them to HTTP responses:
--   MC001 slot not available      MC002 doctor not verified     MC003 slot in the past
--   MC004 illegal state change    MC005 record not found        MC006 account deactivated
--   MC007 not allowed             MC008 patient time clash      MC009 consultation not completed
--   MC010 case has no embedding yet

-- Records WHO is acting, for the current transaction only. The audit trigger reads it.
CREATE OR REPLACE FUNCTION set_actor(p_user uuid) RETURNS void
LANGUAGE sql AS $$ SELECT set_config('mediconnect.actor_user_id', coalesce(p_user::text, ''), true) $$;

-- Turns a doctor's weekly availability rules into concrete future slots. Idempotent: reruns add nothing.
CREATE OR REPLACE FUNCTION generate_slots(p_doctor_id uuid, p_from date DEFAULT current_date, p_days integer DEFAULT 14)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_status text; n integer;
BEGIN
  IF p_days < 1 OR p_days > 60 THEN
    RAISE EXCEPTION 'p_days must be between 1 and 60' USING ERRCODE = '22023';
  END IF;
  SELECT verification_status INTO v_status FROM doctors WHERE doctor_id = p_doctor_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Doctor not found' USING ERRCODE = 'MC005'; END IF;
  IF v_status <> 'VERIFIED' THEN RAISE EXCEPTION 'Only VERIFIED doctors can publish slots' USING ERRCODE = 'MC002'; END IF;

  INSERT INTO time_slots (doctor_id, start_ts, end_ts)
  SELECT r.doctor_id, ts, ts + make_interval(mins => r.slot_minutes)
  FROM availability_rules r
  CROSS JOIN generate_series(p_from::timestamp, (p_from + p_days - 1)::timestamp, interval '1 day') AS d(day)
  CROSS JOIN LATERAL generate_series(d.day + r.start_time,
                                     d.day + r.end_time - make_interval(mins => r.slot_minutes),
                                     make_interval(mins => r.slot_minutes)) AS ts
  WHERE r.doctor_id = p_doctor_id
    AND extract(dow FROM d.day) = r.day_of_week
    AND ts > now()
    AND NOT EXISTS (SELECT 1 FROM time_slots t
                    WHERE t.doctor_id = r.doctor_id
                      AND tstzrange(t.start_ts, t.end_ts) && tstzrange(ts, ts + make_interval(mins => r.slot_minutes)));
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

-- Books a slot. Lock order is ALWAYS patient row, then slot row, so concurrent calls cannot deadlock.
-- The slot's BOOKED status is set by trigger trg_appt_sync_slot, so ad-hoc SQL stays consistent too.
CREATE OR REPLACE FUNCTION book_appointment(p_patient_id uuid, p_slot_id uuid,
                                            p_case_id uuid DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_user uuid; v_active boolean; v_slot time_slots%ROWTYPE; v_doc_status text; v_id uuid;
BEGIN
  SELECT p.user_id, u.is_active INTO v_user, v_active
  FROM patients p JOIN users u USING (user_id)
  WHERE p.patient_id = p_patient_id FOR UPDATE OF p;           -- serialises one patient's bookings
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found' USING ERRCODE = 'MC005'; END IF;
  IF NOT v_active THEN RAISE EXCEPTION 'Account is deactivated' USING ERRCODE = 'MC006'; END IF;
  PERFORM set_actor(v_user);

  SELECT * INTO v_slot FROM time_slots WHERE slot_id = p_slot_id FOR UPDATE;   -- row lock on the slot
  IF NOT FOUND THEN RAISE EXCEPTION 'Slot not found' USING ERRCODE = 'MC005'; END IF;
  IF v_slot.status <> 'AVAILABLE' THEN RAISE EXCEPTION 'Slot is not available' USING ERRCODE = 'MC001'; END IF;
  IF v_slot.start_ts <= now() THEN RAISE EXCEPTION 'Slot is in the past' USING ERRCODE = 'MC003'; END IF;

  SELECT verification_status INTO v_doc_status FROM doctors WHERE doctor_id = v_slot.doctor_id;
  IF v_doc_status IS DISTINCT FROM 'VERIFIED' THEN
    RAISE EXCEPTION 'Doctor is not verified' USING ERRCODE = 'MC002';
  END IF;

  IF p_case_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM medical_cases WHERE case_id = p_case_id AND patient_id = p_patient_id) THEN
    RAISE EXCEPTION 'Case does not belong to this patient' USING ERRCODE = 'MC007';
  END IF;

  IF EXISTS (SELECT 1 FROM appointments a JOIN time_slots s USING (slot_id)
             WHERE a.patient_id = p_patient_id
               AND a.status IN ('BOOKED','CONFIRMED','IN_PROGRESS')
               AND tstzrange(s.start_ts, s.end_ts) && tstzrange(v_slot.start_ts, v_slot.end_ts)) THEN
    RAISE EXCEPTION 'Patient already has an appointment at this time' USING ERRCODE = 'MC008';
  END IF;

  INSERT INTO appointments (patient_id, doctor_id, slot_id, case_id, reason)
  VALUES (p_patient_id, v_slot.doctor_id, p_slot_id, p_case_id, left(p_reason, 1000))
  RETURNING appointment_id INTO v_id;
  RETURN v_id;
END $$;

-- Cancels an appointment (patient, doctor, or admin). The slot is released by trigger trg_appt_sync_slot.
CREATE OR REPLACE PROCEDURE cancel_appointment(p_appointment_id uuid, p_actor_user_id uuid, p_reason text DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE a appointments%ROWTYPE; v_role text; v_pat_user uuid; v_doc_user uuid;
BEGIN
  SELECT * INTO a FROM appointments WHERE appointment_id = p_appointment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found' USING ERRCODE = 'MC005'; END IF;
  SELECT role INTO v_role FROM users WHERE user_id = p_actor_user_id AND is_active;
  IF v_role IS NULL THEN RAISE EXCEPTION 'Unknown or inactive user' USING ERRCODE = 'MC007'; END IF;
  SELECT user_id INTO v_pat_user FROM patients WHERE patient_id = a.patient_id;
  SELECT user_id INTO v_doc_user FROM doctors  WHERE doctor_id  = a.doctor_id;
  IF NOT (v_role = 'ADMIN' OR p_actor_user_id IN (v_pat_user, v_doc_user)) THEN
    RAISE EXCEPTION 'Not allowed to cancel this appointment' USING ERRCODE = 'MC007';
  END IF;
  IF a.status NOT IN ('BOOKED','CONFIRMED') THEN
    RAISE EXCEPTION 'Only BOOKED or CONFIRMED appointments can be cancelled (current status: %)', a.status USING ERRCODE = 'MC004';
  END IF;
  PERFORM set_actor(p_actor_user_id);
  UPDATE appointments
     SET status = 'CANCELLED', cancelled_at = now(), cancel_reason = left(p_reason, 1000)
   WHERE appointment_id = p_appointment_id;
END $$;

-- Doctor starts a consultation for one of their own booked appointments.
CREATE OR REPLACE FUNCTION start_consultation(p_appointment_id uuid, p_doctor_user_id uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a appointments%ROWTYPE; v_doc_user uuid; v_id uuid := gen_random_uuid();
BEGIN
  SELECT * INTO a FROM appointments WHERE appointment_id = p_appointment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found' USING ERRCODE = 'MC005'; END IF;
  SELECT user_id INTO v_doc_user FROM doctors WHERE doctor_id = a.doctor_id;
  IF v_doc_user IS DISTINCT FROM p_doctor_user_id THEN
    RAISE EXCEPTION 'Only the appointment''s doctor can start it' USING ERRCODE = 'MC007';
  END IF;
  IF a.status NOT IN ('BOOKED','CONFIRMED') THEN
    RAISE EXCEPTION 'Cannot start a consultation from status %', a.status USING ERRCODE = 'MC004';
  END IF;
  PERFORM set_actor(p_doctor_user_id);
  UPDATE appointments SET status = 'IN_PROGRESS' WHERE appointment_id = p_appointment_id;
  INSERT INTO consultations (consultation_id, appointment_id, notes_doc_id) VALUES (v_id, p_appointment_id, v_id::text);
  RETURN v_id;
END $$;

CREATE OR REPLACE PROCEDURE complete_consultation(p_consultation_id uuid, p_doctor_user_id uuid, p_follow_up boolean DEFAULT false)
LANGUAGE plpgsql AS $$
DECLARE c consultations%ROWTYPE; v_doc_user uuid;
BEGIN
  SELECT * INTO c FROM consultations WHERE consultation_id = p_consultation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Consultation not found' USING ERRCODE = 'MC005'; END IF;
  SELECT d.user_id INTO v_doc_user FROM appointments a JOIN doctors d USING (doctor_id) WHERE a.appointment_id = c.appointment_id;
  IF v_doc_user IS DISTINCT FROM p_doctor_user_id THEN
    RAISE EXCEPTION 'Only the consultation''s doctor can complete it' USING ERRCODE = 'MC007';
  END IF;
  IF c.status <> 'STARTED' THEN RAISE EXCEPTION 'Consultation already completed' USING ERRCODE = 'MC004'; END IF;
  PERFORM set_actor(p_doctor_user_id);
  UPDATE consultations SET status = 'COMPLETED', ended_at = now(), follow_up_required = p_follow_up WHERE consultation_id = p_consultation_id;
  UPDATE appointments  SET status = 'COMPLETED' WHERE appointment_id = c.appointment_id;
END $$;

-- Semantic case-matching (informational only). Returns ONLY: matched case id, specialization, similarity.
-- No patient identity, title, email or phone ever leaves this function. Doctors may call it only for a case
-- attached to one of their own non-cancelled appointments. Every call is written to case_match_log.
CREATE OR REPLACE FUNCTION find_similar_cases(p_doctor_id uuid, p_case_id uuid, p_k integer DEFAULT 5,
                                              p_min_score real DEFAULT 0.5, p_same_specialization boolean DEFAULT false)
RETURNS TABLE (matched_case_id uuid, specialization text, similarity real)
LANGUAGE plpgsql AS $$
DECLARE v_spec integer;
BEGIN
  IF p_k < 1 OR p_k > 20 THEN RAISE EXCEPTION 'p_k must be between 1 and 20' USING ERRCODE = '22023'; END IF;
  IF NOT EXISTS (SELECT 1 FROM appointments a
                 WHERE a.case_id = p_case_id AND a.doctor_id = p_doctor_id AND a.status <> 'CANCELLED') THEN
    RAISE EXCEPTION 'Doctor has no appointment linked to this case' USING ERRCODE = 'MC007';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM case_embeddings WHERE case_id = p_case_id) THEN
    RAISE EXCEPTION 'Case has no embedding yet' USING ERRCODE = 'MC010';
  END IF;
  SELECT specialization_id INTO v_spec FROM medical_cases WHERE case_id = p_case_id;
  PERFORM set_config('hnsw.ef_search', '100', true);          -- better recall when the pool is filtered

  RETURN QUERY
  WITH q AS (SELECT embedding FROM case_embeddings WHERE case_id = p_case_id),
  ranked AS (
    SELECT c.case_id AS cid, s.name AS spec_name,
           GREATEST(0, 1 - (e.embedding <=> q.embedding))::real AS sim
    FROM q, case_embeddings e
    JOIN medical_cases c ON c.case_id = e.case_id
    LEFT JOIN specializations s ON s.specialization_id = c.specialization_id
    WHERE c.consent_for_matching AND c.status IN ('RESOLVED','CLOSED') AND c.case_id <> p_case_id
      AND (NOT p_same_specialization OR c.specialization_id = v_spec)
    ORDER BY e.embedding <=> q.embedding
    LIMIT p_k),
  kept AS (SELECT * FROM ranked WHERE ranked.sim >= p_min_score),
  logged AS (
    INSERT INTO case_match_log (query_case_id, matched_case_id, doctor_id, similarity_score)
    SELECT p_case_id, k.cid, p_doctor_id, LEAST(1, k.sim) FROM kept k RETURNING 1)
  SELECT k.cid, k.spec_name, k.sim FROM kept k ORDER BY k.sim DESC;
END $$;
