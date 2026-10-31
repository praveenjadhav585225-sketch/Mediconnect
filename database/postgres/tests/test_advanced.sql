-- test_advanced.sql : Day 3 tests for functions, procedures, triggers, audit, views and similarity search.
-- Each test runs in a sub-transaction that is rolled back, so the data is left unchanged.
\pset pager off
DROP TABLE IF EXISTS pg_temp.test_results;
DROP TABLE IF EXISTS pg_temp.fx;
DROP FUNCTION IF EXISTS pg_temp.expect(text,text,text,text);
CREATE TEMP TABLE test_results (n serial, test_id text, description text, expected text, got text, result text);

CREATE FUNCTION pg_temp.expect(p_id text, p_desc text, p_stmt text, p_expected text) RETURNS void AS $f$
DECLARE got text;
BEGIN
  BEGIN
    EXECUTE p_stmt;
    RAISE EXCEPTION 'ok' USING ERRCODE = 'XTEST';
  EXCEPTION WHEN OTHERS THEN
    got := CASE WHEN SQLSTATE = 'XTEST' THEN 'success' ELSE SQLSTATE END;
  END;
  INSERT INTO test_results(test_id, description, expected, got, result)
  VALUES (p_id, p_desc, p_expected, got, CASE WHEN position(got IN p_expected) > 0 THEN 'PASS' ELSE 'FAIL' END);
END $f$ LANGUAGE plpgsql;

-- Fixtures: patients 21/22 have no future appointments; slots are distinct, future and AVAILABLE.
CREATE TEMP TABLE fx AS
WITH pa AS (SELECT p.patient_id, u.user_id FROM patients p JOIN users u USING (user_id) WHERE u.email='patient21@mediconnect.test'),
     pb AS (SELECT p.patient_id, u.user_id FROM patients p JOIN users u USING (user_id) WHERE u.email='patient22@mediconnect.test'),
     pi AS (SELECT p.patient_id, u.user_id FROM patients p JOIN users u USING (user_id) WHERE u.email='patient30@mediconnect.test'),
     pair AS (SELECT t1.slot_id AS s1, t2.slot_id AS s2 FROM time_slots t1 JOIN time_slots t2
              ON t1.start_ts = t2.start_ts AND t1.doctor_id < t2.doctor_id
              WHERE t1.status='AVAILABLE' AND t2.status='AVAILABLE' AND t1.start_ts > now() + interval '2 days'
              ORDER BY t1.start_ts LIMIT 1),
     s3 AS (SELECT slot_id, doctor_id FROM time_slots WHERE status='AVAILABLE' AND start_ts > now() + interval '10 days'
            AND doctor_id = (SELECT doctor_id FROM doctors WHERE license_number='KMC-2012-10003') ORDER BY start_ts LIMIT 1)
SELECT (SELECT patient_id FROM pa) pat_a, (SELECT user_id FROM pa) usr_a,
       (SELECT patient_id FROM pb) pat_b, (SELECT user_id FROM pb) usr_b,
       (SELECT patient_id FROM pi) pat_inactive,
       (SELECT user_id FROM users WHERE role='ADMIN' LIMIT 1) admin_user,
       (SELECT s1 FROM pair) slot1, (SELECT s2 FROM pair) slot2,
       (SELECT slot_id FROM s3) slot3, (SELECT d.user_id FROM doctors d WHERE d.doctor_id=(SELECT doctor_id FROM s3)) slot3_doc_user,
       (SELECT doctor_id FROM doctors WHERE verification_status='PENDING') doc_pending,
       (SELECT doctor_id FROM doctors WHERE license_number='KMC-2010-10001') doc_cardio,
       (SELECT slot_id FROM time_slots WHERE status='AVAILABLE' AND start_ts < now() - interval '1 day' LIMIT 1) past_slot,
       (SELECT appointment_id FROM appointments WHERE status='COMPLETED' LIMIT 1) completed_appt,
       (SELECT c.case_id FROM medical_cases c JOIN specializations s USING (specialization_id) WHERE c.status='SUBMITTED' AND s.name='Cardiology') cardio_case,
       (SELECT a.doctor_id FROM appointments a JOIN medical_cases c USING (case_id) JOIN specializations s USING (specialization_id) WHERE c.status='SUBMITTED' AND s.name='Cardiology') cardio_doc,
       (SELECT doctor_id FROM doctors WHERE license_number='KMC-2013-10004') other_doc;

-- ---------------- generate_slots
SELECT pg_temp.expect('A01','generate_slots adds slots for a verified doctor',
  format($t$DO $b$ BEGIN IF generate_slots(%L, current_date + 20, 7) <= 0 THEN RAISE EXCEPTION 'no slots'; END IF; END $b$$t$, (SELECT doc_cardio FROM fx)), 'success');
SELECT pg_temp.expect('A02','generate_slots is idempotent (second run adds 0)',
  format($t$DO $b$ DECLARE n1 int; n2 int; BEGIN n1 := generate_slots(%L, current_date + 20, 7); n2 := generate_slots(%L, current_date + 20, 7);
     IF n1 <= 0 OR n2 <> 0 THEN RAISE EXCEPTION 'n1=%% n2=%%', n1, n2; END IF; END $b$$t$, (SELECT doc_cardio FROM fx), (SELECT doc_cardio FROM fx)), 'success');
SELECT pg_temp.expect('A03','generate_slots refuses an unverified doctor',
  format($$SELECT generate_slots(%L)$$, (SELECT doc_pending FROM fx)), 'MC002');
SELECT pg_temp.expect('A04','generate_slots refuses 100 days',
  format($$SELECT generate_slots(%L, current_date, 100)$$, (SELECT doc_cardio FROM fx)), '22023');

-- ---------------- book_appointment
SELECT pg_temp.expect('A05','book_appointment succeeds, slot becomes BOOKED (trigger) and the booking is audited',
  format($t$DO $b$ DECLARE v uuid; BEGIN v := book_appointment(%L, %L, NULL, 'test');
     IF (SELECT status FROM time_slots WHERE slot_id=%L) <> 'BOOKED' THEN RAISE EXCEPTION 'slot not booked'; END IF;
     IF NOT EXISTS (SELECT 1 FROM audit_log WHERE table_name='appointments' AND record_id=v::text AND action='INSERT' AND actor_user_id=%L) THEN RAISE EXCEPTION 'no audit row'; END IF;
   END $b$$t$, (SELECT pat_a FROM fx), (SELECT slot3 FROM fx), (SELECT slot3 FROM fx), (SELECT usr_a FROM fx)), 'success');
SELECT pg_temp.expect('A06','Booking an already booked slot is rejected',
  format($$SELECT book_appointment(%L,%L); SELECT book_appointment(%L,%L)$$, (SELECT pat_a FROM fx),(SELECT slot3 FROM fx),(SELECT pat_b FROM fx),(SELECT slot3 FROM fx)), 'MC001');
SELECT pg_temp.expect('A07','Unverified doctors cannot receive bookings (function)',
  format($t$DO $b$ DECLARE sid uuid; BEGIN INSERT INTO time_slots(doctor_id,start_ts,end_ts) VALUES (%L, now()+interval '5 days', now()+interval '5 days 30 minutes') RETURNING slot_id INTO sid;
     PERFORM book_appointment(%L, sid); END $b$$t$, (SELECT doc_pending FROM fx), (SELECT pat_a FROM fx)), 'MC002');
SELECT pg_temp.expect('A08','Unverified doctors cannot receive bookings (direct INSERT, trigger)',
  format($t$DO $b$ DECLARE sid uuid; BEGIN INSERT INTO time_slots(doctor_id,start_ts,end_ts) VALUES (%L, now()+interval '5 days', now()+interval '5 days 30 minutes') RETURNING slot_id INTO sid;
     INSERT INTO appointments(patient_id,doctor_id,slot_id) VALUES (%L,%L,sid); END $b$$t$, (SELECT doc_pending FROM fx), (SELECT pat_a FROM fx), (SELECT doc_pending FROM fx)), 'MC002');
SELECT pg_temp.expect('A09','Booking a slot in the past is rejected',
  format($$SELECT book_appointment(%L,%L)$$, (SELECT pat_a FROM fx),(SELECT past_slot FROM fx)), 'MC003');
SELECT pg_temp.expect('A10','A patient cannot hold two appointments at the same time',
  format($$SELECT book_appointment(%L,%L); SELECT book_appointment(%L,%L)$$, (SELECT pat_a FROM fx),(SELECT slot1 FROM fx),(SELECT pat_a FROM fx),(SELECT slot2 FROM fx)), 'MC008');
SELECT pg_temp.expect('A11','A deactivated account cannot book',
  format($$SELECT book_appointment(%L,%L)$$, (SELECT pat_inactive FROM fx),(SELECT slot3 FROM fx)), 'MC006');
SELECT pg_temp.expect('A12','A case of another patient cannot be attached',
  format($$SELECT book_appointment(%L,%L,%L)$$, (SELECT pat_b FROM fx),(SELECT slot3 FROM fx),(SELECT cardio_case FROM fx)), 'MC007');

-- ---------------- cancel_appointment
SELECT pg_temp.expect('A13','Owner cancels: status CANCELLED and the slot is released',
  format($t$DO $b$ DECLARE v uuid; BEGIN v := book_appointment(%L,%L); CALL cancel_appointment(v, %L, 'plans changed');
     IF (SELECT status FROM appointments WHERE appointment_id=v) <> 'CANCELLED' THEN RAISE EXCEPTION 'not cancelled'; END IF;
     IF (SELECT status FROM time_slots WHERE slot_id=%L) <> 'AVAILABLE' THEN RAISE EXCEPTION 'slot not released'; END IF; END $b$$t$,
  (SELECT pat_a FROM fx),(SELECT slot3 FROM fx),(SELECT usr_a FROM fx),(SELECT slot3 FROM fx)), 'success');
SELECT pg_temp.expect('A14','Another patient cannot cancel it',
  format($t$DO $b$ DECLARE v uuid; BEGIN v := book_appointment(%L,%L); CALL cancel_appointment(v, %L); END $b$$t$,
  (SELECT pat_a FROM fx),(SELECT slot3 FROM fx),(SELECT usr_b FROM fx)), 'MC007');
SELECT pg_temp.expect('A15','Admin can cancel any appointment',
  format($t$DO $b$ DECLARE v uuid; BEGIN v := book_appointment(%L,%L); CALL cancel_appointment(v, %L, 'admin action'); END $b$$t$,
  (SELECT pat_a FROM fx),(SELECT slot3 FROM fx),(SELECT admin_user FROM fx)), 'success');
SELECT pg_temp.expect('A16','Completed appointments cannot be cancelled (procedure)',
  format($$CALL cancel_appointment(%L, %L)$$, (SELECT completed_appt FROM fx),(SELECT admin_user FROM fx)), 'MC004');
SELECT pg_temp.expect('A17','Completed appointments cannot be cancelled even by direct UPDATE (trigger)',
  format($$UPDATE appointments SET status='CANCELLED', cancelled_at=now() WHERE appointment_id=%L$$, (SELECT completed_appt FROM fx)), 'MC004');
SELECT pg_temp.expect('A18','Cancelling twice is rejected',
  format($t$DO $b$ DECLARE v uuid; BEGIN v := book_appointment(%L,%L); CALL cancel_appointment(v, %L); CALL cancel_appointment(v, %L); END $b$$t$,
  (SELECT pat_a FROM fx),(SELECT slot3 FROM fx),(SELECT usr_a FROM fx),(SELECT usr_a FROM fx)), 'MC004');
SELECT pg_temp.expect('A19','A released slot can be rebooked by someone else',
  format($t$DO $b$ DECLARE v uuid; BEGIN v := book_appointment(%L,%L); CALL cancel_appointment(v, %L); PERFORM book_appointment(%L,%L); END $b$$t$,
  (SELECT pat_a FROM fx),(SELECT slot3 FROM fx),(SELECT usr_a FROM fx),(SELECT pat_b FROM fx),(SELECT slot3 FROM fx)), 'success');

-- ---------------- consultation flow + review rule
SELECT pg_temp.expect('A20','Consultation: start, complete, appointment becomes COMPLETED',
  format($t$DO $b$ DECLARE v uuid; c uuid; BEGIN v := book_appointment(%L,%L); c := start_consultation(v, %L);
     IF (SELECT status FROM appointments WHERE appointment_id=v) <> 'IN_PROGRESS' THEN RAISE EXCEPTION 'not in progress'; END IF;
     CALL complete_consultation(c, %L, true);
     IF (SELECT status FROM appointments WHERE appointment_id=v) <> 'COMPLETED' THEN RAISE EXCEPTION 'not completed'; END IF;
     IF NOT (SELECT follow_up_required AND ended_at IS NOT NULL FROM consultations WHERE consultation_id=c) THEN RAISE EXCEPTION 'consultation row wrong'; END IF; END $b$$t$,
  (SELECT pat_a FROM fx),(SELECT slot3 FROM fx),(SELECT slot3_doc_user FROM fx),(SELECT slot3_doc_user FROM fx)), 'success');
SELECT pg_temp.expect('A21','Only the appointment''s own doctor can start a consultation',
  format($$SELECT start_consultation(book_appointment(%L,%L), %L)$$, (SELECT pat_a FROM fx),(SELECT slot3 FROM fx),(SELECT usr_b FROM fx)), 'MC007');
SELECT pg_temp.expect('A22','Review blocked before completion, allowed after',
  format($t$DO $b$ DECLARE v uuid; c uuid; BEGIN v := book_appointment(%L,%L); c := start_consultation(v, %L);
     BEGIN INSERT INTO reviews(consultation_id, rating) VALUES (c, 5); RAISE EXCEPTION 'review accepted too early';
     EXCEPTION WHEN SQLSTATE 'MC009' THEN NULL; END;
     CALL complete_consultation(c, %L); INSERT INTO reviews(consultation_id, rating) VALUES (c, 5); END $b$$t$,
  (SELECT pat_a FROM fx),(SELECT slot3 FROM fx),(SELECT slot3_doc_user FROM fx),(SELECT slot3_doc_user FROM fx)), 'success');

-- ---------------- audit
SELECT pg_temp.expect('A23','Audit log never contains password hashes',
  format($t$DO $b$ BEGIN UPDATE users SET is_active=false WHERE user_id=%L;
     IF NOT EXISTS (SELECT 1 FROM audit_log WHERE table_name='users' AND action='UPDATE' AND new_data IS NOT NULL) THEN RAISE EXCEPTION 'no audit row'; END IF;
     IF EXISTS (SELECT 1 FROM audit_log WHERE (new_data ? 'password_hash') OR (old_data ? 'password_hash')) THEN RAISE EXCEPTION 'password hash leaked'; END IF; END $b$$t$, (SELECT usr_a FROM fx)), 'success');

-- ---------------- find_similar_cases (TEST-ONLY synthetic vectors, one block of dimensions per specialization)
SELECT pg_temp.expect('A24','Matching refused until the case has an embedding',
  format($$SELECT * FROM find_similar_cases(%L,%L)$$, (SELECT cardio_doc FROM fx),(SELECT cardio_case FROM fx)), 'MC010');
SELECT pg_temp.expect('A25','Matching returns 5 same-specialization cases and writes the match log',
  format($t$DO $b$ DECLARE n int; same int; BEGIN
     INSERT INTO case_embeddings (case_id, embedding, text_hash)
     SELECT c.case_id, (SELECT array_agg((CASE WHEN g BETWEEN (c.specialization_id-1)*40 AND (c.specialization_id-1)*40+39 THEN 1.0 ELSE 0.0 END + random()*0.35)::real ORDER BY g) FROM generate_series(0,383) g)::vector,
            md5(c.case_id::text) || md5(c.case_id::text || 'x') FROM medical_cases c WHERE c.status <> 'DRAFT_INCOMPLETE';
     SELECT count(*), count(*) FILTER (WHERE r.specialization = 'Cardiology') INTO n, same FROM find_similar_cases(%L, %L, 5, 0.5, false) r;
     IF n <> 5 OR same <> 5 THEN RAISE EXCEPTION 'n=%% same=%%', n, same; END IF;
     IF (SELECT count(*) FROM case_match_log WHERE query_case_id=%L) <> 5 THEN RAISE EXCEPTION 'match log not written'; END IF; END $b$$t$,
  (SELECT cardio_doc FROM fx),(SELECT cardio_case FROM fx),(SELECT cardio_case FROM fx)), 'success');
SELECT pg_temp.expect('A26','A doctor with no appointment for the case cannot run matching',
  format($t$DO $b$ BEGIN INSERT INTO case_embeddings (case_id, embedding, text_hash) SELECT %L, array_fill(0.1::real, ARRAY[384])::vector, repeat('a',64);
     PERFORM * FROM find_similar_cases(%L, %L); END $b$$t$, (SELECT cardio_case FROM fx),(SELECT other_doc FROM fx),(SELECT cardio_case FROM fx)), 'MC007');
SELECT pg_temp.expect('A27','Matching output exposes only id, specialization and similarity',
  $$SELECT 1 FROM (SELECT parameter_name FROM information_schema.parameters WHERE specific_name LIKE 'find_similar_cases%' AND parameter_mode='OUT') o HAVING array_agg(parameter_name::text ORDER BY parameter_name::text) = ARRAY['matched_case_id','similarity','specialization']$$, 'success');
SELECT pg_temp.expect('A28','p_k = 0 is rejected',
  format($$SELECT * FROM find_similar_cases(%L,%L,0)$$, (SELECT cardio_doc FROM fx),(SELECT cardio_case FROM fx)), '22023');

-- ---------------- views and privileges (as the limited app role)
SELECT pg_temp.expect('A29','App role can read every view and the materialized view',
  $t$DO $b$ BEGIN SET LOCAL ROLE mediconnect_app;
     PERFORM 1 FROM v_doctor_directory LIMIT 1; PERFORM 1 FROM v_appointment_details LIMIT 1; PERFORM 1 FROM v_doctor_workload LIMIT 1;
     PERFORM 1 FROM v_daily_appointments LIMIT 1; PERFORM 1 FROM v_case_trends LIMIT 1; PERFORM 1 FROM v_admin_case_metadata LIMIT 1;
     PERFORM 1 FROM mv_monthly_stats LIMIT 1; PERFORM refresh_dashboard_stats(); END $b$$t$, 'success');
SELECT pg_temp.expect('A30','Admin case view exposes no title, narrative or patient identity',
  $$SELECT 1 FROM information_schema.columns WHERE table_name='v_admin_case_metadata' HAVING count(*) FILTER (WHERE column_name IN ('title','patient_id','full_name','email','phone','narrative')) = 0$$, 'success');
SELECT pg_temp.expect('A31','Doctor directory lists only VERIFIED doctors (expect 10)',
  $t$DO $b$ BEGIN IF (SELECT count(*) FROM v_doctor_directory) <> 10 THEN RAISE EXCEPTION 'count=%', (SELECT count(*) FROM v_doctor_directory); END IF; END $b$$t$, 'success');
SELECT pg_temp.expect('A32','Full-text search through the view finds the dermatologist',
  $t$DO $b$ BEGIN IF NOT EXISTS (SELECT 1 FROM v_doctor_directory WHERE search_vector @@ websearch_to_tsquery('english','rash') AND specialization='Dermatology') THEN RAISE EXCEPTION 'not found'; END IF; END $b$$t$, 'success');

\echo
\echo '=== DAY 3 ADVANCED FEATURE TEST RESULTS ==='
SELECT test_id, description, expected, got, result FROM test_results ORDER BY n;
SELECT count(*) FILTER (WHERE result='PASS') AS passed, count(*) FILTER (WHERE result='FAIL') AS failed, count(*) AS total FROM test_results;
