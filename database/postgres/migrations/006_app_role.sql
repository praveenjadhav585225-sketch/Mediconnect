-- 006_app_role.sql
-- The web app connects as a limited role, not as the postgres superuser (least privilege).
-- Run with:  psql -v app_password='...' -f run_all.sql
SELECT format('CREATE ROLE mediconnect_app LOGIN PASSWORD %L', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mediconnect_app') \gexec
SELECT format('ALTER ROLE mediconnect_app PASSWORD %L', :'app_password') \gexec

GRANT USAGE ON SCHEMA public TO mediconnect_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mediconnect_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mediconnect_app;
-- the audit log is append-only for the app
REVOKE UPDATE, DELETE ON audit_log FROM mediconnect_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mediconnect_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO mediconnect_app;
