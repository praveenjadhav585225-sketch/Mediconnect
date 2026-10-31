-- Day 3 only (functions, triggers, views). Use this on a database that already has Stage 1 loaded.
--   psql -U postgres -d mediconnect -f database/postgres/run_day3.sql
\set ON_ERROR_STOP on
\ir migrations/007_functions_procedures.sql
\ir migrations/008_triggers.sql
\ir migrations/009_views.sql
\echo 'Day 3 objects created.'
