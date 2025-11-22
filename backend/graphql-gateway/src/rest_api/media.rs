use actix_multipart::Multipart;
use actix_web::{post, web, HttpMessage, HttpRequest, HttpResponse};
use futures_util::stream::StreamExt;
use tracing::{error, info};

use crate::clients::proto::media::media_service_client::MediaServiceClient;
use crate::clients::proto::media::{InitiateUploadRequest, MediaType};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

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
            let cd = field.content_disposition();
            if let Some(name) = cd.get_filename() {
                filename = name.to_string();
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
    let media_type = match ext.as_deref() {
        Some("jpg") | Some("jpeg") | Some("png") | Some("gif") | Some("webp") => {
            MediaType::Image as i32
        }
        Some("mp4") | Some("mov") | Some("mkv") | Some("avi") => MediaType::Video as i32,
        Some("mp3") | Some("wav") | Some("aac") => MediaType::Audio as i32,
        _ => MediaType::Unspecified as i32,
    };

    let req = InitiateUploadRequest {
        user_id,
        filename: filename.clone(),
        media_type,
        mime_type: "application/octet-stream".to_string(),
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
