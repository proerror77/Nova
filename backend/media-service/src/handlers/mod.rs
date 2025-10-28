/// HTTP handlers for media-related endpoints
///
/// This module contains handlers for:
/// - Videos: Upload, process, stream videos
/// - Uploads: Handle file uploads for media
/// - Reels: Create, manage short-form video content
///
/// Extracted from user-service as part of P1.2 service splitting.

pub mod videos;
pub mod uploads;
pub mod reels;

// Explicit re-exports to avoid ambiguity
pub use videos::{
    list_videos, get_video, create_video, update_video, delete_video,
};

pub use uploads::{
    start_upload, get_upload, update_upload_progress, complete_upload, cancel_upload,
};

pub use reels::{
    list_reels, get_reel, create_reel, delete_reel,
};
