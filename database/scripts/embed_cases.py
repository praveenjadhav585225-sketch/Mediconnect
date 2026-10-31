"""Generates 384-d embeddings for case texts and stores them in PostgreSQL (pgvector).

  python database/scripts/embed_cases.py            # real model: all-MiniLM-L6-v2 (runs locally on CPU)
  python database/scripts/embed_cases.py --fake     # PLUMBING TEST ONLY: random vectors, no model, NOT meaningful

Input : database/synthetic-data/case_texts.json   (title + narrative, no names or contact details)
Output: case_embeddings(case_id, embedding vector(384), model_name, text_hash)
Skips cases whose text hash and model are unchanged, so it is safe to re-run.
Medical text never leaves this machine: the model is downloaded once, inference is local.
"""
import argparse
import hashlib
import json
import random
from pathlib import Path

import psycopg
from _env import pg_kwargs

DIMS = 384
TEXTS = Path(__file__).resolve().parents[1] / "synthetic-data" / "case_texts.json"


def preprocess(text: str) -> str:
    return " ".join(text.split())          # collapse whitespace; the Day 4 service adds more


def vec_literal(v) -> str:
    return "[" + ",".join(f"{float(x):.7f}" for x in v) + "]"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fake", action="store_true", help="random vectors for testing the pipeline only")
    ap.add_argument("--model", default="all-MiniLM-L6-v2")
    args = ap.parse_args()

    items = json.loads(TEXTS.read_text())
    model_name = "FAKE-random" if args.fake else args.model
    if args.fake:
        print("WARNING: --fake writes random vectors. Similarity results will be meaningless.")
    else:
        from sentence_transformers import SentenceTransformer
        model = SentenceTransformer(args.model)

    with psycopg.connect(**pg_kwargs()) as con:
        cur = con.cursor()
        cur.execute("select case_id::text, text_hash, model_name from case_embeddings")
        existing = {r[0]: (r[1], r[2]) for r in cur.fetchall()}
        todo = []
        for it in items:
            text = preprocess(it["text"])
            h = hashlib.sha256(text.encode()).hexdigest()
            if existing.get(it["case_id"]) != (h, model_name):
                todo.append((it["case_id"], text, h))
        print(f"{len(items)} case texts, {len(todo)} need (re)embedding")
        if not todo:
            return
        if args.fake:
            vecs = [[random.Random(h).gauss(0, 1) for _ in range(DIMS)] for _, _, h in todo]
        else:
            vecs = model.encode([t for _, t, _ in todo], batch_size=16, normalize_embeddings=True, show_progress_bar=True)
        rows = []
        for (cid, _, h), v in zip(todo, vecs):
            if len(v) != DIMS:
                raise SystemExit(f"Embedding has {len(v)} dimensions, expected {DIMS}")
            rows.append((cid, vec_literal(v), model_name, h))
        cur.executemany(
            """INSERT INTO case_embeddings (case_id, embedding, model_name, text_hash)
               VALUES (%s, %s::vector, %s, %s)
               ON CONFLICT (case_id) DO UPDATE
               SET embedding = EXCLUDED.embedding, model_name = EXCLUDED.model_name,
                   text_hash = EXCLUDED.text_hash, created_at = now()""", rows)
        con.commit()
        cur.execute("select count(*), min(vector_dims(embedding)), max(vector_dims(embedding)) from case_embeddings")
        print("case_embeddings now holds (rows, min_dims, max_dims):", cur.fetchone())


if __name__ == "__main__":
    main()
