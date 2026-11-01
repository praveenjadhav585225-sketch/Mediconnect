import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";

export type UserRole = "PATIENT" | "DOCTOR" | "ADMIN";
export type SessionUser = { userId: string; email: string; role: UserRole };

const COOKIE_NAME = "mc_session";
const secretText = process.env.JWT_SECRET ?? "";
function secret() {
  if (secretText.length < 32) throw new Error("JWT_SECRET must contain at least 32 characters");
  return new TextEncoder().encode(secretText);
}

export async function createSession(user: SessionUser) {
  const token = await new SignJWT({ email: user.email, role: user.role })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(user.userId)
    .setIssuedAt()
    .setExpirationTime("8h")
    .sign(secret());

  const jar = await cookies();
  jar.set(COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 8 * 60 * 60,
  });
}

export async function readSession(): Promise<SessionUser | null> {
  const jar = await cookies();
  const token = jar.get(COOKIE_NAME)?.value;
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, secret());
    if (
      typeof payload.sub !== "string" ||
      typeof payload.email !== "string" ||
      !["PATIENT", "DOCTOR", "ADMIN"].includes(String(payload.role))
    ) return null;
    return { userId: payload.sub, email: payload.email, role: payload.role as UserRole };
  } catch {
    return null;
  }
}

export async function requireRole(roles: UserRole[]) {
  const user = await readSession();
  if (!user) {
    return { user: null, response: NextResponse.json({ error: "Unauthenticated" }, { status: 401 }) };
  }
  if (!roles.includes(user.role)) {
    return { user: null, response: NextResponse.json({ error: "Forbidden" }, { status: 403 }) };
  }
  return { user, response: null };
}

export async function clearSession() {
  const jar = await cookies();
  jar.set(COOKIE_NAME, "", { httpOnly: true, path: "/", maxAge: 0, sameSite: "lax" });
}
