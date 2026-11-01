import ProtectedPortal from "@/components/ProtectedPortal";
import { pool } from "@/lib/db";
import { readSession } from "@/lib/auth";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function Consultations() {
  const u = await readSession();
  if (!u) redirect("/login");
  if (u.role !== "DOCTOR") redirect(`/${u.role.toLowerCase()}`);

  const q = await pool.query(
    `SELECT c.consultation_id, c.status, c.started_at, c.ended_at,
            c.follow_up_required, p.full_name
     FROM consultations c
     JOIN appointments a ON a.appointment_id = c.appointment_id
     JOIN doctors d ON d.doctor_id = a.doctor_id
     JOIN patients p ON p.patient_id = a.patient_id
     WHERE d.user_id = $1
     ORDER BY c.started_at DESC LIMIT 100`,
    [u.userId]
  );

  return (
    <ProtectedPortal role="DOCTOR">
      <main className="container">
        <h1>Consultations</h1>
        <div className="card tablewrap">
          <table>
            <thead>
              <tr><th>Patient</th><th>Status</th><th>Started</th><th>Ended</th><th>Follow-up</th></tr>
            </thead>
            <tbody>
              {q.rows.map(c => (
                <tr key={c.consultation_id}>
                  <td>{c.full_name}</td>
                  <td>{c.status}</td>
                  <td>{new Date(c.started_at).toLocaleString()}</td>
                  <td>{c.ended_at ? new Date(c.ended_at).toLocaleString() : "—"}</td>
                  <td>{c.follow_up_required ? "Yes" : "No"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {!q.rows.length && <p className="empty">No consultations.</p>}
        </div>
      </main>
    </ProtectedPortal>
  );
}