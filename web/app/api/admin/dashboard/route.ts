import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";

export const runtime = "nodejs";

export async function GET() {
  const access = await requireRole(["ADMIN"]);
  if (access.response) return access.response;
  return NextResponse.json({
    message: "Admin access verified",
    user: access.user,
    note: "Dashboard metrics will be added in a later day.",
  });
}
