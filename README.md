# MediConnect

MediConnect is a telemedicine platform with role-based portals, appointment
workflows, PostgreSQL clinical records, MongoDB case details, and an embedding
service for semantic case matching.

## Current status

The Day 4 backend and Day 5 web application are implemented. The web app
includes patient, doctor, and admin portals, authentication, protected APIs,
doctor and appointment browsing, case submission, and appointment
book/cancel workflows.

Day 5 installation and environment configuration are documented in
[mediconnect-day5/README_DAY5_INSTALL.md](mediconnect-day5/README_DAY5_INSTALL.md).
The Day 4 API and embedding-service setup is documented in
[README_DAY4.md](README_DAY4.md).

## Validation

From the repository root:

```powershell
python -m pytest embedding-service\tests -q
npm --prefix web run typecheck
npm --prefix web run build
```

The database-backed workflows require the configured PostgreSQL and MongoDB
services. Use synthetic demo records only.

**Safety note:** semantic matching provides similar historical case
descriptions for informational context only. It does not diagnose conditions or
recommend treatment. All data in this project is synthetic.
