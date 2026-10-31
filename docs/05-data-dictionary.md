# MediConnect Data Dictionary (PostgreSQL)

Generated from the live schema by `database/scripts/generate_data_dictionary.py`.

## appointments

| Column | Type | Null? | Default |
|---|---|---|---|
| appointment_id | uuid | NO | gen_random_uuid() |
| patient_id | uuid | NO |  |
| doctor_id | uuid | NO |  |
| slot_id | uuid | NO |  |
| case_id | uuid | YES |  |
| status | text | NO | 'BOOKED'::text |
| reason | text | YES |  |
| booked_at | timestamp with time zone | NO | now() |
| confirmed_at | timestamp with time zone | YES |  |
| cancelled_at | timestamp with time zone | YES |  |
| cancel_reason | text | YES |  |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_appt_cancel | CHECK | `CHECK (((status = 'CANCELLED'::text) = (cancelled_at IS NOT NULL)))` |
| ck_appt_reason | CHECK | `CHECK (((reason IS NULL) OR (length(reason) <= 1000)))` |
| ck_appt_status | CHECK | `CHECK ((status = ANY (ARRAY['BOOKED'::text, 'CONFIRMED'::text, 'IN_PROGRESS'::text, 'COMPLETED'::text, 'CANCELLED'::text, 'NO_SHOW'::text])))` |
| fk_appt_case_patient | FOREIGN KEY | `FOREIGN KEY (case_id, patient_id) REFERENCES medical_cases(case_id, patient_id)` |
| fk_appt_doctor | FOREIGN KEY | `FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)` |
| fk_appt_patient | FOREIGN KEY | `FOREIGN KEY (patient_id) REFERENCES patients(patient_id)` |
| fk_appt_slot_doctor | FOREIGN KEY | `FOREIGN KEY (slot_id, doctor_id) REFERENCES time_slots(slot_id, doctor_id)` |
| appointments_pkey | PRIMARY KEY | `PRIMARY KEY (appointment_id)` |

## audit_log

| Column | Type | Null? | Default |
|---|---|---|---|
| log_id | bigint | NO |  |
| actor_user_id | uuid | YES |  |
| table_name | text | NO |  |
| record_id | text | NO |  |
| action | text | NO |  |
| old_data | jsonb | YES |  |
| new_data | jsonb | YES |  |
| changed_at | timestamp with time zone | NO | now() |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_audit_action | CHECK | `CHECK ((action = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text, 'LOGIN'::text, 'ACCESS'::text])))` |
| fk_audit_user | FOREIGN KEY | `FOREIGN KEY (actor_user_id) REFERENCES users(user_id) ON DELETE SET NULL` |
| audit_log_pkey | PRIMARY KEY | `PRIMARY KEY (log_id)` |

## availability_rules

| Column | Type | Null? | Default |
|---|---|---|---|
| rule_id | integer | NO |  |
| doctor_id | uuid | NO |  |
| day_of_week | smallint | NO |  |
| start_time | time without time zone | NO |  |
| end_time | time without time zone | NO |  |
| slot_minutes | smallint | NO | 30 |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_rules_dow | CHECK | `CHECK (((day_of_week >= 0) AND (day_of_week <= 6)))` |
| ck_rules_slot | CHECK | `CHECK ((slot_minutes = ANY (ARRAY[15, 20, 30, 45, 60])))` |
| ck_rules_time | CHECK | `CHECK ((end_time > start_time))` |
| fk_rules_doctor | FOREIGN KEY | `FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE CASCADE` |
| availability_rules_pkey | PRIMARY KEY | `PRIMARY KEY (rule_id)` |
| ex_rules_no_overlap | EXCLUDE | `EXCLUDE USING gist (doctor_id WITH =, day_of_week WITH =, timerange(start_time, end_time) WITH &&)` |

## case_embeddings

| Column | Type | Null? | Default |
|---|---|---|---|
| case_id | uuid | NO |  |
| embedding | vector(384) | NO |  |
| model_name | text | NO | 'all-MiniLM-L6-v2'::text |
| text_hash | text | NO |  |
| created_at | timestamp with time zone | NO | now() |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_embeddings_hash | CHECK | `CHECK ((text_hash ~ '^[0-9a-f]{64}$'::text))` |
| fk_embeddings_case | FOREIGN KEY | `FOREIGN KEY (case_id) REFERENCES medical_cases(case_id) ON DELETE CASCADE` |
| case_embeddings_pkey | PRIMARY KEY | `PRIMARY KEY (case_id)` |

## case_match_log

| Column | Type | Null? | Default |
|---|---|---|---|
| match_id | uuid | NO | gen_random_uuid() |
| query_case_id | uuid | NO |  |
| matched_case_id | uuid | NO |  |
| doctor_id | uuid | NO |  |
| similarity_score | real | NO |  |
| created_at | timestamp with time zone | NO | now() |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_match_diff | CHECK | `CHECK ((query_case_id <> matched_case_id))` |
| ck_match_score | CHECK | `CHECK (((similarity_score >= (0)::double precision) AND (similarity_score <= (1)::double precision)))` |
| fk_match_doctor | FOREIGN KEY | `FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)` |
| fk_match_matched | FOREIGN KEY | `FOREIGN KEY (matched_case_id) REFERENCES medical_cases(case_id) ON DELETE CASCADE` |
| fk_match_query | FOREIGN KEY | `FOREIGN KEY (query_case_id) REFERENCES medical_cases(case_id) ON DELETE CASCADE` |
| case_match_log_pkey | PRIMARY KEY | `PRIMARY KEY (match_id)` |

## consultations

| Column | Type | Null? | Default |
|---|---|---|---|
| consultation_id | uuid | NO | gen_random_uuid() |
| appointment_id | uuid | NO |  |
| status | text | NO | 'STARTED'::text |
| started_at | timestamp with time zone | NO | now() |
| ended_at | timestamp with time zone | YES |  |
| follow_up_required | boolean | NO | false |
| notes_doc_id | text | YES |  |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_consult_done | CHECK | `CHECK (((status <> 'COMPLETED'::text) OR (ended_at IS NOT NULL)))` |
| ck_consult_status | CHECK | `CHECK ((status = ANY (ARRAY['STARTED'::text, 'COMPLETED'::text])))` |
| ck_consult_times | CHECK | `CHECK (((ended_at IS NULL) OR (ended_at >= started_at)))` |
| fk_consult_appt | FOREIGN KEY | `FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id)` |
| consultations_pkey | PRIMARY KEY | `PRIMARY KEY (consultation_id)` |
| uq_consult_appt | UNIQUE | `UNIQUE (appointment_id)` |

## doctors

| Column | Type | Null? | Default |
|---|---|---|---|
| doctor_id | uuid | NO | gen_random_uuid() |
| user_id | uuid | NO |  |
| specialization_id | integer | NO |  |
| full_name | text | NO |  |
| license_number | text | NO |  |
| experience_years | integer | NO | 0 |
| consultation_fee | numeric(10,2) | NO | 0 |
| bio | text | YES | ''::text |
| verification_status | text | NO | 'PENDING'::text |
| search_vector | tsvector | YES | (generated) |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_doctors_exp | CHECK | `CHECK (((experience_years >= 0) AND (experience_years <= 70)))` |
| ck_doctors_fee | CHECK | `CHECK ((consultation_fee >= (0)::numeric))` |
| ck_doctors_license_len | CHECK | `CHECK ((length(btrim(license_number)) >= 5))` |
| ck_doctors_name | CHECK | `CHECK ((length(btrim(full_name)) >= 2))` |
| ck_doctors_status | CHECK | `CHECK ((verification_status = ANY (ARRAY['PENDING'::text, 'VERIFIED'::text, 'REJECTED'::text, 'SUSPENDED'::text])))` |
| fk_doctors_spec | FOREIGN KEY | `FOREIGN KEY (specialization_id) REFERENCES specializations(specialization_id)` |
| fk_doctors_user | FOREIGN KEY | `FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE` |
| doctors_pkey | PRIMARY KEY | `PRIMARY KEY (doctor_id)` |
| uq_doctors_license | UNIQUE | `UNIQUE (license_number)` |
| uq_doctors_user | UNIQUE | `UNIQUE (user_id)` |

## medical_cases

| Column | Type | Null? | Default |
|---|---|---|---|
| case_id | uuid | NO | gen_random_uuid() |
| patient_id | uuid | NO |  |
| title | text | NO |  |
| specialization_id | integer | YES |  |
| severity | text | NO |  |
| duration_days | integer | NO | 0 |
| status | text | NO | 'SUBMITTED'::text |
| consent_for_matching | boolean | NO | false |
| mongo_detail_id | text | NO |  |
| created_at | timestamp with time zone | NO | now() |
| updated_at | timestamp with time zone | NO | now() |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_cases_duration | CHECK | `CHECK (((duration_days >= 0) AND (duration_days <= 3650)))` |
| ck_cases_severity | CHECK | `CHECK ((severity = ANY (ARRAY['LOW'::text, 'MODERATE'::text, 'HIGH'::text])))` |
| ck_cases_status | CHECK | `CHECK ((status = ANY (ARRAY['DRAFT_INCOMPLETE'::text, 'SUBMITTED'::text, 'UNDER_REVIEW'::text, 'RESOLVED'::text, 'CLOSED'::text])))` |
| ck_cases_title | CHECK | `CHECK ((length(btrim(title)) >= 3))` |
| fk_cases_patient | FOREIGN KEY | `FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE` |
| fk_cases_spec | FOREIGN KEY | `FOREIGN KEY (specialization_id) REFERENCES specializations(specialization_id)` |
| medical_cases_pkey | PRIMARY KEY | `PRIMARY KEY (case_id)` |
| uq_cases_id_patient | UNIQUE | `UNIQUE (case_id, patient_id)` |
| uq_cases_mongo | UNIQUE | `UNIQUE (mongo_detail_id)` |

## patients

| Column | Type | Null? | Default |
|---|---|---|---|
| patient_id | uuid | NO | gen_random_uuid() |
| user_id | uuid | NO |  |
| full_name | text | NO |  |
| date_of_birth | date | NO |  |
| gender | text | YES |  |
| phone | text | YES |  |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_patients_dob | CHECK | `CHECK (((date_of_birth >= '1900-01-01'::date) AND (date_of_birth <= CURRENT_DATE)))` |
| ck_patients_gender | CHECK | `CHECK (((gender IS NULL) OR (gender = ANY (ARRAY['MALE'::text, 'FEMALE'::text, 'OTHER'::text]))))` |
| ck_patients_name | CHECK | `CHECK ((length(btrim(full_name)) >= 2))` |
| ck_patients_phone | CHECK | `CHECK (((phone IS NULL) OR (phone ~ '^\+?[0-9]{10,15}$'::text)))` |
| fk_patients_user | FOREIGN KEY | `FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE` |
| patients_pkey | PRIMARY KEY | `PRIMARY KEY (patient_id)` |
| uq_patients_user | UNIQUE | `UNIQUE (user_id)` |

## reviews

| Column | Type | Null? | Default |
|---|---|---|---|
| review_id | uuid | NO | gen_random_uuid() |
| consultation_id | uuid | NO |  |
| rating | smallint | NO |  |
| comment | text | YES |  |
| created_at | timestamp with time zone | NO | now() |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_reviews_comment | CHECK | `CHECK (((comment IS NULL) OR (length(comment) <= 1000)))` |
| ck_reviews_rating | CHECK | `CHECK (((rating >= 1) AND (rating <= 5)))` |
| fk_reviews_consult | FOREIGN KEY | `FOREIGN KEY (consultation_id) REFERENCES consultations(consultation_id)` |
| reviews_pkey | PRIMARY KEY | `PRIMARY KEY (review_id)` |
| uq_reviews_consult | UNIQUE | `UNIQUE (consultation_id)` |

## specializations

| Column | Type | Null? | Default |
|---|---|---|---|
| specialization_id | integer | NO |  |
| name | text | NO |  |
| description | text | YES |  |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_specializations_name | CHECK | `CHECK ((length(btrim(name)) >= 3))` |
| specializations_pkey | PRIMARY KEY | `PRIMARY KEY (specialization_id)` |
| uq_specializations_name | UNIQUE | `UNIQUE (name)` |

## time_slots

| Column | Type | Null? | Default |
|---|---|---|---|
| slot_id | uuid | NO | gen_random_uuid() |
| doctor_id | uuid | NO |  |
| start_ts | timestamp with time zone | NO |  |
| end_ts | timestamp with time zone | NO |  |
| status | text | NO | 'AVAILABLE'::text |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_slots_status | CHECK | `CHECK ((status = ANY (ARRAY['AVAILABLE'::text, 'BOOKED'::text, 'BLOCKED'::text])))` |
| ck_slots_time | CHECK | `CHECK ((end_ts > start_ts))` |
| fk_slots_doctor | FOREIGN KEY | `FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE CASCADE` |
| time_slots_pkey | PRIMARY KEY | `PRIMARY KEY (slot_id)` |
| uq_slots_doctor_start | UNIQUE | `UNIQUE (doctor_id, start_ts)` |
| uq_slots_id_doctor | UNIQUE | `UNIQUE (slot_id, doctor_id)` |
| ex_slots_no_overlap | EXCLUDE | `EXCLUDE USING gist (doctor_id WITH =, tstzrange(start_ts, end_ts) WITH &&)` |

## users

| Column | Type | Null? | Default |
|---|---|---|---|
| user_id | uuid | NO | gen_random_uuid() |
| email | text | NO |  |
| password_hash | text | NO |  |
| role | text | NO |  |
| is_active | boolean | NO | true |
| created_at | timestamp with time zone | NO | now() |
| last_login_at | timestamp with time zone | YES |  |

**Constraints**

| Name | Kind | Definition |
|---|---|---|
| ck_users_email_fmt | CHECK | `CHECK ((email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text))` |
| ck_users_email_lc | CHECK | `CHECK ((email = lower(email)))` |
| ck_users_pw_hash | CHECK | `CHECK ((length(password_hash) >= 50))` |
| ck_users_role | CHECK | `CHECK ((role = ANY (ARRAY['PATIENT'::text, 'DOCTOR'::text, 'ADMIN'::text])))` |
| users_pkey | PRIMARY KEY | `PRIMARY KEY (user_id)` |
| uq_users_email | UNIQUE | `UNIQUE (email)` |
