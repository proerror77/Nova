-- ============================================
-- Migration: 012_streaming_extensions
-- Description: Enable PostgreSQL extensions for streaming infrastructure
-- Author: Nova Team
-- Date: 2025-01-20
-- ============================================

-- Enable UUID extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable PostGIS for geolocation-based CDN routing (optional)
DO $$
BEGIN
    BEGIN
        EXECUTE 'CREATE EXTENSION IF NOT EXISTS "postgis"';
    EXCEPTION
        WHEN undefined_file THEN
            RAISE NOTICE 'postgis extension not installed; skipping';
        WHEN feature_not_supported THEN
            RAISE NOTICE 'postgis extension not supported in this build; skipping';
        WHEN undefined_object THEN
            RAISE NOTICE 'postgis extension package not available; skipping';
    END;
END
$$;

-- Enable pg_trgm for fuzzy text search on stream titles/tags
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Enable btree_gin for multi-column GIN indexes on JSON fields
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON EXTENSION "uuid-ossp" IS 'UUID generation functions for primary keys';
COMMENT ON EXTENSION "pg_trgm" IS 'Trigram matching for fuzzy search on stream metadata';
COMMENT ON EXTENSION "btree_gin" IS 'GIN indexes for JSON fields (tags, quality_distribution)';
