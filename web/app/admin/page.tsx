
import { pool } from "@/lib/db";
import { readSession } from "@/lib/auth";
import ProtectedPortal from "@/components/ProtectedPortal";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function Admin() {
  // Verify authentication and role before accessing admin data.
  const user = await readSession();

  if (!user) {
    redirect("/login");
  }

  if (user.role !== "ADMIN") {
    redirect("/");
  }

  const q = await pool.query(`
    SELECT
      (SELECT count(*) FROM users)::int AS users,
      (SELECT count(*) FROM patients)::int AS patients,
      (SELECT count(*) FROM doctors)::int AS doctors,
      (SELECT count(*) FROM appointments)::int AS appointments,
      (SELECT count(*) FROM medical_cases)::int AS cases,
      (SELECT count(*) FROM doctors
        WHERE verification_status = 'PENDING')::int AS pending_doctors
  `);

  return (
    <ProtectedPortal role="ADMIN">
      <main className="container">
        <h1>Admin dashboard</h1>

        <section className="grid">
          {Object.entries(q.rows[0]).map(([key, value]) => (
            <div className="card" key={key}>
              {key.replaceAll("_", " ")}
              <div className="metric">{String(value)}</div>
            </div>
          ))}
        </section>
      </main>
    </ProtectedPortal>
  );
}
