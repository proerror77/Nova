//! Data models for live streaming
//!
//! These models represent the contract between API handlers and service layer.
//! They are NOT database models (those are in repository.rs).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// =============================================================================
// Stream Status Enum
// =============================================================================

/// Stream lifecycle status (simplified from 5 to 3 states)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "VARCHAR(20)")]
#[serde(rename_all = "lowercase")]
pub enum StreamStatus {
    /// Stream created but RTMP not yet connected
    Preparing,
    /// RTMP connected, actively streaming
    Live,
    /// Stream ended
    Ended,
}

impl StreamStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Preparing => "preparing",
            Self::Live => "live",
            Self::Ended => "ended",
        }
    }
}

// =============================================================================
// API Request Models
// =============================================================================

/// Request to create a new stream
#[derive(Debug, Deserialize, Validate)]
pub struct CreateStreamRequest {
    #[validate(length(min = 1, max = 255))]
    pub title: String,

    #[validate(length(max = 5000))]
    pub description: Option<String>,

    pub category: Option<StreamCategory>,
}

/// Stream category (for discovery/filtering)
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "VARCHAR(50)")]
#[serde(rename_all = "lowercase")]
pub enum StreamCategory {
    Gaming,
    Music,
    Tech,
    Lifestyle,
    Education,
    Other,
}

// =============================================================================
// API Response Models
// =============================================================================

/// Response after creating a stream
#[derive(Debug, Serialize)]
pub struct CreateStreamResponse {
    pub stream_id: Uuid,
    /// Secret stream key for RTMP authentication (only returned here, never again)
    pub stream_key: String,
    /// RTMP server URL (without stream key)
    pub rtmp_url: String,
    /// Full RTMP URL (server + stream key)
    pub stream_url: String,
    /// HLS URL (null until stream goes live)
    pub hls_url: Option<String>,
    pub status: StreamStatus,
    pub created_at: DateTime<Utc>,
}

/// Stream details (for GET /streams/{id})
#[derive(Debug, Serialize)]
pub struct StreamDetails {
    pub stream_id: Uuid,
    pub creator: CreatorInfo,
    pub title: String,
    pub description: Option<String>,
    pub category: Option<StreamCategory>,
    pub status: StreamStatus,
    pub hls_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub current_viewers: i32,
    pub peak_viewers: i32,
    pub started_at: Option<DateTime<Utc>>,
    pub ended_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub total_unique_viewers: i64,
    pub total_messages: i32,
}

/// Creator information (embedded in stream details)
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CreatorInfo {
    pub id: Uuid,
    pub username: String,
    pub avatar_url: Option<String>,
}

/// Stream summary (for list views)
#[derive(Debug, Serialize)]
pub struct StreamSummary {
    pub stream_id: Uuid,
    pub creator: CreatorInfo,
    pub title: String,
    pub thumbnail_url: Option<String>,
    pub current_viewers: i32,
    pub category: Option<StreamCategory>,
    pub started_at: Option<DateTime<Utc>>,
}

/// Response when viewer joins stream
#[derive(Debug, Serialize)]
pub struct JoinStreamResponse {
    /// HLS manifest URL (for video playback)
    pub hls_url: String,
    /// WebSocket URL for chat (includes JWT token)
    pub chat_ws_url: String,
    /// Current viewer count (after join)
    pub current_viewers: i32,
}

/// Viewer count response
#[derive(Debug, Serialize)]
pub struct ViewerCountResponse {
    pub current_viewers: i32,
    pub peak_viewers: i32,
}

/// Stream list response (paginated)
#[derive(Debug, Serialize)]
pub struct StreamListResponse {
    pub streams: Vec<StreamSummary>,
    pub total: i64,
    pub page: i32,
    pub limit: i32,
}

// =============================================================================
// Analytics Models
// =============================================================================

/// Stream analytics (for creator dashboard)
#[derive(Debug, Serialize)]
pub struct StreamAnalytics {
    pub stream_id: Uuid,
    pub total_unique_viewers: i64,
    pub peak_viewers: i32,
    pub average_watch_duration_secs: i32,
    pub total_messages: i32,
    pub viewer_timeline: Vec<ViewerTimelinePoint>,
    pub top_countries: Vec<CountryStats>,
}

/// Viewer count at a point in time
#[derive(Debug, Serialize)]
pub struct ViewerTimelinePoint {
    pub timestamp: DateTime<Utc>,
    pub viewers: i32,
}

/// Viewer statistics by country
#[derive(Debug, Serialize)]
pub struct CountryStats {
    pub country_code: String,
    pub viewers: i32,
}

// =============================================================================
// Internal Models (not exposed in API)
// =============================================================================

/// Database row for live_streams table
#[derive(Debug, sqlx::FromRow)]
pub(crate) struct StreamRow {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub stream_key: String,
    pub title: String,
    pub description: Option<String>,
    pub category: Option<StreamCategory>,
    pub status: StreamStatus,
    pub rtmp_url: Option<String>,
    pub hls_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub current_viewers: i32,
    pub peak_viewers: i32,
    pub total_unique_viewers: i32,
    pub total_messages: i32,
    pub auto_archive: bool,
    pub created_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub ended_at: Option<DateTime<Utc>>,
}

/// Database row for stream_metadata table
#[derive(Debug, sqlx::FromRow)]
pub(crate) struct StreamMetadataRow {
    pub stream_id: Uuid,
    pub bitrate_kbps: i32,
    pub resolution: String,
    pub fps: i32,
    pub codec: String,
    pub last_bitrate_kbps: Option<i32>,
    pub last_fps: Option<i32>,
    pub dropped_frames: i32,
    pub last_health_check_at: Option<DateTime<Utc>>,
}

// =============================================================================
// Validation
// =============================================================================

use validator::Validate;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stream_status_serialization() {
        assert_eq!(StreamStatus::Preparing.as_str(), "preparing");
        assert_eq!(StreamStatus::Live.as_str(), "live");
        assert_eq!(StreamStatus::Ended.as_str(), "ended");
    }

    #[test]
    fn test_create_stream_request_validation() {
        let valid_req = CreateStreamRequest {
            title: "Test Stream".to_string(),
            description: Some("A test stream".to_string()),
            category: Some(StreamCategory::Gaming),
        };
        assert!(valid_req.validate().is_ok());

        let invalid_req = CreateStreamRequest {
            title: "".to_string(), // Empty title
            description: None,
            category: None,
        };
        assert!(invalid_req.validate().is_err());
    }
}
