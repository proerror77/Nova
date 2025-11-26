use crate::cache::{ContentCache, FeedCache};
use crate::db::channel_repo;
use crate::grpc::AuthClient;
use crate::models::{Channel as DbChannel, Post as DbPost};
use crate::services::feed_ranking::FeedRankingService;
use crate::services::posts::PostService;
use grpc_clients::nova::content_service::v2::content_service_server::{
    ContentService, ContentServiceServer,
};
use grpc_clients::nova::content_service::v2::*;
use grpc_metrics::layer::RequestGuard;
use sqlx::{PgPool, QueryBuilder, Row};
use std::fs;
use std::sync::Arc;
use tokio::sync::broadcast;
use tonic::transport::{Certificate, Identity, Server, ServerTlsConfig};
use tonic::{Request, Response, Status};
use uuid::Uuid;

pub struct ContentServiceImpl {
    pub db_pool: PgPool,
    pub cache: Arc<ContentCache>,
    pub feed_cache: Arc<FeedCache>,
    pub feed_ranking: Arc<FeedRankingService>,
    pub auth_client: Arc<AuthClient>,
}

fn map_status(status: &str) -> i32 {
    match status {
        "draft" => ContentStatus::Draft as i32,
        "published" => ContentStatus::Published as i32,
        "moderated" => ContentStatus::Moderated as i32,
        "deleted" => ContentStatus::Deleted as i32,
        _ => ContentStatus::Unspecified as i32,
    }
}

fn convert_post_to_proto(post: &DbPost) -> Post {
    Post {
        id: post.id.to_string(),
        author_id: post.user_id.to_string(),
        content: post.caption.clone().unwrap_or_default(),
        created_at: post.created_at.timestamp(),
        updated_at: post.updated_at.timestamp(),
        deleted_at: post.soft_delete.map(|d| d.timestamp()).unwrap_or(0),
        status: map_status(post.status.as_str()),
        media_ids: vec![],
        media_urls: post.media_urls.clone().unwrap_or_default(),
        media_type: post.media_type.clone(),
    }
}

fn convert_channel_to_proto(channel: &DbChannel) -> Channel {
    Channel {
        id: channel.id.to_string(),
        name: channel.name.clone(),
        description: channel.description.clone().unwrap_or_default(),
        category: channel.category.clone().unwrap_or_default(),
        subscriber_count: channel.subscriber_count as u32,
    }
}

#[tonic::async_trait]
impl ContentService for ContentServiceImpl {
    async fn create_post(
        &self,
        request: Request<CreatePostRequest>,
    ) -> Result<Response<CreatePostResponse>, Status> {
        let guard = RequestGuard::new("content-service", "CreatePost");
        let req = request.into_inner();

        let author_id = Uuid::parse_str(&req.author_id)
            .map_err(|_| Status::invalid_argument("invalid author_id"))?;

        let post_service = PostService::with_cache(self.db_pool.clone(), self.cache.clone());
        let image_key = format!("text-content-{}", Uuid::new_v4());
        let content = req.content.clone();

        let post = post_service
            .create_post(author_id, Some(content.as_str()), &image_key, "text/plain")
            .await
            .map_err(|e| {
                tracing::error!("create_post failed: {}", e);
                Status::internal("failed to create post")
            })?;

        guard.complete("0");
        Ok(Response::new(CreatePostResponse {
            post: Some(convert_post_to_proto(&post)),
        }))
    }

    async fn get_post(
        &self,
        request: Request<GetPostRequest>,
    ) -> Result<Response<GetPostResponse>, Status> {
        let guard = RequestGuard::new("content-service", "GetPost");
        let req = request.into_inner();
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("invalid post_id"))?;

        let post_service = PostService::with_cache(self.db_pool.clone(), self.cache.clone());
        match post_service.get_post(post_id).await {
            Ok(Some(post)) => {
                guard.complete("0");
                Ok(Response::new(GetPostResponse {
                    post: Some(convert_post_to_proto(&post)),
                    found: true,
                }))
            }
            Ok(None) => {
                guard.complete("5");
                Ok(Response::new(GetPostResponse {
                    post: None,
                    found: false,
                }))
            }
            Err(e) => {
                tracing::error!("get_post error: {}", e);
                guard.complete("13");
                Err(Status::internal("failed to fetch post"))
            }
        }
    }

    async fn get_posts_by_ids(
        &self,
        request: Request<GetPostsByIdsRequest>,
    ) -> Result<Response<GetPostsByIdsResponse>, Status> {
        let req = request.into_inner();
        if req.post_ids.is_empty() {
            return Ok(Response::new(GetPostsByIdsResponse {
                posts: vec![],
                not_found_ids: vec![],
            }));
        }

        let mut post_ids = Vec::with_capacity(req.post_ids.len());
        for pid in &req.post_ids {
            post_ids.push(Uuid::parse_str(pid).map_err(|_| Status::invalid_argument("bad id"))?);
        }

        let posts = sqlx::query_as::<_, DbPost>(
            "SELECT id, user_id, content, caption, media_key, media_type, media_urls, status, created_at, updated_at, deleted_at, soft_delete \
             FROM posts WHERE id = ANY($1::uuid[]) AND soft_delete IS NULL",
        )
        .bind(&post_ids)
        .fetch_all(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("get_posts_by_ids db error: {}", e);
            Status::internal("failed to fetch posts")
        })?;

        let found: std::collections::HashSet<Uuid> = posts.iter().map(|p| p.id).collect();
        let missing: Vec<String> = post_ids
            .into_iter()
            .filter(|id| !found.contains(id))
            .map(|id| id.to_string())
            .collect();

        Ok(Response::new(GetPostsByIdsResponse {
            posts: posts.iter().map(convert_post_to_proto).collect(),
            not_found_ids: missing,
        }))
    }

    async fn get_user_posts(
        &self,
        request: Request<GetUserPostsRequest>,
    ) -> Result<Response<GetUserPostsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("invalid user_id"))?;

        let limit = req.limit.clamp(1, 100) as i64;
        let offset = req.offset.max(0) as i64;

        let (posts, total): (Vec<DbPost>, i64) = if req.status == ContentStatus::Unspecified as i32
        {
            let posts = sqlx::query_as::<_, DbPost>(
                "SELECT id, user_id, content, caption, media_key, media_type, media_urls, status, created_at, updated_at, deleted_at, soft_delete \
                 FROM posts WHERE user_id = $1 AND soft_delete IS NULL ORDER BY created_at DESC LIMIT $2 OFFSET $3",
            )
            .bind(user_id)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.db_pool)
            .await
            .map_err(|e| Status::internal(format!("db error: {}", e)))?;

            let total = sqlx::query_scalar::<_, i64>(
                "SELECT COUNT(*) FROM posts WHERE user_id = $1 AND soft_delete IS NULL",
            )
            .bind(user_id)
            .fetch_one(&self.db_pool)
            .await
            .map_err(|e| Status::internal(format!("db error: {}", e)))?;

            (posts, total)
        } else {
            let status_filter = match req.status {
                s if s == ContentStatus::Draft as i32 => "draft",
                s if s == ContentStatus::Published as i32 => "published",
                s if s == ContentStatus::Moderated as i32 => "moderated",
                s if s == ContentStatus::Deleted as i32 => "deleted",
                _ => "published",
            };

            let posts = sqlx::query_as::<_, DbPost>(
                "SELECT id, user_id, content, caption, media_key, media_type, media_urls, status, created_at, updated_at, deleted_at, soft_delete \
                 FROM posts WHERE user_id = $1 AND status = $2 AND soft_delete IS NULL ORDER BY created_at DESC LIMIT $3 OFFSET $4",
            )
            .bind(user_id)
            .bind(status_filter)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.db_pool)
            .await
            .map_err(|e| Status::internal(format!("db error: {}", e)))?;

            let total = sqlx::query_scalar::<_, i64>(
                "SELECT COUNT(*) FROM posts WHERE user_id = $1 AND status = $2 AND soft_delete IS NULL",
            )
            .bind(user_id)
            .bind(status_filter)
            .fetch_one(&self.db_pool)
            .await
            .map_err(|e| Status::internal(format!("db error: {}", e)))?;

            (posts, total)
        };

        let has_more = (offset + limit) < total;

        Ok(Response::new(GetUserPostsResponse {
            posts: posts.iter().map(convert_post_to_proto).collect(),
            total_count: i32::try_from(total).unwrap_or(i32::MAX),
            has_more,
        }))
    }

    async fn list_recent_posts(
        &self,
        request: Request<ListRecentPostsRequest>,
    ) -> Result<Response<ListRecentPostsResponse>, Status> {
        let req = request.into_inner();
        let limit = req.limit.clamp(1, 500) as i64;

        let rows = if req.exclude_user_id.is_empty() {
            sqlx::query(
                "SELECT id::text AS id FROM posts WHERE status = 'published' AND soft_delete IS NULL ORDER BY created_at DESC LIMIT $1",
            )
            .bind(limit)
            .fetch_all(&self.db_pool)
            .await
        } else {
            sqlx::query(
                "SELECT id::text AS id FROM posts WHERE status = 'published' AND soft_delete IS NULL AND user_id <> $1::uuid ORDER BY created_at DESC LIMIT $2",
            )
            .bind(&req.exclude_user_id)
            .bind(limit)
            .fetch_all(&self.db_pool)
            .await
        }
        .map_err(|e| {
            tracing::error!("list_recent_posts db error: {}", e);
            Status::internal("failed to list recent posts")
        })?;

        let ids = rows
            .into_iter()
            .filter_map(|row| row.try_get::<String, _>("id").ok())
            .collect();

        Ok(Response::new(ListRecentPostsResponse { post_ids: ids }))
    }

    async fn list_trending_posts(
        &self,
        request: Request<ListTrendingPostsRequest>,
    ) -> Result<Response<ListTrendingPostsResponse>, Status> {
        let req = request.into_inner();
        let limit = req.limit.clamp(1, 500) as i64;

        let rows = if req.exclude_user_id.is_empty() {
            sqlx::query(
                "SELECT p.id::text AS id FROM posts p JOIN post_metadata pm ON pm.post_id = p.id WHERE p.status = 'published' AND p.soft_delete IS NULL ORDER BY (pm.like_count * 3 + pm.comment_count * 2 + pm.view_count) DESC, p.created_at DESC LIMIT $1",
            )
            .bind(limit)
            .fetch_all(&self.db_pool)
            .await
        } else {
            sqlx::query(
                "SELECT p.id::text AS id FROM posts p JOIN post_metadata pm ON pm.post_id = p.id WHERE p.status = 'published' AND p.soft_delete IS NULL AND p.user_id <> $1::uuid ORDER BY (pm.like_count * 3 + pm.comment_count * 2 + pm.view_count) DESC, p.created_at DESC LIMIT $2",
            )
            .bind(&req.exclude_user_id)
            .bind(limit)
            .fetch_all(&self.db_pool)
            .await
        }
        .map_err(|e| {
            tracing::error!("list_trending_posts db error: {}", e);
            Status::internal("failed to list trending posts")
        })?;

        let ids = rows
            .into_iter()
            .filter_map(|row| row.try_get::<String, _>("id").ok())
            .collect();

        Ok(Response::new(ListTrendingPostsResponse { post_ids: ids }))
    }

    async fn update_post(
        &self,
        request: Request<UpdatePostRequest>,
    ) -> Result<Response<UpdatePostResponse>, Status> {
        let guard = RequestGuard::new("content-service", "UpdatePost");
        let req = request.into_inner();
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("invalid post_id"))?;

        let mut builder = QueryBuilder::new("UPDATE posts SET updated_at = NOW()");

        if !req.content.is_empty() {
            builder.push(", caption = ").push_bind(req.content.clone());
        }

        if req.visibility != Visibility::Unspecified as i32 {
            builder.push(", privacy = ").push_bind(req.visibility);
        }

        // comments_enabled defaults to false; always persist to keep API deterministic
        builder
            .push(", comments_enabled = ")
            .push_bind(req.comments_enabled);

        builder.push(" WHERE id = ").push_bind(post_id);
        builder.push(" AND soft_delete IS NULL RETURNING id, user_id, content, caption, media_key, media_type, media_urls, status, created_at, updated_at, deleted_at, soft_delete");

        let post = builder
            .build_query_as::<DbPost>()
            .fetch_optional(&self.db_pool)
            .await
            .map_err(|e| {
                tracing::error!("update_post db error: {}", e);
                Status::internal("failed to update post")
            })?;

        if let Some(post) = post {
            guard.complete("0");
            Ok(Response::new(UpdatePostResponse {
                post: Some(convert_post_to_proto(&post)),
            }))
        } else {
            guard.complete("5");
            Err(Status::not_found("post not found"))
        }
    }

    async fn delete_post(
        &self,
        request: Request<DeletePostRequest>,
    ) -> Result<Response<DeletePostResponse>, Status> {
        let guard = RequestGuard::new("content-service", "DeletePost");
        let req = request.into_inner();
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("invalid post_id"))?;

        let result = sqlx::query_scalar::<_, Option<chrono::DateTime<chrono::Utc>>>(
            "UPDATE posts SET soft_delete = NOW() WHERE id = $1 AND soft_delete IS NULL RETURNING soft_delete",
        )
        .bind(post_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("delete_post db error: {}", e);
            Status::internal("failed to delete post")
        })?
        .flatten();

        match result {
            Some(ts) => {
                let _ = self.cache.invalidate_post(post_id).await;
                guard.complete("0");
                Ok(Response::new(DeletePostResponse {
                    post_id: post_id.to_string(),
                    deleted_at: ts.timestamp(),
                }))
            }
            None => {
                guard.complete("5");
                Err(Status::not_found("post not found"))
            }
        }
    }

    async fn list_channels(
        &self,
        request: Request<ListChannelsRequest>,
    ) -> Result<Response<ListChannelsResponse>, Status> {
        let req = request.into_inner();
        let limit = req.limit.clamp(1, 100) as i64;
        let offset = req.offset.max(0) as i64;
        let category = if req.category.is_empty() {
            None
        } else {
            Some(req.category.as_str())
        };

        let (channels, total) = channel_repo::list_channels(&self.db_pool, category, limit, offset)
            .await
            .map_err(|e| {
                tracing::error!(error=%e, "list_channels failed");
                Status::internal("failed to list channels")
            })?;

        Ok(Response::new(ListChannelsResponse {
            channels: channels.iter().map(convert_channel_to_proto).collect(),
            total: total as i32,
        }))
    }

    async fn get_channel(
        &self,
        request: Request<GetChannelRequest>,
    ) -> Result<Response<GetChannelResponse>, Status> {
        let req = request.into_inner();
        let channel_id =
            Uuid::parse_str(&req.id).map_err(|_| Status::invalid_argument("invalid channel id"))?;

        let channel = channel_repo::get_channel(&self.db_pool, channel_id)
            .await
            .map_err(|e| {
                tracing::error!(error=%e, "get_channel failed");
                Status::internal("failed to get channel")
            })?;

        match channel {
            Some(ch) => Ok(Response::new(GetChannelResponse {
                channel: Some(convert_channel_to_proto(&ch)),
                found: true,
            })),
            None => Ok(Response::new(GetChannelResponse {
                channel: None,
                found: false,
            })),
        }
    }
}

/// Helper to start the gRPC server with the provided implementation.
pub async fn start_grpc_server(
    addr: std::net::SocketAddr,
    db_pool: PgPool,
    cache: Arc<ContentCache>,
    feed_cache: Arc<FeedCache>,
    feed_ranking: Arc<FeedRankingService>,
    auth_client: Arc<AuthClient>,
    mut shutdown: broadcast::Receiver<()>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let svc = ContentServiceImpl {
        db_pool,
        cache,
        feed_cache,
        feed_ranking,
        auth_client,
    };

    let mut server_builder = Server::builder();

    if let Some(tls_config) = load_server_tls_config()? {
        server_builder = server_builder.tls_config(tls_config)?;
    } else {
        tracing::warn!("gRPC server TLS is DISABLED; enable GRPC_TLS_ENABLED=true for staging/production");
    }

    server_builder
        .add_service(ContentServiceServer::new(svc))
        .serve_with_shutdown(addr, async move {
            let _ = shutdown.recv().await;
        })
        .await?;
    Ok(())
}

fn load_server_tls_config(
    ) -> Result<Option<ServerTlsConfig>, Box<dyn std::error::Error + Send + Sync>> {
    let tls_enabled = std::env::var("GRPC_TLS_ENABLED")
        .map(|v| matches!(v.as_str(), "1" | "true" | "TRUE"))
        .unwrap_or(false);

    if !tls_enabled {
        return Ok(None);
    }

    let cert_path = std::env::var("GRPC_SERVER_CERT_PATH")
        .map_err(|_| "GRPC_SERVER_CERT_PATH is required when GRPC_TLS_ENABLED=true")?;
    let key_path = std::env::var("GRPC_SERVER_KEY_PATH")
        .map_err(|_| "GRPC_SERVER_KEY_PATH is required when GRPC_TLS_ENABLED=true")?;

    let server_cert = fs::read(&cert_path)
        .map_err(|e| format!("Failed to read server cert {}: {}", cert_path, e))?;
    let server_key = fs::read(&key_path)
        .map_err(|e| format!("Failed to read server key {}: {}", key_path, e))?;

    let mut tls_config = ServerTlsConfig::new().identity(Identity::from_pem(server_cert, server_key));

    let require_client_cert = std::env::var("GRPC_REQUIRE_CLIENT_CERT")
        .map(|v| matches!(v.as_str(), "1" | "true" | "TRUE"))
        .unwrap_or(false);

    if require_client_cert {
        let ca_path = std::env::var("GRPC_CLIENT_CA_CERT_PATH")
            .or_else(|_| std::env::var("GRPC_TLS_CA_CERT_PATH"))
            .map_err(|_| {
                "GRPC_CLIENT_CA_CERT_PATH (or GRPC_TLS_CA_CERT_PATH) is required when GRPC_REQUIRE_CLIENT_CERT=true"
            })?;
        let ca_cert = fs::read(&ca_path)
            .map_err(|e| format!("Failed to read client CA cert {}: {}", ca_path, e))?;

        tls_config = tls_config.client_ca_root(Certificate::from_pem(ca_cert));
        tracing::info!("gRPC server mTLS enabled (client cert required)");
    } else {
        tracing::info!("gRPC server TLS enabled (server cert only)");
    }

    Ok(Some(tls_config))
}
