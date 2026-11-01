import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { pool } from "@/lib/db";

export const runtime = "nodejs";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const access = await requireRole(["PATIENT"]);
  if (access.response) return access.response;
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) return NextResponse.json({ error: "Invalid doctor ID" }, { status: 400 });
  const limit = Math.min(50, Math.max(1, Number(new URL(request.url).searchParams.get("limit") ?? 20)));
  if (!Number.isInteger(limit)) return NextResponse.json({ error: "Invalid slot limit" }, { status: 400 });

  const result = await pool.query(
    `SELECT slot_id, start_ts, end_ts
     FROM time_slots
     WHERE doctor_id = $1 AND status = 'AVAILABLE' AND start_ts > now()
     ORDER BY start_ts
     LIMIT $2`,
    [id, limit],
  );
  return NextResponse.json({ slots: result.rows });
}
