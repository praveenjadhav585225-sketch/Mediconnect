-- DEV ONLY: wipes every table in the public schema. Then re-run run_all.sql.
\set ON_ERROR_STOP on
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
\echo 'Schema reset.'
