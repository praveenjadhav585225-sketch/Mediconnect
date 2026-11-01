// db-check.mjs : finds out WHY the Next.js app cannot reach PostgreSQL. Prints variable NAMES only, never passwords.
// Run from the Next.js project folder (the one with package.json):   node scripts/db-check.mjs
import fs from "node:fs";
import pg from "pg";

const envFile = [".env.local", ".env"].find((f) => fs.existsSync(f));
console.log("working folder :", process.cwd());
console.log("env file found :", envFile ?? "NONE (Next.js reads .env.local / .env from THIS folder, not the repo root)");
if (envFile) process.loadEnvFile(envFile);

const names = ["DATABASE_URL", "PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD", "DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD"];
console.log("variables set  :", names.filter((n) => process.env[n]).join(", ") || "NONE");

const cfg = process.env.DATABASE_URL
  ? { connectionString: process.env.DATABASE_URL }
  : { host: process.env.PGHOST ?? process.env.DB_HOST ?? "localhost", port: Number(process.env.PGPORT ?? process.env.DB_PORT ?? 5432),
      database: process.env.PGDATABASE ?? process.env.DB_NAME, user: process.env.PGUSER ?? process.env.DB_USER,
      password: process.env.PGPASSWORD ?? process.env.DB_PASSWORD };
console.log("will connect as:", cfg.connectionString ? "(DATABASE_URL)" : `${cfg.user}@${cfg.host}:${cfg.port}/${cfg.database}`, "| password set:", Boolean(cfg.password ?? cfg.connectionString));

const pool = new pg.Pool({ ...cfg, connectionTimeoutMillis: 4000 });
try {
  const r = await pool.query("select current_user as me, (select count(*) from users) as users");
  console.log("RESULT         : CONNECTED as", r.rows[0].me, "| users in table:", r.rows[0].users);
} catch (e) {
  console.log("RESULT         : FAILED");
  console.log("  code    :", e.code ?? "(none)");
  console.log("  message :", e.message || "(empty)");
  const hint = { "28P01": "Wrong password for that user (check PGPASSWORD matches the mediconnect_app password).",
    "28000": "User not allowed / does not exist.", "3D000": "Database name wrong (should be mediconnect).",
    ECONNREFUSED: "PostgreSQL not reachable on that host/port.", "42P01": "Connected, but tables missing (wrong database?).",
    "42501": "Connected, but this role lacks privileges." }[e.code];
  if (hint) console.log("  hint    :", hint);
  if (!cfg.password && !cfg.connectionString) console.log("  hint    : no password was loaded, so the .env file is not being read from this folder.");
} finally { await pool.end(); }
