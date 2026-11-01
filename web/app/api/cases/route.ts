
import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { pool } from "@/lib/db";
import { MongoClient } from "mongodb";
import { z } from "zod";
import { randomUUID } from "node:crypto";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

let client: MongoClient | undefined;
let connectionPromise: Promise<MongoClient> | undefined;

async function mongo() {
  if (!process.env.MONGODB_URI) {
    throw new Error("MONGODB_URI is not configured");
  }

  if (!client) {
    client = new MongoClient(process.env.MONGODB_URI);
  }

  if (!connectionPromise) {
    connectionPromise = client.connect().catch((error) => {
      connectionPromise = undefined;
      throw error;
    });
  }

  await connectionPromise;
  return client.db("mediconnect");
}

export async function GET() {
  const a = await requireRole(["PATIENT", "DOCTOR", "ADMIN"]);

  if (a.response) return a.response;

  let sql = `
    SELECT
      mc.case_id,
      mc.patient_id,
      mc.title,
      mc.severity,
      mc.status,
      mc.consent_for_matching,
      mc.created_at,
      p.full_name AS patient_name
    FROM medical_cases mc
    JOIN patients p ON p.patient_id = mc.patient_id
  `;

  const params: string[] = [];

  if (a.user!.role === "PATIENT") {
    sql += ` WHERE p.user_id = $1`;
    params.push(a.user!.userId);
  } else if (a.user!.role === "DOCTOR") {
    sql += `
      JOIN appointments ap ON ap.case_id = mc.case_id
      JOIN doctors d ON d.doctor_id = ap.doctor_id
      WHERE d.user_id = $1
    `;
    params.push(a.user!.userId);
  }

  sql += ` ORDER BY mc.created_at DESC LIMIT 100`;

  const q = await pool.query(sql, params);
   if (a.user!.role === "ADMIN") {
  const adminCases = await pool.query(`
    SELECT *
    FROM v_admin_case_metadata
    ORDER BY created_at DESC
    LIMIT 100
  `);

  return NextResponse.json({ cases: adminCases.rows });
}

  const db = await mongo();

  const docs = await db
    .collection("case_details")
    .find({
      case_id: { $in: q.rows.map((r) => r.case_id) },
    })
    .project({
      case_id: 1,
      narrative: 1,
      symptoms: 1,
      anonymised_summary: 1,
      created_at: 1,
    })
    .toArray();

  const map = new Map(
    docs.map((d) => [String(d.case_id), d])
  );

  return NextResponse.json({
    cases: q.rows.map((r) => ({
      ...r,
      details: map.get(String(r.case_id)) ?? null,
    })),
  });
}

const schema = z.object({
  title: z.string().trim().min(3).max(200),
  severity: z.enum(["LOW", "MODERATE", "HIGH"]),
  durationDays: z.number().int().min(0).max(3650),
  specializationId: z.number().int().positive().optional(),
  narrative: z.string().trim().min(10).max(12000),
  symptoms: z.array(
    z.object({
      name: z.string().trim().min(1).max(120),
      onsetDays: z.number().int().min(0).max(3650),
      intensity: z.number().int().min(1).max(10),
    })
  ).min(1).max(30),
  consentForMatching: z.boolean(),
});

export async function POST(req: Request) {
  const a = await requireRole(["PATIENT"]);

  if (a.response) return a.response;

  let body: unknown;

  try {
    body = await req.json();
  } catch {
    return NextResponse.json(
      { error: "Invalid JSON body" },
      { status: 400 }
    );
  }

  const b = schema.safeParse(body);

  if (!b.success) {
    return NextResponse.json(
      { error: "Invalid case data" },
      { status: 400 }
    );
  }

  const p = await pool.query(
    `SELECT patient_id FROM patients WHERE user_id = $1`,
    [a.user!.userId]
  );

  if (!p.rowCount) {
    return NextResponse.json(
      { error: "Patient profile not found" },
      { status: 404 }
    );
  }

  const caseId = randomUUID();
  const db = await mongo();

  const doc = {
    case_id: caseId,
    narrative: b.data.narrative,
    symptoms: b.data.symptoms.map((s) => ({
      name: s.name,
      onset_days: s.onsetDays,
      intensity: s.intensity,
    })),
    vitals: {},
    medical_history_flags: [],
    attachments: [],
    anonymised_summary: "",
    created_at: new Date(),
  };

  const ins = await db
    .collection("case_details")
    .insertOne(doc);

  try {
    await pool.query(
      `INSERT INTO medical_cases
      (case_id, patient_id, title, specialization_id,
       severity, duration_days, status,
       consent_for_matching, mongo_detail_id)
      VALUES ($1,$2,$3,$4,$5,$6,'SUBMITTED',$7,$8)`,
      [
        caseId,
        p.rows[0].patient_id,
        b.data.title,
        b.data.specializationId ?? null,
        b.data.severity,
        b.data.durationDays,
        b.data.consentForMatching,
        String(ins.insertedId),
      ]
    );
  } catch (error) {
    await db.collection("case_details").deleteOne({
      _id: ins.insertedId,
    });

    throw error;
  }

  return NextResponse.json(
    { caseId, status: "SUBMITTED" },
    { status: 201 }
  );
}
