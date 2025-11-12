/// Authorization module for content-service
///
/// Provides ownership-based permission checks for posts, comments, and other content.
/// This service verifies that users can only modify content they own.
use actix_web::{error::ErrorForbidden, Error};
use uuid::Uuid;

use crate::models::{Bookmark, Post};
// Note: Comment, Like, PostShare ownership checks moved to social-service

/// Result type for permission checks
pub type PermissionResult = Result<(), Error>;

/// Check if a user owns a post
pub fn check_post_ownership(user_id: Uuid, post: &Post) -> PermissionResult {
    if post.user_id == user_id {
        Ok(())
    } else {
        Err(ErrorForbidden(
            "You don't have permission to modify this post",
        ))
    }
}

/// Check if a user owns a bookmark
pub fn check_bookmark_ownership(user_id: Uuid, bookmark: &Bookmark) -> PermissionResult {
    if bookmark.user_id == user_id {
        Ok(())
    } else {
        Err(ErrorForbidden(
            "You don't have permission to delete this bookmark",
        ))
    }
}

/// Verify user has access to delete a post
/// Only the owner can delete their own posts
pub fn check_post_deletion(user_id: Uuid, post: &Post) -> PermissionResult {
    check_post_ownership(user_id, post)
}

/// Verify user has access to update a post
/// Only the owner can update their own posts
pub fn check_post_update(user_id: Uuid, post: &Post) -> PermissionResult {
    check_post_ownership(user_id, post)
}

// Note: check_comment_ownership, check_like_ownership, check_share_ownership
// moved to social-service
