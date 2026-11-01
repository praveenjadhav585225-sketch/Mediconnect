"""Read-only PostgreSQL/MongoDB consistency checks for Day 6 case integration."""
import sys

import psycopg
from pymongo import MongoClient

from _env import mongo_settings, pg_kwargs


def main() -> int:
    mongo_uri, database_name = mongo_settings()
    mongo = MongoClient(mongo_uri, serverSelectionTimeoutMS=3000)[database_name]
    with psycopg.connect(**pg_kwargs()) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT c.case_id::text, c.status,
                          EXISTS (SELECT 1 FROM case_embeddings e WHERE e.case_id = c.case_id)
                   FROM medical_cases c"""
            )
            cases = cursor.fetchall()

    complete_cases = {row[0] for row in cases if row[1] != "DRAFT_INCOMPLETE"}
    postgres_ids = {row[0] for row in cases}
    mongo_ids = {str(row["case_id"]) for row in mongo.case_details.find({}, {"case_id": 1})}
    missing_mongo = complete_cases - mongo_ids
    orphan_mongo = mongo_ids - postgres_ids
    missing_embeddings = {row[0] for row in cases if row[1] != "DRAFT_INCOMPLETE" and not row[2]}

    print(f"PostgreSQL cases: {len(postgres_ids)}")
    print(f"MongoDB case details: {len(mongo_ids)}")
    print(f"Missing MongoDB details: {len(missing_mongo)}")
    print(f"Orphan MongoDB details: {len(orphan_mongo)}")
    print(f"Non-draft cases without embeddings: {len(missing_embeddings)}")
    if missing_mongo or orphan_mongo or missing_embeddings:
        return 1
    print("PASS: PostgreSQL, MongoDB, and pgvector case records are consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
