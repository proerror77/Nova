//! Stream service commands (Actor pattern)
//!
//! Define all possible operations on streams as enum variants.
//! This enables message-passing concurrency without locks.

use super::models::*;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::sync::oneshot;
use uuid::Uuid;

/// Stream command - all operations as enum variants
/// 
/// Handlers send commands through a channel instead of holding locks.
/// The StreamActor processes them sequentially, eliminating race conditions.
#[derive(Debug)]
pub enum StreamCommand {
    /// Create a new stream
    CreateStream {
        creator_id: Uuid,
        request: CreateStreamRequest,
        responder: oneshot::Sender<Result<CreateStreamResponse>>,
    },

    /// Start stream (called by RTMP webhook)
    StartStream {
        stream_key: String,
        responder: oneshot::Sender<Result<()>>,
    },

    /// Stop stream (called by RTMP webhook or user action)
    StopStream {
        stream_id: Uuid,
        responder: oneshot::Sender<Result<()>>,
    },

    /// Get stream details
    GetStreamDetails {
        stream_id: Uuid,
        responder: oneshot::Sender<Result<StreamDetails>>,
    },

    /// Get all active streams
    GetActiveStreams {
        responder: oneshot::Sender<Result<Vec<StreamSummary>>>,
    },

    /// Search streams by title or category
    SearchStreams {
        query: String,
        category: Option<String>,
        limit: i64,
        offset: i64,
        responder: oneshot::Sender<Result<SearchStreamsResponse>>,
    },

    /// Join stream (increment viewer count)
    JoinStream {
        stream_id: Uuid,
        user_id: Uuid,
        responder: oneshot::Sender<Result<()>>,
    },

    /// Leave stream (decrement viewer count)
    LeaveStream {
        stream_id: Uuid,
        user_id: Uuid,
        responder: oneshot::Sender<Result<()>>,
    },

    /// Get current viewer count
    GetViewerCount {
        stream_id: Uuid,
        responder: oneshot::Sender<Result<i64>>,
    },

    /// Post comment on stream
    PostStreamComment {
        stream_id: Uuid,
        user_id: Uuid,
        text: String,
        responder: oneshot::Sender<Result<StreamComment>>,
    },

    /// Get comments for stream
    GetStreamComments {
        stream_id: Uuid,
        limit: i64,
        offset: i64,
        responder: oneshot::Sender<Result<Vec<StreamComment>>>,
    },

    /// Get stream analytics
    GetStreamAnalytics {
        stream_id: Uuid,
        responder: oneshot::Sender<Result<StreamAnalytics>>,
    },

    /// Update stream (title, description, etc.)
    UpdateStream {
        stream_id: Uuid,
        request: UpdateStreamRequest,
        responder: oneshot::Sender<Result<()>>,
    },
}

/// Stream summary for list/search responses
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamSummary {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub title: String,
    pub category: Option<String>,
    pub status: String,
    pub viewer_count: i64,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub thumbnail_url: Option<String>,
}

/// Stream details response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamDetails {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub category: Option<String>,
    pub status: String,
    pub viewer_count: i64,
    pub stream_key: String,
    pub rtmp_url: String,
    pub hls_url: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub started_at: Option<chrono::DateTime<chrono::Utc>>,
    pub ended_at: Option<chrono::DateTime<chrono::Utc>>,
    pub thumbnail_url: Option<String>,
}

/// Search streams response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchStreamsResponse {
    pub streams: Vec<StreamSummary>,
    pub total: i64,
}

/// Stream comment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamComment {
    pub id: Uuid,
    pub stream_id: Uuid,
    pub user_id: Uuid,
    pub text: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// Stream analytics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamAnalytics {
    pub stream_id: Uuid,
    pub total_viewers: i64,
    pub peak_viewers: i64,
    pub average_viewers: f64,
    pub total_comments: i64,
    pub duration_seconds: i64,
}

/// Update stream request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateStreamRequest {
    pub title: Option<String>,
    pub description: Option<String>,
    pub category: Option<String>,
}
