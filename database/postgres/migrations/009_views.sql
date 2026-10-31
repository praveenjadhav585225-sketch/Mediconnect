-- 009_views.sql : read models for the app and dashboards

-- Bookable doctors with rating and next free slot. search_vector is exposed so full-text search can use the GIN index.
CREATE VIEW v_doctor_directory AS
SELECT d.doctor_id, d.full_name, d.specialization_id, s.name AS specialization, d.experience_years,
       d.consultation_fee, d.bio, d.search_vector,
       COALESCE(r.review_count, 0) AS review_count, r.avg_rating,
       (SELECT min(t.start_ts) FROM time_slots t
         WHERE t.doctor_id = d.doctor_id AND t.status = 'AVAILABLE' AND t.start_ts > now()) AS next_available
FROM doctors d
JOIN specializations s ON s.specialization_id = d.specialization_id
LEFT JOIN (SELECT a.doctor_id, count(*) AS review_count, round(avg(rv.rating), 2) AS avg_rating
           FROM reviews rv JOIN consultations c ON c.consultation_id = rv.consultation_id
           JOIN appointments a ON a.appointment_id = c.appointment_id GROUP BY a.doctor_id) r ON r.doctor_id = d.doctor_id
WHERE d.verification_status = 'VERIFIED';

CREATE VIEW v_appointment_details AS
SELECT a.appointment_id, a.status, a.reason, a.booked_at, a.cancelled_at, a.cancel_reason,
       t.start_ts, t.end_ts, a.patient_id, p.full_name AS patient_name,
       a.doctor_id, d.full_name AS doctor_name, s.name AS specialization,
       a.case_id, c.consultation_id, c.status AS consultation_status, c.follow_up_required
FROM appointments a
JOIN time_slots t ON t.slot_id = a.slot_id
JOIN patients p ON p.patient_id = a.patient_id
JOIN doctors d ON d.doctor_id = a.doctor_id
JOIN specializations s ON s.specialization_id = d.specialization_id
LEFT JOIN consultations c ON c.appointment_id = a.appointment_id;

CREATE VIEW v_doctor_workload AS
SELECT d.doctor_id, d.full_name, s.name AS specialization,
       count(a.appointment_id)                                         AS total_appointments,
       count(*) FILTER (WHERE a.status = 'COMPLETED')                  AS completed,
       count(*) FILTER (WHERE a.status = 'CANCELLED')                  AS cancelled,
       count(*) FILTER (WHERE a.status = 'NO_SHOW')                    AS no_show,
       count(*) FILTER (WHERE a.status IN ('BOOKED','CONFIRMED'))      AS upcoming,
       round(100.0 * count(*) FILTER (WHERE a.status = 'CANCELLED') / NULLIF(count(a.appointment_id), 0), 1) AS cancellation_rate_pct
FROM doctors d
JOIN specializations s ON s.specialization_id = d.specialization_id
LEFT JOIN appointments a ON a.doctor_id = d.doctor_id
GROUP BY d.doctor_id, d.full_name, s.name;

CREATE VIEW v_daily_appointments AS
SELECT (t.start_ts AT TIME ZONE 'Asia/Kolkata')::date AS day,
       count(*) AS total,
       count(*) FILTER (WHERE a.status = 'COMPLETED') AS completed,
       count(*) FILTER (WHERE a.status = 'CANCELLED') AS cancelled,
       count(*) FILTER (WHERE a.status IN ('BOOKED','CONFIRMED')) AS upcoming
FROM appointments a JOIN time_slots t ON t.slot_id = a.slot_id
GROUP BY 1;

CREATE VIEW v_case_trends AS
SELECT to_char(c.created_at AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM') AS month, s.name AS specialization,
       count(*) AS cases, count(*) FILTER (WHERE c.severity = 'HIGH') AS high_severity
FROM medical_cases c LEFT JOIN specializations s ON s.specialization_id = c.specialization_id
GROUP BY 1, 2;

-- What an ADMIN may see about cases: metadata only. No title, narrative or patient identity.
CREATE VIEW v_admin_case_metadata AS
SELECT c.case_id, s.name AS specialization, c.severity, c.status, c.consent_for_matching, c.created_at,
       EXISTS (SELECT 1 FROM case_embeddings e WHERE e.case_id = c.case_id) AS has_embedding
FROM medical_cases c LEFT JOIN specializations s ON s.specialization_id = c.specialization_id;

-- Pre-computed monthly numbers for the admin dashboard (refresh with refresh_dashboard_stats()).
CREATE MATERIALIZED VIEW mv_monthly_stats AS
SELECT to_char(t.start_ts AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM') AS month,
       count(*) AS appointments,
       count(*) FILTER (WHERE a.status = 'COMPLETED') AS completed,
       count(*) FILTER (WHERE a.status = 'CANCELLED') AS cancelled,
       count(DISTINCT a.patient_id) AS unique_patients
FROM appointments a JOIN time_slots t ON t.slot_id = a.slot_id
GROUP BY 1;
CREATE UNIQUE INDEX uq_mv_monthly_stats ON mv_monthly_stats (month);

CREATE OR REPLACE FUNCTION refresh_dashboard_stats() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS
$$ REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_stats $$;
GRANT EXECUTE ON FUNCTION refresh_dashboard_stats() TO mediconnect_app;
GRANT SELECT ON mv_monthly_stats TO mediconnect_app;
