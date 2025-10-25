-- ClickHouse initialization for Nova analytics

-- Events stream (generic)
CREATE TABLE IF NOT EXISTS events (
  event_id String,
  event_type String,
  user_id Int64,
  timestamp Int64,
  properties String
) ENGINE = MergeTree
ORDER BY (timestamp, event_type)
SETTINGS index_granularity = 8192;

-- Follows CDC mirror (for feed/trending joins)
CREATE TABLE IF NOT EXISTS follows_cdc (
  follower_id Int64,
  followee_id Int64,
  created_at DateTime DEFAULT now()
) ENGINE = MergeTree
ORDER BY (created_at, follower_id)
SETTINGS index_granularity = 8192;

-- Post events (engagement tracking)
CREATE TABLE IF NOT EXISTS post_events (
  event_time DateTime DEFAULT now(),
  event_type String,
  user_id String,
  post_id String DEFAULT ''
) ENGINE = MergeTree
ORDER BY (event_time, event_type)
SETTINGS index_granularity = 8192;

