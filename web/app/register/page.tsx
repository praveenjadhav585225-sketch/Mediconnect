"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

export default function Register() {
  const router = useRouter();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setBusy(true);
    const form = new FormData(event.currentTarget);
    try {
      const response = await fetch("/api/auth/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(Object.fromEntries(form)),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? "Registration failed");
      router.replace("/patient");
      router.refresh();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Registration failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="login card">
      <h1>Create patient account</h1>
      <p className="muted">Synthetic data only. Do not enter real patient information.</p>
      <form onSubmit={submit}>
        <label className="field">Full name<input name="fullName" required maxLength={150} /></label>
        <label className="field">Email<input name="email" type="email" required maxLength={254} /></label>
        <label className="field">Password<input name="password" type="password" minLength={8} required /></label>
        <label className="field">Date of birth<input name="dateOfBirth" type="date" required /></label>
        <label className="field">Gender<select name="gender" defaultValue=""><option value="">Prefer not to say</option><option value="MALE">Male</option><option value="FEMALE">Female</option><option value="OTHER">Other</option></select></label>
        <label className="field">Phone (optional)<input name="phone" pattern="^\+?[0-9]{10,15}$" /></label>
        {error && <p className="error">{error}</p>}
        <button className="btn" disabled={busy}>{busy ? "Creating account..." : "Create account"}</button>
      </form>
      <p className="muted">Already registered? <Link href="/login">Sign in</Link></p>
    </main>
  );
}
