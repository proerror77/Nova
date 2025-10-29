pub mod reels;
pub mod uploads;
/// HTTP handlers for media-related endpoints
///
/// This module contains handlers for:
/// - Videos: Upload, process, stream videos
/// - Uploads: Handle file uploads for media
/// - Reels: Create, manage short-form video content
///
/// Extracted from user-service as part of P1.2 service splitting.
pub mod videos;

// Explicit re-exports to avoid ambiguity
pub use videos::{create_video, delete_video, get_video, list_videos, update_video};

pub use uploads::{
    cancel_upload, complete_upload, get_upload, start_upload, update_upload_progress,
};

pub use reels::{create_reel, delete_reel, get_reel, list_reels};
