-- 021_video_embeddings_pgvector.sql
-- Adds video_embeddings table using real[] for 512-d embeddings and helper functions

-- Extension 'vector' is optional; we proceed without failing if missing
-- CREATE EXTENSION IF NOT EXISTS vector; -- Uncomment when vector is available

-- Embeddings table (512-d expected but not enforced at DB level)
CREATE TABLE IF NOT EXISTS video_embeddings (
    video_id UUID PRIMARY KEY,
    embedding REAL[] NOT NULL,
    model_version TEXT NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Helper: dot product of two real[] vectors
CREATE OR REPLACE FUNCTION vec_dot(a REAL[], b REAL[])
RETURNS DOUBLE PRECISION AS $$
    SELECT COALESCE(SUM((a[i])::DOUBLE PRECISION * (b[i])::DOUBLE PRECISION), 0)
    FROM generate_subscripts(a, 1) g(i)
$$ LANGUAGE SQL IMMUTABLE;

-- Helper: L2 norm of a real[] vector
CREATE OR REPLACE FUNCTION vec_norm(a REAL[])
RETURNS DOUBLE PRECISION AS $$
    SELECT SQRT(COALESCE(SUM((a[i])::DOUBLE PRECISION * (a[i])::DOUBLE PRECISION), 0))
    FROM generate_subscripts(a, 1) g(i)
$$ LANGUAGE SQL IMMUTABLE;

-- Helper: cosine similarity between two real[] vectors
CREATE OR REPLACE FUNCTION vec_cosine_similarity(a REAL[], b REAL[])
RETURNS DOUBLE PRECISION AS $$
    SELECT CASE
        WHEN vec_norm(a) = 0 OR vec_norm(b) = 0 THEN 0
        ELSE vec_dot(a, b) / (vec_norm(a) * vec_norm(b))
    END
$$ LANGUAGE SQL IMMUTABLE;

-- Optional IVF index if 'vector' extension is available
-- CREATE INDEX IF NOT EXISTS idx_video_embeddings_embedding
--   ON video_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

