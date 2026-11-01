# Final Presentation and Viva Guide

## Suggested presentation sequence

1. Problem statement: safe telemedicine workflow demonstration using synthetic
   data.
2. Objectives and user roles.
3. System architecture and request flow.
4. PostgreSQL schema, constraints, functions, triggers, and views.
5. MongoDB document validation and separation of clinical details.
6. Embedding service and pgvector similarity flow.
7. Patient booking/cancellation and case submission demonstration.
8. Doctor matching and admin aggregate dashboard.
9. QA results, privacy checks, and known limitations.
10. Future work: consultation mutation UI, reviews, verification, and
    availability administration.

## Demonstration checklist

- Start PostgreSQL and MongoDB.
- Start FastAPI on port 8001.
- Start Next.js on port 3000.
- Show login and role-specific navigation.
- Show patient doctor directory and appointment booking.
- Cancel a synthetic appointment and show the slot is released.
- Submit a synthetic case with matching consent.
- Show the PostgreSQL/MongoDB/pgvector consistency output.
- Show doctor semantic matches for an assigned case.
- Show admin aggregate metrics without patient-identifying case fields.

## Viva questions and short answers

### Why use both PostgreSQL and MongoDB?

PostgreSQL provides strong relational integrity and transactional scheduling.
MongoDB stores variable-shape case and consultation documents without forcing
all clinical detail into relational columns.

### Why is the embedding stored in PostgreSQL?

The project already uses PostgreSQL for case ownership and workflow rules.
pgvector keeps similarity search close to those authorization and consent
checks and supports indexed cosine search.

### How is double booking prevented?

The booking function locks patient and slot rows in a fixed order. A partial
unique index permits only one non-cancelled appointment per slot, and triggers
keep slot status synchronized.

### What happens if MongoDB succeeds but PostgreSQL fails?

The API rolls back the PostgreSQL transaction and deletes the inserted
MongoDB document. The read-only saga verifier detects any non-draft mismatch.

### How is privacy enforced?

Role checks run at every protected route. Admin case responses use
`v_admin_case_metadata`, which omits names, titles, narratives, email, and
phone. Doctor matching requires an assigned active appointment and only
returns anonymised match metadata.

### Does semantic matching diagnose a patient?

No. It ranks similar historical synthetic cases for informational context only.
It does not diagnose, recommend treatment, or replace a clinician.

### What is the password strategy?

Passwords are verified using Argon2id. Sessions use signed JWTs in HTTP-only
cookies, with a minimum 32-character JWT secret.

### What remains outside the submission scope?

Doctor availability editing, verification mutations, consultation-note editing,
reviews, and frontend consultation start/complete controls are not exposed in
the current UI/API and are explicitly documented as future work.
