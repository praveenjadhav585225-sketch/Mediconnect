-- 005_alter_and_drop_examples.sql
-- Real schema evolution that also demonstrates ALTER and DROP for the course requirement.

-- ALTER TABLE ... ADD COLUMN : track last login for the admin user overview
ALTER TABLE users ADD COLUMN last_login_at timestamptz;

-- ALTER TABLE ... ADD CONSTRAINT : a doctor cannot be VERIFIED without a licence of sensible length
ALTER TABLE doctors ADD CONSTRAINT ck_doctors_license_len CHECK (length(btrim(license_number)) >= 5);

-- ALTER TABLE ... ALTER COLUMN : bio default so doctor cards never show NULL
ALTER TABLE doctors ALTER COLUMN bio SET DEFAULT '';

-- CREATE then DROP : a throw-away table and index, to show DROP safely
CREATE TABLE tmp_migration_probe (id integer PRIMARY KEY, note text);
CREATE INDEX idx_tmp_probe_note ON tmp_migration_probe (note);
DROP INDEX idx_tmp_probe_note;
DROP TABLE tmp_migration_probe;
