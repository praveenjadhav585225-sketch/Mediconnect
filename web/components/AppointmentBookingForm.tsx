"use client";

import { useEffect, useState } from "react";

type Doctor = { doctor_id: string; full_name: string; specialization: string };
type Slot = { slot_id: string; start_ts: string; end_ts: string };

export default function AppointmentBookingForm() {
  const [doctors, setDoctors] = useState<Doctor[]>([]);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [doctorId, setDoctorId] = useState("");
  const [slotId, setSlotId] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    fetch("/api/doctors").then(async (response) => {
      if (!response.ok) throw new Error("Could not load doctors");
      setDoctors((await response.json()).doctors);
    }).catch((reason) => setError(reason instanceof Error ? reason.message : "Could not load doctors"));
  }, []);

  useEffect(() => {
    setSlots([]);
    setSlotId("");
    if (!doctorId) return;
    fetch(`/api/doctors/${doctorId}/slots`).then(async (response) => {
      if (!response.ok) throw new Error("Could not load available slots");
      setSlots((await response.json()).slots);
    }).catch((reason) => setError(reason instanceof Error ? reason.message : "Could not load slots"));
  }, [doctorId]);

  async function book() {
    setMessage("");
    setError("");
    const response = await fetch("/api/appointments", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ slotId }),
    });
    const body = await response.json();
    if (!response.ok) {
      setError(body.error ?? "Booking failed");
      return;
    }
    setMessage(`Appointment booked: ${body.appointmentId}`);
    setSlotId("");
  }

  return (
    <section className="card">
      <h2>Book an appointment</h2>
      <label className="field">Doctor<select value={doctorId} onChange={(event) => setDoctorId(event.target.value)}><option value="">Select a doctor</option>{doctors.map((doctor) => <option key={doctor.doctor_id} value={doctor.doctor_id}>{doctor.full_name} — {doctor.specialization}</option>)}</select></label>
      <label className="field">Available slot<select value={slotId} onChange={(event) => setSlotId(event.target.value)} disabled={!doctorId}><option value="">Select a slot</option>{slots.map((slot) => <option key={slot.slot_id} value={slot.slot_id}>{new Date(slot.start_ts).toLocaleString()}</option>)}</select></label>
      {error && <p className="error">{error}</p>}
      {message && <p className="notice">{message}</p>}
      <button className="btn" disabled={!slotId} onClick={book}>Book appointment</button>
    </section>
  );
}
