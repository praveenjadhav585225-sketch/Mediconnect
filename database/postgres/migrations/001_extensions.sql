-- 001_extensions.sql
-- vector     : pgvector, stores 384-d MiniLM embeddings and does cosine search
-- btree_gist : lets EXCLUDE constraints mix equality (=) with range overlap (&&)
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Range type over TIME, used to stop overlapping weekly availability rules.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'timerange') THEN
    CREATE TYPE timerange AS RANGE (subtype = time);
  END IF;
END $$;
