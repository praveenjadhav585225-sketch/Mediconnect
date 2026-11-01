import ProtectedPortal from "@/components/ProtectedPortal";
import { pool } from "@/lib/db";
import { readSession } from "@/lib/auth";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function DoctorAppointments() {
  const u = await readSession();
  if (!u) redirect("/login");
  if (u.role !== "DOCTOR") redirect(`/${u.role.toLowerCase()}`);

  const q = await pool.query(
    `SELECT appointment_id, status, start_ts, patient_name, reason, consultation_status
     FROM v_appointment_details
     WHERE doctor_id = (SELECT doctor_id FROM doctors WHERE user_id = $1)
     ORDER BY start_ts DESC LIMIT 100`,
    [u.userId]
  );

  return (
    <ProtectedPortal role="DOCTOR">
      <main className="container">
        <h1>Appointments</h1>
        <div className="card tablewrap">
          <table>
            <thead>
              <tr><th>Patient</th><th>Start</th><th>Status</th><th>Consultation</th><th>Reason</th></tr>
            </thead>
            <tbody>
              {q.rows.map(a => (
                <tr key={a.appointment_id}>
                  <td>{a.patient_name}</td>
                  <td>{a.start_ts ? new Date(a.start_ts).toLocaleString() : "—"}</td>
                  <td>{a.status}</td>
                  <td>{a.consultation_status || "Not started"}</td>
                  <td>{a.reason || "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {!q.rows.length && <p className="empty">No appointments.</p>}
        </div>
      </main>
    </ProtectedPortal>
  );
}