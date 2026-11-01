"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function AppointmentCancelButton({ appointmentId, status }: { appointmentId: string; status: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  if (!["BOOKED", "CONFIRMED"].includes(status)) return null;

  async function cancel() {
    const reason = window.prompt("Cancellation reason");
    if (!reason) return;
    setBusy(true);
    const response = await fetch(`/api/appointments/${appointmentId}/cancel`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ reason }),
    });
    if (!response.ok) {
      const body = await response.json();
      window.alert(body.error ?? "Cancellation failed");
    } else {
      router.refresh();
    }
    setBusy(false);
  }

  return <button className="btn" disabled={busy} onClick={cancel}>{busy ? "Cancelling..." : "Cancel"}</button>;
}
