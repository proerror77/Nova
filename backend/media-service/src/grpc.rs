// gRPC service implementation for media service (services_v2 proto)
use crate::services::video::gcs::GcsSigner;
use chrono::Utc;
use sqlx::PgPool;
use std::fs;
use std::sync::Arc;
use tokio::sync::broadcast;
use tonic::transport::{Certificate, Identity, ServerTlsConfig};
use tonic::{Request, Response, Status};
use uuid::Uuid;

// Import generated proto code from services_v2/media_service.proto
pub mod nova {
    pub mod media {
        pub mod v1 {
            tonic::include_proto!("nova.media.v1");
        }
    }
}

use nova::media::v1::media_service_server::{MediaService, MediaServiceServer};
use nova::media::v1::*;

/// Media file database model
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct MediaFileRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub filename: String,
    pub media_type: String,
    pub mime_type: String,
    pub size_bytes: i64,
    pub storage_path: Option<String>,
    pub cdn_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub status: String,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub duration_seconds: Option<i32>,
    pub checksum: Option<String>,
    pub created_at: chrono::DateTime<Utc>,
    pub updated_at: chrono::DateTime<Utc>,
    pub deleted_at: Option<chrono::DateTime<Utc>>,
}

/// Upload session database model
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct UploadRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub media_id: Option<Uuid>,
    pub filename: String,
    pub media_type: String,
    pub mime_type: String,
    pub size_bytes: i64,
    pub storage_path: Option<String>,
    pub presigned_url: Option<String>,
    pub expires_at: Option<chrono::DateTime<Utc>>,
    pub status: String,
    pub created_at: chrono::DateTime<Utc>,
    pub updated_at: chrono::DateTime<Utc>,
}

impl MediaFileRow {
    fn to_proto(&self) -> MediaFile {
        MediaFile {
            id: self.id.to_string(),
            user_id: self.user_id.to_string(),
            filename: self.filename.clone(),
            media_type: string_to_media_type(&self.media_type) as i32,
            mime_type: self.mime_type.clone(),
            size_bytes: self.size_bytes,
            storage_path: self.storage_path.clone().unwrap_or_default(),
            cdn_url: self.cdn_url.clone().unwrap_or_default(),
            thumbnail_url: self.thumbnail_url.clone().unwrap_or_default(),
            status: string_to_processing_status(&self.status) as i32,
            metadata: Some(MediaMetadata {
                width: self.width.unwrap_or(0),
                height: self.height.unwrap_or(0),
                format: String::new(),
                duration_seconds: self.duration_seconds.unwrap_or(0),
                bitrate: 0,
                codec: String::new(),
                framerate: 0,
                variants: vec![],
                sample_rate: 0,
                channels: 0,
                checksum: self.checksum.clone().unwrap_or_default(),
                exif: Default::default(),
            }),
            created_at: Some(prost_types::Timestamp {
                seconds: self.created_at.timestamp(),
                nanos: 0,
            }),
            updated_at: Some(prost_types::Timestamp {
                seconds: self.updated_at.timestamp(),
                nanos: 0,
            }),
            deleted_at: self.deleted_at.map(|dt| prost_types::Timestamp {
                seconds: dt.timestamp(),
                nanos: 0,
            }),
        }
    }
}

fn string_to_media_type(s: &str) -> MediaType {
    match s.to_lowercase().as_str() {
        "image" => MediaType::Image,
        "video" => MediaType::Video,
        "audio" => MediaType::Audio,
        "document" => MediaType::Document,
        _ => MediaType::Unspecified,
    }
}

fn media_type_to_string(mt: i32) -> String {
    match MediaType::try_from(mt).unwrap_or(MediaType::Unspecified) {
        MediaType::Image => "image".to_string(),
        MediaType::Video => "video".to_string(),
        MediaType::Audio => "audio".to_string(),
        MediaType::Document => "document".to_string(),
        MediaType::Unspecified => "unspecified".to_string(),
    }
}

fn string_to_processing_status(s: &str) -> ProcessingStatus {
    match s.to_lowercase().as_str() {
        "uploading" => ProcessingStatus::Uploading,
        "processing" => ProcessingStatus::Processing,
        "ready" => ProcessingStatus::Ready,
        "failed" => ProcessingStatus::Failed,
        _ => ProcessingStatus::Unspecified,
    }
}

/// MediaService gRPC implementation (services_v2)
#[derive(Clone)]
pub struct MediaServiceImpl {
    db_pool: PgPool,
    cdn_url: String,
    gcs_signer: Arc<GcsSigner>,
    gcs_bucket: String,
}

impl MediaServiceImpl {
    pub fn new(
        db_pool: PgPool,
        cdn_url: String,
        gcs_signer: Arc<GcsSigner>,
        gcs_bucket: String,
    ) -> Self {
        Self {
            db_pool,
            cdn_url,
            gcs_signer,
            gcs_bucket,
        }
    }
}

#[tonic::async_trait]
impl MediaService for MediaServiceImpl {
    /// Initiate a new upload - returns presigned URL for direct object upload
    #[tracing::instrument(skip(self, request), fields(user_id = %request.get_ref().user_id, filename = %request.get_ref().filename))]
    async fn initiate_upload(
        &self,
        request: Request<InitiateUploadRequest>,
    ) -> Result<Response<InitiateUploadResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        if req.filename.trim().is_empty() {
            return Err(Status::invalid_argument("Filename is required"));
        }

        if req.size_bytes <= 0 {
            return Err(Status::invalid_argument("Size must be greater than zero"));
        }

        let upload_id = Uuid::new_v4();
        let started_at = std::time::Instant::now();
        let media_type = media_type_to_string(req.media_type);
        let mime_type = if req.mime_type.is_empty() {
            "application/octet-stream".to_string()
        } else {
            req.mime_type.clone()
        };

        // Generate GCS storage path
        let ext = req
            .filename
            .rsplit('.')
            .next()
            .unwrap_or("bin")
            .to_lowercase();
        let storage_path = format!("uploads/{}/{}.{}", user_id, upload_id, ext);

        // Generate GCS signed URL for upload
        let presigned_url = self
            .gcs_signer
            .sign_put_url(
                &self.gcs_bucket,
                &storage_path,
                &mime_type,
                std::time::Duration::from_secs(900),
            )
            .map_err(|e| {
                tracing::error!("Failed to generate GCS signed URL: {:?}", e);
                Status::internal("Failed to generate upload URL")
            })?;

        let expires_at = Utc::now() + chrono::Duration::minutes(15);

        // Insert upload record
        sqlx::query(
            "INSERT INTO uploads (id, user_id, filename, media_type, mime_type, size_bytes, storage_path, presigned_url, expires_at, status)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending')",
        )
        .bind(upload_id)
        .bind(user_id)
        .bind(&req.filename)
        .bind(&media_type)
        .bind(&mime_type)
        .bind(req.size_bytes)
        .bind(&storage_path)
        .bind(&presigned_url)
        .bind(expires_at)
        .execute(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to create upload record: {:?}", e);
            Status::internal("Failed to create upload session")
        })?;

        tracing::info!(
            upload_id = %upload_id,
            user_id = %user_id,
            filename = %req.filename,
            elapsed_ms = %started_at.elapsed().as_millis(),
            size_bytes = %req.size_bytes,
            "InitiateUpload: Created upload session"
        );

        Ok(Response::new(InitiateUploadResponse {
            upload_id: upload_id.to_string(),
            presigned_url,
            headers: Default::default(),
            expires_at: expires_at.timestamp(),
        }))
    }

    /// Complete an upload after client has uploaded to presigned URL
    #[tracing::instrument(skip(self, request), fields(user_id = %request.get_ref().user_id, upload_id = %request.get_ref().upload_id))]
    async fn complete_upload(
        &self,
        request: Request<CompleteUploadRequest>,
    ) -> Result<Response<CompleteUploadResponse>, Status> {
        let req = request.into_inner();

        let upload_id = Uuid::parse_str(&req.upload_id)
            .map_err(|_| Status::invalid_argument("Invalid upload ID"))?;

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        // Get upload record
        let started_at = std::time::Instant::now();
        let upload: UploadRow = sqlx::query_as(
            "SELECT id, user_id, media_id, filename, media_type, mime_type, size_bytes,
                    storage_path, presigned_url, expires_at, status, created_at, updated_at
             FROM uploads WHERE id = $1 AND user_id = $2",
        )
        .bind(upload_id)
        .bind(user_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error: {:?}", e);
            Status::internal("Database error")
        })?
        .ok_or_else(|| Status::not_found("Upload not found"))?;

        if upload.status == "completed" {
            return Err(Status::already_exists("Upload already completed"));
        }

        // Create media file record
        let media_id = Uuid::new_v4();
        let cdn_url = format!(
            "{}/{}",
            self.cdn_url.trim_end_matches('/'),
            upload.storage_path.as_deref().unwrap_or("")
        );

        let media: MediaFileRow = sqlx::query_as(
            "INSERT INTO media_files (id, user_id, filename, media_type, mime_type, size_bytes, storage_path, cdn_url, status, checksum)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'ready', $9)
             RETURNING id, user_id, filename, media_type, mime_type, size_bytes, storage_path, cdn_url, thumbnail_url, status, width, height, duration_seconds, checksum, created_at, updated_at, deleted_at",
        )
        .bind(media_id)
        .bind(user_id)
        .bind(&upload.filename)
        .bind(&upload.media_type)
        .bind(&upload.mime_type)
        .bind(upload.size_bytes)
        .bind(&upload.storage_path)
        .bind(&cdn_url)
        .bind(if req.checksum.is_empty() { None } else { Some(&req.checksum) })
        .fetch_one(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to create media record: {:?}", e);
            Status::internal("Failed to create media record")
        })?;

        // Update upload status
        sqlx::query("UPDATE uploads SET status = 'completed', media_id = $2, updated_at = NOW() WHERE id = $1")
            .bind(upload_id)
            .bind(media_id)
            .execute(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to update upload status: {:?}", e);
            Status::internal("Failed to complete upload")
        })?;

        tracing::info!(
            upload_id = %upload_id,
            media_id = %media_id,
            elapsed_ms = %started_at.elapsed().as_millis(),
            size_bytes = %upload.size_bytes,
            "CompleteUpload: Upload completed successfully"
        );

        Ok(Response::new(CompleteUploadResponse {
            media: Some(media.to_proto()),
        }))
    }

    /// Cancel an upload
    async fn cancel_upload(
        &self,
        request: Request<CancelUploadRequest>,
    ) -> Result<Response<()>, Status> {
        let req = request.into_inner();

        let upload_id = Uuid::parse_str(&req.upload_id)
            .map_err(|_| Status::invalid_argument("Invalid upload ID"))?;

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        sqlx::query("UPDATE uploads SET status = 'cancelled', updated_at = NOW() WHERE id = $1 AND user_id = $2")
            .bind(upload_id)
            .bind(user_id)
            .execute(&self.db_pool)
            .await
            .map_err(|e| {
                tracing::error!("Failed to cancel upload: {:?}", e);
                Status::internal("Failed to cancel upload")
            })?;

        Ok(Response::new(()))
    }

    /// Get media by ID
    async fn get_media(
        &self,
        request: Request<GetMediaRequest>,
    ) -> Result<Response<GetMediaResponse>, Status> {
        let req = request.into_inner();

        let media_id = Uuid::parse_str(&req.media_id)
            .map_err(|_| Status::invalid_argument("Invalid media ID"))?;

        let media: Option<MediaFileRow> = sqlx::query_as(
            "SELECT id, user_id, filename, media_type, mime_type, size_bytes, storage_path, cdn_url,
                    thumbnail_url, status, width, height, duration_seconds, checksum, created_at, updated_at, deleted_at
             FROM media_files WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(media_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error: {:?}", e);
            Status::internal("Database error")
        })?;

        Ok(Response::new(GetMediaResponse {
            media: media.map(|m| m.to_proto()),
        }))
    }

    /// Get media by IDs (batch)
    async fn get_media_by_ids(
        &self,
        request: Request<GetMediaByIdsRequest>,
    ) -> Result<Response<GetMediaByIdsResponse>, Status> {
        let req = request.into_inner();

        let media_ids: Vec<Uuid> = req
            .media_ids
            .iter()
            .filter_map(|id| Uuid::parse_str(id).ok())
            .collect();

        if media_ids.is_empty() {
            return Ok(Response::new(GetMediaByIdsResponse {
                media: vec![],
                not_found_ids: req.media_ids,
            }));
        }

        let media: Vec<MediaFileRow> = sqlx::query_as(
            "SELECT id, user_id, filename, media_type, mime_type, size_bytes, storage_path, cdn_url,
                    thumbnail_url, status, width, height, duration_seconds, checksum, created_at, updated_at, deleted_at
             FROM media_files WHERE id = ANY($1) AND deleted_at IS NULL",
        )
        .bind(&media_ids)
        .fetch_all(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error: {:?}", e);
            Status::internal("Database error")
        })?;

        let found_ids: std::collections::HashSet<String> =
            media.iter().map(|m| m.id.to_string()).collect();
        let not_found_ids: Vec<String> = req
            .media_ids
            .into_iter()
            .filter(|id| !found_ids.contains(id))
            .collect();

        Ok(Response::new(GetMediaByIdsResponse {
            media: media.into_iter().map(|m| m.to_proto()).collect(),
            not_found_ids,
        }))
    }

    /// Get user's media files
    async fn get_user_media(
        &self,
        request: Request<GetUserMediaRequest>,
    ) -> Result<Response<GetUserMediaResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        let limit = if req.limit > 0 { req.limit } else { 20 };
        let offset = if req.offset >= 0 { req.offset } else { 0 };

        let media: Vec<MediaFileRow> = sqlx::query_as(
            "SELECT id, user_id, filename, media_type, mime_type, size_bytes, storage_path, cdn_url,
                    thumbnail_url, status, width, height, duration_seconds, checksum, created_at, updated_at, deleted_at
             FROM media_files WHERE user_id = $1 AND deleted_at IS NULL
             ORDER BY created_at DESC LIMIT $2 OFFSET $3",
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error: {:?}", e);
            Status::internal("Database error")
        })?;

        let total_count: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM media_files WHERE user_id = $1 AND deleted_at IS NULL",
        )
        .bind(user_id)
        .fetch_one(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error: {:?}", e);
            Status::internal("Database error")
        })?;

        Ok(Response::new(GetUserMediaResponse {
            media: media.into_iter().map(|m| m.to_proto()).collect(),
            total_count: total_count.0 as i32,
            has_more: (offset + limit) < total_count.0 as i32,
        }))
    }

    /// Generate thumbnail (stub implementation)
    async fn generate_thumbnail(
        &self,
        _request: Request<GenerateThumbnailRequest>,
    ) -> Result<Response<GenerateThumbnailResponse>, Status> {
        Err(Status::unimplemented(
            "Thumbnail generation not yet implemented",
        ))
    }

    /// Transcode video (stub implementation)
    async fn transcode_video(
        &self,
        _request: Request<TranscodeVideoRequest>,
    ) -> Result<Response<TranscodeVideoResponse>, Status> {
        Err(Status::unimplemented(
            "Video transcoding not yet implemented",
        ))
    }

    /// Get transcode status (stub implementation)
    async fn get_transcode_status(
        &self,
        _request: Request<GetTranscodeStatusRequest>,
    ) -> Result<Response<GetTranscodeStatusResponse>, Status> {
        Err(Status::unimplemented(
            "Transcode status not yet implemented",
        ))
    }

    /// Get streaming URL
    async fn get_streaming_url(
        &self,
        request: Request<GetStreamingUrlRequest>,
    ) -> Result<Response<GetStreamingUrlResponse>, Status> {
        let req = request.into_inner();

        let media_id = Uuid::parse_str(&req.media_id)
            .map_err(|_| Status::invalid_argument("Invalid media ID"))?;

        let media: MediaFileRow = sqlx::query_as(
            "SELECT id, user_id, filename, media_type, mime_type, size_bytes, storage_path, cdn_url,
                    thumbnail_url, status, width, height, duration_seconds, checksum, created_at, updated_at, deleted_at
             FROM media_files WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(media_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error: {:?}", e);
            Status::internal("Database error")
        })?
        .ok_or_else(|| Status::not_found("Media not found"))?;

        let expires_at = Utc::now() + chrono::Duration::hours(1);

        Ok(Response::new(GetStreamingUrlResponse {
            url: media.cdn_url.unwrap_or_default(),
            expires_at: expires_at.timestamp(),
            available_qualities: vec![],
        }))
    }

    /// Get download URL
    async fn get_download_url(
        &self,
        request: Request<GetDownloadUrlRequest>,
    ) -> Result<Response<GetDownloadUrlResponse>, Status> {
        let req = request.into_inner();

        let media_id = Uuid::parse_str(&req.media_id)
            .map_err(|_| Status::invalid_argument("Invalid media ID"))?;

        let media: MediaFileRow = sqlx::query_as(
            "SELECT id, user_id, filename, media_type, mime_type, size_bytes, storage_path, cdn_url,
                    thumbnail_url, status, width, height, duration_seconds, checksum, created_at, updated_at, deleted_at
             FROM media_files WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(media_id)
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error: {:?}", e);
            Status::internal("Database error")
        })?
        .ok_or_else(|| Status::not_found("Media not found"))?;

        let expires_in = if req.expires_in_seconds > 0 {
            req.expires_in_seconds
        } else {
            3600
        };
        let expires_at = Utc::now() + chrono::Duration::seconds(expires_in);

        Ok(Response::new(GetDownloadUrlResponse {
            url: media.cdn_url.unwrap_or_default(),
            expires_at: expires_at.timestamp(),
        }))
    }

    /// Delete media
    async fn delete_media(
        &self,
        request: Request<DeleteMediaRequest>,
    ) -> Result<Response<()>, Status> {
        let req = request.into_inner();

        let media_id = Uuid::parse_str(&req.media_id)
            .map_err(|_| Status::invalid_argument("Invalid media ID"))?;

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        let result = sqlx::query(
            "UPDATE media_files SET deleted_at = NOW(), updated_at = NOW() WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
        )
        .bind(media_id)
        .bind(user_id)
        .execute(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error: {:?}", e);
            Status::internal("Database error")
        })?;

        if result.rows_affected() == 0 {
            return Err(Status::not_found("Media not found or not owned by user"));
        }

        Ok(Response::new(()))
    }

    /// Bulk delete media
    async fn bulk_delete_media(
        &self,
        request: Request<BulkDeleteMediaRequest>,
    ) -> Result<Response<()>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        let media_ids: Vec<Uuid> = req
            .media_ids
            .iter()
            .filter_map(|id| Uuid::parse_str(id).ok())
            .collect();

        if media_ids.is_empty() {
            return Ok(Response::new(()));
        }

        sqlx::query(
            "UPDATE media_files SET deleted_at = NOW(), updated_at = NOW() WHERE id = ANY($1) AND user_id = $2 AND deleted_at IS NULL",
        )
        .bind(&media_ids)
        .bind(user_id)
        .execute(&self.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database error: {:?}", e);
            Status::internal("Database error")
        })?;

        Ok(Response::new(()))
    }
}

/// Create and start the gRPC server
pub async fn start_grpc_server(
    addr: std::net::SocketAddr,
    db_pool: PgPool,
    cdn_url: String,
    gcs_signer: Arc<GcsSigner>,
    gcs_bucket: String,
    mut shutdown: broadcast::Receiver<()>,
) -> Result<(), Box<dyn std::error::Error>> {
    use tonic::transport::Server;

    tracing::info!("Starting gRPC server at {}", addr);

    let service = MediaServiceImpl::new(db_pool, cdn_url, gcs_signer, gcs_bucket);

    let mut server_builder = Server::builder();

    if let Some(tls_config) = load_server_tls_config()? {
        server_builder = server_builder.tls_config(tls_config)?;
    } else {
        tracing::warn!(
            "gRPC server TLS is DISABLED; enable GRPC_TLS_ENABLED=true for staging/production"
        );
    }

    server_builder
        .add_service(MediaServiceServer::new(service))
        .serve_with_shutdown(addr, async move {
            let _ = shutdown.recv().await;
        })
        .await?;

    Ok(())
}

fn load_server_tls_config() -> Result<Option<ServerTlsConfig>, Box<dyn std::error::Error>> {
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

    let mut tls_config =
        ServerTlsConfig::new().identity(Identity::from_pem(server_cert, server_key));

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
