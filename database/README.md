# MediConnect: Database Layer (Stage 1 / Day 2)

PostgreSQL (relational + pgvector) and MongoDB (documents). All data is **synthetic**.
Demo password for every seeded account: `Demo@12345` (stored only as Argon2id hashes).

## One-time setup (Windows PowerShell, from the repo root `mediconnect\`)

```powershell
copy .env.example .env          # then edit .env: set PG_ADMIN_PASSWORD and choose a PGPASSWORD for the app role
.\embedding-service\.venv\Scripts\Activate.ps1
pip install -r database\requirements-db.txt
```

## PostgreSQL

```powershell
$env:PGPASSWORD = "<your postgres superuser password>"
psql -U postgres -d mediconnect -v app_password="<same value as PGPASSWORD in .env>" -f database/postgres/run_all.sql
psql -U postgres -d mediconnect -f database/postgres/run_seed.sql
psql -U postgres -d mediconnect -f database/postgres/run_tests.sql
```

Start over any time (DEV ONLY, deletes all data):
`psql -U postgres -d mediconnect -f database/postgres/reset.sql` then run the first two commands again.

## MongoDB

```powershell
mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/validators/create_collections.js
mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/indexes/create_indexes.js
mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/seed/seed_all.js
mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/tests/mongo_tests.js
mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/aggregations/pipelines.js
```

## Embeddings (real all-MiniLM-L6-v2, local CPU)

```powershell
python database\scripts\embed_cases.py            # embeds 70 synthetic case texts, 384-d, stores in pgvector
python database\scripts\check_connections.py      # PostgreSQL + pgvector + MongoDB health check
```

`--fake` exists only to test the pipeline without the model. Never use it for real similarity results.

## What is where

| Path | Purpose |
|---|---|
| `postgres/migrations/001-006` | extensions, tables, constraints, indexes, ALTER/DROP examples, least-privilege app role |
| `postgres/seed/` | synthetic users, doctors, cases, slots, appointments, consultations, reviews |
| `postgres/tests/` | 40 integrity tests, CRUD/JOIN/HAVING/subquery/FTS/index tests, pgvector tests |
| `postgres/tests/results/` | saved output from the last verified run |
| `mongodb/validators/` | `$jsonSchema` validators for 3 collections |
| `mongodb/indexes/` | unique, text and multikey indexes |
| `mongodb/aggregations/` | 6 aggregation pipelines |
| `synthetic-data/generate_seed.py` | deterministic generator for every seed file |
| `scripts/` | connection check, embedding loader, data-dictionary generator |

## Design notes

- **No trigger needed for slot/doctor consistency**: `appointments (slot_id, doctor_id)` is a composite FK to `time_slots`.
- **Case ownership is enforced by the database**: `appointments (case_id, patient_id)` is a composite FK to `medical_cases`.
- **One active booking per slot** via a partial unique index; cancelled rows free the slot.
- **No double-booked doctor time** via `EXCLUDE USING gist` on slot time ranges; overlapping weekly rules are blocked the same way.
- **Cross-database links** are plain ids (`medical_cases.mongo_detail_id`, `consultations.notes_doc_id`). No text is duplicated.
- **Known limitation**: PostgreSQL and MongoDB cannot share one transaction. The Day 6 saga (write order + `DRAFT_INCOMPLETE` + cleanup) covers it.

---

# Day 3: Advanced DBMS features

Apply to a database that already has Stage 1 loaded (no data is touched):

```powershell
psql -U postgres -d mediconnect -f database/postgres/run_day3.sql
psql -U postgres -d mediconnect -f database/postgres/tests/test_advanced.sql
python database\postgres\tests\concurrency_test.py
psql -U postgres -d mediconnect -f database/postgres/tests/demo_queries.sql
```

| Feature | Where |
|---|---|
| Transactions + row locking | `book_appointment` (locks patient row, then slot row, always in that order) |
| Stored functions / procedures | `generate_slots`, `book_appointment`, `start_consultation`, `find_similar_cases` (functions); `cancel_appointment`, `complete_consultation` (procedures) |
| Triggers | audit logging on 6 tables, slot-status sync, legal status transitions, doctor-must-be-verified, review-after-completion, `updated_at` |
| Views | `v_doctor_directory`, `v_appointment_details`, `v_doctor_workload`, `v_daily_appointments`, `v_case_trends`, `v_admin_case_metadata` |
| Materialized view | `mv_monthly_stats` + `refresh_dashboard_stats()` |
| Indexes | B-tree, partial, GIN (full-text), HNSW (vector cosine) |
| Vector similarity | `find_similar_cases(doctor, case, k, min_score, same_specialization)` |

**Error codes** raised by the routines (the API maps these to HTTP responses):
`MC001` slot taken, `MC002` doctor not verified, `MC003` slot in the past, `MC004` illegal state change,
`MC005` not found, `MC006` account deactivated, `MC007` not allowed, `MC008` patient time clash,
`MC009` review before completion, `MC010` case has no embedding yet.

**Audit actor:** the routines call `set_actor(user_id)` so audit rows record who acted. API code that updates tables directly
should run `SELECT set_actor('<user uuid>')` first inside the same transaction.

**Time zone:** open every application connection with `SET timezone = 'Asia/Kolkata'`, because slot generation converts local times.
