-- Realtime location sharing support
-- Allows users to share their location with conversations (1:1 or groups)

-- Note: user_id FK removed - users table is in separate database (identity-service)
CREATE TABLE IF NOT EXISTS user_locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,

    -- Location data (WGS84 coordinates)
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,

    -- Accuracy in meters (0-5000)
    accuracy_meters INT NOT NULL DEFAULT 0,

    -- Altitude in meters (optional, for future altitude-aware features)
    altitude_meters DECIMAL(9, 2),

    -- Heading in degrees (0-360, optional)
    heading_degrees DECIMAL(6, 2),

    -- Speed in m/s (optional)
    speed_mps DECIMAL(6, 2),

    -- Sharing status
    is_active BOOLEAN NOT NULL DEFAULT true,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    stopped_at TIMESTAMP WITH TIME ZONE,

    -- Soft delete support
    deleted_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT valid_latitude CHECK (latitude >= -90 AND latitude <= 90),
    CONSTRAINT valid_longitude CHECK (longitude >= -180 AND longitude <= 180),
    CONSTRAINT valid_accuracy CHECK (accuracy_meters >= 0 AND accuracy_meters <= 10000),
    CONSTRAINT valid_heading CHECK (heading_degrees IS NULL OR (heading_degrees >= 0 AND heading_degrees <= 360))
);

-- Index for fast lookups during conversation view
CREATE INDEX IF NOT EXISTS idx_user_locations_conversation
    ON user_locations(conversation_id, is_active, deleted_at)
    WHERE is_active = true AND deleted_at IS NULL;

-- Index for user's active shares (personal location history)
CREATE INDEX IF NOT EXISTS idx_user_locations_user
    ON user_locations(user_id, created_at DESC)
    WHERE is_active = true AND deleted_at IS NULL;

-- For finding active locations in a conversation
CREATE INDEX IF NOT EXISTS idx_user_locations_active
    ON user_locations(conversation_id, updated_at DESC)
    WHERE is_active = true AND deleted_at IS NULL;

-- Location sharing audit log
-- Note: user_id FK removed - users table is in separate database (identity-service)
CREATE TABLE IF NOT EXISTS location_share_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,

    -- Event type: started, updated, stopped
    event_type VARCHAR(20) NOT NULL,

    -- Location snapshot at time of event
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    accuracy_meters INT,

    -- Duration in seconds (for stopped events)
    duration_seconds INT,

    -- Total distance in meters (for future analytics)
    distance_meters INT,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_event_type CHECK (event_type IN ('started', 'updated', 'stopped'))
);

-- Index for audit trail
CREATE INDEX IF NOT EXISTS idx_location_share_events_user
    ON location_share_events(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_location_share_events_conversation
    ON location_share_events(conversation_id, created_at DESC);

-- Table for location access permissions (future: fine-grained controls)
-- Note: user_id FK removed - users table is in separate database (identity-service)
CREATE TABLE IF NOT EXISTS location_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,

    -- Who can see this user's location
    allow_conversations BOOLEAN NOT NULL DEFAULT true,  -- Can share in conversations
    allow_search BOOLEAN NOT NULL DEFAULT false,        -- Can appear in location-based search (future)

    -- Geographic privacy
    blur_location BOOLEAN NOT NULL DEFAULT false,       -- Blur to 100m accuracy

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_location_permissions_user
    ON location_permissions(user_id);
