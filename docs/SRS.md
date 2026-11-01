# Software Requirements Specification

## 1. Purpose

MediConnect demonstrates a safe, synthetic-data telemedicine workflow backed by
relational and document databases. It is intended for academic DBMS
evaluation, not clinical use.

## 2. Users

- **Patient:** registers, signs in, views doctors, books/cancels appointments,
  and submits a case with optional matching consent.
- **Doctor:** signs in, views assigned appointments and consultations, and
  requests anonymised similar resolved cases for assigned cases.
- **Administrator:** views aggregate platform metrics and non-clinical case
  metadata.

## 3. Functional requirements

| ID | Requirement |
|---|---|
| FR-01 | Authenticate active users with Argon2id password verification. |
| FR-02 | Maintain role-specific HTTP-only JWT sessions. |
| FR-03 | Enforce patient, doctor, and admin authorization at API boundaries. |
| FR-04 | Register synthetic patient accounts transactionally. |
| FR-05 | List verified doctors and future available slots. |
| FR-06 | Book one available slot through a PostgreSQL locking function. |
| FR-07 | Cancel an owned appointment through a PostgreSQL procedure. |
| FR-08 | Store case headers in PostgreSQL and clinical details in MongoDB. |
| FR-09 | Generate and store 384-dimensional local embeddings in pgvector. |
| FR-10 | Return semantic matches only to an authorized doctor. |
| FR-11 | Prevent admin access to patient-identifying case details. |
| FR-12 | Provide health, consistency, and saga verification scripts. |

## 4. Non-functional requirements

- **Security:** validate input, hash passwords, use parameterized SQL, protect
  cookies, and never commit local credentials.
- **Privacy:** use synthetic data; separate patient identity from case detail;
  return metadata-only admin case views.
- **Consistency:** use database transactions, constraints, cleanup on
  cross-store failure, and explicit `DRAFT_INCOMPLETE` recovery semantics.
- **Performance:** use indexed directory, appointment, text, and vector paths.
- **Maintainability:** keep migrations, seed scripts, API routes, and QA
  verification commands reproducible.

## 5. Constraints and assumptions

- PostgreSQL, MongoDB, and the embedding service are local dependencies.
- PostgreSQL and MongoDB cannot share a transaction; the case saga handles
  the failure boundary.
- Similarity output is informational and must not be interpreted as diagnosis.
- Demo credentials are synthetic and must not be reused in production.

## 6. Acceptance criteria

The submission is acceptable when typecheck, production build, embedding tests,
service checks, consistency checks, role tests, appointment tests, case
submission, semantic authorization, and privacy tests pass as recorded in
[DAY7_QA_REPORT.md](../DAY7_QA_REPORT.md).

