// authz-matrix.mjs : read-only authorization review of the RUNNING app.
//   1. discovers every app/api/**/route.ts and its exported methods
//   2. logs in as patient / doctor / admin (synthetic accounts, password Demo@12345)
//   3. calls every GET route as anonymous + each role, using REAL case/appointment ids from your database
//   4. prints a status matrix, flags leaks and unprotected routes, scans JSON bodies for forbidden fields
// Run from the Next.js folder (the one with package.json) while `npm run dev` is running:
//     node scripts/authz-matrix.mjs                      (default http://localhost:3000)
//     node scripts/authz-matrix.mjs --base http://localhost:3000 --login /api/auth/login
// Only GET requests are sent. Write routes (POST/PUT/PATCH/DELETE) are listed but NOT called.
import fs from "node:fs";
import path from "node:path";
import pg from "pg";

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i > -1 ? process.argv[i + 1] : d; };
const BASE = arg("base", "http://localhost:3000").replace(/\/$/, "");
const PASSWORD = arg("password", "Demo@12345");
for (const f of [".env.local", ".env"]) if (fs.existsSync(f)) { process.loadEnvFile(f); break; }

// ---------- 1. discover routes
const apiRoot = ["app/api", "src/app/api"].map((p) => path.resolve(p)).find(fs.existsSync);
if (!apiRoot) { console.error("Cannot find app/api. Run this from the Next.js project folder."); process.exit(2); }
const routes = [];
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (/^route\.(ts|js|tsx|jsx)$/.test(e.name)) {
      const src = fs.readFileSync(p, "utf8");
      const methods = [...new Set([...src.matchAll(/export\s+(?:async\s+)?(?:function|const)\s+(GET|POST|PUT|PATCH|DELETE)\b/g)].map((m) => m[1]))];
      const segs = path.relative(apiRoot, path.dirname(p)).split(path.sep).filter((s) => s && !/^\(.*\)$/.test(s));
      routes.push({ segs, methods, template: "/api/" + segs.join("/") });
    }
  }
})(apiRoot);
routes.sort((a, b) => a.template.localeCompare(b.template));

// ---------- 2. real ids from the database
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, host: process.env.PGHOST, port: process.env.PGPORT && Number(process.env.PGPORT),
  database: process.env.PGDATABASE, user: process.env.PGUSER, password: process.env.PGPASSWORD });
const q = async (sql, p) => (await pool.query(sql, p)).rows[0];
const own = await q(`select c.case_id, a.appointment_id, du.email as doctor_email
  from medical_cases c join patients p using (patient_id) join users u on u.user_id = p.user_id
  join appointments a on a.case_id = c.case_id join doctors d on d.doctor_id = a.doctor_id join users du on du.user_id = d.user_id
  where u.email = 'patient01@mediconnect.test' and c.status = 'SUBMITTED' limit 1`);
const other = await q(`select c.case_id, a.appointment_id from medical_cases c join patients p using (patient_id) join users u on u.user_id = p.user_id
  join appointments a on a.case_id = c.case_id where u.email = 'patient02@mediconnect.test' and c.status = 'SUBMITTED' limit 1`);
await pool.end();
if (!own || !other) { console.error("Seed data not found (patient01/patient02 active cases). Is the seed loaded?"); process.exit(2); }
const RANDOM = "00000000-0000-4000-8000-000000000000";

// ---------- 3. identities
const who = {
  anon: null,
  patient: "patient01@mediconnect.test",
  doctor: own.doctor_email,        // the doctor who HAS an appointment for patient01's case
  admin: "admin@mediconnect.test",
};
const loginPath = arg("login", routes.find((r) => /auth\/login/.test(r.template))?.template ?? "/api/auth/login");
const cookies = { anon: "" };
for (const [role, email] of Object.entries(who)) {
  if (!email) continue;
  const res = await fetch(BASE + loginPath, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }) });
  const set = res.headers.getSetCookie?.() ?? [];
  cookies[role] = set.map((c) => c.split(";")[0]).join("; ");
  console.log(`login ${role.padEnd(7)} ${email.padEnd(28)} -> HTTP ${res.status}${cookies[role] ? "" : "  (NO session cookie!)"}`);
}

// ---------- 4. probes
const kind = (t) => (/case/.test(t) ? "case" : /appointment/.test(t) ? "appt" : "other");
const idsFor = (k, label) => {
  const good = { case: own.case_id, appt: own.appointment_id, other: RANDOM }[k];
  const bad = { case: other.case_id, appt: other.appointment_id, other: RANDOM }[k];
  return label === "bad" ? bad : good;
};
function probes(r) {
  const dynamic = r.segs.some((s) => /^\[.*\]$/.test(s));
  const k = kind(r.template);
  const fill = (label) => "/api/" + r.segs.map((s) => (/^\[.*\]$/.test(s) ? idsFor(k, label) : s)).join("/");
  if (!dynamic) return [["anon", "anon", fill()], ["patient", "patient", fill()], ["doctor", "doctor", fill()], ["admin", "admin", fill()]];
  return [["anon", "anon", fill("good")], ["patient", "patient(own)", fill("good")], ["patient", "patient(other)", fill("bad")],
          ["doctor", "doctor(auth)", fill("good")], ["doctor", "doctor(unauth)", fill("bad")], ["admin", "admin", fill("good")]];
}
const keysOf = (v, acc = new Set()) => { if (Array.isArray(v)) v.forEach((x) => keysOf(x, acc)); else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { acc.add(k); keysOf(x, acc); } return acc; };
const CLINICAL = ["narrative", "symptoms", "vitals", "anonymised_summary", "medical_history_flags", "attachments", "title"];
const IDENTITY = ["email", "phone", "full_name", "patient_name", "date_of_birth"];
const isDeny = (s) => s === 401 || s === 403 || s === 404;
const fails = [], reviews = [];

console.log(`\nDiscovered ${routes.length} API routes under ${path.relative(process.cwd(), apiRoot)}\n`);
for (const r of routes) {
  const writes = r.methods.filter((m) => m !== "GET");
  if (!r.methods.includes("GET")) { console.log(`${("(" + r.methods.join(",") + ") " + r.template).padEnd(52)} write-only, not called`); continue; }
  const line = [];
  for (const [role, label, url] of probes(r)) {
    const res = await fetch(BASE + url, { headers: cookies[role] ? { cookie: cookies[role] } : {} });
    const text = await res.text();
    let body; try { body = JSON.parse(text); } catch { body = null; }
    const keys = body ? keysOf(body) : new Set();
    const tag = `${r.template} as ${label}`;
    line.push(`${label}:${res.status}`);
    if (res.status >= 500) fails.push(`${tag} -> HTTP ${res.status} (server error)`);
    for (const bad of ["password_hash", "password"]) if (keys.has(bad)) fails.push(`${tag} exposes "${bad}"`);
    const isCase = /case/.test(r.template), isAdminRoute = /(^|\/)admin(\/|$)/.test(r.template);
    if (label === "anon" && res.status === 200 && !/\/health$/.test(r.template)) (/admin|case|appointment|consultation|patient|notification|audit|\/me$/.test(r.template) ? fails : reviews).push(`${tag} is reachable WITHOUT login`);
    if (isAdminRoute && (label.startsWith("patient") || label.startsWith("doctor")) && !isDeny(res.status)) fails.push(`${tag} -> ${res.status} (admin-only route open to ${label})`);
    if ((label === "patient(other)" || label === "doctor(unauth)") && res.status === 200) fails.push(`${tag} -> 200 (can read someone else's record)`);
    if (label.startsWith("admin") && isCase && res.status === 200) { const leaked = CLINICAL.filter((c) => keys.has(c)); if (leaked.length) fails.push(`${tag} exposes clinical fields: ${leaked.join(", ")}`); }
    if (label === "doctor(auth)" && isCase && res.status === 200) { const leaked = IDENTITY.filter((c) => keys.has(c)); if (leaked.length) reviews.push(`${tag} returns identity fields: ${leaked.join(", ")} (confirm intended)`); }
  }
  console.log(`${("GET " + r.template).padEnd(52)}${writes.length ? " [also " + writes.join(",") + "] " : " "}${line.join("  ")}`);
}

// ---------- 5. PAGES (server-side guard). A page that returns 200 to the wrong role is only "protected" by browser code.
const appRoot = ["app", "src/app"].map((p) => path.resolve(p)).find(fs.existsSync);
const pages = [];
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== "api") walk(p); }
    else if (/^page\.(tsx|jsx|ts|js)$/.test(e.name)) {
      const segs = path.relative(appRoot, path.dirname(p)).split(path.sep).filter((s) => s && !/^\(.*\)$/.test(s));
      if (!segs.some((s) => /^\[.*\]$/.test(s))) pages.push("/" + segs.join("/"));
    }
  }
})(appRoot);
pages.sort();
console.log(`\nDiscovered ${pages.length} static pages (status per role; 3xx/401/403/404 = denied, 200 = page served)\n`);
const denied = (s) => (s >= 300 && s < 400) || s === 401 || s === 403 || s === 404;
for (const pg of pages) {
  const st = {};
  for (const role of ["anon", "patient", "doctor", "admin"]) {
    const res = await fetch(BASE + pg, { redirect: "manual", headers: cookies[role] ? { cookie: cookies[role] } : {} });
    st[role] = res.status; await res.arrayBuffer();
    if (res.status >= 500) fails.push(`page ${pg} as ${role} -> HTTP ${res.status}`);
  }
  console.log(`PAGE ${pg.padEnd(46)} ${Object.entries(st).map(([r, s]) => `${r}:${s}`).join("  ")}`);
  const area = /(^|\/)admin(\/|$)/.test(pg) ? "admin" : /(^|\/)doctor(\/|$)/.test(pg) ? "doctor" : /(^|\/)patient(\/|$)/.test(pg) ? "patient" : null;
  const protectedWord = /dashboard|appointment|case|profile|consultation|availability|admin/.test(pg);
  if (area === "admin") for (const r of ["anon", "patient", "doctor"]) if (!denied(st[r])) fails.push(`page ${pg} served (HTTP ${st[r]}) to ${r}: no server-side guard`);
  if (area === "doctor") for (const r of ["anon", "patient"]) if (!denied(st[r])) fails.push(`page ${pg} served (HTTP ${st[r]}) to ${r}: no server-side guard`);
  if (area === "patient") { if (!denied(st.anon)) fails.push(`page ${pg} served to anon: no server-side guard`);
                             if (!denied(st.doctor)) reviews.push(`page ${pg} served to a doctor (confirm intended)`); }
  if (!area && protectedWord && !denied(st.anon)) fails.push(`page ${pg} served to anon: no server-side guard`);
}

console.log(`\n=== RESULT: ${fails.length} FAIL, ${reviews.length} REVIEW ===`);
fails.forEach((f) => console.log("FAIL   " + f));
reviews.forEach((f) => console.log("REVIEW " + f));
if (!fails.length) console.log("No leaks, unprotected sensitive routes or server errors found by this check. (It cannot prove the absence of every flaw.)");
process.exit(fails.length ? 1 : 0);
