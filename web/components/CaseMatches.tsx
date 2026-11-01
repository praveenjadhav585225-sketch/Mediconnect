"use client";

import { useState } from "react";

type Match = { matched_case_id: string; specialization: string | null; similarity: number };

export default function CaseMatches({ caseId }: { caseId: string }) {
  const [matches, setMatches] = useState<Match[] | null>(null);
  const [error, setError] = useState("");

  async function load() {
    setError("");
    const response = await fetch(`/api/cases/${caseId}/matches`);
    const body = await response.json();
    if (!response.ok) {
      setError(body.error ?? "Matching failed");
      return;
    }
    setMatches(body.matches);
  }

  return (
    <div>
      <button className="btn" onClick={load}>Find similar resolved cases</button>
      {error && <p className="error">{error}</p>}
      {matches && <ul>{matches.map((match) => <li key={match.matched_case_id}>{match.specialization ?? "Unspecified"} — {(Number(match.similarity) * 100).toFixed(1)}% similar</li>)}</ul>}
    </div>
  );
}
