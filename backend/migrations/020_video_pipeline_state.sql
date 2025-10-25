-- Video processing pipeline status persistence

CREATE TABLE IF NOT EXISTS video_pipeline_state (
    video_id UUID PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE,
    stage VARCHAR(64) NOT NULL,
    progress_percent INT NOT NULL DEFAULT 0 CHECK (progress_percent >= 0 AND progress_percent <= 100),
    current_step TEXT NOT NULL,
    error TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

