-- Loads all synthetic data (run AFTER run_all.sql).
--   psql -U postgres -d mediconnect -f database/postgres/run_seed.sql
\set ON_ERROR_STOP on
\ir seed/01_reference_and_users.sql
\ir seed/02_cases.sql
\ir seed/03_slots_appointments.sql
\echo 'Seed loaded.'
