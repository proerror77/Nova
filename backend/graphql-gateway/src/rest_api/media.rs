use actix_multipart::Multipart;
use actix_web::{delete, get, post, web, HttpMessage, HttpRequest, HttpResponse};
use futures_util::stream::StreamExt;
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::media::media_service_client::MediaServiceClient;
use crate::clients::proto::media::{
    CompleteUploadRequest, DeleteMediaRequest, GetDownloadUrlRequest, GetMediaRequest,
    GetStreamingUrlRequest, GetUserMediaRequest, InitiateUploadRequest, MediaType,
    StreamingProtocol,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use crate::rest_api::models::ErrorResponse;

/// Simplified single-shot upload: returns upload_id/presigned_url for client to PUT.
#[post("/api/v2/media/upload")]
pub async fn upload_media(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    mut payload: Multipart,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    const MAX_UPLOAD_BYTES: usize = 20 * 1024 * 1024; // 20MB guardrail

    // Collect filename (if any) to pass along; body not stored here.
    let mut filename = String::new();
    let mut total_bytes: usize = 0;
    while let Some(item) = payload.next().await {
        if let Ok(mut field) = item {
            if let Some(cd) = field.content_disposition() {
                if let Some(name) = cd.get_filename() {
                    filename = name.to_string();
                }
            }
            // Drain stream to avoid blocking client; actual bytes not stored in gateway.
            while let Some(chunk_res) = field.next().await {
                match chunk_res {
                    Ok(bytes) => {
                        total_bytes += bytes.len();
                        if total_bytes > MAX_UPLOAD_BYTES {
                            return HttpResponse::PayloadTooLarge()
                                .body("upload exceeds 20MB limit");
                        }
                    }
                    Err(e) => {
                        error!("Error reading upload field: {}", e);
                        return HttpResponse::BadRequest().finish();
                    }
                }
            }
        }
    }

    if filename.is_empty() {
        return HttpResponse::BadRequest().body("filename required");
    }

    let mut media_client: MediaServiceClient<_> = clients.media_client();
    let ext = filename.rsplit('.').next().map(|ext| ext.to_lowercase());

    // Infer MIME type from file extension for accurate presigned URL signing
    // This ensures the Content-Type used when uploading matches the signature
    let (media_type, mime_type) = match ext.as_deref() {
        Some("jpg") | Some("jpeg") => (MediaType::Image as i32, "image/jpeg".to_string()),
        Some("png") => (MediaType::Image as i32, "image/png".to_string()),
        Some("gif") => (MediaType::Image as i32, "image/gif".to_string()),
        Some("webp") => (MediaType::Image as i32, "image/webp".to_string()),
        Some("heic") | Some("heif") => (MediaType::Image as i32, "image/heic".to_string()),
        Some("mp4") => (MediaType::Video as i32, "video/mp4".to_string()),
        Some("mov") => (MediaType::Video as i32, "video/quicktime".to_string()),
        Some("mkv") => (MediaType::Video as i32, "video/x-matroska".to_string()),
        Some("avi") => (MediaType::Video as i32, "video/x-msvideo".to_string()),
        Some("webm") => (MediaType::Video as i32, "video/webm".to_string()),
        Some("mp3") => (MediaType::Audio as i32, "audio/mpeg".to_string()),
        Some("wav") => (MediaType::Audio as i32, "audio/wav".to_string()),
        Some("aac") => (MediaType::Audio as i32, "audio/aac".to_string()),
        Some("m4a") => (MediaType::Audio as i32, "audio/mp4".to_string()),
        Some("ogg") => (MediaType::Audio as i32, "audio/ogg".to_string()),
        _ => (
            MediaType::Unspecified as i32,
            "application/octet-stream".to_string(),
        ),
    };

    let req = InitiateUploadRequest {
        user_id,
        filename: filename.clone(),
        media_type,
        mime_type,
        size_bytes: total_bytes as i64,
    };

    match media_client.initiate_upload(req).await {
        Ok(resp) => {
            info!("InitiateUpload ok for {}", filename);
            HttpResponse::Ok().json(resp.into_inner())
        }
        Err(e) => {
            error!("InitiateUpload failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

// ============================================================================
// Additional Media API Endpoints
// ============================================================================

/// Request body for initiating an upload (lightweight, no file data)
#[derive(Debug, Deserialize)]
pub struct InitiateUploadBody {
    pub filename: String,
    pub size_bytes: i64,
    #[serde(default)]
    pub content_type: Option<String>,
}

/// Response for initiate upload - includes presigned URL for direct GCS upload
#[derive(Debug, Serialize)]
pub struct InitiateUploadResponse {
    pub upload_id: String,
    pub presigned_url: String,
    pub expires_at: i64,
}

/// POST /api/v2/media/upload/initiate
/// Lightweight endpoint to get presigned URL without uploading file data.
/// Client should then PUT the file directly to the presigned URL.
#[post("/api/v2/media/upload/initiate")]
pub async fn initiate_upload(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<InitiateUploadBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    info!(
        user_id = %user_id,
        filename = %body.filename,
        size_bytes = %body.size_bytes,
        "POST /api/v2/media/upload/initiate"
    );

    if body.filename.is_empty() {
        return HttpResponse::BadRequest().json(ErrorResponse::new("filename is required"));
    }

    if body.size_bytes <= 0 {
        return HttpResponse::BadRequest().json(ErrorResponse::new("size_bytes must be positive"));
    }

    const MAX_UPLOAD_BYTES: i64 = 20 * 1024 * 1024; // 20MB
    if body.size_bytes > MAX_UPLOAD_BYTES {
        return HttpResponse::PayloadTooLarge()
            .json(ErrorResponse::new("File size exceeds 20MB limit"));
    }

    let ext = body
        .filename
        .rsplit('.')
        .next()
        .map(|ext| ext.to_lowercase());

    // Infer MIME type from file extension or use provided content_type
    let (media_type, mime_type) = if let Some(ct) = &body.content_type {
        let mt = if ct.starts_with("image/") {
            MediaType::Image as i32
        } else if ct.starts_with("video/") {
            MediaType::Video as i32
        } else if ct.starts_with("audio/") {
            MediaType::Audio as i32
        } else {
            MediaType::Unspecified as i32
        };
        (mt, ct.clone())
    } else {
        match ext.as_deref() {
            Some("jpg") | Some("jpeg") => (MediaType::Image as i32, "image/jpeg".to_string()),
            Some("png") => (MediaType::Image as i32, "image/png".to_string()),
            Some("gif") => (MediaType::Image as i32, "image/gif".to_string()),
            Some("webp") => (MediaType::Image as i32, "image/webp".to_string()),
            Some("heic") | Some("heif") => (MediaType::Image as i32, "image/heic".to_string()),
            Some("mp4") => (MediaType::Video as i32, "video/mp4".to_string()),
            Some("mov") => (MediaType::Video as i32, "video/quicktime".to_string()),
            Some("mkv") => (MediaType::Video as i32, "video/x-matroska".to_string()),
            Some("avi") => (MediaType::Video as i32, "video/x-msvideo".to_string()),
            Some("webm") => (MediaType::Video as i32, "video/webm".to_string()),
            Some("mp3") => (MediaType::Audio as i32, "audio/mpeg".to_string()),
            Some("wav") => (MediaType::Audio as i32, "audio/wav".to_string()),
            Some("aac") => (MediaType::Audio as i32, "audio/aac".to_string()),
            Some("m4a") => (MediaType::Audio as i32, "audio/mp4".to_string()),
            Some("ogg") => (MediaType::Audio as i32, "audio/ogg".to_string()),
            _ => (
                MediaType::Unspecified as i32,
                "application/octet-stream".to_string(),
            ),
        }
    };

    let mut media_client: MediaServiceClient<_> = clients.media_client();

    let req = InitiateUploadRequest {
        user_id,
        filename: body.filename.clone(),
        media_type,
        mime_type,
        size_bytes: body.size_bytes,
    };

    match media_client.initiate_upload(req).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            info!(
                upload_id = %inner.upload_id,
                "InitiateUpload successful"
            );
            HttpResponse::Ok().json(InitiateUploadResponse {
                upload_id: inner.upload_id,
                presigned_url: inner.presigned_url,
                expires_at: inner.expires_at,
            })
        }
        Err(e) => {
            error!("InitiateUpload failed: {}", e);
            HttpResponse::ServiceUnavailable().json(ErrorResponse::with_message(
                "Failed to initiate upload",
                e.message(),
            ))
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct CompleteUploadBody {
    pub checksum: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UserMediaQuery {
    #[serde(default = "default_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
    pub media_type: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct StreamQuery {
    pub protocol: Option<String>,
    pub quality: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct DownloadQuery {
    #[serde(default = "default_expires")]
    pub expires_in_seconds: i64,
}

fn default_limit() -> i32 {
    20
}

fn default_expires() -> i64 {
    3600
}

#[derive(Debug, Serialize)]
pub struct MediaResponse {
    pub id: String,
    pub user_id: String,
    pub filename: String,
    pub media_type: String,
    pub mime_type: String,
    pub size_bytes: i64,
    pub cdn_url: String,
    pub thumbnail_url: String,
    pub status: String,
    pub created_at: i64,
}

/// GET /api/v2/media/{media_id}
/// Get media metadata by ID
#[get("/api/v2/media/{media_id}")]
pub async fn get_media(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> HttpResponse {
    if http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return HttpResponse::Unauthorized().finish();
    }

    let media_id = path.into_inner();
    info!(media_id = %media_id, "GET /api/v2/media/{media_id}");

    let mut media_client: MediaServiceClient<_> = clients.media_client();

    match media_client
        .get_media(GetMediaRequest {
            media_id: media_id.clone(),
        })
        .await
    {
        Ok(resp) => {
            let inner = resp.into_inner();
            if let Some(media) = inner.media {
                let media_type_str = format!("{:?}", media.media_type());
                let status_str = format!("{:?}", media.status());
                HttpResponse::Ok().json(MediaResponse {
                    id: media.id,
                    user_id: media.user_id,
                    filename: media.filename,
                    media_type: media_type_str,
                    mime_type: media.mime_type,
                    size_bytes: media.size_bytes,
                    cdn_url: media.cdn_url,
                    thumbnail_url: media.thumbnail_url,
                    status: status_str,
                    created_at: media.created_at.map(|t| t.seconds).unwrap_or(0),
                })
            } else {
                HttpResponse::NotFound().json(ErrorResponse::with_message(
                    "Media not found",
                    format!("No media with id {}", media_id),
                ))
            }
        }
        Err(e) => {
            error!("GetMedia failed: {}", e);
            HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "Failed to get media",
                e.message(),
            ))
        }
    }
}

/// POST /api/v2/media/upload/{upload_id}/complete
/// Complete an upload after client has uploaded to presigned URL
#[post("/api/v2/media/upload/{upload_id}/complete")]
pub async fn complete_upload(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
    body: web::Json<CompleteUploadBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let upload_id = path.into_inner();
    info!(upload_id = %upload_id, "POST /api/v2/media/upload/{upload_id}/complete");

    let mut media_client: MediaServiceClient<_> = clients.media_client();

    match media_client
        .complete_upload(CompleteUploadRequest {
            upload_id: upload_id.clone(),
            user_id,
            checksum: body.checksum.clone().unwrap_or_default(),
        })
        .await
    {
        Ok(resp) => {
            let inner = resp.into_inner();
            if let Some(media) = inner.media {
                let media_type_str = format!("{:?}", media.media_type());
                let status_str = format!("{:?}", media.status());
                HttpResponse::Ok().json(MediaResponse {
                    id: media.id,
                    user_id: media.user_id,
                    filename: media.filename,
                    media_type: media_type_str,
                    mime_type: media.mime_type,
                    size_bytes: media.size_bytes,
                    cdn_url: media.cdn_url,
                    thumbnail_url: media.thumbnail_url,
                    status: status_str,
                    created_at: media.created_at.map(|t| t.seconds).unwrap_or(0),
                })
            } else {
                HttpResponse::BadRequest().json(ErrorResponse::with_message(
                    "Upload completion failed",
                    "Upload not found or already completed",
                ))
            }
        }
        Err(e) => {
            error!("CompleteUpload failed: {}", e);
            HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "Failed to complete upload",
                e.message(),
            ))
        }
    }
}

/// GET /api/v2/media/user/{user_id}
/// Get user's media files
#[get("/api/v2/media/user/{user_id}")]
pub async fn get_user_media(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
    query: web::Query<UserMediaQuery>,
) -> HttpResponse {
    if http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return HttpResponse::Unauthorized().finish();
    }

    let user_id = path.into_inner();
    info!(user_id = %user_id, limit = query.limit, "GET /api/v2/media/user/{user_id}");

    let media_type = match query.media_type.as_deref() {
        Some("image") => MediaType::Image as i32,
        Some("video") => MediaType::Video as i32,
        Some("audio") => MediaType::Audio as i32,
        Some("document") => MediaType::Document as i32,
        _ => MediaType::Unspecified as i32,
    };

    let mut media_client: MediaServiceClient<_> = clients.media_client();

    match media_client
        .get_user_media(GetUserMediaRequest {
            user_id,
            media_type,
            limit: query.limit,
            offset: query.offset,
        })
        .await
    {
        Ok(resp) => {
            let inner = resp.into_inner();
            let media: Vec<MediaResponse> = inner
                .media
                .into_iter()
                .map(|m| {
                    let media_type_str = format!("{:?}", m.media_type());
                    let status_str = format!("{:?}", m.status());
                    MediaResponse {
                        id: m.id,
                        user_id: m.user_id,
                        filename: m.filename,
                        media_type: media_type_str,
                        mime_type: m.mime_type,
                        size_bytes: m.size_bytes,
                        cdn_url: m.cdn_url,
                        thumbnail_url: m.thumbnail_url,
                        status: status_str,
                        created_at: m.created_at.map(|t| t.seconds).unwrap_or(0),
                    }
                })
                .collect();

            HttpResponse::Ok().json(serde_json::json!({
                "media": media,
                "total_count": inner.total_count,
                "has_more": inner.has_more,
            }))
        }
        Err(e) => {
            error!("GetUserMedia failed: {}", e);
            HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "Failed to get user media",
                e.message(),
            ))
        }
    }
}

/// GET /api/v2/media/{media_id}/stream
/// Get streaming URL for video
#[get("/api/v2/media/{media_id}/stream")]
pub async fn get_streaming_url(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
    query: web::Query<StreamQuery>,
) -> HttpResponse {
    if http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return HttpResponse::Unauthorized().finish();
    }

    let media_id = path.into_inner();
    info!(media_id = %media_id, "GET /api/v2/media/{media_id}/stream");

    let protocol = match query.protocol.as_deref() {
        Some("hls") => StreamingProtocol::Hls as i32,
        Some("dash") => StreamingProtocol::Dash as i32,
        Some("progressive") => StreamingProtocol::Progressive as i32,
        _ => StreamingProtocol::Hls as i32, // Default to HLS
    };

    let mut media_client: MediaServiceClient<_> = clients.media_client();

    match media_client
        .get_streaming_url(GetStreamingUrlRequest {
            media_id,
            protocol,
            quality: query.quality.clone().unwrap_or_default(),
        })
        .await
    {
        Ok(resp) => {
            let inner = resp.into_inner();
            HttpResponse::Ok().json(serde_json::json!({
                "url": inner.url,
                "expires_at": inner.expires_at,
                "available_qualities": inner.available_qualities.iter().map(|v| {
                    serde_json::json!({
                        "variant_id": v.variant_id,
                        "width": v.width,
                        "height": v.height,
                        "bitrate": v.bitrate,
                        "format": v.format,
                    })
                }).collect::<Vec<_>>(),
            }))
        }
        Err(e) => {
            error!("GetStreamingUrl failed: {}", e);
            HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "Failed to get streaming URL",
                e.message(),
            ))
        }
    }
}

/// GET /api/v2/media/{media_id}/download
/// Get download URL
#[get("/api/v2/media/{media_id}/download")]
pub async fn get_download_url(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
    query: web::Query<DownloadQuery>,
) -> HttpResponse {
    if http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return HttpResponse::Unauthorized().finish();
    }

    let media_id = path.into_inner();
    info!(media_id = %media_id, "GET /api/v2/media/{media_id}/download");

    let mut media_client: MediaServiceClient<_> = clients.media_client();

    match media_client
        .get_download_url(GetDownloadUrlRequest {
            media_id,
            expires_in_seconds: query.expires_in_seconds,
        })
        .await
    {
        Ok(resp) => {
            let inner = resp.into_inner();
            HttpResponse::Ok().json(serde_json::json!({
                "url": inner.url,
                "expires_at": inner.expires_at,
            }))
        }
        Err(e) => {
            error!("GetDownloadUrl failed: {}", e);
            HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "Failed to get download URL",
                e.message(),
            ))
        }
    }
}

/// DELETE /api/v2/media/{media_id}
/// Delete media file
#[delete("/api/v2/media/{media_id}")]
pub async fn delete_media(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let media_id = path.into_inner();
    info!(media_id = %media_id, user_id = %user_id, "DELETE /api/v2/media/{media_id}");

    let mut media_client: MediaServiceClient<_> = clients.media_client();

    match media_client
        .delete_media(DeleteMediaRequest { media_id, user_id })
        .await
    {
        Ok(_) => HttpResponse::NoContent().finish(),
        Err(e) => {
            error!("DeleteMedia failed: {}", e);
            if e.code() == tonic::Code::NotFound {
                HttpResponse::NotFound()
                    .json(ErrorResponse::with_message("Media not found", e.message()))
            } else if e.code() == tonic::Code::PermissionDenied {
                HttpResponse::Forbidden().json(ErrorResponse::with_message(
                    "Not authorized to delete this media",
                    e.message(),
                ))
            } else {
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to delete media",
                    e.message(),
                ))
            }
        }
    }
}
