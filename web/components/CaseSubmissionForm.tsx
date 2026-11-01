"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

export default function CaseSubmissionForm() {
  const router = useRouter();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setMessage("");
    setBusy(true);
    const form = new FormData(event.currentTarget);
    const symptoms = String(form.get("symptoms") ?? "").split(",").map((name) => ({
      name: name.trim(),
      onsetDays: 0,
      intensity: 1,
    })).filter((symptom) => symptom.name);
    try {
      const response = await fetch("/api/cases", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: form.get("title"),
          severity: form.get("severity"),
          durationDays: Number(form.get("durationDays")),
          narrative: form.get("narrative"),
          symptoms,
          consentForMatching: form.get("consentForMatching") === "on",
        }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? "Case submission failed");
      event.currentTarget.reset();
      setMessage(`Case submitted: ${body.caseId}`);
      router.refresh();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Case submission failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="card" onSubmit={submit}>
      <h2>Submit a synthetic case</h2>
      <label className="field">Title<input name="title" minLength={3} maxLength={200} required /></label>
      <label className="field">Severity<select name="severity" defaultValue="LOW"><option>LOW</option><option>MODERATE</option><option>HIGH</option></select></label>
      <label className="field">Duration (days)<input name="durationDays" type="number" min="0" max="3650" defaultValue="0" required /></label>
      <label className="field">Symptoms (comma-separated)<input name="symptoms" minLength={2} required /></label>
      <label className="field">Narrative<textarea name="narrative" minLength={20} maxLength={5000} required /></label>
      <label><input name="consentForMatching" type="checkbox" /> Allow anonymised semantic matching</label>
      {error && <p className="error">{error}</p>}
      {message && <p className="notice">{message}</p>}
      <button className="btn" disabled={busy}>{busy ? "Submitting..." : "Submit case"}</button>
    </form>
  );
}
