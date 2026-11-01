# MediConnect Day 7 QA Report

Date: 2026-11-01  
Environment: local Windows development environment  
Data policy: synthetic demo data only

## Automated and service checks

| ID | Test case | Expected result | Actual result |
|---|---|---|---|
| QA-001 | `npm --prefix web run typecheck` | TypeScript exits successfully | PASS |
| QA-002 | `npm --prefix web run build` | Production build completes | PASS |
| QA-003 | `python -m pytest embedding-service\tests -q` | Embedding tests pass | PASS: 4 passed |
| QA-004 | Database connection check | PostgreSQL, pgvector, and MongoDB available | PASS |
| QA-005 | PostgreSQL/MongoDB/pgvector consistency | No missing or orphan non-draft case records | PASS |
| QA-006 | Saga consistency check | Non-draft cases have MongoDB documents and 384-d vectors | PASS |

The existing `DRAFT_INCOMPLETE` fixture is intentionally excluded from the
non-draft consistency requirement.

## Authentication and authorization

| ID | Test case | Expected result | Actual result |
|---|---|---|---|
| QA-010 | Anonymous `GET /api/auth/me` | HTTP 401 | PASS: 401 |
| QA-011 | Patient, doctor, and admin synthetic login | HTTP 200 for each | PASS: 200 for each |
| QA-012 | Patient dashboard API | Patient receives HTTP 200 | PASS: 200 |
| QA-013 | Doctor dashboard API | Doctor receives HTTP 200 | PASS: 200 |
| QA-014 | Admin dashboard API | Admin receives HTTP 200 | PASS: 200 |
| QA-015 | Patient requests admin dashboard | HTTP 403 | PASS: 403 |
| QA-016 | Logout then `GET /api/auth/me` | Logout succeeds; subsequent request is HTTP 401 | PASS: 200 then 401 |
| QA-017 | Invalid registration payload | HTTP 400 with validation error | PASS: 400 |
| QA-018 | Anonymous appointment booking | HTTP 401 | PASS: 401 |

## Patient, doctor, and admin workflows

| ID | Test case | Expected result | Actual result |
|---|---|---|---|
| QA-020 | Patient dashboard in browser | Patient navigation and metrics render | PASS |
| QA-021 | Doctor dashboard in browser | Doctor navigation and metrics render | PASS |
| QA-022 | Admin dashboard in browser | Admin-only metrics render | PASS |
| QA-023 | Patient books an available synthetic slot | HTTP 201 and appointment created | PASS: 201 |
| QA-024 | Patient cancels the QA appointment | HTTP 200 and slot is released | PASS: 200 |
| QA-025 | Patient submits a synthetic case | MongoDB, PostgreSQL, and pgvector writes succeed | PASS: HTTP 201 |
| QA-026 | QA case cleanup | Only the known synthetic QA record is removed | PASS |

## Semantic matching and privacy

| ID | Test case | Expected result | Actual result |
|---|---|---|---|
| QA-030 | Doctor requests matches for an assigned embedded case | HTTP 200; response contains only match IDs, specialization, and scores | PASS: 200 with 5 matches |
| QA-031 | Doctor requests matches for an unassigned case | HTTP 403 | PASS: 403 |
| QA-032 | Admin reads case metadata | No patient name, title, narrative, email, or phone fields | PASS: none exposed |
| QA-033 | Cross-database consistency after case submission and cleanup | No missing or orphan records; vectors remain 384-dimensional | PASS |

## Screenshots captured

Browser screenshots were captured during this QA run for:

1. MediConnect login page.
2. Patient dashboard showing appointment metrics and patient navigation.
3. Doctor dashboard showing appointment metrics and doctor navigation.
4. Admin dashboard showing aggregate metrics and admin navigation.

The screenshots show synthetic names and aggregate/demo values only.

## Consultation workflow scope

The database contains consultation start and completion routines, and the
doctor consultation page successfully renders existing consultation records.
The current frontend/API does not expose start-consultation, complete-
consultation, or doctor-note mutation controls. Those mutation flows were not
claimed as tested and were not expanded during Day 7 because adding them would
introduce a new workflow beyond the existing verified implementation.

## Defect fixed during QA

The appointment cancellation API called the PostgreSQL `cancel_appointment`
procedure with `SELECT`, which produced PostgreSQL error `42809`. It was
changed to use `CALL`; the booking/cancellation workflow was then rerun
successfully with HTTP 201 and HTTP 200.

The local web and embedding-service API keys initially differed, causing a
case submission HTTP 503. The local-only environment configuration was aligned
without exposing or committing either secret. Case submission was rerun
successfully with HTTP 201.
