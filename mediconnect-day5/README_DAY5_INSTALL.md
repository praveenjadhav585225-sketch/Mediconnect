# MediConnect Day 5 – Frontend and role dashboards

## Installation
1. Extract this ZIP into `C:\Users\DELL\dev\mediconnect` and merge the `web` folder.
2. Back up your existing Day 4 files first. This overlay replaces `web/app/page.tsx`, `web/app/layout.tsx`, and `web/app/api/admin/dashboard/route.ts`.
3. From `web`, install MongoDB driver:
   `npm install mongodb`
4. Add this variable to `web/.env.local` without removing existing variables:
   `MONGODB_URI=mongodb://127.0.0.1:27017/mediconnect`
5. Run `npm run typecheck`, then `npm run build`.

## Included
- Login page and role-aware navigation.
- Patient, doctor and admin dashboards.
- Patient doctor directory, appointment list and case list.
- Doctor appointment and consultation lists.
- Admin user, doctor and appointment overview.
- Protected APIs for dashboard data, doctor directory, appointments and patient cases.
- Appointment booking and cancellation call existing PostgreSQL functions.

## Important limitations
- Day 5 provides read/list workflows and a minimal patient case-submission endpoint.
- It does not yet implement doctor availability editing, doctor verification mutations, consultation note editing, reviews, or semantic case matching. These require dedicated workflow and security tests.
- Semantic matching and the DRAFT_INCOMPLETE recovery/privacy tests belong to Day 6.
- Use synthetic demo records only. Do not enter real patient information.
- This overlay does not change PostgreSQL schema.
