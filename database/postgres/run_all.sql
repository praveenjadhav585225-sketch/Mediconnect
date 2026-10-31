-- Applies every migration in order. Run from anywhere:
--   psql -U postgres -d mediconnect -v app_password="YourAppPw" -f database/postgres/run_all.sql
\set ON_ERROR_STOP on
\ir migrations/001_extensions.sql
\ir migrations/002_core_tables.sql
\ir migrations/003_clinical_tables.sql
\ir migrations/004_indexes.sql
\ir migrations/005_alter_and_drop_examples.sql
\ir migrations/006_app_role.sql
\echo 'Migrations applied.'
