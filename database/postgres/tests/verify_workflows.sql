-- verify_workflows.sql : read-only checks after you book / cancel through the UI.
--   psql -U postgres -d mediconnect -f database/postgres/tests/verify_workflows.sql
\pset pager off
\echo '=== W1: 8 newest appointments ==='
SELECT left(a.appointment_id::text, 8) AS appt, p.full_name AS patient, d.full_name AS doctor, a.status AS appt_status, t.status AS slot_status,
       to_char(t.start_ts AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI') AS slot, to_char(a.booked_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI') AS booked_at
FROM appointments a JOIN patients p USING (patient_id) JOIN doctors d USING (doctor_id) JOIN time_slots t USING (slot_id)
ORDER BY a.booked_at DESC LIMIT 8;

\echo '=== W2: slot status must match appointment status (every row below = a BUG) ==='
SELECT left(a.appointment_id::text, 8) AS appt, a.status AS appt_status, t.status AS slot_status
FROM appointments a JOIN time_slots t USING (slot_id)
WHERE (a.status <> 'CANCELLED' AND t.status <> 'BOOKED')
   OR (a.status = 'CANCELLED' AND t.status = 'BOOKED' AND NOT EXISTS (SELECT 1 FROM appointments x WHERE x.slot_id = a.slot_id AND x.status <> 'CANCELLED'));
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS slot_consistency, count(*) AS violations
FROM time_slots t WHERE (t.status = 'BOOKED' AND NOT EXISTS (SELECT 1 FROM appointments a WHERE a.slot_id = t.slot_id AND a.status <> 'CANCELLED'))
   OR (t.status = 'AVAILABLE' AND EXISTS (SELECT 1 FROM appointments a WHERE a.slot_id = t.slot_id AND a.status <> 'CANCELLED'));

\echo '=== W3: no slot may have two active appointments ==='
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS no_double_booking, count(*) AS violations
FROM (SELECT slot_id FROM appointments WHERE status <> 'CANCELLED' GROUP BY slot_id HAVING count(*) > 1) x;

\echo '=== W4: latest 10 audit entries (who did what) ==='
SELECT to_char(changed_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI:SS') AS at, coalesce(u.email, '(none)') AS actor, table_name, action,
       old_data->>'status' AS old_status, new_data->>'status' AS new_status
FROM audit_log l LEFT JOIN users u ON u.user_id = l.actor_user_id ORDER BY log_id DESC LIMIT 10;

\echo '=== W5: audit rows with NO actor (the app should call set_actor() before direct updates) ==='
SELECT count(*) AS rows_without_actor FROM audit_log WHERE actor_user_id IS NULL AND changed_at > now() - interval '1 day';
