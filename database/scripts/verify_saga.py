"""Verifies that a submitted case really exists in all three stores (PostgreSQL, MongoDB, pgvector).
Run after submitting a case in the app:   python database/scripts/verify_saga.py
Read-only. Exit code 1 if a non-draft case is missing its MongoDB document (the saga's core promise)."""
import sys
import psycopg
from _env import pg_kwargs, mongo_settings


def run(cur, mdb) -> int:
    cur.execute("""select c.case_id::text, c.title, c.status, c.consent_for_matching, c.created_at,
                          (select vector_dims(e.embedding) from case_embeddings e where e.case_id = c.case_id) as dims
                   from medical_cases c order by c.created_at desc""")
    cases = cur.fetchall()
    mongo_ids = {d["case_id"] for d in mdb.case_details.find({}, {"case_id": 1})}
    pg_ids = {c[0] for c in cases}
    problems = 0
    print("Newest 5 cases (PostgreSQL header | MongoDB narrative | pgvector embedding)")
    print(f"{'case_id':38} {'status':17} {'PG':3} {'Mongo':6} {'vector':7} title")
    for cid, title, status, consent, created, dims in cases[:5]:
        print(f"{cid:38} {status:17} {'yes':3} {'yes' if cid in mongo_ids else 'NO':6} {('yes/' + str(dims)) if dims else 'no':7} {title[:40]}")
    missing_mongo = [c for c in cases if c[2] != "DRAFT_INCOMPLETE" and c[0] not in mongo_ids]
    orphan_mongo = mongo_ids - pg_ids
    drafts = [c for c in cases if c[2] == "DRAFT_INCOMPLETE"]
    no_vec = [c for c in cases if c[2] != "DRAFT_INCOMPLETE" and c[5] is None]
    bad_dims = [c for c in cases if c[5] not in (None, 384)]
    print(f"\ntotals: PostgreSQL cases={len(cases)}  MongoDB documents={len(mongo_ids)}")
    for ok, msg in [(not missing_mongo, f"every non-draft PostgreSQL case has a MongoDB document ({len(missing_mongo)} missing)"),
                    (not orphan_mongo, f"no MongoDB document without a PostgreSQL case ({len(orphan_mongo)} orphans)"),
                    (not bad_dims, f"every stored embedding has 384 dimensions ({len(bad_dims)} wrong)")]:
        print(f"[{'PASS' if ok else 'FAIL'}] {msg}")
        problems += 0 if ok else 1
    print(f"[INFO] DRAFT_INCOMPLETE cases (expected after a failed save): {len(drafts)}")
    print(f"[INFO] non-draft cases without an embedding: {len(no_vec)}"
          + ("  (embedding on submit is wired up in Day 6; seed cases get theirs from embed_cases.py)" if no_vec else ""))
    return problems


if __name__ == "__main__":
    from pymongo import MongoClient
    uri, dbname = mongo_settings()
    with psycopg.connect(**pg_kwargs()) as con:
        sys.exit(1 if run(con.cursor(), MongoClient(uri, serverSelectionTimeoutMS=3000)[dbname]) else 0)
