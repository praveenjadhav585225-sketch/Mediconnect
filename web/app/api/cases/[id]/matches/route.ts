import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { pool } from "@/lib/db";

export const runtime = "nodejs";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const access = await requireRole(["DOCTOR"]);
  if (access.response) return access.response;
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) {
    return NextResponse.json({ error: "Invalid case ID" }, { status: 400 });
  }

  const search = new URL(request.url).searchParams;
  const k = Math.min(20, Math.max(1, Number(search.get("k") ?? 5)));
  const sameSpecialization = search.get("sameSpecialization") === "true";
  if (!Number.isInteger(k)) return NextResponse.json({ error: "Invalid result count" }, { status: 400 });

  try {
    const result = await pool.query(
      `SELECT matched_case_id, specialization, similarity
       FROM find_similar_cases(
         (SELECT doctor_id FROM doctors WHERE user_id = $1),
         $2::uuid, $3::integer, $4::real, $5::boolean
       )`,
      [access.user!.userId, id, k, 0.5, sameSpecialization],
    );
    return NextResponse.json({ matches: result.rows });
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "MC007") return NextResponse.json({ error: "Case is not assigned to this doctor" }, { status: 403 });
    if (code === "MC010") return NextResponse.json({ error: "This case has no embedding yet" }, { status: 409 });
    console.error("Semantic case matching failed", error);
    return NextResponse.json({ error: "Semantic matching is unavailable" }, { status: 503 });
  }
}
