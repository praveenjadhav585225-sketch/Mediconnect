# MediConnect — Day 4: Backend API and Authentication

This package adds the FastAPI embedding service and Next.js API layer. It does not rerun or modify Day 1–3 database migrations, seed data, bookings, or embeddings.

## What Day 4 adds

1. FastAPI embedding service using `all-MiniLM-L6-v2` to generate 384-dimensional embeddings.
2. Next.js App Router API with login, logout, current-user, health-check, and admin-dashboard endpoints.
3. Argon2id password verification.
4. JWT-based sessions using HTTP-only cookies.
5. Input validation and role-based access control.

## Important assumptions

- PostgreSQL already contains the Day 1–3 schema.
- The `users` table contains `user_id`, `email`, `password_hash`, `role`, and `is_active`.
- Supported roles: `PATIENT`, `DOCTOR`, and `ADMIN`.
- Existing synthetic user passwords are stored as Argon2id hashes.
- The Next.js application is located in the `web` directory.
- The embedding endpoint generates embeddings only. It does not diagnose conditions or recommend treatment.

## A. FastAPI embedding service

From the project root:

```powershell
cd C:\Users\DELL\dev\mediconnect
.\embedding-service\.venv\Scripts\Activate.ps1
python -m pip install -r embedding-service\requirements-day4.txt
```

Create the local environment file if it does not already exist:

```powershell
Copy-Item embedding-service\.env.day4.example embedding-service\.env
```

Configure a strong `EMBEDDING_API_KEY` in `embedding-service\.env`.

Start the service:

```powershell
uvicorn app.main:app --app-dir embedding-service --host 127.0.0.1 --port 8001
```

Health endpoint:

```text
http://127.0.0.1:8001/health
```

## B. FastAPI tests

Run from the project root:

```powershell
python -m pytest embedding-service\tests -q
```

Verified result:

```text
4 passed in 22.16s
```

Test the embedding endpoint using the configured API key:

```powershell
$headers = @{ "X-API-Key" = "YOUR_EMBEDDING_API_KEY" }

$body = @{
    text = "Patient reports recurring chest discomfort and shortness of breath."
} | ConvertTo-Json

$result = Invoke-RestMethod `
    -Method Post `
    -Uri "http://127.0.0.1:8001/embed" `
    -Headers $headers `
    -ContentType "application/json" `
    -Body $body

$result.dimensions
$result.embedding.Count
```

Expected embedding dimensions: `384`.

## C. Next.js configuration

Open a separate PowerShell terminal:

```powershell
cd C:\Users\DELL\dev\mediconnect\web
npm install
```

Configure `web\.env.local`:

```text
DATABASE_URL=postgresql://mediconnect_app:YOUR_PASSWORD@localhost:5432/mediconnect
JWT_SECRET=YOUR_RANDOM_SECRET_AT_LEAST_32_CHARACTERS
EMBEDDING_SERVICE_URL=http://127.0.0.1:8001
EMBEDDING_API_KEY=YOUR_EMBEDDING_API_KEY
```

Important:
- Use the restricted `mediconnect_app` database account.
- URL-encode special characters in the database password.
- Use a randomly generated JWT secret of at least 32 characters.
- Use the same embedding API key in both services.
- Never commit `.env.local` or `.env`.

Start Next.js:

```powershell
npm run dev
```

Application URL:

```text
http://localhost:3000
```

## D. API endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/api/health` | Database health check |
| POST | `/api/auth/login` | Authenticate user |
| GET | `/api/auth/me` | Retrieve current session |
| POST | `/api/auth/logout` | Clear session |
| GET | `/api/admin/dashboard` | Admin-only dashboard |

## E. Synthetic demo accounts

All seeded accounts use the synthetic demo password:

```text
Demo@12345
```

| Role | Email |
|---|---|
| Admin | `admin@mediconnect.test` |
| Doctor | `doctor01@mediconnect.test` |
| Patient | `patient01@mediconnect.test` |

The `patient30` account is inactive and should not be used for login testing.

These credentials are for local synthetic-data development only.

## F. Authentication verification

### Patient login

```powershell
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

$body = @{
    email = "patient01@mediconnect.test"
    password = "Demo@12345"
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri "http://localhost:3000/api/auth/login" `
    -Method POST `
    -ContentType "application/json" `
    -Body $body `
    -WebSession $session
```

### Current user

```powershell
Invoke-RestMethod `
    -Uri "http://localhost:3000/api/auth/me" `
    -Method GET `
    -WebSession $session
```

### Logout

```powershell
Invoke-RestMethod `
    -Uri "http://localhost:3000/api/auth/logout" `
    -Method POST `
    -WebSession $session
```

After logout, `/api/auth/me` should return HTTP 401.

### Role-based access

A patient attempting to access the admin dashboard should receive HTTP 403.

An authenticated admin should receive a successful response from:

```text
GET /api/admin/dashboard
```

## G. Verified Day 4 results

| Verification | Result |
|---|---|
| FastAPI automated tests | 4/4 passed |
| PostgreSQL connection | Connected |
| Next.js health endpoint | HTTP 200 |
| Argon2id password verification | Passed |
| Patient login | Successful |
| JWT session verification | Successful |
| Logout | Successful |
| Access after logout | HTTP 401 |
| Patient access to admin dashboard | HTTP 403 |
| Admin login | Successful |
| Admin dashboard access | Successful |

These results are from the local development environment.

## H. Day 6 integrated workflow

Start PostgreSQL, MongoDB, and the embedding service before starting Next.js.
The Day 6 case workflow writes the MongoDB case document first, requests a
local 384-dimensional embedding, and then commits the PostgreSQL case header
and pgvector row in one transaction. If the PostgreSQL transaction fails, the
MongoDB document is removed; a failed embedding request prevents either
database write.

Additional verification commands:

```powershell
python database\scripts\verify_integration.py
python database\scripts\verify_saga.py
npm --prefix web run typecheck
npm --prefix web run build
```

Use `/register` for a synthetic patient account, then test login, appointment
booking/cancellation, and case submission from the patient portal. Doctors can
request anonymised similar resolved cases from their consultation page. Matching
is informational only and requires the case's consent flag; no real patient
data should be entered.

## H. GitHub submission

From the project root:

```powershell
cd C:\Users\DELL\dev\mediconnect
git status --short
```

Verify that the following are not staged:

- `.env`
- `.env.local`
- `node_modules`
- `.next`
- `.venv`
- Private keys or generated secrets

After reviewing the staged files:

```powershell
git diff --cached --check
git diff --cached --stat
```

Commit and push:

```powershell
git commit -m "feat(api): add FastAPI embedding service and Next.js authentication APIs"
git push origin main
```

## Day 4 deliverables

- FastAPI embedding service.
- FastAPI automated tests.
- Next.js API scaffold.
- PostgreSQL connection.
- Argon2id authentication.
- JWT session management.
- Role-based access control.
- README documentation and GitHub commit.

**Day 4 verification is successful for the tests listed above. GitHub submission remains pending until the commit and push are completed.**