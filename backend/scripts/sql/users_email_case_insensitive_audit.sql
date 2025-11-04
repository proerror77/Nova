-- Audit script: find case-insensitive duplicate emails prior to CITEXT conversion
-- Usage:
--   psql "$DATABASE_URL" -f backend/scripts/sql/users_email_case_insensitive_audit.sql

WITH normalized AS (
  SELECT id, email, LOWER(email) AS email_lower, created_at
  FROM users
)
SELECT email_lower,
       COUNT(*) AS dup_count,
       MIN(created_at) AS earliest_created_at,
       ARRAY_AGG(id ORDER BY created_at ASC) AS user_ids
FROM normalized
GROUP BY email_lower
HAVING COUNT(*) > 1
ORDER BY dup_count DESC, email_lower;

-- Tip: review the rows and decide which account is canonical (usually earliest_created_at)
--       then update the others before applying CITEXT conversion.

