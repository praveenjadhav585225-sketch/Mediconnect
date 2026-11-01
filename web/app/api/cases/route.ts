import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { pool } from "@/lib/db";
import { z } from "zod";
import { randomUUID } from "node:crypto";
import { ObjectId } from "mongodb";
import { caseEmbeddingText, createCaseEmbedding, embeddingTextHash } from "@/lib/embedding";
import { getMongoDb } from "@/lib/mongo";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const access = await requireRole(["PATIENT", "DOCTOR", "ADMIN"]);
  if (access.response) return access.response;

  if (access.user!.role === "ADMIN") {
    const result = await pool.query(`
      SELECT * FROM v_admin_case_metadata
      ORDER BY created_at DESC
      LIMIT 100
    `);
    return NextResponse.json({ cases: result.rows });
  }

  let sql = `
    SELECT mc.case_id, mc.patient_id, mc.title, mc.severity, mc.status,
           mc.consent_for_matching, mc.created_at, p.full_name AS patient_name
    FROM medical_cases mc
    JOIN patients p ON p.patient_id = mc.patient_id
  `;
  const params: string[] = [];

  if (access.user!.role === "PATIENT") {
    sql += " WHERE p.user_id = $1";
    params.push(access.user!.userId);
  } else {
    sql += `
      JOIN appointments ap ON ap.case_id = mc.case_id
      JOIN doctors d ON d.doctor_id = ap.doctor_id
      WHERE d.user_id = $1 AND ap.status <> 'CANCELLED'
    `;
    params.push(access.user!.userId);
  }
  sql += " ORDER BY mc.created_at DESC LIMIT 100";

  const result = await pool.query(sql, params);
  const db = await getMongoDb();
  const details = await db.collection("case_details").find({
    case_id: { $in: result.rows.map((row) => row.case_id) },
  }).project({
    case_id: 1,
    narrative: 1,
    symptoms: 1,
    anonymised_summary: 1,
    created_at: 1,
  }).toArray();
  const byCase = new Map(details.map((detail) => [String(detail.case_id), detail]));

  return NextResponse.json({
    cases: result.rows.map((row) => ({
      ...row,
      details: byCase.get(String(row.case_id)) ?? null,
    })),
  });
}

const schema = z.object({
  title: z.string().trim().min(3).max(200),
  severity: z.enum(["LOW", "MODERATE", "HIGH"]),
  durationDays: z.number().int().min(0).max(3650),
  specializationId: z.number().int().positive().optional(),
  narrative: z.string().trim().min(20).max(5000),
  symptoms: z.array(z.object({
    name: z.string().trim().min(2).max(100),
    onsetDays: z.number().int().min(0).max(3650),
    intensity: z.number().int().min(1).max(10),
  })).min(1).max(30),
  consentForMatching: z.boolean(),
});

export async function POST(request: Request) {
  const access = await requireRole(["PATIENT"]);
  if (access.response) return access.response;

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  const parsed = schema.safeParse(raw);
  if (!parsed.success) return NextResponse.json({ error: "Invalid case data" }, { status: 400 });

  const patient = await pool.query(
    "SELECT patient_id FROM patients WHERE user_id = $1",
    [access.user!.userId],
  );
  if (!patient.rowCount) return NextResponse.json({ error: "Patient profile not found" }, { status: 404 });

  const text = caseEmbeddingText(parsed.data.title, parsed.data.narrative);
  let embedding: string;
  let textHash: string;
  try {
    [embedding, textHash] = await Promise.all([
      createCaseEmbedding(text),
      embeddingTextHash(text),
    ]);
  } catch (error) {
    console.error("Case embedding failed", error);
    return NextResponse.json(
      { error: "Case could not be submitted because semantic matching is unavailable" },
      { status: 503 },
    );
  }

  const caseId = randomUUID();
  const db = await getMongoDb();
  let insertedId: ObjectId;
  try {
    const inserted = await db.collection("case_details").insertOne({
      case_id: caseId,
      narrative: parsed.data.narrative,
      symptoms: parsed.data.symptoms.map((symptom) => ({
        name: symptom.name,
        onset_days: symptom.onsetDays,
        intensity: symptom.intensity,
      })),
      vitals: {},
      medical_history_flags: [],
      attachments: [],
      anonymised_summary: "Patient-submitted synthetic case.",
      created_at: new Date(),
    });
    insertedId = inserted.insertedId;
  } catch (error) {
    console.error("MongoDB case insert failed", error);
    return NextResponse.json({ error: "Case storage is unavailable" }, { status: 503 });
  }

  const connection = await pool.connect();
  try {
    await connection.query("BEGIN");
    await connection.query(
      `INSERT INTO medical_cases
       (case_id, patient_id, title, specialization_id, severity, duration_days,
        status, consent_for_matching, mongo_detail_id)
       VALUES ($1,$2,$3,$4,$5,$6,'SUBMITTED',$7,$8)`,
      [
        caseId,
        patient.rows[0].patient_id,
        parsed.data.title,
        parsed.data.specializationId ?? null,
        parsed.data.severity,
        parsed.data.durationDays,
        parsed.data.consentForMatching,
        caseId,
      ],
    );
    await connection.query(
      `INSERT INTO case_embeddings (case_id, embedding, model_name, text_hash)
       VALUES ($1, $2::vector, $3, $4)`,
      [caseId, `[${embedding}]`, "all-MiniLM-L6-v2", textHash],
    );
    await connection.query("COMMIT");
  } catch (error) {
    await connection.query("ROLLBACK").catch((rollbackError) => {
      console.error("Case transaction rollback failed", rollbackError);
    });
    await db.collection("case_details").deleteOne({ _id: insertedId }).catch((cleanupError) => {
      console.error("MongoDB case cleanup failed", cleanupError);
    });
    console.error("PostgreSQL case insert failed", error);
    return NextResponse.json({ error: "Case could not be saved consistently" }, { status: 503 });
  } finally {
    connection.release();
  }

  return NextResponse.json({ caseId, status: "SUBMITTED" }, { status: 201 });
}
