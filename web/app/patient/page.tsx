import ProtectedPortal from "@/components/ProtectedPortal";
import { pool } from "@/lib/db";
import { readSession } from "@/lib/auth";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function Patient() {
  const u = await readSession();
  if (!u) redirect("/login");
  if (u.role !== "PATIENT") redirect(`/${u.role.toLowerCase()}`);

  const q = await pool.query(
    `SELECT p.full_name,
            COUNT(a.appointment_id)::int AS total,
            COUNT(a.appointment_id) FILTER (
              WHERE a.status IN ('BOOKED','CONFIRMED','IN_PROGRESS')
            )::int AS active
     FROM patients p
     LEFT JOIN appointments a ON a.patient_id = p.patient_id
     WHERE p.user_id = $1
     GROUP BY p.full_name`,
    [u.userId]
  );

  const r = q.rows[0];

  return (
    <ProtectedPortal role="PATIENT">
      <main className="container">
        <h1>Patient dashboard</h1>
        <p className="muted">Welcome, {r?.full_name || u.email}</p>
        <section className="grid">
          <div className="card">Total appointments<div className="metric">{r?.total ?? 0}</div></div>
          <div className="card">Active appointments<div className="metric">{r?.active ?? 0}</div></div>
          <div className="card">
            <h3>Find a doctor</h3>
            <a className="btn" href="/patient/doctors">Browse doctors</a>
          </div>
        </section>
      </main>
    </ProtectedPortal>
  );
}