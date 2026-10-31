"""Shared helpers: load .env from the repo root and build connection settings. Nothing is hard-coded."""
import os
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).resolve().parents[2] / ".env", override=True)
except ImportError:  # python-dotenv optional; plain environment variables still work
    pass


def pg_kwargs(admin: bool = False) -> dict:
    user = os.getenv("PG_ADMIN_USER", "postgres") if admin else os.getenv("PGUSER", "mediconnect_app")
    password = os.getenv("PG_ADMIN_PASSWORD") if admin else os.getenv("PGPASSWORD")
    if not password:
        raise SystemExit("Missing database password. Copy .env.example to .env and fill it in.")
    return dict(host=os.getenv("PGHOST", "localhost"), port=int(os.getenv("PGPORT", "5432")),
                dbname=os.getenv("PGDATABASE", "mediconnect"), user=user, password=password)


def mongo_settings() -> tuple[str, str]:
    return os.getenv("MONGODB_URI", "mongodb://localhost:27017"), os.getenv("MONGODB_DB", "mediconnect")
