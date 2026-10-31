-- demo_queries.sql : live-demo script for the advanced DBMS features. Safe to run: everything is rolled back.
--   psql -U postgres -d mediconnect -f database/postgres/tests/demo_queries.sql
\pset pager off
\echo '##### 1. TRANSACTION + STORED FUNCTION/PROCEDURE: full appointment lifecycle (rolled back at the end)'
BEGIN;
SELECT set_config('demo.pat',  (SELECT patient_id::text FROM patients p JOIN users u USING (user_id) WHERE u.email='patient21@mediconnect.test'), true);
SELECT set_config('demo.usr',  (SELECT user_id::text FROM users WHERE email='patient21@mediconnect.test'), true);
SELECT set_config('demo.slot', (SELECT slot_id::text FROM time_slots WHERE status='AVAILABLE' AND start_ts > now() + interval '8 days' ORDER BY start_ts LIMIT 1), true);
SELECT book_appointment(current_setting('demo.pat')::uuid, current_setting('demo.slot')::uuid, NULL, 'Demo booking') AS appointment_id \gset
\echo 'after book_appointment: appointment BOOKED, slot BOOKED (set by trigger)'
SELECT a.status AS appointment, t.status AS slot FROM appointments a JOIN time_slots t USING (slot_id) WHERE a.appointment_id = :'appointment_id';
\echo 'booking the same slot again fails (the ERROR below is the expected result):'
SAVEPOINT s1;
SELECT book_appointment((SELECT patient_id FROM patients p JOIN users u USING (user_id) WHERE u.email='patient22@mediconnect.test'), current_setting('demo.slot')::uuid);
ROLLBACK TO s1;
CALL cancel_appointment(:'appointment_id', current_setting('demo.usr')::uuid, 'Demo cancellation');
\echo 'after cancel_appointment: appointment CANCELLED, slot released to AVAILABLE'
SELECT a.status AS appointment, t.status AS slot FROM appointments a JOIN time_slots t USING (slot_id) WHERE a.appointment_id = :'appointment_id';
\echo 'the audit trigger recorded every state change:'
SELECT table_name, action, old_data->>'status' AS old_status, new_data->>'status' AS new_status FROM audit_log WHERE record_id = :'appointment_id' ORDER BY log_id;
ROLLBACK;

\echo
\echo '##### 2. VIEWS: doctor directory (verified doctors, rating, next free slot)'
SELECT full_name, specialization, review_count, avg_rating, to_char(next_available AT TIME ZONE 'Asia/Kolkata','DD Mon HH24:MI') AS next_slot FROM v_doctor_directory ORDER BY avg_rating DESC NULLS LAST, full_name LIMIT 5;
\echo '##### 3. JOIN + GROUP BY + HAVING + SUBQUERY: doctors busier than the average doctor'
SELECT full_name, specialization, total_appointments, cancellation_rate_pct FROM v_doctor_workload
WHERE total_appointments > (SELECT avg(total_appointments) FROM v_doctor_workload) ORDER BY total_appointments DESC;
\echo '##### 4. MATERIALIZED VIEW: monthly dashboard numbers'
SELECT refresh_dashboard_stats();
SELECT * FROM mv_monthly_stats ORDER BY month DESC LIMIT 3;

\echo
\echo '##### 5. EXPLAIN ANALYZE: full-text doctor search (GIN index; seq scan disabled only because the table is tiny)'
BEGIN; SET LOCAL enable_seqscan = off;
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON, SUMMARY ON) SELECT doctor_id FROM doctors WHERE search_vector @@ websearch_to_tsquery('english','heart');
\echo '##### 6. EXPLAIN ANALYZE: available slots for one doctor (partial B-tree index)'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON, SUMMARY ON) SELECT slot_id, start_ts FROM time_slots
WHERE doctor_id = (SELECT doctor_id FROM doctors WHERE license_number='KMC-2010-10001') AND status='AVAILABLE' AND start_ts > now() ORDER BY start_ts LIMIT 10;
ROLLBACK;

\echo '##### 7. EXPLAIN ANALYZE: vector similarity (HNSW). Needs embeddings: run  python database/scripts/embed_cases.py  first'
SELECT count(*) AS embeddings_loaded FROM case_embeddings;
BEGIN; SET LOCAL enable_seqscan = off;
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON, SUMMARY ON)
SELECT e.case_id FROM case_embeddings e JOIN medical_cases c USING (case_id)
WHERE c.consent_for_matching AND c.status IN ('RESOLVED','CLOSED')
ORDER BY e.embedding <=> (SELECT embedding FROM case_embeddings LIMIT 1) LIMIT 5;
ROLLBACK;
