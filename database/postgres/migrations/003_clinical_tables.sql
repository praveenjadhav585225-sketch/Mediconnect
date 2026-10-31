-- 003_clinical_tables.sql : cases, embeddings, appointments, consultations, reviews, logs

CREATE TABLE medical_cases (
    case_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id            uuid    NOT NULL,
    title                 text    NOT NULL,
    specialization_id     integer,
    severity              text    NOT NULL,
    duration_days         integer NOT NULL DEFAULT 0,
    status                text    NOT NULL DEFAULT 'SUBMITTED',
    consent_for_matching  boolean NOT NULL DEFAULT false,
    mongo_detail_id       text    NOT NULL,      -- case_details.case_id in MongoDB (narrative lives there only)
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_cases_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    CONSTRAINT fk_cases_spec    FOREIGN KEY (specialization_id) REFERENCES specializations(specialization_id),
    CONSTRAINT uq_cases_mongo   UNIQUE (mongo_detail_id),
    -- target of the composite FK that ties an appointment's case to the same patient
    CONSTRAINT uq_cases_id_patient UNIQUE (case_id, patient_id),
    CONSTRAINT ck_cases_title    CHECK (length(btrim(title)) >= 3),
    CONSTRAINT ck_cases_severity CHECK (severity IN ('LOW','MODERATE','HIGH')),
    CONSTRAINT ck_cases_duration CHECK (duration_days BETWEEN 0 AND 3650),
    CONSTRAINT ck_cases_status   CHECK (status IN ('DRAFT_INCOMPLETE','SUBMITTED','UNDER_REVIEW','RESOLVED','CLOSED'))
);

CREATE TABLE case_embeddings (
    case_id     uuid PRIMARY KEY,
    embedding   vector(384) NOT NULL,
    model_name  text        NOT NULL DEFAULT 'all-MiniLM-L6-v2',
    text_hash   text        NOT NULL,            -- SHA-256 hex of the embedded text, detects stale vectors
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_embeddings_case FOREIGN KEY (case_id) REFERENCES medical_cases(case_id) ON DELETE CASCADE,
    CONSTRAINT ck_embeddings_hash CHECK (text_hash ~ '^[0-9a-f]{64}$')
);

CREATE TABLE appointments (
    appointment_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id      uuid NOT NULL,
    doctor_id       uuid NOT NULL,
    slot_id         uuid NOT NULL,
    case_id         uuid,
    status          text NOT NULL DEFAULT 'BOOKED',
    reason          text,
    booked_at       timestamptz NOT NULL DEFAULT now(),
    confirmed_at    timestamptz,
    cancelled_at    timestamptz,
    cancel_reason   text,
    CONSTRAINT fk_appt_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    CONSTRAINT fk_appt_doctor  FOREIGN KEY (doctor_id)  REFERENCES doctors(doctor_id),
    -- the slot must belong to the same doctor as the appointment (no trigger needed)
    CONSTRAINT fk_appt_slot_doctor FOREIGN KEY (slot_id, doctor_id) REFERENCES time_slots(slot_id, doctor_id),
    -- a linked case must belong to the same patient (NULL case_id skips the check)
    CONSTRAINT fk_appt_case_patient FOREIGN KEY (case_id, patient_id) REFERENCES medical_cases(case_id, patient_id),
    CONSTRAINT ck_appt_status CHECK (status IN ('BOOKED','CONFIRMED','IN_PROGRESS','COMPLETED','CANCELLED','NO_SHOW')),
    CONSTRAINT ck_appt_cancel CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL)),
    CONSTRAINT ck_appt_reason CHECK (reason IS NULL OR length(reason) <= 1000)
);
-- Only ONE non-cancelled appointment may hold a slot. Cancelled rows free the slot for rebooking.
CREATE UNIQUE INDEX uq_appt_active_slot ON appointments (slot_id) WHERE status <> 'CANCELLED';

CREATE TABLE consultations (
    consultation_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id      uuid NOT NULL,
    status              text NOT NULL DEFAULT 'STARTED',
    started_at          timestamptz NOT NULL DEFAULT now(),
    ended_at            timestamptz,
    follow_up_required  boolean NOT NULL DEFAULT false,
    notes_doc_id        text,                    -- consultation_notes.consultation_id in MongoDB
    CONSTRAINT uq_consult_appt UNIQUE (appointment_id),
    CONSTRAINT fk_consult_appt FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id),
    CONSTRAINT ck_consult_status CHECK (status IN ('STARTED','COMPLETED')),
    CONSTRAINT ck_consult_times  CHECK (ended_at IS NULL OR ended_at >= started_at),
    CONSTRAINT ck_consult_done   CHECK (status <> 'COMPLETED' OR ended_at IS NOT NULL)
);

CREATE TABLE reviews (
    review_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id  uuid     NOT NULL,
    rating           smallint NOT NULL,
    comment          text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_reviews_consult UNIQUE (consultation_id),     -- one review per consultation
    CONSTRAINT fk_reviews_consult FOREIGN KEY (consultation_id) REFERENCES consultations(consultation_id),
    CONSTRAINT ck_reviews_rating  CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT ck_reviews_comment CHECK (comment IS NULL OR length(comment) <= 1000)
);

CREATE TABLE case_match_log (
    match_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    query_case_id     uuid NOT NULL,
    matched_case_id   uuid NOT NULL,
    doctor_id         uuid NOT NULL,
    similarity_score  real NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_match_query   FOREIGN KEY (query_case_id)   REFERENCES medical_cases(case_id) ON DELETE CASCADE,
    CONSTRAINT fk_match_matched FOREIGN KEY (matched_case_id) REFERENCES medical_cases(case_id) ON DELETE CASCADE,
    CONSTRAINT fk_match_doctor  FOREIGN KEY (doctor_id)       REFERENCES doctors(doctor_id),
    CONSTRAINT ck_match_score   CHECK (similarity_score BETWEEN 0 AND 1),
    CONSTRAINT ck_match_diff    CHECK (query_case_id <> matched_case_id)
);

CREATE TABLE audit_log (
    log_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id  uuid,
    table_name     text        NOT NULL,
    record_id      text        NOT NULL,
    action         text        NOT NULL,
    old_data       jsonb,
    new_data       jsonb,
    changed_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_audit_user   FOREIGN KEY (actor_user_id) REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT ck_audit_action CHECK (action IN ('INSERT','UPDATE','DELETE','LOGIN','ACCESS'))
);
