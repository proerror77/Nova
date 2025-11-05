// gRPC service implementation for content service
use crate::cache::{ContentCache, FeedCache};
use crate::error::AppError;
use crate::handlers::feed::FeedQueryParams;
use crate::models::{Comment, Post};
use crate::services::comments::CommentService;
use crate::services::feed_ranking::FeedRankingService;
use crate::services::posts::PostService;
use sqlx::PgPool;
use std::sync::Arc;
use tokio::sync::broadcast;
use tonic::{Request, Response, Status};
use tracing::warn;
use uuid::Uuid;

// Import generated proto code
pub mod nova {
    pub mod common {
        pub mod v1 {
            tonic::include_proto!("nova.common.v1");
        }
        pub use v1::*;
    }
    pub mod content {
        pub mod v1 {
            tonic::include_proto!("nova.content_service.v1");
        }
        pub use v1::*;
    }
}

use nova::common::ErrorStatus;
use nova::content::content_service_server::ContentService;
use nova::content::*;

/// ContentService gRPC implementation
pub struct ContentServiceImpl {
    db_pool: PgPool,
    cache: Arc<ContentCache>,
    feed_cache: Arc<FeedCache>,
    feed_ranking: Arc<FeedRankingService>,
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

fn convert_comment_to_proto(comment: &Comment) -> crate::grpc::nova::content::Comment {
    crate::grpc::nova::content::Comment {
        id: comment.id.to_string(),
        post_id: comment.post_id.to_string(),
        creator_id: comment.user_id.to_string(),
        content: comment.content.clone(),
        created_at: comment.created_at.timestamp(),
    }
}

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

#[tonic::async_trait]
impl ContentService for ContentServiceImpl {
    /// Get a post by ID
    async fn get_post(
        &self,
        request: Request<GetPostRequest>,
    ) -> Result<Response<GetPostResponse>, Status> {
        let req = request.into_inner();

        tracing::info!("gRPC: Getting post with ID: {}", req.post_id);

        // Parse post ID from string UUID
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post ID format"))?;

        // Fetch post using PostService
        let post_service = PostService::with_cache(self.db_pool.clone(), self.cache.clone());
        match post_service.get_post(post_id).await {
            Ok(Some(post)) => {
                let response = GetPostResponse {
                    post: Some(convert_post_to_proto(&post)),
                    found: true,
                    error: ok_error(),
                };
                Ok(Response::new(response))
            }
            Ok(None) => {
                let response = GetPostResponse {
                    post: None,
                    found: false,
                    error: make_error("NOT_FOUND", "Post not found"),
                };
                Ok(Response::new(response))
            }
            Err(e) => {
                tracing::error!("Error fetching post: {}", e);
                Err(Status::internal("Failed to fetch post"))
            }
        }
    }

    /// Create a new post
    async fn create_post(
        &self,
        request: Request<CreatePostRequest>,
    ) -> Result<Response<CreatePostResponse>, Status> {
        let req = request.into_inner();

        tracing::info!("gRPC: Creating post from user: {}", req.creator_id);

        // Parse user ID
        let user_id = Uuid::parse_str(&req.creator_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

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
                Ok(Response::new(response))
            }
            Err(e) => {
                tracing::error!("Error creating post: {}", e);
                Err(Status::internal("Failed to create post"))
            }
        }
    }

    /// Get comments for a post
    async fn get_comments(
        &self,
        request: Request<GetCommentsRequest>,
    ) -> Result<Response<GetCommentsResponse>, Status> {
        let req = request.into_inner();

        tracing::info!(
            "gRPC: Getting comments for post: {} (limit: {}, offset: {})",
            req.post_id,
            req.limit,
            req.offset
        );

        // Parse post ID
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post ID format"))?;

        // Get comments using CommentService
        let comment_service = CommentService::new(self.db_pool.clone());
        match comment_service
            .get_post_comments(post_id, req.limit as i64, req.offset as i64)
            .await
        {
            Ok(comments) => {
                let total = comments.len() as i32;
                let comment_list = comments
                    .into_iter()
                    .map(|c| convert_comment_to_proto(&c))
                    .collect();

                let response = GetCommentsResponse {
                    comments: comment_list,
                    total,
                    error: ok_error(),
                };
                Ok(Response::new(response))
            }
            Err(e) => {
                tracing::error!("Error fetching comments: {}", e);
                Err(Status::internal("Failed to fetch comments"))
            }
        }
    }

    /// Like a post
    async fn like_post(
        &self,
        request: Request<LikePostRequest>,
    ) -> Result<Response<LikePostResponse>, Status> {
        let req = request.into_inner();

        tracing::info!("gRPC: User {} liking post {}", req.user_id, req.post_id);

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post ID format"))?;

        // Ensure the post exists and is not soft-deleted
        let post_exists = sqlx::query_scalar::<_, i64>(
            "SELECT 1 FROM posts WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(post_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error checking post existence: {}", e);
            Status::internal("Failed to validate post")
        })?;

        if post_exists.is_none() {
            return Err(Status::not_found("Post not found"));
        }

        let insert_result = sqlx::query(
            r#"
            INSERT INTO likes (user_id, post_id)
            VALUES ($1, $2)
            ON CONFLICT (user_id, post_id) DO NOTHING
            "#,
        )
        .bind(user_id)
        .bind(post_id)
        .execute(&self.db_pool)
        .await;

        match insert_result {
            Ok(result) => {
                // If a new like was inserted, invalidate the post cache to ensure
                // the like_count is refreshed on next read
                if result.rows_affected() > 0 {
                    // Invalidate post cache to force refresh on next get_post call
                    let _ = self.cache.invalidate_post(post_id).await;
                    tracing::debug!("Invalidated cache for post {} after new like", post_id);
                }

                Ok(Response::new(LikePostResponse {
                    success: true,
                    error: ok_error(),
                }))
            }
            Err(err) => {
                tracing::error!(
                    "Error inserting like (user={} post={}): {}",
                    user_id,
                    post_id,
                    err
                );
                Err(Status::internal("Failed to like post"))
            }
        }
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
        let query_str = format!(
            "SELECT id, user_id, caption, image_key, image_sizes, status, content_type, created_at, updated_at, deleted_at FROM posts WHERE id = ANY($1::uuid[]) AND deleted_at IS NULL ORDER BY created_at DESC",
        );

        let posts = sqlx::query_as::<_, Post>(&query_str)
            .bind(&post_ids)
            .fetch_all(&self.db_pool)
            .await
            .map_err(|e| {
                tracing::error!("Database error fetching posts by IDs: {}", e);
                Status::internal("Failed to fetch posts")
            })?;

        let proto_posts = posts.iter().map(|p| convert_post_to_proto(p)).collect();

        Ok(Response::new(GetPostsByIdsResponse { posts: proto_posts }))
    }

    /// Get posts by author with pagination
    async fn get_posts_by_author(
        &self,
        request: Request<GetPostsByAuthorRequest>,
    ) -> Result<Response<GetPostsByAuthorResponse>, Status> {
        let req = request.into_inner();

        tracing::info!(
            "gRPC: Getting posts by author: {} (status: {}, limit: {}, offset: {})",
            req.author_id,
            req.status,
            req.limit,
            req.offset
        );

        // Parse author ID
        let author_id = Uuid::parse_str(&req.author_id)
            .map_err(|_| Status::invalid_argument("Invalid author ID format"))?;

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
        let posts = if req.status.is_empty() {
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
        }
        .map_err(|e| {
            tracing::error!("Database error fetching posts by author: {}", e);
            Status::internal("Failed to fetch posts")
        })?;

        // Fetch total count
        let total: i64 = if req.status.is_empty() {
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
        }
        .map_err(|e| {
            tracing::error!("Database error counting posts by author: {}", e);
            Status::internal("Failed to count posts")
        })?;

        let proto_posts = posts.iter().map(|p| convert_post_to_proto(p)).collect();

        let total_count = i32::try_from(total).unwrap_or_else(|_| {
            tracing::warn!("Post count exceeded i32::MAX: {}", total);
            i32::MAX
        });

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
        let req = request.into_inner();

        tracing::info!("gRPC: Updating post: {}", req.post_id);

        // Parse post ID
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post ID format"))?;

        // Start a transaction to ensure atomicity
        let mut tx = self.db_pool.begin().await.map_err(|e| {
            tracing::error!("Database error starting transaction: {}", e);
            Status::internal("Failed to update post")
        })?;

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

            query.fetch_optional(&mut *tx).await.map_err(|e| {
                tracing::error!("Database error updating post: {}", e);
                Status::internal("Failed to update post")
            })?;

            sqlx::query("SELECT 1").execute(&mut *tx).await
        };

        match update_query {
            Ok(_) => {
                // Commit transaction and invalidate cache
                tx.commit().await.map_err(|e| {
                    tracing::error!("Database error committing transaction: {}", e);
                    Status::internal("Failed to update post")
                })?;

                // Invalidate cache for this post
                let _ = self.cache.invalidate_post(post_id).await;
                tracing::debug!("Invalidated cache for post {} after update", post_id);

                // Fetch the updated post
                let post_service =
                    PostService::with_cache(self.db_pool.clone(), self.cache.clone());
                match post_service.get_post(post_id).await {
                    Ok(Some(post)) => Ok(Response::new(UpdatePostResponse {
                        post: Some(convert_post_to_proto(&post)),
                    })),
                    Ok(None) => {
                        tracing::warn!("Updated post {} not found", post_id);
                        Err(Status::not_found("Post not found after update"))
                    }
                    Err(e) => {
                        tracing::error!("Error fetching updated post: {}", e);
                        Err(Status::internal("Failed to fetch updated post"))
                    }
                }
            }
            Err(e) => {
                tracing::error!("Error updating post: {}", e);
                Err(Status::internal("Failed to update post"))
            }
        }
    }

    /// Delete (soft delete) a post
    async fn delete_post(
        &self,
        request: Request<DeletePostRequest>,
    ) -> Result<Response<DeletePostResponse>, Status> {
        let req = request.into_inner();

        tracing::info!(
            "gRPC: Deleting post: {} (deleted_by: {})",
            req.post_id,
            req.deleted_by_id
        );

        // Parse IDs
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post ID format"))?;
        // Validate deleted_by_id exists (not used in this implementation but required by proto)
        let _deleted_by_id = Uuid::parse_str(&req.deleted_by_id)
            .map_err(|_| Status::invalid_argument("Invalid deleted_by_id format"))?;

        // Soft delete the post (set deleted_at timestamp)
        let result = sqlx::query_scalar::<_, chrono::DateTime<chrono::Utc>>(
            "UPDATE posts SET deleted_at = NOW() WHERE id = $1 AND deleted_at IS NULL RETURNING deleted_at",
        )
        .bind(post_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error deleting post: {}", e);
            Status::internal("Failed to delete post")
        })?;

        match result {
            Some(deleted_at) => {
                // Invalidate cache for this post
                let _ = self.cache.invalidate_post(post_id).await;
                tracing::debug!("Invalidated cache for post {} after delete", post_id);

                Ok(Response::new(DeletePostResponse {
                    post_id: post_id.to_string(),
                    deleted_at: deleted_at.timestamp(),
                }))
            }
            None => {
                tracing::warn!("Post {} not found or already deleted", post_id);
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

    /// Get personalized feed via gRPC
    async fn get_feed(
        &self,
        request: Request<GetFeedRequest>,
    ) -> Result<Response<GetFeedResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        let algo = if req.algo.is_empty() {
            "ch".to_string()
        } else {
            req.algo.clone()
        };

        if algo != "ch" && algo != "time" {
            return Err(Status::invalid_argument(
                "Invalid algo parameter. Must be 'ch' or 'time'",
            ));
        }

        let limit = if req.limit == 0 { 20 } else { req.limit }.min(100).max(1);

        let params = FeedQueryParams {
            algo: algo.clone(),
            limit,
            cursor: if req.cursor.is_empty() {
                None
            } else {
                Some(req.cursor.clone())
            },
        };

        let offset = params
            .decode_cursor()
            .map_err(|e| map_app_error(e, "get_feed"))?;

        let (post_ids, has_more, total_count) = match self
            .feed_ranking
            .get_feed(user_id, limit as usize, offset)
            .await
        {
            Ok(result) => result,
            Err(e) => {
                warn!("Primary feed fetch failed for user {}: {}", user_id, e);
                self.feed_ranking
                    .fallback_feed(user_id, limit as usize, offset)
                    .await
                    .map_err(|err| map_app_error(err, "fallback_feed"))?
            }
        };

        let cursor = if has_more && !post_ids.is_empty() {
            Some(FeedQueryParams::encode_cursor(offset + post_ids.len()))
        } else {
            None
        };

        let response = GetFeedResponse {
            post_ids: post_ids.iter().map(|id| id.to_string()).collect(),
            cursor: cursor.unwrap_or_default(),
            has_more,
            total_count: total_count as u32,
            error: ok_error(),
        };

        Ok(Response::new(response))
    }

    async fn invalidate_feed_event(
        &self,
        request: Request<InvalidateFeedEventRequest>,
    ) -> Result<Response<InvalidateFeedResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        let target_user_id = if req.target_user_id.is_empty() {
            None
        } else {
            Some(
                Uuid::parse_str(&req.target_user_id)
                    .map_err(|_| Status::invalid_argument("Invalid target user ID"))?,
            )
        };

        self.feed_cache
            .invalidate_by_event(&req.event_type, user_id, target_user_id)
            .await
            .map_err(|e| map_app_error(e, "invalidate_feed_event"))?;

        Ok(Response::new(InvalidateFeedResponse {
            success: true,
            error: ok_error(),
        }))
    }

    async fn batch_invalidate_feed(
        &self,
        request: Request<BatchInvalidateFeedRequest>,
    ) -> Result<Response<InvalidateFeedResponse>, Status> {
        let req = request.into_inner();
        let mut user_ids = Vec::with_capacity(req.user_ids.len());
        for id in req.user_ids {
            let parsed = Uuid::parse_str(&id)
                .map_err(|_| Status::invalid_argument("Invalid user ID in batch"))?;
            user_ids.push(parsed);
        }

        self.feed_cache
            .batch_invalidate(user_ids)
            .await
            .map_err(|e| map_app_error(e, "batch_invalidate_feed"))?;

        Ok(Response::new(InvalidateFeedResponse {
            success: true,
            error: ok_error(),
        }))
    }

    async fn warm_feed(
        &self,
        request: Request<WarmFeedRequest>,
    ) -> Result<Response<InvalidateFeedResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        let mut post_ids = Vec::with_capacity(req.post_ids.len());
        for id in req.post_ids {
            let parsed =
                Uuid::parse_str(&id).map_err(|_| Status::invalid_argument("Invalid post ID"))?;
            post_ids.push(parsed);
        }

        self.feed_cache
            .warm_cache(user_id, post_ids)
            .await
            .map_err(|e| map_app_error(e, "warm_feed"))?;

        Ok(Response::new(InvalidateFeedResponse {
            success: true,
            error: ok_error(),
        }))
    }
}

impl ContentServiceImpl {
    /// Create a new ContentServiceImpl with database pool
    pub fn new(
        db_pool: PgPool,
        cache: Arc<ContentCache>,
        feed_cache: Arc<FeedCache>,
        feed_ranking: Arc<FeedRankingService>,
    ) -> Self {
        Self {
            db_pool,
            cache,
            feed_cache,
            feed_ranking,
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
    mut shutdown: broadcast::Receiver<()>,
) -> Result<(), Box<dyn std::error::Error>> {
    use nova::content::content_service_server::ContentServiceServer;
    use tonic::transport::Server;

    tracing::info!("Starting gRPC server at {}", addr);

    let service = ContentServiceImpl::new(db_pool, cache, feed_cache, feed_ranking);
    Server::builder()
        .add_service(ContentServiceServer::new(service))
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
