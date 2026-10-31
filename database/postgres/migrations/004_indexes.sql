-- 004_indexes.sql
-- PK / UNIQUE constraints already create their own B-tree indexes. These are the extra ones.

-- B-tree: foreign-key lookups and dashboards
CREATE INDEX idx_appt_patient        ON appointments (patient_id, status);
CREATE INDEX idx_appt_doctor_status  ON appointments (doctor_id, status);
CREATE INDEX idx_cases_patient       ON medical_cases (patient_id, created_at DESC);
CREATE INDEX idx_match_query         ON case_match_log (query_case_id);
CREATE INDEX idx_match_doctor_time   ON case_match_log (doctor_id, created_at DESC);
CREATE INDEX idx_audit_record        ON audit_log (table_name, record_id);
CREATE INDEX idx_audit_time          ON audit_log (changed_at DESC);

-- Partial: patients only ever search for slots that are still free
CREATE INDEX idx_slots_available ON time_slots (doctor_id, start_ts) WHERE status = 'AVAILABLE';
-- Partial: bookable doctors by specialization
CREATE INDEX idx_doctors_verified_spec ON doctors (specialization_id) WHERE verification_status = 'VERIFIED';
-- Partial: the historical pool that semantic matching is allowed to search
CREATE INDEX idx_cases_matching_pool ON medical_cases (specialization_id)
    WHERE consent_for_matching AND status IN ('RESOLVED','CLOSED');

-- GIN: full-text doctor search
CREATE INDEX idx_doctors_search ON doctors USING gin (search_vector);

-- HNSW: approximate nearest neighbour for cosine distance (<=>)
CREATE INDEX idx_embeddings_hnsw ON case_embeddings
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
