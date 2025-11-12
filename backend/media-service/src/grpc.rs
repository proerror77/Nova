// gRPC service implementation for media service
use anyhow::Context;
use sqlx::PgPool;
use std::sync::Arc;
use tonic::{Request, Response, Status};
use uuid::Uuid;

use crate::cache::MediaCache;
use crate::error::AppError;
use crate::models::{CreateReelRequest as CreateReelPayload, Upload as DbUpload, Video as DbVideo};
use crate::services::{ReelService, ReelTranscodePipeline, VideoService};
use nova::common::v1::ErrorStatus;
use tokio::sync::broadcast;

// Import generated proto code
pub mod nova {
    pub mod common {
        pub mod v1 {
            tonic::include_proto!("nova.common.v1");
        }
        pub use v1::*;
    }
    pub mod media_service {
        pub mod v1 {
            tonic::include_proto!("nova.media_service.v1");
        }
        pub use v1::*;
    }
}

use nova::media_service::v1::media_service_server::MediaService;
use nova::media_service::v1::*;

/// Convert database `Video` model to gRPC proto message.
fn video_to_proto(video: DbVideo) -> Video {
    Video {
        id: video.id.to_string(),
        creator_id: video.creator_id.to_string(),
        title: video.title,
        description: video.description.unwrap_or_default(),
        duration_seconds: video.duration_seconds,
        cdn_url: video.cdn_url.unwrap_or_default(),
        thumbnail_url: video.thumbnail_url.unwrap_or_default(),
        status: video.status,
        visibility: video.visibility,
        created_at: video.created_at.timestamp(),
    }
}

/// Convert database `Upload` model to gRPC proto message.
fn upload_to_proto(upload: DbUpload) -> Upload {
    Upload {
        id: upload.id.to_string(),
        user_id: upload.user_id.to_string(),
        video_id: upload.video_id.map(|id| id.to_string()).unwrap_or_default(),
        file_name: upload.file_name,
        file_size: upload.file_size,
        uploaded_size: upload.uploaded_size,
        status: upload.status,
        created_at: upload.created_at.timestamp(),
    }
}

#[inline]
fn make_error(code: &'static str, message: impl Into<String>) -> ErrorStatus {
    ErrorStatus {
        code: code.to_string(),
        message: message.into(),
        metadata: Default::default(),
    }
}

/// Convert a `ReelResponse` DTO to proto representation.
fn reel_response_to_proto(reel: crate::models::ReelResponse) -> Reel {
    Reel {
        id: reel.id,
        creator_id: reel.creator_id,
        upload_id: reel.upload_id.unwrap_or_default(),
        caption: reel.caption.unwrap_or_default(),
        music_title: reel.music_title.unwrap_or_default(),
        music_artist: reel.music_artist.unwrap_or_default(),
        duration_seconds: reel.duration_seconds.unwrap_or_default(),
        visibility: reel.visibility,
        status: reel.status,
        processing_stage: reel.processing_stage,
        processing_progress: i32::from(reel.processing_progress),
        allow_comments: reel.allow_comments,
        allow_shares: reel.allow_shares,
        cover_image_url: reel.cover_image_url.unwrap_or_default(),
        source_video_url: reel.source_video_url.unwrap_or_default(),
        published_at: reel.published_at.unwrap_or_default(),
        failed_at: reel.failed_at.unwrap_or_default(),
        created_at: reel.created_at,
        updated_at: reel.updated_at,
        variants: reel
            .variants
            .into_iter()
            .map(|variant| ReelVariant {
                quality: variant.quality,
                codec: variant.codec,
                bitrate_kbps: variant.bitrate_kbps,
                width: variant.width,
                height: variant.height,
                frame_rate: variant.frame_rate,
                cdn_url: variant.cdn_url.unwrap_or_default(),
                file_size_bytes: variant.file_size_bytes.unwrap_or_default(),
                is_default: variant.is_default,
            })
            .collect(),
        transcode_jobs: reel
            .transcode_jobs
            .into_iter()
            .map(|job| ReelTranscodeJob {
                target_quality: job.target_quality,
                status: job.status,
                stage: job.stage,
                progress: i32::from(job.progress),
                updated_at: job.updated_at,
                error: job
                    .error_message
                    .map(|msg| make_error("TRANSCODE_JOB_ERROR", msg)),
            })
            .collect(),
    }
}

/// Map `sqlx::Error` to tonic `Status`, logging the context-specific error message.
fn map_sqlx_error(err: sqlx::Error, context: &str) -> Status {
    if let sqlx::Error::RowNotFound = err {
        Status::not_found(context)
    } else {
        tracing::error!("Database error ({}): {:?}", context, err);
        Status::internal("Database operation failed")
    }
}

/// Convert `AppError` to tonic `Status`.
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
            Status::internal("Cache error")
        }
    }
}

/// MediaService gRPC implementation
#[derive(Clone)]
pub struct MediaServiceImpl {
    db_pool: PgPool,
    reel_pipeline: ReelTranscodePipeline,
    cache: Arc<MediaCache>,
}

impl MediaServiceImpl {
    pub fn new(
        db_pool: PgPool,
        reel_pipeline: ReelTranscodePipeline,
        cache: Arc<MediaCache>,
    ) -> Self {
        Self {
            db_pool,
            reel_pipeline,
            cache,
        }
    }
}

#[tonic::async_trait]
impl MediaService for MediaServiceImpl {
    /// Get a video by ID
    async fn get_video(
        &self,
        request: Request<GetVideoRequest>,
    ) -> Result<Response<GetVideoResponse>, Status> {
        let req = request.into_inner();

        let video_id = Uuid::parse_str(&req.video_id)
            .map_err(|_| Status::invalid_argument("Invalid video ID"))?;

        tracing::info!("gRPC: Getting video with ID: {}", video_id);

        let video_service = VideoService::with_cache(self.db_pool.clone(), self.cache.clone());
        let video = video_service
            .get_video(video_id)
            .await
            .map_err(|e| map_app_error(e, "get_video"))?;

        let response = match video {
            Some(video) => GetVideoResponse {
                video: Some(video_to_proto(video)),
                found: true,
                error: None,
            },
            None => GetVideoResponse {
                video: None,
                found: false,
                error: Some(make_error("NOT_FOUND", "Video not found")),
            },
        };

        Ok(Response::new(response))
    }

    /// Get videos for a user
    async fn get_user_videos(
        &self,
        request: Request<GetUserVideosRequest>,
    ) -> Result<Response<GetUserVideosResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;
        let limit = if req.limit > 0 { req.limit } else { 20 };

        tracing::info!(
            "gRPC: Getting videos for user: {} (limit: {})",
            user_id,
            limit
        );

        let videos = sqlx::query_as::<_, DbVideo>(
            "SELECT id, creator_id, title, description, duration_seconds, cdn_url, \
             thumbnail_url, status, visibility, created_at, updated_at \
             FROM videos WHERE creator_id = $1 AND deleted_at IS NULL \
             ORDER BY created_at DESC LIMIT $2",
        )
        .bind(user_id)
        .bind(limit)
        .fetch_all(&self.db_pool)
        .await
        .map_err(|e| map_sqlx_error(e, "get_user_videos"))?;

        let response = GetUserVideosResponse {
            videos: videos.into_iter().map(video_to_proto).collect(),
            error: None,
        };

        Ok(Response::new(response))
    }

    /// Create a new video
    async fn create_video(
        &self,
        request: Request<CreateVideoRequest>,
    ) -> Result<Response<CreateVideoResponse>, Status> {
        let req = request.into_inner();

        let creator_id = Uuid::parse_str(&req.creator_id)
            .map_err(|_| Status::invalid_argument("Invalid creator ID"))?;

        let title = req.title.trim().to_string();
        if title.is_empty() {
            return Err(Status::invalid_argument("Title is required"));
        }

        let description = req.description.trim().to_string();
        let description_ref = if description.is_empty() {
            None
        } else {
            Some(description.as_str())
        };

        let visibility_input = req.visibility.trim();
        let visibility = if visibility_input.is_empty() {
            "public".to_string()
        } else {
            visibility_input.to_string()
        };

        let video_id = Uuid::new_v4();
        let status = "uploading";

        tracing::info!(
            "gRPC: Creating video {} for user {} (visibility: {})",
            video_id,
            creator_id,
            visibility
        );

        let video = sqlx::query_as::<_, DbVideo>(
            "INSERT INTO videos (id, creator_id, title, description, duration_seconds, \
             cdn_url, thumbnail_url, status, visibility, created_at, updated_at) \
             VALUES ($1, $2, $3, $4, 0, NULL, NULL, $5, $6, NOW(), NOW()) \
             RETURNING id, creator_id, title, description, duration_seconds, cdn_url, \
             thumbnail_url, status, visibility, created_at, updated_at",
        )
        .bind(video_id)
        .bind(creator_id)
        .bind(&title)
        .bind(description_ref)
        .bind(status)
        .bind(&visibility)
        .fetch_one(&self.db_pool)
        .await
        .map_err(|e| map_sqlx_error(e, "create_video"))?;

        let response = CreateVideoResponse {
            video: Some(video_to_proto(video)),
            error: None,
        };

        Ok(Response::new(response))
    }

    /// List reels with pagination (simple limit)
    async fn list_reels(
        &self,
        request: Request<ListReelsRequest>,
    ) -> Result<Response<ListReelsResponse>, Status> {
        let req = request.into_inner();
        let limit = if req.limit > 0 { req.limit as i64 } else { 20 };

        let service = ReelService::new(self.db_pool.clone());
        let reels = service
            .list_reels(limit)
            .await
            .map_err(|err| map_app_error(err, "list_reels"))?;

        let response = ListReelsResponse {
            reels: reels.into_iter().map(reel_response_to_proto).collect(),
            error: None,
        };

        Ok(Response::new(response))
    }

    /// Get a single reel by ID
    async fn get_reel(
        &self,
        request: Request<GetReelRequest>,
    ) -> Result<Response<GetReelResponse>, Status> {
        let req = request.into_inner();

        let reel_id = Uuid::parse_str(&req.reel_id)
            .map_err(|_| Status::invalid_argument("Invalid reel ID"))?;

        let service = ReelService::new(self.db_pool.clone());
        match service.get_reel(reel_id).await {
            Ok(reel) => Ok(Response::new(GetReelResponse {
                reel: Some(reel_response_to_proto(reel)),
                found: true,
                error: None,
            })),
            Err(AppError::NotFound(msg)) => Ok(Response::new(GetReelResponse {
                reel: None,
                found: false,
                error: Some(make_error("NOT_FOUND", msg)),
            })),
            Err(err) => Err(map_app_error(err, "get_reel")),
        }
    }

    /// Create a new reel and enqueue transcoding
    async fn create_reel(
        &self,
        request: Request<CreateReelRequest>,
    ) -> Result<Response<CreateReelResponse>, Status> {
        let req = request.into_inner();

        let creator_id = Uuid::parse_str(&req.creator_id)
            .map_err(|_| Status::invalid_argument("Invalid creator ID"))?;

        if req.upload_id.trim().is_empty() {
            return Err(Status::invalid_argument("upload_id is required"));
        }

        let payload = CreateReelPayload {
            upload_id: req.upload_id.clone(),
            caption: if req.caption.is_empty() {
                None
            } else {
                Some(req.caption.clone())
            },
            music_title: if req.music_title.is_empty() {
                None
            } else {
                Some(req.music_title.clone())
            },
            music_artist: if req.music_artist.is_empty() {
                None
            } else {
                Some(req.music_artist.clone())
            },
            duration_seconds: if req.duration_seconds > 0 {
                Some(req.duration_seconds)
            } else {
                None
            },
            visibility: if req.visibility.is_empty() {
                None
            } else {
                Some(req.visibility.clone())
            },
            allow_comments: Some(req.allow_comments),
            allow_shares: Some(req.allow_shares),
            cover_image_url: if req.cover_image_url.is_empty() {
                None
            } else {
                Some(req.cover_image_url.clone())
            },
        };

        let service = ReelService::new(self.db_pool.clone());
        let reel = service
            .create_reel(creator_id, payload, &self.reel_pipeline)
            .await
            .map_err(|err| map_app_error(err, "create_reel"))?;

        let response = CreateReelResponse {
            reel: Some(reel_response_to_proto(reel)),
            error: None,
        };

        Ok(Response::new(response))
    }

    /// Get upload details
    async fn get_upload(
        &self,
        request: Request<GetUploadRequest>,
    ) -> Result<Response<GetUploadResponse>, Status> {
        let req = request.into_inner();

        let upload_id = Uuid::parse_str(&req.upload_id)
            .map_err(|_| Status::invalid_argument("Invalid upload ID"))?;

        tracing::info!("gRPC: Getting upload with ID: {}", upload_id);

        let upload = sqlx::query_as::<_, DbUpload>(
            "SELECT id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at \
             FROM uploads WHERE id = $1",
        )
        .bind(upload_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| map_sqlx_error(e, "get_upload"))?;

        let response = match upload {
            Some(upload) => GetUploadResponse {
                upload: Some(upload_to_proto(upload)),
                found: true,
                error: None,
            },
            None => GetUploadResponse {
                upload: None,
                found: false,
                error: Some(make_error("NOT_FOUND", "Upload not found")),
            },
        };

        Ok(Response::new(response))
    }

    /// Update upload progress
    async fn update_upload_progress(
        &self,
        request: Request<UpdateUploadProgressRequest>,
    ) -> Result<Response<UpdateUploadProgressResponse>, Status> {
        let req = request.into_inner();

        if req.uploaded_size < 0 {
            return Err(Status::invalid_argument(
                "uploaded_size must be a non-negative value",
            ));
        }

        let upload_id = Uuid::parse_str(&req.upload_id)
            .map_err(|_| Status::invalid_argument("Invalid upload ID"))?;

        tracing::info!(
            "gRPC: Updating upload {} progress to {} bytes",
            upload_id,
            req.uploaded_size
        );

        let upload = sqlx::query_as::<_, DbUpload>(
            "UPDATE uploads SET uploaded_size = $2, updated_at = NOW() WHERE id = $1 \
             RETURNING id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at",
        )
        .bind(upload_id)
        .bind(req.uploaded_size)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| map_sqlx_error(e, "update_upload_progress"))?;

        let upload = upload.ok_or_else(|| Status::not_found("Upload not found"))?;

        let response = UpdateUploadProgressResponse {
            upload: Some(upload_to_proto(upload)),
            error: None,
        };

        Ok(Response::new(response))
    }

    /// Start a new upload
    async fn start_upload(
        &self,
        request: Request<StartUploadRequest>,
    ) -> Result<Response<StartUploadResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        if req.file_name.trim().is_empty() {
            return Err(Status::invalid_argument("file_name is required"));
        }

        if req.file_size <= 0 {
            return Err(Status::invalid_argument(
                "file_size must be greater than zero",
            ));
        }

        let upload_id = Uuid::new_v4();
        let status = "uploading";

        tracing::info!(
            "gRPC: Starting upload {} for user {} (file: {}, size: {}, content_type: {})",
            upload_id,
            user_id,
            req.file_name,
            req.file_size,
            req.content_type
        );

        let upload = sqlx::query_as::<_, DbUpload>(
            "INSERT INTO uploads (id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at) \
             VALUES ($1, $2, NULL, $3, $4, 0, $5, NOW(), NOW()) \
             RETURNING id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at",
        )
        .bind(upload_id)
        .bind(user_id)
        .bind(&req.file_name)
        .bind(req.file_size)
        .bind(status)
        .fetch_one(&self.db_pool)
        .await
        .map_err(|e| map_sqlx_error(e, "start_upload"))?;

        let response = StartUploadResponse {
            upload: Some(upload_to_proto(upload)),
            error: None,
        };

        Ok(Response::new(response))
    }

    /// Complete an upload
    async fn complete_upload(
        &self,
        request: Request<CompleteUploadRequest>,
    ) -> Result<Response<CompleteUploadResponse>, Status> {
        let req = request.into_inner();

        let upload_id = Uuid::parse_str(&req.upload_id)
            .map_err(|_| Status::invalid_argument("Invalid upload ID"))?;

        tracing::info!("gRPC: Completing upload {}", upload_id);

        let upload = sqlx::query_as::<_, DbUpload>(
            "UPDATE uploads SET status = 'completed', updated_at = NOW() WHERE id = $1 \
             RETURNING id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at",
        )
        .bind(upload_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| map_sqlx_error(e, "complete_upload"))?;

        let upload = upload.ok_or_else(|| Status::not_found("Upload not found"))?;

        let response = CompleteUploadResponse {
            upload: Some(upload_to_proto(upload)),
            error: None,
        };

        Ok(Response::new(response))
    }
}

/// Create a gRPC server for media service
pub async fn start_grpc_server(
    addr: std::net::SocketAddr,
    db_pool: PgPool,
    cache: Arc<MediaCache>,
    mut shutdown: broadcast::Receiver<()>,
) -> Result<(), Box<dyn std::error::Error>> {
    use media_service_server::MediaServiceServer;
    use tonic::transport::Server;

    tracing::info!("Starting gRPC server at {}", addr);

    // ✅ P0-1: Load mTLS configuration
    let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
        Ok(config) => {
            tracing::info!("mTLS enabled - service-to-service authentication active");
            Some(config)
        }
        Err(e) => {
            tracing::warn!(
                "mTLS disabled - TLS config not found: {}. Using development mode for testing only.",
                e
            );
            if cfg!(debug_assertions) {
                tracing::info!("Development mode: Starting without TLS (NOT FOR PRODUCTION)");
                None
            } else {
                return Err(format!(
                    "Production requires mTLS - GRPC_SERVER_CERT_PATH must be set: {}",
                    e
                ).into());
            }
        }
    };

    let mut server_builder = Server::builder();
    if let Some(tls_cfg) = tls_config {
        let server_tls = tls_cfg
            .build_server_tls()
            .context("Failed to build server TLS config")?;
        server_builder = server_builder
            .tls_config(server_tls)
            .context("Failed to configure TLS on gRPC server")?;
        tracing::info!("gRPC server TLS configured successfully");
    }

    let reel_pipeline = ReelTranscodePipeline::new(db_pool.clone());
    let service = MediaServiceImpl::new(db_pool, reel_pipeline, cache);
    server_builder
        .add_service(MediaServiceServer::new(service))
        .serve_with_shutdown(addr, async move {
            let _ = shutdown.recv().await;
        })
        .await?;

    Ok(())
}
