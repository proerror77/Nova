/// Authorization module for content-service
///
/// Provides ownership-based permission checks for posts, comments, and other content.
/// This service verifies that users can only modify content they own.

use actix_web::{error::ErrorForbidden, Error};
use uuid::Uuid;

use crate::models::{Post, Comment, Like, Bookmark, PostShare};

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

/// Check if a user owns a comment
pub fn check_comment_ownership(user_id: Uuid, comment: &Comment) -> PermissionResult {
    if comment.user_id == user_id {
        Ok(())
    } else {
        Err(ErrorForbidden(
            "You don't have permission to modify this comment",
        ))
    }
}

/// Check if a user owns a like
pub fn check_like_ownership(user_id: Uuid, like: &Like) -> PermissionResult {
    if like.user_id == user_id {
        Ok(())
    } else {
        Err(ErrorForbidden(
            "You don't have permission to delete this like",
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

/// Check if a user owns a post share
pub fn check_post_share_ownership(user_id: Uuid, share: &PostShare) -> PermissionResult {
    if share.user_id == user_id {
        Ok(())
    } else {
        Err(ErrorForbidden(
            "You don't have permission to delete this share",
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

/// Verify user has access to delete a comment
/// Only the owner can delete their own comments
pub fn check_comment_deletion(user_id: Uuid, comment: &Comment) -> PermissionResult {
    check_comment_ownership(user_id, comment)
}

/// Verify user has access to update a comment
/// Only the owner can update their own comments
pub fn check_comment_update(user_id: Uuid, comment: &Comment) -> PermissionResult {
    check_comment_ownership(user_id, comment)
}
