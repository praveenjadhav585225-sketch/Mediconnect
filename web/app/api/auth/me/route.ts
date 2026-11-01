import { NextResponse } from "next/server";
import { readSession } from "@/lib/auth";

export const runtime = "nodejs";

export async function GET() {
  const user = await readSession();
  if (!user) return NextResponse.json({ error: "Unauthenticated" }, { status: 401 });
  return NextResponse.json({ user });
}
