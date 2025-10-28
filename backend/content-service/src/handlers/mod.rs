/// HTTP handlers for content-related endpoints
///
/// This module contains handlers for:
/// - Posts: Create, read, update, delete posts with media attachments
/// - Comments: Create, read, update, delete comments on posts
/// - Stories: Create, read, update, delete temporary visual content
///
/// Extracted from user-service as part of P1.2 service splitting.

pub mod comments;
pub mod posts;
pub mod stories;

// Re-export handler functions at module level
pub use comments::{
    create_comment, get_post_comments, get_comment, get_comment_replies,
    update_comment, delete_comment,
};
pub use posts::{
    create_post, get_post, get_user_posts, update_post_status, delete_post,
};
pub use stories::{
    create_story, get_story, get_stories_feed, get_user_stories,
    track_story_view, update_story_privacy, delete_story,
    add_close_friend, remove_close_friend,
};
