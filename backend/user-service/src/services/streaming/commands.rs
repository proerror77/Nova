//! Stream service commands for actor pattern
//!
//! Converts all StreamService methods to command-based message passing
//! to eliminate Arc<Mutex> locks and enable sequential processing

use super::models::*;
use tokio::sync::oneshot;
use uuid::Uuid;

/// All possible commands for the streaming service actor
#[derive(Debug)]
pub enum StreamCommand {
    /// Create a new stream
    CreateStream {
        creator_id: Uuid,
        request: CreateStreamRequest,
        responder: oneshot::Sender<anyhow::Result<CreateStreamResponse>>,
    },

    /// Start a stream (RTMP webhook callback)
    StartStream {
        stream_key: String,
        responder: oneshot::Sender<anyhow::Result<()>>,
    },

    /// End a stream (RTMP webhook callback)
    EndStream {
        stream_key: String,
        responder: oneshot::Sender<anyhow::Result<()>>,
    },

    /// Viewer joins a stream
    JoinStream {
        stream_id: Uuid,
        user_id: Uuid,
        responder: oneshot::Sender<anyhow::Result<JoinStreamResponse>>,
    },

    /// Viewer leaves a stream
    LeaveStream {
        stream_id: Uuid,
        user_id: Uuid,
        responder: oneshot::Sender<anyhow::Result<()>>,
    },

    /// Get detailed stream information
    GetStreamDetails {
        stream_id: Uuid,
        responder: oneshot::Sender<anyhow::Result<StreamDetails>>,
    },

    /// List live streams with pagination
    ListLiveStreams {
        category: Option<StreamCategory>,
        page: i32,
        limit: i32,
        responder: oneshot::Sender<anyhow::Result<StreamListResponse>>,
    },

    /// Post a comment to stream chat
    PostComment {
        comment: StreamComment,
        responder: oneshot::Sender<anyhow::Result<StreamComment>>,
    },

    /// Get recent comments for a stream
    RecentComments {
        stream_id: Uuid,
        limit: usize,
        responder: oneshot::Sender<anyhow::Result<Vec<StreamComment>>>,
    },
}

impl StreamCommand {
    /// Extract the stream_id from the command if available (for logging/routing)
    pub fn stream_id_hint(&self) -> Option<Uuid> {
        match self {
            Self::JoinStream { stream_id, .. }
            | Self::LeaveStream { stream_id, .. }
            | Self::GetStreamDetails { stream_id, .. }
            | Self::PostComment {
                comment: StreamComment { stream_id, .. },
                ..
            }
            | Self::RecentComments { stream_id, .. } => Some(*stream_id),
            _ => None,
        }
    }
}
