-- test_constraints.sql : 38 integrity tests. Every test runs in a sub-transaction that is rolled back,
-- so the database is left unchanged. "success" means the statement was ACCEPTED (then rolled back).
\set ON_ERROR_STOP off
\pset pager off
CREATE TEMP TABLE test_results (n serial, test_id text, description text, expected text, got text, result text);

CREATE FUNCTION pg_temp.expect(p_id text, p_desc text, p_stmt text, p_expected text) RETURNS void AS $f$
DECLARE got text;
BEGIN
  BEGIN
    EXECUTE p_stmt;
    RAISE EXCEPTION 'ok' USING ERRCODE = 'XTEST';      -- statement succeeded: undo it
  EXCEPTION WHEN OTHERS THEN
    got := CASE WHEN SQLSTATE = 'XTEST' THEN 'success' ELSE SQLSTATE END;
  END;
  INSERT INTO test_results(test_id, description, expected, got, result)
  VALUES (p_id, p_desc, p_expected, got, CASE WHEN position(got IN p_expected) > 0 THEN 'PASS' ELSE 'FAIL' END);
END $f$ LANGUAGE plpgsql;

CREATE TEMP TABLE fx AS SELECT
  (SELECT user_id    FROM users    WHERE email = 'patient01@mediconnect.test') AS u_pat,
  (SELECT patient_id FROM patients p JOIN users u USING (user_id) WHERE u.email = 'patient01@mediconnect.test') AS pat1,
  (SELECT patient_id FROM patients p JOIN users u USING (user_id) WHERE u.email = 'patient02@mediconnect.test') AS pat2,
  (SELECT doctor_id  FROM doctors  WHERE license_number = 'KMC-2010-10001') AS doc1,
  (SELECT doctor_id  FROM doctors  WHERE license_number = 'KMC-2012-10003') AS doc3,
  (SELECT specialization_id FROM specializations WHERE name = 'Cardiology') AS spec_c,
  (SELECT hash FROM (SELECT password_hash AS hash FROM users LIMIT 1) h) AS good_hash,
  -- an appointment that is still active and in the future, plus its slot
  (SELECT a.appointment_id FROM appointments a JOIN time_slots s USING (slot_id) WHERE a.status='BOOKED' AND s.start_ts > now() ORDER BY s.start_ts LIMIT 1) AS appt_future,
  (SELECT a.slot_id        FROM appointments a JOIN time_slots s USING (slot_id) WHERE a.status='BOOKED' AND s.start_ts > now() ORDER BY s.start_ts LIMIT 1) AS slot_booked,
  (SELECT consultation_id FROM consultations LIMIT 1) AS consult1,
  (SELECT c.consultation_id FROM consultations c LEFT JOIN reviews r USING (consultation_id) WHERE r.review_id IS NULL LIMIT 1) AS consult_no_review,
  (SELECT c.case_id FROM medical_cases c JOIN patients p USING (patient_id) JOIN users u USING (user_id) WHERE u.email='patient01@mediconnect.test' AND c.status='SUBMITTED') AS case_a,
  (SELECT case_id FROM medical_cases WHERE status='RESOLVED'  ORDER BY created_at LIMIT 1) AS case_b;

-- ---------- users / patients / doctors
SELECT pg_temp.expect('T01','Duplicate email rejected (UNIQUE)',
  $$INSERT INTO users(email,password_hash,role) VALUES ('patient01@mediconnect.test', repeat('x',60), 'PATIENT')$$, '23505');
SELECT pg_temp.expect('T02','Invalid role rejected (CHECK)',
  $$INSERT INTO users(email,password_hash,role) VALUES ('a@b.test', repeat('x',60), 'HACKER')$$, '23514');
SELECT pg_temp.expect('T03','Upper-case email rejected (CHECK)',
  $$INSERT INTO users(email,password_hash,role) VALUES ('UPPER@b.test', repeat('x',60), 'PATIENT')$$, '23514');
SELECT pg_temp.expect('T04','Malformed email rejected (CHECK)',
  $$INSERT INTO users(email,password_hash,role) VALUES ('not-an-email', repeat('x',60), 'PATIENT')$$, '23514');
SELECT pg_temp.expect('T05','Plain-text-length password rejected (CHECK)',
  $$INSERT INTO users(email,password_hash,role) VALUES ('c@d.test', 'password123', 'PATIENT')$$, '23514');
SELECT pg_temp.expect('T06','Patient without a user rejected (FK)',
  $$INSERT INTO patients(user_id,full_name,date_of_birth) VALUES (gen_random_uuid(),'Test Person','1990-01-01')$$, '23503');
SELECT pg_temp.expect('T07','Future date of birth rejected (CHECK)',
  format($$UPDATE patients SET date_of_birth = current_date + 5 WHERE patient_id=%L$$, (SELECT pat1 FROM fx)), '23514');
SELECT pg_temp.expect('T08','Invalid phone number rejected (CHECK)',
  format($$UPDATE patients SET phone='12-ab' WHERE patient_id=%L$$, (SELECT pat1 FROM fx)), '23514');
SELECT pg_temp.expect('T09','Duplicate licence number rejected (UNIQUE)',
  format($$UPDATE doctors SET license_number='KMC-2010-10001' WHERE doctor_id=%L$$, (SELECT doc3 FROM fx)), '23505');
SELECT pg_temp.expect('T10','Negative consultation fee rejected (CHECK)',
  format($$UPDATE doctors SET consultation_fee=-5 WHERE doctor_id=%L$$, (SELECT doc1 FROM fx)), '23514');
SELECT pg_temp.expect('T11','Unknown specialization rejected (FK)',
  format($$UPDATE doctors SET specialization_id=9999 WHERE doctor_id=%L$$, (SELECT doc1 FROM fx)), '23503');

-- ---------- availability and slots
SELECT pg_temp.expect('T12','Availability end <= start rejected (CHECK)',
  format($$INSERT INTO availability_rules(doctor_id,day_of_week,start_time,end_time) VALUES (%L,3,'11:00','10:00')$$, (SELECT doc1 FROM fx)), '23514');
SELECT pg_temp.expect('T13','Overlapping availability rule rejected (EXCLUDE)',
  format($$INSERT INTO availability_rules(doctor_id,day_of_week,start_time,end_time) VALUES (%L,1,'12:00','14:00')$$, (SELECT doc1 FROM fx)), '23P01');
SELECT pg_temp.expect('T14','Adjacent, non-overlapping availability accepted',
  format($$INSERT INTO availability_rules(doctor_id,day_of_week,start_time,end_time) VALUES (%L,1,'13:00','14:00')$$, (SELECT doc1 FROM fx)), 'success');
SELECT pg_temp.expect('T15','Duplicate slot for same doctor and start rejected',
  format($$INSERT INTO time_slots(doctor_id,start_ts,end_ts) SELECT doctor_id,start_ts,end_ts FROM time_slots WHERE slot_id=%L$$, (SELECT slot_booked FROM fx)), '23505|23P01');
SELECT pg_temp.expect('T16','Partially overlapping slot rejected (EXCLUDE)',
  format($$INSERT INTO time_slots(doctor_id,start_ts,end_ts) SELECT doctor_id,start_ts + interval '5 minutes',end_ts + interval '5 minutes' FROM time_slots WHERE slot_id=%L$$, (SELECT slot_booked FROM fx)), '23P01');
SELECT pg_temp.expect('T17','Slot end before start rejected (CHECK)',
  format($$INSERT INTO time_slots(doctor_id,start_ts,end_ts) VALUES (%L, now() + interval '90 days', now() + interval '89 days')$$, (SELECT doc1 FROM fx)), '23514');

-- ---------- appointments
SELECT pg_temp.expect('T18','Double booking of a booked slot rejected (partial UNIQUE)',
  format($$INSERT INTO appointments(patient_id,doctor_id,slot_id) SELECT %L, doctor_id, slot_id FROM time_slots WHERE slot_id=%L$$, (SELECT pat2 FROM fx), (SELECT slot_booked FROM fx)), '23505');
SELECT pg_temp.expect('T19','Appointment with a slot of ANOTHER doctor rejected (composite FK)',
  format($$INSERT INTO appointments(patient_id,doctor_id,slot_id) SELECT %L, %L, slot_id FROM time_slots WHERE doctor_id=%L AND status='AVAILABLE' LIMIT 1$$, (SELECT pat2 FROM fx), (SELECT doc3 FROM fx), (SELECT doc1 FROM fx)), '23503');
SELECT pg_temp.expect('T20','Appointment linked to ANOTHER patient''s case rejected (composite FK)',
  format($$INSERT INTO appointments(patient_id,doctor_id,slot_id,case_id) SELECT %L, doctor_id, slot_id, %L FROM time_slots WHERE doctor_id=%L AND status='AVAILABLE' LIMIT 1$$,
         (SELECT pat2 FROM fx), (SELECT case_a FROM fx), (SELECT doc1 FROM fx)), '23503');
SELECT pg_temp.expect('T21','CANCELLED without cancelled_at rejected (CHECK)',
  format($$UPDATE appointments SET status='CANCELLED' WHERE appointment_id=%L$$, (SELECT appt_future FROM fx)), '23514');
SELECT pg_temp.expect('T22','Invalid appointment status rejected (CHECK)',
  format($$UPDATE appointments SET status='MAYBE' WHERE appointment_id=%L$$, (SELECT appt_future FROM fx)), '23514');
SELECT pg_temp.expect('T23','Cancel then REBOOK the same slot is allowed',
  format($t$DO $b$ BEGIN
     UPDATE appointments SET status='CANCELLED', cancelled_at=now() WHERE appointment_id=%L;
     INSERT INTO appointments(patient_id,doctor_id,slot_id) SELECT %L, doctor_id, slot_id FROM time_slots WHERE slot_id=%L;
   END $b$$t$, (SELECT appt_future FROM fx), (SELECT pat2 FROM fx), (SELECT slot_booked FROM fx)), 'success');

-- ---------- consultations / reviews
SELECT pg_temp.expect('T24','COMPLETED consultation without ended_at rejected (CHECK)',
  format($$INSERT INTO consultations(appointment_id,status,ended_at) VALUES (%L,'COMPLETED',NULL)$$, (SELECT appt_future FROM fx)), '23514');
SELECT pg_temp.expect('T25','Second consultation for the same appointment rejected (UNIQUE)',
  format($$INSERT INTO consultations(appointment_id) SELECT appointment_id FROM consultations WHERE consultation_id=%L$$, (SELECT consult1 FROM fx)), '23505');
SELECT pg_temp.expect('T26','Rating 6 rejected (CHECK)',
  format($$INSERT INTO reviews(consultation_id,rating) VALUES (%L,6)$$, (SELECT consult_no_review FROM fx)), '23514');
SELECT pg_temp.expect('T27','Valid rating 5 accepted',
  format($$INSERT INTO reviews(consultation_id,rating) VALUES (%L,5)$$, (SELECT consult_no_review FROM fx)), 'success');
SELECT pg_temp.expect('T28','Second review for same consultation rejected (UNIQUE)',
  format($$INSERT INTO reviews(consultation_id,rating) SELECT consultation_id,4 FROM reviews LIMIT 1$$), '23505');
SELECT pg_temp.expect('T29','Review for a missing consultation rejected (FK)',
  $$INSERT INTO reviews(consultation_id,rating) VALUES (gen_random_uuid(),4)$$, '23503');

-- ---------- cases, embeddings, match log
SELECT pg_temp.expect('T30','Invalid case severity rejected (CHECK)',
  format($$UPDATE medical_cases SET severity='EXTREME' WHERE case_id=%L$$, (SELECT case_a FROM fx)), '23514');
SELECT pg_temp.expect('T31','Duplicate Mongo detail id rejected (UNIQUE)',
  format($$UPDATE medical_cases SET mongo_detail_id=(SELECT mongo_detail_id FROM medical_cases WHERE case_id=%L) WHERE case_id=%L$$, (SELECT case_b FROM fx), (SELECT case_a FROM fx)), '23505');
SELECT pg_temp.expect('T32','Embedding with wrong dimension (3, not 384) rejected (vector type)',
  format($$INSERT INTO case_embeddings(case_id,embedding,text_hash) VALUES (%L,'[1,2,3]',repeat('a',64))$$, (SELECT case_a FROM fx)), '22000');
SELECT pg_temp.expect('T33','Embedding with malformed text hash rejected (CHECK)',
  format($$INSERT INTO case_embeddings(case_id,embedding,text_hash) VALUES (%L,array_fill(0.1::real, ARRAY[384])::vector,'short')$$, (SELECT case_a FROM fx)), '23514');
SELECT pg_temp.expect('T34','Embedding for a missing case rejected (FK)',
  $$INSERT INTO case_embeddings(case_id,embedding,text_hash) VALUES (gen_random_uuid(),array_fill(0.1::real, ARRAY[384])::vector,repeat('a',64))$$, '23503');
SELECT pg_temp.expect('T35','Valid 384-d embedding accepted',
  format($$INSERT INTO case_embeddings(case_id,embedding,text_hash) VALUES (%L,array_fill(0.1::real, ARRAY[384])::vector,repeat('a',64))$$, (SELECT case_a FROM fx)), 'success');
SELECT pg_temp.expect('T36','Match log: case matched with itself rejected (CHECK)',
  format($$INSERT INTO case_match_log(query_case_id,matched_case_id,doctor_id,similarity_score) VALUES (%L,%L,%L,0.5)$$, (SELECT case_a FROM fx), (SELECT case_a FROM fx), (SELECT doc1 FROM fx)), '23514');
SELECT pg_temp.expect('T37','Match log: similarity score 1.5 rejected (CHECK)',
  format($$INSERT INTO case_match_log(query_case_id,matched_case_id,doctor_id,similarity_score) VALUES (%L,%L,%L,1.5)$$, (SELECT case_a FROM fx), (SELECT case_b FROM fx), (SELECT doc1 FROM fx)), '23514');

-- ---------- cascade + privileges
SELECT pg_temp.expect('T38','Deleting a user cascades to the patient profile',
  $t$DO $b$ DECLARE uid uuid; BEGIN
     INSERT INTO users(email,password_hash,role) VALUES ('cascade@test.test', repeat('x',60), 'PATIENT') RETURNING user_id INTO uid;
     INSERT INTO patients(user_id,full_name,date_of_birth) VALUES (uid,'Cascade Test','1990-01-01');
     DELETE FROM users WHERE user_id = uid;
     IF EXISTS (SELECT 1 FROM patients WHERE user_id = uid) THEN RAISE EXCEPTION 'patient survived'; END IF;
   END $b$$t$, 'success');
SELECT pg_temp.expect('T39','App role CANNOT update the audit log (privilege)',
  $t$DO $b$ BEGIN SET LOCAL ROLE mediconnect_app; UPDATE audit_log SET action='LOGIN'; END $b$$t$, '42501');
SELECT pg_temp.expect('T40','App role CAN read and write normal tables',
  $t$DO $b$ BEGIN SET LOCAL ROLE mediconnect_app; PERFORM count(*) FROM users; UPDATE doctors SET bio = bio WHERE false; END $b$$t$, 'success');

\echo
\echo '=== CONSTRAINT / INTEGRITY TEST RESULTS ==='
SELECT test_id, description, expected, got, result FROM test_results ORDER BY n;
SELECT count(*) FILTER (WHERE result='PASS') AS passed, count(*) FILTER (WHERE result='FAIL') AS failed, count(*) AS total FROM test_results;
