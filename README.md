# MediConnect

MediConnect is a synthetic-data telemedicine and clinical-case integration
platform developed as a DBMS mini-project. It combines role-based web
portals, appointment workflows, PostgreSQL transactional data, MongoDB
clinical-detail documents, and local semantic case matching with pgvector.

Semantic matching is informational only. It displays similar historical
synthetic cases and never diagnoses a condition or recommends treatment.

## 1. Objectives

- Provide authenticated patient, doctor, and administrator workflows.
- Store relational identity, scheduling, and workflow data in PostgreSQL.
- Store flexible case narratives and consultation documents in MongoDB.
- Generate local 384-dimensional `all-MiniLM-L6-v2` embeddings.
- Use pgvector cosine similarity for consent-aware doctor case matching.
- Demonstrate constraints, transactions, locking, triggers, views, indexes,
  audit logging, and cross-database consistency checks.

## 2. Technology stack

| Layer | Technology |
|---|---|
| Frontend and API | Next.js 15 App Router, React 19, TypeScript |
| Authentication | Argon2id password verification, JWT HTTP-only cookie sessions |
| Relational database | PostgreSQL with `vector` and `btree_gist` extensions |
| Document database | MongoDB with JSON Schema validators and indexes |
| Embeddings | FastAPI, Sentence Transformers, `all-MiniLM-L6-v2`, 384 dimensions |
| Validation | Zod (TypeScript), Pydantic (Python), PostgreSQL constraints |
| Testing | pytest, TypeScript compiler, Next.js production build, API smoke tests |

## 3. System architecture

```text
Browser
  |
  v
Next.js web app (port 3000)
  |-- JWT session and role authorization
  |-- PostgreSQL: users, schedules, appointments, cases, embeddings
  |-- MongoDB: case_details, consultation_notes, notifications
  |
  +--> FastAPI embedding service (port 8001)
          |
          +--> local all-MiniLM-L6-v2 model
```

Detailed architecture and data-flow notes are in
[docs/architecture.md](docs/architecture.md).

## 4. Database design

### PostgreSQL

PostgreSQL stores users, patient/doctor profiles, specializations,
availability rules, time slots, appointments, medical-case headers,
pgvector embeddings, consultations, reviews, match logs, and audit records.
Database functions enforce booking, cancellation, consultation, and semantic
matching rules. Partial unique indexes prevent double booking; exclusion
constraints prevent overlapping doctor slots and availability rules.

### MongoDB

MongoDB stores flexible `case_details`, `consultation_notes`, and
`notifications` documents. `case_details` contains the narrative and
symptoms; patient identity is kept in PostgreSQL. JSON Schema validation,
unique case identifiers, text indexes, and multikey symptom indexes are
created by the scripts in `database/mongodb`.

### pgvector

`case_embeddings.embedding` is `vector(384)`. Embeddings are generated
locally, stored with a SHA-256 text hash and model name, and searched with
cosine distance. The PostgreSQL `find_similar_cases` function requires an
authorized doctor appointment, consent on historical cases, and logs matches.

See [docs/database-schema.md](docs/database-schema.md) and the generated
[data dictionary](docs/05-data-dictionary.md).

## 5. Installation and setup

### Prerequisites

- Windows PowerShell
- Node.js 20 or newer
- Python 3.11 or newer
- PostgreSQL with `psql`
- MongoDB with `mongosh`

### Configure local secrets

```powershell
Copy-Item .env.example .env
Copy-Item embedding-service\.env.day4.example embedding-service\.env
Copy-Item web\.env.local.example web\.env.local
```

Set local passwords and secrets in those ignored files. Use the same strong
`EMBEDDING_API_KEY` in `embedding-service\.env` and `web\.env.local`. Never
commit `.env`, `.env.local`, database passwords, API keys, or JWT secrets.

### Install dependencies

```powershell
.\embedding-service\.venv\Scripts\Activate.ps1
python -m pip install -r embedding-service\requirements-day4.txt
npm --prefix web install
```

### Initialize databases with synthetic data

```powershell
$env:PGPASSWORD = "<postgres-admin-password>"
psql -U postgres -d mediconnect -v app_password="<app-password>" -f database\postgres\run_all.sql
psql -U postgres -d mediconnect -f database\postgres\run_seed.sql

mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/validators/create_collections.js
mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/indexes/create_indexes.js
mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/seed/seed_all.js

python database\scripts\embed_cases.py
```

### Start services

Terminal 1:

```powershell
uvicorn app.main:app --app-dir embedding-service --host 127.0.0.1 --port 8001
```

Terminal 2:

```powershell
npm --prefix web run dev
```

Open `http://localhost:3000`.

## 6. API documentation

| Method | Endpoint | Access | Purpose |
|---|---|---|---|
| GET | `/api/health` | Public | PostgreSQL health |
| POST | `/api/auth/login` | Public | Authenticate a user |
| POST | `/api/auth/register` | Public | Create a synthetic patient |
| GET | `/api/auth/me` | Authenticated | Read current session |
| POST | `/api/auth/logout` | Authenticated | Clear session |
| GET | `/api/patient/dashboard` | Patient | Patient metrics |
| GET | `/api/doctor/dashboard` | Doctor | Doctor workload |
| GET | `/api/admin/dashboard` | Admin | Aggregate metrics |
| GET | `/api/doctors` | Patient/Admin | Verified doctor directory |
| GET | `/api/doctors/:id/slots` | Patient | Available future slots |
| GET/POST | `/api/appointments` | Authenticated/Patient | List or book appointments |
| POST | `/api/appointments/:id/cancel` | Owner/Doctor/Admin | Cancel an appointment |
| GET | `/api/cases` | Patient/Doctor/Admin | Role-filtered cases |
| POST | `/api/cases` | Patient | Store case and embedding |
| GET | `/api/cases/:id/matches` | Doctor | Consent-aware semantic matches |

All request bodies are validated. Database business-rule errors are mapped
to explicit HTTP responses; unauthorized users receive 401/403 responses.

## 7. Synthetic demo credentials

These credentials are for local synthetic-data development only:

| Role | Email | Password |
|---|---|---|
| Admin | `admin@mediconnect.test` | `Demo@12345` |
| Doctor | `doctor01@mediconnect.test` | `Demo@12345` |
| Patient | `patient01@mediconnect.test` | `Demo@12345` |

Do not use real patient information.

## 8. Verification

```powershell
python -m pytest embedding-service\tests -q
npm --prefix web run typecheck
npm --prefix web run build
python database\scripts\check_connections.py
python database\scripts\verify_integration.py
python database\scripts\verify_saga.py
```

The Day 7 execution report records actual results:
[DAY7_QA_REPORT.md](DAY7_QA_REPORT.md).

## 9. Submission documents

- [Software Requirements Specification](docs/SRS.md)
- [Architecture and data flow](docs/architecture.md)
- [Database schema](docs/database-schema.md)
- [Presentation and viva guide](docs/presentation-viva.md)
- [Day 7 QA report](DAY7_QA_REPORT.md)
- [Patient dashboard screenshot](docs/patient-dashboard.png)
- [Doctor dashboard screenshot](docs/doctor-dashboard.png)
- [Admin dashboard screenshot](docs/admin-dashboard.png)
- [Day 4 setup and API notes](README_DAY4.md)
- [Day 5 installation notes](mediconnect-day5/README_DAY5_INSTALL.md)

## 10. Scope and limitations

Doctor availability editing, doctor verification mutations, consultation-note
editing, reviews, and frontend consultation start/complete controls are not
implemented in the current submission. They are not represented as completed
features in the QA report. The implemented consultation and semantic matching
database routines remain available for future workflow extensions.
