const EMBEDDING_DIMENSIONS = 384;

export function caseEmbeddingText(title: string, narrative: string) {
  return `${title.trim()}. ${narrative.trim()}`.replace(/\s+/g, " ");
}

export function embeddingTextHash(text: string) {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)).then((digest) =>
    Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join(""),
  );
}

export async function createCaseEmbedding(text: string) {
  const serviceUrl = process.env.EMBEDDING_SERVICE_URL;
  const apiKey = process.env.EMBEDDING_API_KEY;
  if (!serviceUrl || !apiKey) {
    throw new Error("Embedding service configuration is missing");
  }

  const response = await fetch(`${serviceUrl.replace(/\/$/, "")}/embed`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-API-Key": apiKey },
    body: JSON.stringify({ text }),
    signal: AbortSignal.timeout(30_000),
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`Embedding service returned HTTP ${response.status}`);
  }

  const body: unknown = await response.json();
  if (
    !body ||
    typeof body !== "object" ||
    !("embedding" in body) ||
    !Array.isArray(body.embedding) ||
    body.embedding.length !== EMBEDDING_DIMENSIONS ||
    body.embedding.some((value) => typeof value !== "number" || !Number.isFinite(value))
  ) {
    throw new Error("Embedding service returned an invalid vector");
  }

  return body.embedding.join(",");
}

