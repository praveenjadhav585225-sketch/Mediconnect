import { NextRequest, NextResponse } from "next/server";
import argon2 from "argon2";
import { z } from "zod";
import { pool } from "@/lib/db";
import { createSession, UserRole } from "@/lib/auth";

export const runtime = "nodejs";

const loginSchema = z.object({
  email: z.string().trim().email().max(254),
  password: z.string().min(8).max(128),
});

export async function POST(request: NextRequest) {
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return NextResponse.json({ error: "Request body must be valid JSON" }, { status: 400 });
  }

  const parsed = loginSchema.safeParse(raw);
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid email or password format", details: parsed.error.flatten().fieldErrors }, { status: 400 });
  }

  try {
    const result = await pool.query(
      `SELECT user_id, email, password_hash, role, is_active
       FROM users
       WHERE lower(email) = lower($1)
       LIMIT 1`,
      [parsed.data.email],
    );
    const row = result.rows[0];
    if (!row || !row.is_active) {
      return NextResponse.json({ error: "Invalid email or password" }, { status: 401 });
    }

    const passwordMatches = await argon2.verify(row.password_hash, parsed.data.password);
    if (!passwordMatches) {
      return NextResponse.json({ error: "Invalid email or password" }, { status: 401 });
    }

    const role = String(row.role).toUpperCase() as UserRole;
    if (!["PATIENT", "DOCTOR", "ADMIN"].includes(role)) {
      return NextResponse.json({ error: "Account role is not supported" }, { status: 403 });
    }

    const user = { userId: String(row.user_id), email: String(row.email), role };
    await createSession(user);
    return NextResponse.json({ message: "Login successful", user });
  } catch (error) {
    console.error("Login failed", error);
    return NextResponse.json({ error: "Authentication service unavailable" }, { status: 503 });
  }
}
