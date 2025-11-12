/// HTTP handlers for content-related endpoints
///
/// This module contains handlers for:
/// - Posts: Create, read, update, delete posts with media attachments
/// - Stories: Create, read, update, delete temporary visual content
///
/// Note: Comment/like/share operations are handled by social-service via gRPC.
/// Extracted from user-service as part of P1.2 service splitting.
pub mod feed;
pub mod posts;
pub mod stories;

// Re-export handler functions at module level
pub use feed::get_feed;
pub use posts::{create_post, delete_post, get_post, get_user_posts, update_post_status};
pub use stories::{
    add_close_friend, create_story, delete_story, get_stories_feed, get_story, get_user_stories,
    remove_close_friend, track_story_view, update_story_privacy,
};
