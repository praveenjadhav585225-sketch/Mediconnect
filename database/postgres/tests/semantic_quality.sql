-- semantic_quality.sql : how good is the REAL MiniLM matching? (read-only, needs: python database/scripts/embed_cases.py)
-- For each of the 6 active cases, take the top-5 most similar historical cases and see how many share the specialization.
-- Some cross-over is NORMAL: cardiology and pulmonology both describe breathlessness. Report it honestly, it is not a defect.
\pset pager off
\echo '=== Q1: embeddings loaded and model used ==='
SELECT model_name, count(*) AS embeddings, min(vector_dims(embedding)) AS dims FROM case_embeddings GROUP BY model_name;

\echo '=== Q2: per active case, how many of the top-5 neighbours share its specialization ==='
SELECT sq.name AS query_specialization,
       count(*) AS neighbours,
       count(*) FILTER (WHERE n.specialization_id = a.specialization_id) AS same_specialization,
       round(avg(n.sim)::numeric, 3) AS avg_similarity
FROM (SELECT c.case_id, c.specialization_id, e.embedding FROM medical_cases c JOIN case_embeddings e USING (case_id) WHERE c.status='SUBMITTED') a
JOIN specializations sq ON sq.specialization_id = a.specialization_id
CROSS JOIN LATERAL (
  SELECT c.specialization_id, 1 - (e.embedding <=> a.embedding) AS sim
  FROM case_embeddings e JOIN medical_cases c USING (case_id)
  WHERE c.consent_for_matching AND c.status IN ('RESOLVED','CLOSED')
  ORDER BY e.embedding <=> a.embedding LIMIT 5) n
GROUP BY sq.name ORDER BY sq.name;

\echo '=== Q3: overall ==='
SELECT count(*) AS neighbours_checked,
       count(*) FILTER (WHERE n.specialization_id = a.specialization_id) AS same_specialization,
       round(100.0 * count(*) FILTER (WHERE n.specialization_id = a.specialization_id) / count(*), 1) AS pct_same
FROM (SELECT c.specialization_id, e.embedding FROM medical_cases c JOIN case_embeddings e USING (case_id) WHERE c.status='SUBMITTED') a
CROSS JOIN LATERAL (
  SELECT c.specialization_id FROM case_embeddings e JOIN medical_cases c USING (case_id)
  WHERE c.consent_for_matching AND c.status IN ('RESOLVED','CLOSED')
  ORDER BY e.embedding <=> a.embedding LIMIT 5) n;
