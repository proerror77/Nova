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
    pub mod content {
        tonic::include_proto!("nova.content");
    }
}

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
                    error: String::new(),
                };
                Ok(Response::new(response))
            }
            Ok(None) => {
                let response = GetPostResponse {
                    post: None,
                    found: false,
                    error: "Post not found".to_string(),
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
                    error: String::new(),
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
                    error: String::new(),
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
            "SELECT 1 FROM posts WHERE id = $1 AND soft_delete IS NULL",
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
            Ok(_) => Ok(Response::new(LikePostResponse {
                success: true,
                error: String::new(),
            })),
            Err(err) => {
                // Treat duplicate likes as success to keep the operation idempotent
                if let Some(db_err) = err.as_database_error() {
                    if db_err.code() == Some("23505".into()) {
                        return Ok(Response::new(LikePostResponse {
                            success: true,
                            error: String::new(),
                        }));
                    }
                }

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

        let total_i32 = i32::try_from(total).unwrap_or(i32::MAX);

        let response = GetUserBookmarksResponse {
            posts: bookmark_posts,
            total: total_i32,
            error: String::new(),
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
            error: String::new(),
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
            error: String::new(),
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
            error: String::new(),
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
            error: String::new(),
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
