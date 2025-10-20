-- ============================================
-- Migration: 012_streaming_extensions
-- Description: Enable PostgreSQL extensions for streaming infrastructure
-- Author: Nova Team
-- Date: 2025-01-20
-- ============================================

-- Enable UUID extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable PostGIS for geolocation-based CDN routing
CREATE EXTENSION IF NOT EXISTS "postgis";

-- Enable pg_trgm for fuzzy text search on stream titles/tags
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Enable btree_gin for multi-column GIN indexes on JSON fields
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON EXTENSION "uuid-ossp" IS 'UUID generation functions for primary keys';
COMMENT ON EXTENSION "postgis" IS 'Geographic objects support for CDN edge location routing';
COMMENT ON EXTENSION "pg_trgm" IS 'Trigram matching for fuzzy search on stream metadata';
COMMENT ON EXTENSION "btree_gin" IS 'GIN indexes for JSON fields (tags, quality_distribution)';
