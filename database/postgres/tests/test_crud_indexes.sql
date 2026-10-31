-- test_crud_indexes.sql : DML (INSERT/UPDATE/DELETE/SELECT), JOIN / GROUP BY / HAVING / subquery,
-- index existence and EXPLAIN checks. Runs inside a transaction and is rolled back.
\pset pager off
BEGIN;

\echo '=== C1: INSERT user + patient, SELECT it back ==='
WITH u AS (INSERT INTO users(email,password_hash,role) VALUES ('crud.test@mediconnect.test', repeat('h',64), 'PATIENT') RETURNING user_id)
INSERT INTO patients(user_id, full_name, date_of_birth, gender, phone)
SELECT user_id, 'Crud Test', '1995-05-05', 'FEMALE', '+919876543210' FROM u;
SELECT p.full_name, u.email, u.role FROM patients p JOIN users u USING (user_id) WHERE u.email = 'crud.test@mediconnect.test';

\echo '=== C2: UPDATE then verify ==='
UPDATE patients SET phone = '+919000011111' WHERE user_id = (SELECT user_id FROM users WHERE email='crud.test@mediconnect.test');
SELECT phone FROM patients WHERE full_name = 'Crud Test';

\echo '=== C3: DELETE the user, the patient row must go too (ON DELETE CASCADE) ==='
DELETE FROM users WHERE email = 'crud.test@mediconnect.test';
SELECT count(*) AS patient_rows_left FROM patients WHERE full_name = 'Crud Test';

\echo '=== C4: JOIN + GROUP BY + ORDER BY: appointments per doctor and status ==='
SELECT d.full_name AS doctor, s.name AS specialization,
       count(*) FILTER (WHERE a.status = 'COMPLETED') AS completed,
       count(*) FILTER (WHERE a.status = 'CANCELLED') AS cancelled,
       count(*) AS total
FROM doctors d JOIN specializations s USING (specialization_id) JOIN appointments a USING (doctor_id)
GROUP BY d.doctor_id, d.full_name, s.name ORDER BY total DESC, doctor LIMIT 5;

\echo '=== C5: HAVING: doctors whose average rating is 4 or more with at least 2 reviews ==='
SELECT d.full_name, count(r.review_id) AS reviews, round(avg(r.rating),2) AS avg_rating
FROM doctors d JOIN appointments a USING (doctor_id) JOIN consultations c USING (appointment_id) JOIN reviews r USING (consultation_id)
GROUP BY d.doctor_id, d.full_name HAVING count(r.review_id) >= 2 AND avg(r.rating) >= 4 ORDER BY avg_rating DESC;

\echo '=== C6: Subquery: patients who have a submitted case but no appointment yet (expect 0 after seed) ==='
SELECT count(*) AS patients_with_case_but_no_appointment
FROM patients p WHERE EXISTS (SELECT 1 FROM medical_cases c WHERE c.patient_id = p.patient_id AND c.status = 'SUBMITTED')
  AND NOT EXISTS (SELECT 1 FROM appointments a WHERE a.patient_id = p.patient_id AND a.case_id IS NOT NULL);

\echo '=== C7: Full-text doctor search ranked by relevance (uses the GIN index) ==='
SELECT full_name, round(ts_rank(search_vector, q)::numeric, 3) AS rank
FROM doctors, websearch_to_tsquery('english', 'heart') q
WHERE search_vector @@ q AND verification_status = 'VERIFIED' ORDER BY rank DESC;

\echo '=== I1: expected indexes exist (expect 0 missing) ==='
SELECT count(*) AS missing_indexes FROM unnest(ARRAY['idx_appt_patient','idx_appt_doctor_status','idx_cases_patient','idx_match_query',
  'idx_match_doctor_time','idx_audit_record','idx_audit_time','idx_slots_available','idx_doctors_verified_spec','idx_cases_matching_pool',
  'idx_doctors_search','idx_embeddings_hnsw','uq_appt_active_slot']) AS e(name)
WHERE NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname = e.name);

\echo '=== I2: index types in use (B-tree, partial, GIN, HNSW) ==='
SELECT indexname,
       CASE WHEN indexdef ILIKE '%USING gin%' THEN 'GIN' WHEN indexdef ILIKE '%USING hnsw%' THEN 'HNSW'
            WHEN indexdef ILIKE '% WHERE %' THEN 'B-tree (partial)' ELSE 'B-tree' END AS kind
FROM pg_indexes WHERE schemaname='public' AND indexname IN ('idx_appt_patient','idx_slots_available','idx_cases_matching_pool','idx_doctors_search','idx_embeddings_hnsw','uq_appt_active_slot') ORDER BY kind, indexname;

SET LOCAL enable_seqscan = off;   -- tables are tiny, so force the planner to show the index it WOULD use at scale
\echo '=== I3: EXPLAIN, GIN full-text index ==='
EXPLAIN (COSTS OFF) SELECT doctor_id FROM doctors WHERE search_vector @@ websearch_to_tsquery('english','heart');
\echo '=== I4: EXPLAIN, partial index for available slots ==='
EXPLAIN (COSTS OFF) SELECT slot_id FROM time_slots WHERE doctor_id = (SELECT doctor_id FROM doctors LIMIT 1) AND status = 'AVAILABLE' AND start_ts > now();
\echo '=== I5: EXPLAIN, partial index for the matching pool ==='
EXPLAIN (COSTS OFF) SELECT case_id FROM medical_cases WHERE specialization_id = 1 AND consent_for_matching AND status IN ('RESOLVED','CLOSED');

ROLLBACK;
