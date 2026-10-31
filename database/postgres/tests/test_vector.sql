-- test_vector.sql : pgvector plumbing test.
-- IMPORTANT: this uses TEST-ONLY synthetic vectors (one block of dimensions per specialization + noise),
-- NOT MiniLM embeddings. It proves cosine search, filtering, the HNSW index and the dimension check work.
-- Real semantic quality is measured later with embed_cases.py (real model). Everything is rolled back.
\pset pager off
\echo '=== embeddings stored BEFORE this test (left untouched) ==='
SELECT count(*) AS embeddings_before FROM case_embeddings;
BEGIN;
DELETE FROM case_embeddings;      -- test uses its own vectors; rolled back at the end, your real embeddings are safe
SELECT setseed(0.42);

INSERT INTO case_embeddings (case_id, embedding, text_hash)
SELECT c.case_id,
       (SELECT array_agg(
                 (CASE WHEN g BETWEEN (c.specialization_id-1)*40 AND (c.specialization_id-1)*40 + 39 THEN 1.0 ELSE 0.0 END
                  + random()*0.35)::real ORDER BY g)
        FROM generate_series(0, 383) g)::vector,
       md5(c.case_id::text) || md5(c.case_id::text || 'x')
FROM medical_cases c
WHERE c.status <> 'DRAFT_INCOMPLETE';

\echo '=== V1: rows inserted into case_embeddings (expect 70) ==='
SELECT count(*) AS embeddings, min(vector_dims(embedding)) AS dims_min, max(vector_dims(embedding)) AS dims_max FROM case_embeddings;

\echo '=== V2: top-5 similar cases for the active CARDIOLOGY case (pool: consented + RESOLVED/CLOSED only) ==='
WITH q AS (SELECT e.embedding, c.case_id FROM case_embeddings e JOIN medical_cases c USING (case_id)
           WHERE c.status = 'SUBMITTED' AND c.specialization_id = 1)
SELECT s.name AS specialization, c.title, round((1 - (e.embedding <=> q.embedding))::numeric, 3) AS similarity
FROM q, case_embeddings e
JOIN medical_cases c ON c.case_id = e.case_id
JOIN specializations s ON s.specialization_id = c.specialization_id
WHERE c.consent_for_matching AND c.status IN ('RESOLVED','CLOSED') AND c.case_id <> q.case_id
ORDER BY e.embedding <=> q.embedding
LIMIT 5;

\echo '=== V3: automated check, top-5 neighbours of EVERY active case are in the same specialization ==='
WITH active AS (SELECT c.case_id, c.specialization_id, e.embedding FROM medical_cases c JOIN case_embeddings e USING (case_id) WHERE c.status='SUBMITTED'),
top5 AS (
  SELECT a.case_id AS qid, a.specialization_id AS qspec, n.specialization_id AS nspec
  FROM active a
  CROSS JOIN LATERAL (
     SELECT c.specialization_id FROM case_embeddings e JOIN medical_cases c USING (case_id)
     WHERE c.consent_for_matching AND c.status IN ('RESOLVED','CLOSED')
     ORDER BY e.embedding <=> a.embedding LIMIT 5) n)
SELECT count(*) AS neighbours_checked, count(*) FILTER (WHERE qspec = nspec) AS same_specialization,
       CASE WHEN count(*) = count(*) FILTER (WHERE qspec = nspec) THEN 'PASS' ELSE 'FAIL' END AS result FROM top5;

\echo '=== V4: what the matching pool excludes (consent + status filter) ==='
SELECT count(*) FILTER (WHERE c.status IN ('RESOLVED','CLOSED'))                                   AS resolved_or_closed,
       count(*) FILTER (WHERE c.consent_for_matching AND c.status IN ('RESOLVED','CLOSED'))        AS in_matching_pool,
       count(*) FILTER (WHERE NOT c.consent_for_matching AND c.status IN ('RESOLVED','CLOSED'))    AS excluded_no_consent,
       count(*) FILTER (WHERE c.status NOT IN ('RESOLVED','CLOSED'))                              AS excluded_not_finished
FROM case_embeddings e JOIN medical_cases c USING (case_id);

\echo '=== V5: similarity threshold (>= 0.60) keeps only close matches ==='
WITH q AS (SELECT e.embedding FROM case_embeddings e JOIN medical_cases c USING (case_id) WHERE c.status='SUBMITTED' AND c.specialization_id = 3)
SELECT count(*) AS matches_above_threshold
FROM q, case_embeddings e JOIN medical_cases c USING (case_id)
WHERE c.consent_for_matching AND c.status IN ('RESOLVED','CLOSED') AND 1 - (e.embedding <=> q.embedding) >= 0.60;

\echo '=== V6: EXPLAIN, is the HNSW index used? (seq scan disabled only because the table has just 70 rows) ==='
SET LOCAL enable_seqscan = off;
EXPLAIN (COSTS OFF)
SELECT case_id FROM case_embeddings
ORDER BY embedding <=> (SELECT embedding FROM case_embeddings LIMIT 1) LIMIT 5;

ROLLBACK;
\echo '=== after ROLLBACK: must equal embeddings_before ==='
SELECT count(*) FROM case_embeddings;
