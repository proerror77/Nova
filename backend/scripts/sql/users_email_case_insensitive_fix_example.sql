-- Example data-fix: resolve case-insensitive duplicate emails by suffixing '+dedup-<id>'
-- IMPORTANT: Review before running in production.
--            Prefer communicating with affected users and using domain-specific resolution.
-- Usage:
--   psql "$DATABASE_URL" -v EMAIL_DOMAIN_FALLBACK='example.com' -f backend/scripts/sql/users_email_case_insensitive_fix_example.sql

BEGIN;

-- 1) Identify duplicates (case-insensitive)
CREATE TEMP TABLE tmp_email_dups AS
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
HAVING COUNT(*) > 1;

-- 2) Choose winners (earliest created_at) and mark others as losers
CREATE TEMP TABLE tmp_email_losers AS
SELECT d.email_lower,
       UNNEST(user_ids[2:ARRAY_LENGTH(user_ids, 1)]) AS loser_id
FROM tmp_email_dups d;

-- 3) Update losers by suffixing local-part with '+dedup-<shortid>'
--    This preserves domain and keeps email RFC-valid.
--    Example: alice@example.com -> alice+dedup-1a2b3c4d@example.com
UPDATE users u
SET email = (
  SELECT
    concat(
      split_part(u.email, '@', 1),
      '+dedup-',
      SUBSTR(u.id::text, 1, 8),
      '@',
      split_part(u.email, '@', 2)
    )
)
FROM tmp_email_losers l
WHERE u.id = l.loser_id;

-- 4) Optional: de-activate losers (domain specific)
-- UPDATE users u SET is_active = FALSE FROM tmp_email_losers l WHERE u.id = l.loser_id;

COMMIT;

-- After this, re-run the audit to confirm no dupes remain, then apply CITEXT migration.

