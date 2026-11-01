import { NextResponse } from "next/server";
import argon2 from "argon2";
import { z } from "zod";
import { pool } from "@/lib/db";
import { createSession } from "@/lib/auth";

export const runtime = "nodejs";

const schema = z.object({
  email: z.string().trim().email().max(254).transform((value) => value.toLowerCase()),
  password: z.string().min(8).max(128),
  fullName: z.string().trim().min(2).max(150),
  dateOfBirth: z.string().date(),
  gender: z.enum(["MALE", "FEMALE", "OTHER"]).optional(),
  phone: z.string().regex(/^\+?[0-9]{10,15}$/).optional(),
});

export async function POST(request: Request) {
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return NextResponse.json({ error: "Request body must be valid JSON" }, { status: 400 });
  }
  const parsed = schema.safeParse(raw);
  if (!parsed.success) return NextResponse.json({ error: "Invalid registration data" }, { status: 400 });

  const date = new Date(`${parsed.data.dateOfBirth}T00:00:00Z`);
  if (date < new Date("1900-01-01T00:00:00Z") || date > new Date()) {
    return NextResponse.json({ error: "Date of birth is not valid" }, { status: 400 });
  }

  const connection = await pool.connect();
  try {
    await connection.query("BEGIN");
    const passwordHash = await argon2.hash(parsed.data.password, { type: argon2.argon2id });
    const user = await connection.query(
      `INSERT INTO users (email, password_hash, role)
       VALUES ($1, $2, 'PATIENT')
       RETURNING user_id, email, role`,
      [parsed.data.email, passwordHash],
    );
    await connection.query(
      `INSERT INTO patients (user_id, full_name, date_of_birth, gender, phone)
       VALUES ($1, $2, $3::date, $4, $5)`,
      [
        user.rows[0].user_id,
        parsed.data.fullName,
        parsed.data.dateOfBirth,
        parsed.data.gender ?? null,
        parsed.data.phone ?? null,
      ],
    );
    await connection.query("COMMIT");

    const sessionUser = {
      userId: String(user.rows[0].user_id),
      email: user.rows[0].email,
      role: "PATIENT" as const,
    };
    await createSession(sessionUser);
    return NextResponse.json({ message: "Registration successful", user: sessionUser }, { status: 201 });
  } catch (error) {
    await connection.query("ROLLBACK").catch((rollbackError) => {
      console.error("Registration rollback failed", rollbackError);
    });
    const code = (error as { code?: string }).code;
    if (code === "23505") return NextResponse.json({ error: "An account with that email already exists" }, { status: 409 });
    if (code === "23514") return NextResponse.json({ error: "Registration data violates a database rule" }, { status: 400 });
    console.error("Registration failed", error);
    return NextResponse.json({ error: "Registration service unavailable" }, { status: 503 });
  } finally {
    connection.release();
  }
}
