use sqlx::PgPool;
use std::sync::Arc;
use tonic::{Request, Response, Status};
use transactional_outbox::{OutboxError, SqlxOutboxRepository};
use uuid::Uuid;

use crate::services::CounterService;

// Error conversion helper function
fn outbox_error_to_status(err: OutboxError) -> Status {
    Status::internal(format!("Outbox error: {}", err))
}

// Generated protobuf code (from proto/social.proto)
pub mod social {
    tonic::include_proto!("nova.social_service.v2");
}

use social::social_service_server::SocialService;
use social::*;

/// App state shared across gRPC handlers
#[derive(Clone)]
pub struct AppState {
    pub pg_pool: PgPool,
    pub counter_service: CounterService,
    pub outbox_repo: Arc<SqlxOutboxRepository>,
}

impl AppState {
    pub fn new(
        pg_pool: PgPool,
        counter_service: CounterService,
        outbox_repo: Arc<SqlxOutboxRepository>,
    ) -> Self {
        Self {
            pg_pool,
            counter_service,
            outbox_repo,
        }
    }
}

/// Implementation of SocialService gRPC service with Transactional Outbox pattern
///
/// Key design decisions:
/// 1. **Atomicity**: Business logic + outbox event in same PostgreSQL transaction
/// 2. **Cache-Aside**: Update Redis AFTER successful commit (best-effort)
/// 3. **Idempotency**: ON CONFLICT DO NOTHING for like operations
/// 4. **Event Publishing**: Use transactional-outbox publish_event! macro
pub struct SocialServiceImpl {
    state: Arc<AppState>,
}

impl SocialServiceImpl {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
}

#[tonic::async_trait]
impl SocialService for SocialServiceImpl {
    // ========== Like Operations ==========

    /// Create a like (idempotent: returns success if already liked)
    async fn create_like(
        &self,
        request: Request<CreateLikeRequest>,
    ) -> Result<Response<CreateLikeResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Start transaction
        let mut tx = self
            .state
            .pg_pool
            .begin()
            .await
            .map_err(|e| Status::internal(format!("Failed to start transaction: {}", e)))?;

        // 1. Insert like (idempotent: ON CONFLICT DO NOTHING)
        let like_id = Uuid::new_v4();
        let result = sqlx::query_as::<_, (Uuid,)>(
            "INSERT INTO likes (id, user_id, post_id, created_at)
             VALUES ($1, $2, $3, NOW())
             ON CONFLICT (user_id, post_id) DO NOTHING
             RETURNING id",
        )
        .bind(like_id)
        .bind(user_id)
        .bind(post_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| Status::internal(format!("Failed to insert like: {}", e)))?;

        let was_created = result.is_some();
        let final_like_id = result.map(|(id,)| id).unwrap_or(like_id);

        // 2. Publish event via transactional-outbox (only if new like)
        if was_created {
            use transactional_outbox::{OutboxEvent, OutboxRepository};

            let event_payload = serde_json::json!({
                "like_id": final_like_id.to_string(),
                "user_id": user_id.to_string(),
                "post_id": post_id.to_string(),
                "created_at": chrono::Utc::now().to_rfc3339(),
            });

            let event = OutboxEvent {
                id: Uuid::new_v4(),
                aggregate_type: "like".to_string(),
                aggregate_id: final_like_id,
                event_type: "social.like.created".to_string(),
                payload: event_payload,
                metadata: None,
                created_at: chrono::Utc::now(),
                published_at: None,
                retry_count: 0,
                last_error: None,
            };

            self.state
                .outbox_repo
                .insert(&mut tx, &event)
                .await
                .map_err(outbox_error_to_status)?;
        }

        // 3. Commit transaction (atomic: like + outbox event)
        tx.commit()
            .await
            .map_err(|e| Status::internal(format!("Failed to commit transaction: {}", e)))?;

        // 4. Update Redis counter (after successful commit, best-effort)
        let new_count = if was_created {
            let counter_svc = self.state.counter_service.clone();
            counter_svc
                .increment_like_count(post_id)
                .await
                .unwrap_or_else(|e| {
                    tracing::warn!(
                        post_id=%post_id,
                        error=%e,
                        "Failed to increment Redis counter (data is in DB)"
                    );
                    0
                })
        } else {
            // Get current count if like already existed
            let counter_svc = self.state.counter_service.clone();
            counter_svc.get_like_count(post_id).await.unwrap_or(0)
        };

        Ok(Response::new(CreateLikeResponse {
            success: true,
            like_id: final_like_id.to_string(),
            new_like_count: new_count,
        }))
    }

    /// Delete a like
    async fn delete_like(
        &self,
        request: Request<DeleteLikeRequest>,
    ) -> Result<Response<DeleteLikeResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Start transaction
        let mut tx = self
            .state
            .pg_pool
            .begin()
            .await
            .map_err(|e| Status::internal(format!("Failed to start transaction: {}", e)))?;

        // 1. Delete like
        let result = sqlx::query_as::<_, (Uuid,)>(
            "DELETE FROM likes
             WHERE user_id = $1 AND post_id = $2
             RETURNING id",
        )
        .bind(user_id)
        .bind(post_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| Status::internal(format!("Failed to delete like: {}", e)))?;

        let was_deleted = result.is_some();

        // 2. Publish event (only if like existed)
        if was_deleted {
            use transactional_outbox::{OutboxEvent, OutboxRepository};

            let event_payload = serde_json::json!({
                "user_id": user_id.to_string(),
                "post_id": post_id.to_string(),
                "deleted_at": chrono::Utc::now().to_rfc3339(),
            });

            let event = OutboxEvent {
                id: Uuid::new_v4(),
                aggregate_type: "like".to_string(),
                aggregate_id: post_id,
                event_type: "social.like.deleted".to_string(),
                payload: event_payload,
                metadata: None,
                created_at: chrono::Utc::now(),
                published_at: None,
                retry_count: 0,
                last_error: None,
            };

            self.state
                .outbox_repo
                .insert(&mut tx, &event)
                .await
                .map_err(outbox_error_to_status)?;
        }

        // 3. Commit transaction
        tx.commit()
            .await
            .map_err(|e| Status::internal(format!("Failed to commit transaction: {}", e)))?;

        // 4. Update Redis counter
        let new_count = if was_deleted {
            let counter_svc = self.state.counter_service.clone();
            counter_svc
                .decrement_like_count(post_id)
                .await
                .unwrap_or_else(|e| {
                    tracing::warn!(
                        post_id=%post_id,
                        error=%e,
                        "Failed to decrement Redis counter"
                    );
                    0
                })
        } else {
            let counter_svc = self.state.counter_service.clone();
            counter_svc.get_like_count(post_id).await.unwrap_or(0)
        };

        Ok(Response::new(DeleteLikeResponse {
            success: true,
            new_like_count: new_count,
        }))
    }

    /// Get like status for a user on a post
    async fn get_like_status(
        &self,
        request: Request<GetLikeStatusRequest>,
    ) -> Result<Response<GetLikeStatusResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Query like status from database
        let result = sqlx::query_as::<_, (chrono::NaiveDateTime,)>(
            "SELECT created_at FROM likes WHERE user_id = $1 AND post_id = $2",
        )
        .bind(user_id)
        .bind(post_id)
        .fetch_optional(&self.state.pg_pool)
        .await
        .map_err(|e| Status::internal(format!("Failed to fetch like status: {}", e)))?;

        let (is_liked, liked_at) = match result {
            Some((created_at,)) => (
                true,
                Some(prost_types::Timestamp {
                    seconds: created_at.and_utc().timestamp(),
                    nanos: created_at.and_utc().timestamp_subsec_nanos() as i32,
                }),
            ),
            None => (false, None),
        };

        Ok(Response::new(GetLikeStatusResponse { is_liked, liked_at }))
    }

    /// Get like count for a post
    async fn get_like_count(
        &self,
        request: Request<GetLikeCountRequest>,
    ) -> Result<Response<GetLikeCountResponse>, Status> {
        let req = request.into_inner();

        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Try Redis first, fallback to PostgreSQL
        let counter_svc = self.state.counter_service.clone();
        let count = match counter_svc.get_like_count(post_id).await {
            Ok(count) => count,
            Err(_) => {
                // Redis miss, query PostgreSQL
                sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM likes WHERE post_id = $1")
                    .bind(post_id)
                    .fetch_one(&self.state.pg_pool)
                    .await
                    .map_err(|e| Status::internal(format!("Failed to count likes: {}", e)))?
            }
        };

        Ok(Response::new(GetLikeCountResponse { like_count: count }))
    }

    /// Get list of users who liked a post (paginated)
    async fn get_likers(
        &self,
        request: Request<GetLikersRequest>,
    ) -> Result<Response<GetLikersResponse>, Status> {
        let req = request.into_inner();

        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        let limit = if req.limit > 0 && req.limit <= 100 {
            req.limit
        } else {
            20
        };

        // For simplicity, use offset-based pagination
        // TODO: Implement cursor-based pagination for better scalability
        let offset = if req.cursor.is_empty() {
            0
        } else {
            req.cursor
                .parse::<i64>()
                .map_err(|_| Status::invalid_argument("Invalid cursor"))?
        };

        let likers = sqlx::query_as::<_, (Uuid, chrono::NaiveDateTime)>(
            "SELECT user_id, created_at FROM likes
             WHERE post_id = $1
             ORDER BY created_at DESC
             LIMIT $2 OFFSET $3",
        )
        .bind(post_id)
        .bind(limit as i64)
        .bind(offset)
        .fetch_all(&self.state.pg_pool)
        .await
        .map_err(|e| Status::internal(format!("Failed to fetch likers: {}", e)))?;

        let has_more = likers.len() == limit as usize;
        let next_cursor = if has_more {
            (offset + limit as i64).to_string()
        } else {
            String::new()
        };

        let proto_likers: Vec<Liker> = likers
            .into_iter()
            .map(|(user_id, created_at)| Liker {
                user_id: user_id.to_string(),
                liked_at: Some(prost_types::Timestamp {
                    seconds: created_at.and_utc().timestamp(),
                    nanos: created_at.and_utc().timestamp_subsec_nanos() as i32,
                }),
            })
            .collect();

        Ok(Response::new(GetLikersResponse {
            likers: proto_likers,
            next_cursor,
            has_more,
        }))
    }

    // ========== Share Operations ==========

    /// Create a share
    async fn create_share(
        &self,
        request: Request<CreateShareRequest>,
    ) -> Result<Response<CreateShareResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        let share_type_str = match req.share_type {
            1 => "REPOST",
            2 => "STORY",
            3 => "DM",
            4 => "EXTERNAL",
            _ => return Err(Status::invalid_argument("Invalid share_type")),
        };

        let target_user_id = if !req.target_user_id.is_empty() {
            Some(
                Uuid::parse_str(&req.target_user_id)
                    .map_err(|_| Status::invalid_argument("Invalid target_user_id"))?,
            )
        } else {
            None
        };

        // Start transaction
        let mut tx = self
            .state
            .pg_pool
            .begin()
            .await
            .map_err(|e| Status::internal(format!("Failed to start transaction: {}", e)))?;

        // 1. Insert share
        let share_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO shares (id, user_id, post_id, share_type, target_user_id, created_at)
             VALUES ($1, $2, $3, $4, $5, NOW())",
        )
        .bind(share_id)
        .bind(user_id)
        .bind(post_id)
        .bind(share_type_str)
        .bind(target_user_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| Status::internal(format!("Failed to insert share: {}", e)))?;

        // 2. Publish event
        use transactional_outbox::{OutboxEvent, OutboxRepository};

        let event_payload = serde_json::json!({
            "share_id": share_id.to_string(),
            "user_id": user_id.to_string(),
            "post_id": post_id.to_string(),
            "share_type": share_type_str,
            "target_user_id": target_user_id.map(|id| id.to_string()),
            "created_at": chrono::Utc::now().to_rfc3339(),
        });

        let event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_type: "share".to_string(),
            aggregate_id: share_id,
            event_type: "social.share.created".to_string(),
            payload: event_payload,
            metadata: None,
            created_at: chrono::Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };

        self.state
            .outbox_repo
            .insert(&mut tx, &event)
            .await
            .map_err(outbox_error_to_status)?;

        // 3. Commit transaction
        tx.commit()
            .await
            .map_err(|e| Status::internal(format!("Failed to commit transaction: {}", e)))?;

        // 4. Update Redis counter
        let counter_svc = self.state.counter_service.clone();
        let new_count = counter_svc
            .increment_share_count(post_id)
            .await
            .unwrap_or_else(|e| {
                tracing::warn!(
                    post_id=%post_id,
                    error=%e,
                    "Failed to increment share counter"
                );
                0
            });

        Ok(Response::new(CreateShareResponse {
            success: true,
            share_id: share_id.to_string(),
            new_share_count: new_count,
        }))
    }

    /// Get share count for a post
    async fn get_share_count(
        &self,
        request: Request<GetShareCountRequest>,
    ) -> Result<Response<GetShareCountResponse>, Status> {
        let req = request.into_inner();

        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Try Redis first, fallback to PostgreSQL
        let counter_svc = self.state.counter_service.clone();
        let count = match counter_svc.get_share_count(post_id).await {
            Ok(count) => count,
            Err(_) => {
                sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM shares WHERE post_id = $1")
                    .bind(post_id)
                    .fetch_one(&self.state.pg_pool)
                    .await
                    .map_err(|e| Status::internal(format!("Failed to count shares: {}", e)))?
            }
        };

        Ok(Response::new(GetShareCountResponse { share_count: count }))
    }

    /// Get list of shares for a post
    async fn get_shares(
        &self,
        request: Request<GetSharesRequest>,
    ) -> Result<Response<GetSharesResponse>, Status> {
        let req = request.into_inner();

        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        let limit = if req.limit > 0 && req.limit <= 100 {
            req.limit
        } else {
            20
        };

        let offset = if req.cursor.is_empty() {
            0
        } else {
            req.cursor
                .parse::<i64>()
                .map_err(|_| Status::invalid_argument("Invalid cursor"))?
        };

        let shares = sqlx::query_as::<_, (Uuid, Uuid, String, chrono::NaiveDateTime)>(
            "SELECT id, user_id, share_type, created_at FROM shares
             WHERE post_id = $1
             ORDER BY created_at DESC
             LIMIT $2 OFFSET $3",
        )
        .bind(post_id)
        .bind(limit as i64)
        .bind(offset)
        .fetch_all(&self.state.pg_pool)
        .await
        .map_err(|e| Status::internal(format!("Failed to fetch shares: {}", e)))?;

        let has_more = shares.len() == limit as usize;
        let next_cursor = if has_more {
            (offset + limit as i64).to_string()
        } else {
            String::new()
        };

        let proto_shares: Vec<Share> = shares
            .into_iter()
            .map(|(id, user_id, share_type, created_at)| Share {
                share_id: id.to_string(),
                user_id: user_id.to_string(),
                share_type: match share_type.as_str() {
                    "REPOST" => 1,
                    "STORY" => 2,
                    "DM" => 3,
                    "EXTERNAL" => 4,
                    _ => 0,
                },
                shared_at: Some(prost_types::Timestamp {
                    seconds: created_at.and_utc().timestamp(),
                    nanos: created_at.and_utc().timestamp_subsec_nanos() as i32,
                }),
            })
            .collect();

        Ok(Response::new(GetSharesResponse {
            shares: proto_shares,
            next_cursor,
            has_more,
        }))
    }

    // ========== Comment Operations (Stubs) ==========

    async fn create_comment(
        &self,
        _request: Request<CreateCommentRequest>,
    ) -> Result<Response<CreateCommentResponse>, Status> {
        // TODO: Implement with same transactional-outbox pattern
        Err(Status::unimplemented(
            "Comment operations not yet implemented",
        ))
    }

    async fn update_comment(
        &self,
        _request: Request<UpdateCommentRequest>,
    ) -> Result<Response<UpdateCommentResponse>, Status> {
        Err(Status::unimplemented(
            "Comment operations not yet implemented",
        ))
    }

    async fn delete_comment(
        &self,
        _request: Request<DeleteCommentRequest>,
    ) -> Result<Response<DeleteCommentResponse>, Status> {
        Err(Status::unimplemented(
            "Comment operations not yet implemented",
        ))
    }

    async fn get_comment(
        &self,
        _request: Request<GetCommentRequest>,
    ) -> Result<Response<GetCommentResponse>, Status> {
        Err(Status::unimplemented(
            "Comment operations not yet implemented",
        ))
    }

    async fn list_comments(
        &self,
        _request: Request<ListCommentsRequest>,
    ) -> Result<Response<ListCommentsResponse>, Status> {
        Err(Status::unimplemented(
            "Comment operations not yet implemented",
        ))
    }

    async fn get_comment_count(
        &self,
        _request: Request<GetCommentCountRequest>,
    ) -> Result<Response<GetCommentCountResponse>, Status> {
        Err(Status::unimplemented(
            "Comment operations not yet implemented",
        ))
    }

    // ========== Batch Operations ==========

    async fn batch_get_like_status(
        &self,
        _request: Request<BatchGetLikeStatusRequest>,
    ) -> Result<Response<BatchGetLikeStatusResponse>, Status> {
        // TODO: Implement with Redis MGET optimization
        Err(Status::unimplemented(
            "Batch operations not yet implemented",
        ))
    }

    async fn batch_get_counts(
        &self,
        _request: Request<BatchGetCountsRequest>,
    ) -> Result<Response<BatchGetCountsResponse>, Status> {
        // TODO: Implement with Redis MGET optimization
        Err(Status::unimplemented(
            "Batch operations not yet implemented",
        ))
    }
}
