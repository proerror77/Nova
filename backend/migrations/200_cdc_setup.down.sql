-- Rollback CDC Setup Migration

-- Drop publication
DROP PUBLICATION IF EXISTS nova_cdc_publication;

-- Reset replica identity to default
ALTER TABLE posts REPLICA IDENTITY DEFAULT;
ALTER TABLE follows REPLICA IDENTITY DEFAULT;
ALTER TABLE comments REPLICA IDENTITY DEFAULT;
ALTER TABLE likes REPLICA IDENTITY DEFAULT;

-- Drop CDC tracking tables
DROP TABLE IF EXISTS cdc_sync_status;
DROP TABLE IF EXISTS cdc_heartbeat;
