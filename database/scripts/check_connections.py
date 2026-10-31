"""Checks PostgreSQL (as the limited app role), pgvector and MongoDB.
Run from the repo root with the venv active:   python database/scripts/check_connections.py"""
import sys
import psycopg
from _env import pg_kwargs, mongo_settings

failed = 0


def report(name, ok, detail=""):
    global failed
    failed += 0 if ok else 1
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f"  ->  {detail}" if detail else ""))


try:
    with psycopg.connect(**pg_kwargs()) as con:
        cur = con.cursor()
        cur.execute("select current_user, version()")
        user, ver = cur.fetchone()
        report("PostgreSQL connection (app role)", True, f"user={user}, {ver.split(',')[0]}")
        cur.execute("select extversion from pg_extension where extname='vector'")
        row = cur.fetchone()
        report("pgvector extension", bool(row), f"version {row[0]}" if row else "not installed")
        cur.execute("select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'")
        n = cur.fetchone()[0]
        report("Tables present", n >= 13, f"{n} tables (expected 13)")
        cur.execute("select '[1,2,3]'::vector <=> '[1,2,4]'::vector")
        report("Cosine distance works", True, f"{cur.fetchone()[0]:.5f}")
        cur.execute("select count(*) from users")
        report("App role can read data", True, f"{cur.fetchone()[0]} users")
except Exception as e:
    report("PostgreSQL", False, str(e).splitlines()[0])

try:
    from pymongo import MongoClient
    uri, dbname = mongo_settings()
    client = MongoClient(uri, serverSelectionTimeoutMS=3000)
    client.admin.command("ping")
    report("MongoDB ping", True, f"server {client.server_info()['version']}")
    names = client[dbname].list_collection_names()
    for c in ("case_details", "consultation_notes", "notifications"):
        report(f"Collection {c}", c in names, f"{client[dbname][c].count_documents({})} documents" if c in names else "missing")
except Exception as e:
    report("MongoDB", False, str(e).splitlines()[0][:140])

sys.exit(1 if failed else 0)
