-- ============================================
-- Migration: 012_streaming_extensions
-- Description: Enable PostgreSQL extensions for streaming infrastructure
-- Author: Nova Team
-- Date: 2025-01-20
-- ============================================

-- Enable UUID extension (if available)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'uuid-ossp') THEN
        CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    ELSE
        RAISE NOTICE 'uuid-ossp extension not available; skipping';
    END IF;
END$$;

-- Enable PostGIS for geolocation-based CDN routing (if available)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'postgis') THEN
        CREATE EXTENSION IF NOT EXISTS "postgis";
    ELSE
        RAISE NOTICE 'postgis extension not available; skipping';
    END IF;
END$$;

-- Enable pg_trgm for fuzzy text search on stream titles/tags (if available)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_trgm') THEN
        CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    ELSE
        RAISE NOTICE 'pg_trgm extension not available; skipping';
    END IF;
END$$;

-- Enable btree_gin for multi-column GIN indexes on JSON fields (if available)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'btree_gin') THEN
        CREATE EXTENSION IF NOT EXISTS "btree_gin";
    ELSE
        RAISE NOTICE 'btree_gin extension not available; skipping';
    END IF;
END$$;

-- ============================================
-- Comments for documentation
-- ============================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'uuid-ossp') THEN
        EXECUTE 'COMMENT ON EXTENSION "uuid-ossp" IS ''UUID generation functions for primary keys''';
    END IF;
END $$;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        EXECUTE 'COMMENT ON EXTENSION "postgis" IS ''Geographic objects support for CDN edge location routing''';
    END IF;
END $$;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
        EXECUTE 'COMMENT ON EXTENSION "pg_trgm" IS ''Trigram matching for fuzzy search on stream metadata''';
    END IF;
END $$;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gin') THEN
        EXECUTE 'COMMENT ON EXTENSION "btree_gin" IS ''GIN indexes for JSON fields (tags, quality_distribution)''';
    END IF;
END $$;
