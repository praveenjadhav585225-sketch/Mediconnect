-- Runs every database test. Everything is rolled back, so the data is left unchanged.
--   psql -U postgres -d mediconnect -f database/postgres/run_tests.sql
\ir tests/test_constraints.sql
\ir tests/test_crud_indexes.sql
\ir tests/test_advanced.sql
\ir tests/test_vector.sql
