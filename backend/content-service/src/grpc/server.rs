// gRPC service implementation for content service
use crate::cache::{ContentCache, FeedCache};
use crate::error::AppError;
use crate::grpc::AuthClient;
use crate::models::Post;
use crate::services::feed_ranking::FeedRankingService;
use crate::services::posts::PostService;
use chrono::{DateTime, Utc};
use grpc_metrics::layer::RequestGuard;
use sqlx::PgPool;
use std::sync::Arc;
use tokio::sync::broadcast;
use tonic::{Request, Response, Status};
use uuid::Uuid;

// Import generated proto code
pub mod nova {
    pub mod common {
        pub mod v2 {
            tonic::include_proto!("nova.common.v2");
        }
        pub use v2::*;
    }
    pub mod content_service {
        pub mod v2 {
            tonic::include_proto!("nova.content_service.v2");
        }
        pub use v2::*;
    }
    // Re-export content_service as content for backward compatibility
    pub use content_service as content;
}

use grpc_clients::nova::social_service::v2 as social_proto;
use grpc_clients::GrpcClientPool;
use nova::common::ErrorStatus;
use nova::content::content_service_server::ContentService;
use nova::content::*;

/// ContentService gRPC implementation
pub struct ContentServiceImpl {
    db_pool: PgPool,
    cache: Arc<ContentCache>,
    feed_cache: Arc<FeedCache>,
    feed_ranking: Arc<FeedRankingService>,
    auth_client: Arc<AuthClient>,
    grpc_pool: Arc<GrpcClientPool>,
}

fn convert_post_to_proto(post: &Post) -> crate::grpc::nova::content::Post {
    crate::grpc::nova::content::Post {
        id: post.id.to_string(),
        creator_id: post.user_id.to_string(),
        content: post.caption.clone().unwrap_or_default(),
        created_at: post.created_at.timestamp(),
        updated_at: post.updated_at.timestamp(),
    }
}

// Note: Comment operations have been moved to social-service.
// These gRPC methods now return Unimplemented status.

#[inline]
fn ok_error() -> Option<ErrorStatus> {
    None
}

#[inline]
fn make_error(code: &'static str, message: impl Into<String>) -> Option<ErrorStatus> {
    Some(ErrorStatus {
        code: code.to_string(),
        message: message.into(),
        metadata: Default::default(),
    })
}

fn timestamp_parts_to_secs(seconds: i64, nanos: i32) -> i64 {
    DateTime::<Utc>::from_timestamp(seconds, nanos as u32)
        .map(|dt| dt.timestamp())
        .unwrap_or(seconds)
}

fn map_social_comment(comment: social_proto::Comment) -> Comment {
    let created_at = comment
        .created_at
        .map(|ts| timestamp_parts_to_secs(ts.seconds, ts.nanos))
        .unwrap_or(0);

    Comment {
        id: comment.comment_id,
        post_id: comment.post_id,
        creator_id: comment.user_id,
        content: comment.content,
        created_at,
    }
}

fn map_social_like(like: social_proto::Liker) -> PostLike {
    let liked_at = like
        .liked_at
        .map(|ts| timestamp_parts_to_secs(ts.seconds, ts.nanos))
        .unwrap_or(0);

    PostLike {
        user_id: like.user_id,
        liked_at,
    }
}

fn map_social_status(status: Status, context: &str) -> Status {
    tracing::error!(
        context,
        code = ?status.code(),
        message = %status.message(),
        "social-service gRPC call failed"
    );
    Status::new(
        status.code(),
        format!("{context} failed: {}", status.message()),
    )
}

#[tonic::async_trait]
impl ContentService for ContentServiceImpl {
    /// Get a post by ID
    async fn get_post(
        &self,
        request: Request<GetPostRequest>,
    ) -> Result<Response<GetPostResponse>, Status> {
        let guard = RequestGuard::new("content-service", "GetPost");
        let req = request.into_inner();

        tracing::info!("gRPC: Getting post with ID: {}", req.post_id);

        // Parse post ID from string UUID
        let post_id = match Uuid::parse_str(&req.post_id) {
            Ok(id) => id,
            Err(_) => {
                guard.complete("3");
                return Err(Status::invalid_argument("Invalid post ID format"));
            }
        };

        // Fetch post using PostService
        let post_service = PostService::with_cache(self.db_pool.clone(), self.cache.clone());
        match post_service.get_post(post_id).await {
            Ok(Some(post)) => {
                let response = GetPostResponse {
                    post: Some(convert_post_to_proto(&post)),
                    found: true,
                    error: ok_error(),
                };
                guard.complete("0");
                Ok(Response::new(response))
            }
            Ok(None) => {
                let response = GetPostResponse {
                    post: None,
                    found: false,
                    error: make_error("NOT_FOUND", "Post not found"),
                };
                guard.complete("5");
                Ok(Response::new(response))
            }
            Err(e) => {
                tracing::error!("Error fetching post: {}", e);
                guard.complete("13");
                Err(Status::internal("Failed to fetch post"))
            }
        }
    }

    /// Create a new post
    async fn create_post(
        &self,
        request: Request<CreatePostRequest>,
    ) -> Result<Response<CreatePostResponse>, Status> {
        let guard = RequestGuard::new("content-service", "CreatePost");
        let req = request.into_inner();

        tracing::info!("gRPC: Creating post from user: {}", req.creator_id);

        // Parse user ID
        let user_id = match Uuid::parse_str(&req.creator_id) {
            Ok(id) => id,
            Err(_) => {
                guard.complete("3");
                return Err(Status::invalid_argument("Invalid user ID format"));
            }
        };

        // Create post using PostService
        let post_service = PostService::with_cache(self.db_pool.clone(), self.cache.clone());
        let content = req.content;
        let image_key = format!("text-content-{}", Uuid::new_v4());
        match post_service
            .create_post(user_id, Some(content.as_str()), &image_key, "text/plain")
            .await
        {
            Ok(post) => {
                let response = CreatePostResponse {
                    post: Some(convert_post_to_proto(&post)),
                    error: ok_error(),
                };
                guard.complete("0");
                Ok(Response::new(response))
            }
            Err(e) => {
                tracing::error!("Error creating post: {}", e);
                guard.complete("13");
                Err(Status::internal("Failed to create post"))
            }
        }
    }

    /// Get comments for a post (DEPRECATED - use social-service)
    async fn get_comments(
        &self,
        _request: Request<GetCommentsRequest>,
    ) -> Result<Response<GetCommentsResponse>, Status> {
        let req = _request.into_inner();

        if req.post_id.is_empty() {
            return Err(Status::invalid_argument("post_id is required"));
        }

        let limit = if req.limit <= 0 { 50 } else { req.limit }.min(100);
        let offset = req.offset.max(0);

        let social_req = social_proto::ListCommentsRequest {
            post_id: req.post_id.clone(),
            limit,
            cursor: if offset == 0 {
                String::new()
            } else {
                offset.to_string()
            },
            sort: social_proto::CommentSort::Newest as i32,
        };

        let mut social_client = self.grpc_pool.social();
        let response = social_client
            .list_comments(Request::new(social_req))
            .await
            .map_err(|status| map_social_status(status, "social_service.ListComments"))?
            .into_inner();

        let total = response.comments.len() as i32;
        let comments = response
            .comments
            .into_iter()
            .map(map_social_comment)
            .collect();

        Ok(Response::new(GetCommentsResponse {
            comments,
            total,
            error: ok_error(),
        }))
    }

    /// Create a comment (DEPRECATED - use social-service)
    async fn create_comment(
        &self,
        _request: Request<CreateCommentRequest>,
    ) -> Result<Response<CreateCommentResponse>, Status> {
        let req = _request.into_inner();

        if req.post_id.is_empty() || req.user_id.is_empty() || req.content.trim().is_empty() {
            return Err(Status::invalid_argument(
                "post_id, user_id, and content are required",
            ));
        }

        let social_req = social_proto::CreateCommentRequest {
            post_id: req.post_id.clone(),
            user_id: req.user_id.clone(),
            content: req.content.clone(),
            parent_comment_id: req.parent_comment_id.clone(),
        };

        let mut social_client = self.grpc_pool.social();
        let response = social_client
            .create_comment(Request::new(social_req))
            .await
            .map_err(|status| map_social_status(status, "social_service.CreateComment"))?
            .into_inner();

        let comment = response
            .comment
            .map(map_social_comment)
            .ok_or_else(|| Status::internal("social-service returned empty comment payload"))?;

        Ok(Response::new(CreateCommentResponse {
            comment: Some(comment),
            error: ok_error(),
        }))
    }

    /// Update a comment (DEPRECATED - use social-service)
    async fn update_comment(
        &self,
        _request: Request<UpdateCommentRequest>,
    ) -> Result<Response<UpdateCommentResponse>, Status> {
        let req = _request.into_inner();

        if req.comment_id.is_empty() || req.user_id.is_empty() {
            return Err(Status::invalid_argument(
                "comment_id and user_id are required",
            ));
        }

        let social_req = social_proto::UpdateCommentRequest {
            comment_id: req.comment_id.clone(),
            user_id: req.user_id.clone(),
            content: req.content.clone(),
        };

        let mut social_client = self.grpc_pool.social();
        let response = social_client
            .update_comment(Request::new(social_req))
            .await
            .map_err(|status| map_social_status(status, "social_service.UpdateComment"))?
            .into_inner();

        let comment = response
            .comment
            .map(map_social_comment)
            .ok_or_else(|| Status::internal("social-service returned empty comment payload"))?;

        Ok(Response::new(UpdateCommentResponse {
            comment: Some(comment),
            error: ok_error(),
        }))
    }

    /// Delete a comment (DEPRECATED - use social-service)
    async fn delete_comment(
        &self,
        _request: Request<DeleteCommentRequest>,
    ) -> Result<Response<DeleteCommentResponse>, Status> {
        let req = _request.into_inner();

        if req.comment_id.is_empty() || req.user_id.is_empty() {
            return Err(Status::invalid_argument(
                "comment_id and user_id are required",
            ));
        }

        let social_req = social_proto::DeleteCommentRequest {
            comment_id: req.comment_id.clone(),
            user_id: req.user_id.clone(),
        };

        let mut social_client = self.grpc_pool.social();
        social_client
            .delete_comment(Request::new(social_req))
            .await
            .map_err(|status| map_social_status(status, "social_service.DeleteComment"))?;

        Ok(Response::new(DeleteCommentResponse {
            comment_id: req.comment_id,
            deleted_at: Utc::now().timestamp(),
        }))
    }

    /// Like a post (DEPRECATED - use social-service)
    async fn like_post(
        &self,
        _request: Request<LikePostRequest>,
    ) -> Result<Response<LikePostResponse>, Status> {
        let req = _request.into_inner();

        if req.post_id.is_empty() || req.user_id.is_empty() {
            return Err(Status::invalid_argument("post_id and user_id are required"));
        }

        let social_req = social_proto::CreateLikeRequest {
            user_id: req.user_id.clone(),
            post_id: req.post_id.clone(),
        };

        let mut social_client = self.grpc_pool.social();
        let response = social_client
            .create_like(Request::new(social_req))
            .await
            .map_err(|status| map_social_status(status, "social_service.CreateLike"))?
            .into_inner();

        Ok(Response::new(LikePostResponse {
            success: response.success,
            error: ok_error(),
        }))
    }

    /// Unlike a post (DEPRECATED - use social-service)
    async fn unlike_post(
        &self,
        _request: Request<UnlikePostRequest>,
    ) -> Result<Response<UnlikePostResponse>, Status> {
        let req = _request.into_inner();

        if req.post_id.is_empty() || req.user_id.is_empty() {
            return Err(Status::invalid_argument("post_id and user_id are required"));
        }

        let social_req = social_proto::DeleteLikeRequest {
            user_id: req.user_id.clone(),
            post_id: req.post_id.clone(),
        };

        let mut social_client = self.grpc_pool.social();
        let response = social_client
            .delete_like(Request::new(social_req))
            .await
            .map_err(|status| map_social_status(status, "social_service.DeleteLike"))?
            .into_inner();

        Ok(Response::new(UnlikePostResponse {
            success: response.success,
            error: ok_error(),
        }))
    }

    /// Get users who liked a post (DEPRECATED - use social-service)
    async fn get_post_likes(
        &self,
        _request: Request<GetPostLikesRequest>,
    ) -> Result<Response<GetPostLikesResponse>, Status> {
        let req = _request.into_inner();

        if req.post_id.is_empty() {
            return Err(Status::invalid_argument("post_id is required"));
        }

        let limit = if req.limit <= 0 { 50 } else { req.limit }.min(100);
        let offset = req.offset.max(0);

        let social_req = social_proto::GetLikersRequest {
            post_id: req.post_id.clone(),
            limit,
            cursor: if offset == 0 {
                String::new()
            } else {
                offset.to_string()
            },
        };

        let mut social_client = self.grpc_pool.social();
        let response = social_client
            .get_likers(Request::new(social_req))
            .await
            .map_err(|status| map_social_status(status, "social_service.GetLikers"))?
            .into_inner();

        let like_rows = response
            .likers
            .into_iter()
            .map(map_social_like)
            .collect::<Vec<_>>();

        let total_count = like_rows.len() as i32;

        Ok(Response::new(GetPostLikesResponse {
            likes: like_rows,
            total_count,
            error: ok_error(),
        }))
    }

    /// Get multiple posts by IDs (batch operation)
    async fn get_posts_by_ids(
        &self,
        request: Request<GetPostsByIdsRequest>,
    ) -> Result<Response<GetPostsByIdsResponse>, Status> {
        let req = request.into_inner();

        if req.post_ids.is_empty() {
            return Ok(Response::new(GetPostsByIdsResponse { posts: vec![] }));
        }

        tracing::info!("gRPC: Getting {} posts by IDs", req.post_ids.len());

        // Parse all post IDs
        let mut post_ids = Vec::with_capacity(req.post_ids.len());
        for post_id_str in &req.post_ids {
            let post_id = Uuid::parse_str(post_id_str)
                .map_err(|_| Status::invalid_argument("Invalid post ID format"))?;
            post_ids.push(post_id);
        }

        // Build the query with proper parameterization for all post IDs
        let query_str = "SELECT id, user_id, caption, image_key, image_sizes, status, content_type, created_at, updated_at, deleted_at FROM posts WHERE id = ANY($1::uuid[]) AND deleted_at IS NULL ORDER BY created_at DESC".to_string();

        let posts = sqlx::query_as::<_, Post>(&query_str)
            .bind(&post_ids)
            .fetch_all(&self.db_pool)
            .await
            .map_err(|e| {
                tracing::error!("Database error fetching posts by IDs: {}", e);
                Status::internal("Failed to fetch posts")
            })?;

        let proto_posts = posts.iter().map(convert_post_to_proto).collect();

        Ok(Response::new(GetPostsByIdsResponse { posts: proto_posts }))
    }

    /// Get posts by author with pagination
    async fn get_posts_by_author(
        &self,
        request: Request<GetPostsByAuthorRequest>,
    ) -> Result<Response<GetPostsByAuthorResponse>, Status> {
        let guard = RequestGuard::new("content-service", "GetPostsByAuthor");
        let req = request.into_inner();

        tracing::info!(
            "gRPC: Getting posts by author: {} (status: {}, limit: {}, offset: {})",
            req.author_id,
            req.status,
            req.limit,
            req.offset
        );

        // Parse author ID
        let author_id = match Uuid::parse_str(&req.author_id) {
            Ok(id) => id,
            Err(_) => {
                guard.complete("3");
                return Err(Status::invalid_argument("Invalid author ID format"));
            }
        };

        let limit = req.limit.clamp(1, 100) as i64;
        let offset = req.offset.max(0) as i64;

        // Build query with optional status filter
        let (query_str, count_query_str) = if req.status.is_empty() {
            (
                "SELECT id, user_id, caption, image_key, image_sizes, status, content_type, created_at, updated_at, deleted_at FROM posts WHERE user_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT $2 OFFSET $3".to_string(),
                "SELECT COUNT(*) FROM posts WHERE user_id = $1 AND deleted_at IS NULL".to_string(),
            )
        } else {
            (
                "SELECT id, user_id, caption, image_key, image_sizes, status, content_type, created_at, updated_at, deleted_at FROM posts WHERE user_id = $1 AND status = $2 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT $3 OFFSET $4".to_string(),
                "SELECT COUNT(*) FROM posts WHERE user_id = $1 AND status = $2 AND deleted_at IS NULL".to_string(),
            )
        };

        // Fetch posts
        let posts = match if req.status.is_empty() {
            sqlx::query_as::<_, Post>(&query_str)
                .bind(author_id)
                .bind(limit)
                .bind(offset)
                .fetch_all(&self.db_pool)
                .await
        } else {
            sqlx::query_as::<_, Post>(&query_str)
                .bind(author_id)
                .bind(&req.status)
                .bind(limit)
                .bind(offset)
                .fetch_all(&self.db_pool)
                .await
        } {
            Ok(p) => p,
            Err(e) => {
                tracing::error!("Database error fetching posts by author: {}", e);
                guard.complete("13");
                return Err(Status::internal("Failed to fetch posts"));
            }
        };

        // Fetch total count
        let total: i64 = match if req.status.is_empty() {
            sqlx::query_scalar(&count_query_str)
                .bind(author_id)
                .fetch_one(&self.db_pool)
                .await
        } else {
            sqlx::query_scalar(&count_query_str)
                .bind(author_id)
                .bind(&req.status)
                .fetch_one(&self.db_pool)
                .await
        } {
            Ok(t) => t,
            Err(e) => {
                tracing::error!("Database error counting posts by author: {}", e);
                guard.complete("13");
                return Err(Status::internal("Failed to count posts"));
            }
        };

        let proto_posts = posts.iter().map(convert_post_to_proto).collect();

        let total_count = i32::try_from(total).unwrap_or_else(|_| {
            tracing::warn!("Post count exceeded i32::MAX: {}", total);
            i32::MAX
        });

        guard.complete("0");
        Ok(Response::new(GetPostsByAuthorResponse {
            posts: proto_posts,
            total_count,
        }))
    }

    /// Update a post
    async fn update_post(
        &self,
        request: Request<UpdatePostRequest>,
    ) -> Result<Response<UpdatePostResponse>, Status> {
        let guard = RequestGuard::new("content-service", "UpdatePost");
        let req = request.into_inner();

        tracing::info!("gRPC: Updating post: {}", req.post_id);

        // Parse post ID
        let post_id = match Uuid::parse_str(&req.post_id) {
            Ok(id) => id,
            Err(_) => {
                guard.complete("3");
                return Err(Status::invalid_argument("Invalid post ID format"));
            }
        };

        // Start a transaction to ensure atomicity
        let mut tx = match self.db_pool.begin().await {
            Ok(tx) => tx,
            Err(e) => {
                tracing::error!("Database error starting transaction: {}", e);
                guard.complete("13");
                return Err(Status::internal("Failed to update post"));
            }
        };

        // Update the post with only non-empty fields
        let update_query = if req.title.is_empty()
            && req.content.is_empty()
            && req.privacy.is_empty()
            && req.status.is_empty()
        {
            // No fields to update
            sqlx::query("SELECT id FROM posts WHERE id = $1 AND deleted_at IS NULL")
                .bind(post_id)
                .execute(&mut *tx)
                .await
        } else {
            // Build dynamic update based on provided fields
            let mut updates = vec!["updated_at = NOW()".to_string()];
            let mut bindings: Vec<String> = vec![];
            let mut param_index = 2;

            if !req.title.is_empty() {
                updates.push(format!("title = ${}", param_index));
                bindings.push(req.title.clone());
                param_index += 1;
            }

            if !req.content.is_empty() {
                updates.push(format!("caption = ${}", param_index));
                bindings.push(req.content.clone());
                param_index += 1;
            }

            if !req.privacy.is_empty() {
                updates.push(format!("privacy = ${}", param_index));
                bindings.push(req.privacy.clone());
                param_index += 1;
            }

            if !req.status.is_empty() {
                updates.push(format!("status = ${}", param_index));
                bindings.push(req.status.clone());
            }

            let update_clause = updates.join(", ");
            let query_str = format!(
                "UPDATE posts SET {} WHERE id = $1 AND deleted_at IS NULL RETURNING id, user_id, caption, image_key, image_sizes, status, content_type, created_at, updated_at, deleted_at",
                update_clause
            );

            let mut query = sqlx::query_as::<_, Post>(&query_str).bind(post_id);

            for binding in bindings {
                query = query.bind(binding);
            }

            match query.fetch_optional(&mut *tx).await {
                Ok(_) => {}
                Err(e) => {
                    tracing::error!("Database error updating post: {}", e);
                    guard.complete("13");
                    return Err(Status::internal("Failed to update post"));
                }
            }

            sqlx::query("SELECT 1").execute(&mut *tx).await
        };

        match update_query {
            Ok(_) => {
                // Commit transaction and invalidate cache
                if let Err(e) = tx.commit().await {
                    tracing::error!("Database error committing transaction: {}", e);
                    guard.complete("13");
                    return Err(Status::internal("Failed to update post"));
                }

                // Invalidate cache for this post
                let _ = self.cache.invalidate_post(post_id).await;
                tracing::debug!("Invalidated cache for post {} after update", post_id);

                // Fetch the updated post
                let post_service =
                    PostService::with_cache(self.db_pool.clone(), self.cache.clone());
                match post_service.get_post(post_id).await {
                    Ok(Some(post)) => {
                        guard.complete("0");
                        Ok(Response::new(UpdatePostResponse {
                            post: Some(convert_post_to_proto(&post)),
                        }))
                    }
                    Ok(None) => {
                        tracing::warn!("Updated post {} not found", post_id);
                        guard.complete("5");
                        Err(Status::not_found("Post not found after update"))
                    }
                    Err(e) => {
                        tracing::error!("Error fetching updated post: {}", e);
                        guard.complete("13");
                        Err(Status::internal("Failed to fetch updated post"))
                    }
                }
            }
            Err(e) => {
                tracing::error!("Error updating post: {}", e);
                guard.complete("13");
                Err(Status::internal("Failed to update post"))
            }
        }
    }

    /// Delete (soft delete) a post
    async fn delete_post(
        &self,
        request: Request<DeletePostRequest>,
    ) -> Result<Response<DeletePostResponse>, Status> {
        let guard = RequestGuard::new("content-service", "DeletePost");
        let req = request.into_inner();

        tracing::info!(
            "gRPC: Deleting post: {} (deleted_by: {})",
            req.post_id,
            req.deleted_by_id
        );

        // Parse IDs
        let post_id = match Uuid::parse_str(&req.post_id) {
            Ok(id) => id,
            Err(_) => {
                guard.complete("3");
                return Err(Status::invalid_argument("Invalid post ID format"));
            }
        };
        // Validate deleted_by_id exists (not used in this implementation but required by proto)
        let _deleted_by_id = match Uuid::parse_str(&req.deleted_by_id) {
            Ok(id) => id,
            Err(_) => {
                guard.complete("3");
                return Err(Status::invalid_argument("Invalid deleted_by_id format"));
            }
        };

        // Soft delete the post (set deleted_at timestamp)
        let result = match sqlx::query_scalar::<_, chrono::DateTime<chrono::Utc>>(
            "UPDATE posts SET deleted_at = NOW() WHERE id = $1 AND deleted_at IS NULL RETURNING deleted_at",
        )
        .bind(post_id)
        .fetch_optional(&self.db_pool)
        .await {
            Ok(r) => r,
            Err(e) => {
                tracing::error!("Database error deleting post: {}", e);
                guard.complete("13");
                return Err(Status::internal("Failed to delete post"));
            }
        };

        match result {
            Some(deleted_at) => {
                // Invalidate cache for this post
                let _ = self.cache.invalidate_post(post_id).await;
                tracing::debug!("Invalidated cache for post {} after delete", post_id);

                guard.complete("0");
                Ok(Response::new(DeletePostResponse {
                    post_id: post_id.to_string(),
                    deleted_at: deleted_at.timestamp(),
                }))
            }
            None => {
                tracing::warn!("Post {} not found or already deleted", post_id);
                guard.complete("5");
                Err(Status::not_found("Post not found or already deleted"))
            }
        }
    }

    /// Decrement like count (unlike operation)
    async fn decrement_like_count(
        &self,
        request: Request<DecrementLikeCountRequest>,
    ) -> Result<Response<DecrementLikeCountResponse>, Status> {
        let req = request.into_inner();

        tracing::info!("gRPC: Decrementing like count for post: {}", req.post_id);

        // Parse post ID
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post ID format"))?;

        // Get the current like count from the likes table
        let like_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM likes WHERE post_id = $1")
            .bind(post_id)
            .fetch_one(&self.db_pool)
            .await
            .map_err(|e| {
                tracing::error!("Database error counting likes: {}", e);
                Status::internal("Failed to decrement like count")
            })?;

        // Invalidate cache to force refresh
        let _ = self.cache.invalidate_post(post_id).await;
        tracing::debug!("Invalidated cache for post {} after decrement", post_id);

        let like_count_i32 = i32::try_from(like_count).unwrap_or_else(|_| {
            tracing::warn!(
                "Like count exceeded i32::MAX for post {}: {}",
                post_id,
                like_count
            );
            i32::MAX
        });

        Ok(Response::new(DecrementLikeCountResponse {
            like_count: like_count_i32,
        }))
    }

    /// Check if a post exists
    async fn check_post_exists(
        &self,
        request: Request<CheckPostExistsRequest>,
    ) -> Result<Response<CheckPostExistsResponse>, Status> {
        let req = request.into_inner();

        tracing::info!("gRPC: Checking post existence: {}", req.post_id);

        // Parse post ID
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post ID format"))?;

        // Check if post exists and is not soft-deleted
        let exists: bool = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM posts WHERE id = $1 AND deleted_at IS NULL)",
        )
        .bind(post_id)
        .fetch_one(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error checking post existence: {}", e);
            Status::internal("Failed to check post existence")
        })?;

        Ok(Response::new(CheckPostExistsResponse { exists }))
    }

    /// Get user bookmarks
    async fn get_user_bookmarks(
        &self,
        request: Request<GetUserBookmarksRequest>,
    ) -> Result<Response<GetUserBookmarksResponse>, Status> {
        let req = request.into_inner();

        tracing::info!(
            "gRPC: Getting bookmarks for user: {} (limit: {}, offset: {})",
            req.user_id,
            req.limit,
            req.offset
        );

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let limit = req.limit.clamp(1, 100) as i64;
        let offset = req.offset.max(0) as i64;

        // Fetch bookmarks joined with posts (ignoring soft-deleted posts)
        let posts = sqlx::query_as::<_, Post>(
            r#"
            SELECT
                p.id,
                p.user_id,
                p.caption,
                p.image_key,
                p.image_sizes,
                p.status,
                p.content_type,
                p.created_at,
                p.updated_at,
                p.soft_delete
            FROM bookmarks b
            INNER JOIN posts p ON p.id = b.post_id
            WHERE b.user_id = $1
              AND p.soft_delete IS NULL
            ORDER BY b.bookmarked_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error fetching bookmarks: {}", e);
            Status::internal("Failed to load bookmarks")
        })?;

        // Fetch total count for pagination
        let total =
            sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM bookmarks WHERE user_id = $1")
                .bind(user_id)
                .fetch_one(&self.db_pool)
                .await
                .map_err(|e| {
                    tracing::error!("Database error counting bookmarks: {}", e);
                    Status::internal("Failed to count bookmarks")
                })?;

        let bookmark_posts = posts
            .into_iter()
            .map(|post| convert_post_to_proto(&post))
            .collect();

        let total_i32 = i32::try_from(total).unwrap_or_else(|_| {
            tracing::warn!("Bookmark count exceeded i32::MAX: {}", total);
            i32::MAX
        });

        let response = GetUserBookmarksResponse {
            posts: bookmark_posts,
            total: total_i32,
            error: ok_error(),
        };

        Ok(Response::new(response))
    }

    // Note: Social operations (create_comment, update_comment, delete_comment,
    // like_post, unlike_post, get_post_likes) have been moved to social-service.
    // The stub implementations above return Unimplemented status.
}

impl ContentServiceImpl {
    /// Create a new ContentServiceImpl with database pool
    pub fn new(
        db_pool: PgPool,
        cache: Arc<ContentCache>,
        feed_cache: Arc<FeedCache>,
        feed_ranking: Arc<FeedRankingService>,
        auth_client: Arc<AuthClient>,
        grpc_pool: Arc<GrpcClientPool>,
    ) -> Self {
        Self {
            db_pool,
            cache,
            feed_cache,
            feed_ranking,
            auth_client,
            grpc_pool,
        }
    }
}

/// Create a gRPC server for content service
pub async fn start_grpc_server(
    addr: std::net::SocketAddr,
    db_pool: PgPool,
    cache: Arc<ContentCache>,
    feed_cache: Arc<FeedCache>,
    feed_ranking: Arc<FeedRankingService>,
    auth_client: Arc<AuthClient>,
    grpc_pool: Arc<GrpcClientPool>,
    mut shutdown: broadcast::Receiver<()>,
) -> Result<(), Box<dyn std::error::Error>> {
    use nova::content::content_service_server::ContentServiceServer;
    use tonic::transport::Server;
    use tonic_health::server::health_reporter;

    tracing::info!("Starting gRPC server at {}", addr);

    let service = ContentServiceImpl::new(
        db_pool,
        cache,
        feed_cache,
        feed_ranking,
        auth_client,
        grpc_pool,
    );

    // Health service
    let (mut health, health_service) = health_reporter();
    health
        .set_serving::<crate::grpc::nova::content::content_service_server::ContentServiceServer<ContentServiceImpl>>()
        .await;

    // Server-side correlation-id extractor interceptor
    fn server_interceptor(
        mut req: tonic::Request<()>,
    ) -> Result<tonic::Request<()>, tonic::Status> {
        if let Some(val) = req.metadata().get("correlation-id") {
            if let Ok(s) = val.to_str() {
                let correlation_id = s.to_string();
                req.extensions_mut().insert::<String>(correlation_id);
            }
        }
        Ok(req)
    }

    // ✅ P0: Load mTLS configuration
    //
    // In production, missing TLS configuration is a hard error.
    // In non-production environments (development only),
    // we allow starting without TLS to keep the environment usable.
    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    let env_lower = app_env.to_ascii_lowercase();
    let tls_required_env = matches!(env_lower.as_str(), "production" | "staging");

    let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
        Ok(config) => {
            tracing::info!(
                "mTLS enabled - service-to-service authentication active (env = {})",
                app_env
            );
            Some(config)
        }
        Err(e) => {
            tracing::warn!(
                "mTLS disabled - TLS config not found for env '{}': {}.",
                app_env,
                e
            );

            if tls_required_env {
                return Err(format!(
                    "Production/Staging requires mTLS - GRPC_SERVER_CERT_PATH must be set: {}",
                    e
                )
                .into());
            }

            tracing::info!(
                "Development environment ({}): running gRPC server without TLS (NOT FOR PRODUCTION)",
                app_env
            );
            None
        }
    };

    // ✅ P0: Build server with optional TLS
    let mut server_builder = Server::builder();

    if let Some(tls_cfg) = tls_config {
        let server_tls = tls_cfg
            .build_server_tls()
            .map_err(|e| format!("Failed to build server TLS config: {}", e))?;
        server_builder = server_builder
            .tls_config(server_tls)
            .map_err(|e| format!("Failed to configure TLS on gRPC server: {}", e))?;
        tracing::info!("gRPC server TLS configured successfully");
    }

    server_builder
        .add_service(health_service)
        .add_service(ContentServiceServer::with_interceptor(
            service,
            server_interceptor,
        ))
        .serve_with_shutdown(addr, async move {
            // Wait for shutdown notification; ignore errors if sender dropped.
            let _ = shutdown.recv().await;
        })
        .await?;

    Ok(())
}

fn map_app_error(err: AppError, context: &str) -> Status {
    match err {
        AppError::ValidationError(msg) | AppError::BadRequest(msg) => {
            Status::invalid_argument(format!("{}: {}", context, msg))
        }
        AppError::NotFound(msg) => Status::not_found(msg),
        AppError::Unauthorized(msg) | AppError::Forbidden(msg) => Status::permission_denied(msg),
        AppError::Conflict(msg) => Status::already_exists(msg),
        AppError::DatabaseError(msg) => {
            tracing::error!("Database error ({}): {}", context, msg);
            Status::internal("Database operation failed")
        }
        AppError::Internal(msg) => {
            tracing::error!("Internal error ({}): {}", context, msg);
            Status::internal("Internal server error")
        }
        AppError::CacheError(msg) => {
            tracing::error!("Cache error ({}): {}", context, msg);
            Status::internal("Cache operation failed")
        }
    }
}
