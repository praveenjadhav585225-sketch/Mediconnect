-- 03_slots_appointments.sql  (SYNTHETIC)
-- Slots are generated relative to the day you load the seed: 21 days back, 13 days ahead.
-- Appointments, consultations and reviews use deterministic ids, so MongoDB seeds can reference them.
SET timezone = 'Asia/Kolkata';
BEGIN;

-- 1. Slots from the weekly availability rules (this is what generate_slots() will do in Day 3)
INSERT INTO time_slots (doctor_id, start_ts, end_ts)
SELECT r.doctor_id, ts, ts + make_interval(mins => r.slot_minutes)
FROM availability_rules r
CROSS JOIN generate_series(current_date::timestamp - interval '21 days', current_date::timestamp + interval '13 days', interval '1 day') AS d(day)
CROSS JOIN LATERAL generate_series(d.day + r.start_time,
                                   d.day + r.end_time - make_interval(mins => r.slot_minutes),
                                   make_interval(mins => r.slot_minutes)) AS ts
WHERE extract(dow FROM d.day) = r.day_of_week;

-- 2. Thirty past appointments. rn picks doctor (rn-1)%10, patient (rn-1)%30, and that doctor's ((rn-1)/10+1)-th slot.
WITH vd AS (SELECT doctor_id, row_number() OVER (ORDER BY license_number COLLATE "C") - 1 AS di
            FROM doctors WHERE verification_status = 'VERIFIED'),
     pt AS (SELECT p.patient_id, row_number() OVER (ORDER BY u.email COLLATE "C") - 1 AS pi
            FROM patients p JOIN users u USING (user_id)),
     ps AS (SELECT slot_id, doctor_id, start_ts, end_ts,
                   row_number() OVER (PARTITION BY doctor_id ORDER BY start_ts) AS sn
            FROM time_slots WHERE end_ts < now() - interval '1 hour'),
     seq AS (SELECT n AS rn FROM generate_series(1, 30) n)
INSERT INTO appointments (appointment_id, patient_id, doctor_id, slot_id, status, reason, booked_at, cancelled_at, cancel_reason)
SELECT md5('appt:' || rn)::uuid, pt.patient_id, vd.doctor_id, ps.slot_id,
       CASE WHEN rn % 6 = 0 THEN 'CANCELLED' WHEN rn % 6 = 5 THEN 'NO_SHOW' ELSE 'COMPLETED' END,
       'Synthetic follow-up visit', ps.start_ts - interval '3 days',
       CASE WHEN rn % 6 = 0 THEN ps.start_ts - interval '1 day' END,
       CASE WHEN rn % 6 = 0 THEN 'Patient unavailable (synthetic)' END
FROM seq
JOIN vd ON vd.di = (rn - 1) % 10
JOIN pt ON pt.pi = (rn - 1) % 30
JOIN ps ON ps.doctor_id = vd.doctor_id AND ps.sn = (rn - 1) / 10 + 1;

-- 3. Consultations for COMPLETED appointments, ids derived from the appointment id
INSERT INTO consultations (consultation_id, appointment_id, status, started_at, ended_at, follow_up_required, notes_doc_id)
SELECT md5('consult:' || a.appointment_id::text)::uuid, a.appointment_id, 'COMPLETED', s.start_ts, s.end_ts,
       get_byte(decode(md5(a.appointment_id::text), 'hex'), 2) % 5 = 0,
       md5('consult:' || a.appointment_id::text)::uuid::text
FROM appointments a JOIN time_slots s USING (slot_id)
WHERE a.status = 'COMPLETED';

-- 4. Reviews for roughly three quarters of completed consultations
INSERT INTO reviews (consultation_id, rating, comment, created_at)
SELECT c.consultation_id,
       3 + get_byte(decode(md5(c.consultation_id::text), 'hex'), 0) % 3,
       CASE get_byte(decode(md5(c.consultation_id::text), 'hex'), 1) % 3
            WHEN 0 THEN 'Clear explanation, on time.' WHEN 1 THEN 'Smooth video session (synthetic).' ELSE NULL END,
       c.ended_at + interval '2 hours'
FROM consultations c
WHERE get_byte(decode(md5(c.consultation_id::text), 'hex'), 1) % 4 <> 0;

-- 5. Demo scenario: each active SUBMITTED case gets the earliest future slot of a VERIFIED doctor in its specialization
INSERT INTO appointments (patient_id, doctor_id, slot_id, case_id, status, reason, booked_at)
SELECT c.patient_id, s.doctor_id, s.slot_id, c.case_id, 'BOOKED', 'Consultation for submitted case', now() - interval '2 hours'
FROM medical_cases c
CROSS JOIN LATERAL (
    SELECT ts.slot_id, ts.doctor_id
    FROM time_slots ts JOIN doctors d ON d.doctor_id = ts.doctor_id
    WHERE d.specialization_id = c.specialization_id AND d.verification_status = 'VERIFIED'
      AND ts.status = 'AVAILABLE' AND ts.start_ts > now() + interval '1 day'
    ORDER BY ts.start_ts, d.license_number COLLATE "C" LIMIT 1) s
WHERE c.status = 'SUBMITTED';

UPDATE time_slots SET status = 'BOOKED'
WHERE slot_id IN (SELECT slot_id FROM appointments WHERE status <> 'CANCELLED');

-- 6. Eight more future bookings without a case (every second one already confirmed)
WITH vd AS (SELECT doctor_id, row_number() OVER (ORDER BY license_number COLLATE "C") - 1 AS di
            FROM doctors WHERE verification_status = 'VERIFIED'),
     pt AS (SELECT p.patient_id, row_number() OVER (ORDER BY u.email COLLATE "C") - 1 AS pi
            FROM patients p JOIN users u USING (user_id) WHERE u.is_active),
     fs AS (SELECT slot_id, doctor_id, row_number() OVER (PARTITION BY doctor_id ORDER BY start_ts) AS sn
            FROM time_slots WHERE status = 'AVAILABLE' AND start_ts > now() + interval '1 day'),
     seq AS (SELECT n AS rn FROM generate_series(1, 8) n)
INSERT INTO appointments (patient_id, doctor_id, slot_id, status, reason, booked_at, confirmed_at)
SELECT pt.patient_id, vd.doctor_id, fs.slot_id,
       CASE WHEN rn % 2 = 0 THEN 'CONFIRMED' ELSE 'BOOKED' END, 'Synthetic general consultation',
       now() - interval '1 day', CASE WHEN rn % 2 = 0 THEN now() - interval '20 hours' END
FROM seq JOIN vd ON vd.di = (rn + 2) % 10 JOIN pt ON pt.pi = rn + 10
JOIN fs ON fs.doctor_id = vd.doctor_id AND fs.sn = 3;

UPDATE time_slots SET status = 'BOOKED'
WHERE slot_id IN (SELECT slot_id FROM appointments WHERE status <> 'CANCELLED');

COMMIT;
