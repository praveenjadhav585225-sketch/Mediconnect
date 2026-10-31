-- 002_core_tables.sql : identity, doctors, availability, slots

CREATE TABLE users (
    user_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email          text        NOT NULL,
    password_hash  text        NOT NULL,
    role           text        NOT NULL,
    is_active      boolean     NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_users_email      UNIQUE (email),
    CONSTRAINT ck_users_role       CHECK (role IN ('PATIENT','DOCTOR','ADMIN')),
    CONSTRAINT ck_users_email_lc   CHECK (email = lower(email)),
    CONSTRAINT ck_users_email_fmt  CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    -- argon2id / bcrypt hashes are long; a short value means plain text slipped in
    CONSTRAINT ck_users_pw_hash    CHECK (length(password_hash) >= 50)
);

CREATE TABLE patients (
    patient_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        uuid NOT NULL,
    full_name      text NOT NULL,
    date_of_birth  date NOT NULL,
    gender         text,
    phone          text,
    CONSTRAINT uq_patients_user  UNIQUE (user_id),
    CONSTRAINT fk_patients_user  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT ck_patients_name  CHECK (length(btrim(full_name)) >= 2),
    CONSTRAINT ck_patients_dob   CHECK (date_of_birth BETWEEN DATE '1900-01-01' AND CURRENT_DATE),
    CONSTRAINT ck_patients_gender CHECK (gender IS NULL OR gender IN ('MALE','FEMALE','OTHER')),
    CONSTRAINT ck_patients_phone CHECK (phone IS NULL OR phone ~ '^\+?[0-9]{10,15}$')
);

CREATE TABLE specializations (
    specialization_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name               text NOT NULL,
    description        text,
    CONSTRAINT uq_specializations_name UNIQUE (name),
    CONSTRAINT ck_specializations_name CHECK (length(btrim(name)) >= 3)
);

CREATE TABLE doctors (
    doctor_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid    NOT NULL,
    specialization_id   integer NOT NULL,
    full_name           text    NOT NULL,
    license_number      text    NOT NULL,
    experience_years    integer NOT NULL DEFAULT 0,
    consultation_fee    numeric(10,2) NOT NULL DEFAULT 0,
    bio                 text,
    verification_status text    NOT NULL DEFAULT 'PENDING',
    -- generated column: name weighted higher than bio for full-text ranking
    search_vector       tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(full_name,'')), 'A') ||
        setweight(to_tsvector('english', coalesce(bio,'')),       'B')
    ) STORED,
    CONSTRAINT uq_doctors_user    UNIQUE (user_id),
    CONSTRAINT uq_doctors_license UNIQUE (license_number),
    CONSTRAINT fk_doctors_user    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_doctors_spec    FOREIGN KEY (specialization_id) REFERENCES specializations(specialization_id),
    CONSTRAINT ck_doctors_name    CHECK (length(btrim(full_name)) >= 2),
    CONSTRAINT ck_doctors_exp     CHECK (experience_years BETWEEN 0 AND 70),
    CONSTRAINT ck_doctors_fee     CHECK (consultation_fee >= 0),
    CONSTRAINT ck_doctors_status  CHECK (verification_status IN ('PENDING','VERIFIED','REJECTED','SUSPENDED'))
);

CREATE TABLE availability_rules (
    rule_id        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id      uuid     NOT NULL,
    day_of_week    smallint NOT NULL,          -- 0 = Sunday ... 6 = Saturday
    start_time     time     NOT NULL,
    end_time       time     NOT NULL,
    slot_minutes   smallint NOT NULL DEFAULT 30,
    CONSTRAINT fk_rules_doctor FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    CONSTRAINT ck_rules_dow    CHECK (day_of_week BETWEEN 0 AND 6),
    CONSTRAINT ck_rules_time   CHECK (end_time > start_time),
    CONSTRAINT ck_rules_slot   CHECK (slot_minutes IN (15,20,30,45,60)),
    -- same doctor, same weekday, overlapping time ranges are rejected
    CONSTRAINT ex_rules_no_overlap EXCLUDE USING gist (
        doctor_id WITH =,
        day_of_week WITH =,
        timerange(start_time, end_time) WITH &&
    )
);

CREATE TABLE time_slots (
    slot_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id  uuid        NOT NULL,
    start_ts   timestamptz NOT NULL,
    end_ts     timestamptz NOT NULL,
    status     text        NOT NULL DEFAULT 'AVAILABLE',
    CONSTRAINT fk_slots_doctor FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    CONSTRAINT ck_slots_time   CHECK (end_ts > start_ts),
    CONSTRAINT ck_slots_status CHECK (status IN ('AVAILABLE','BOOKED','BLOCKED')),
    CONSTRAINT uq_slots_doctor_start UNIQUE (doctor_id, start_ts),
    -- needed as the target of the composite FK from appointments
    CONSTRAINT uq_slots_id_doctor    UNIQUE (slot_id, doctor_id),
    CONSTRAINT ex_slots_no_overlap EXCLUDE USING gist (
        doctor_id WITH =,
        tstzrange(start_ts, end_ts) WITH &&
    )
);
