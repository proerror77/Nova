//! HTTP handlers for Video Service
//!
//! These handlers expose the VideoService via HTTP endpoints.
//! They translate HTTP requests into the protobuf types used by the gRPC service.

use actix_web::{web, HttpResponse, Result as ActixResult};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::grpc::{
    UploadVideoRequest, GetVideoMetadataRequest, TranscodeVideoRequest,
    GetTranscodingProgressRequest, ListVideosRequest, DeleteVideoRequest,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadVideoPayload {
    pub user_id: String,
    pub title: String,
    pub description: Option<String>,
    pub file_name: String,
    pub file_size: i64,
    pub mime_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GetVideoMetadataQuery {
    pub video_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodeVideoPayload {
    pub video_id: String,
    pub target_resolutions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GetTranscodingProgressQuery {
    pub job_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListVideosQuery {
    pub user_id: String,
    pub limit: Option<u32>,
    pub cursor: Option<String>,
    pub sort_by: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteVideoPayload {
    pub video_id: String,
    pub user_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadVideoResponse {
    pub video_id: String,
    pub upload_url: String,
    pub upload_session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodeVideoResponse {
    pub job_id: String,
    pub video_id: String,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoMetadataResponse {
    pub id: String,
    pub user_id: String,
    pub title: String,
    pub description: String,
    pub duration: i32,
}

/// Upload a new video
pub async fn upload_video(
    payload: web::Json<UploadVideoPayload>,
) -> ActixResult<HttpResponse> {
    let _request = UploadVideoRequest {
        user_id: payload.user_id.clone(),
        title: payload.title.clone(),
        description: payload.description.clone().unwrap_or_default(),
        file_name: payload.file_name.clone(),
        file_size: payload.file_size,
        mime_type: payload.mime_type.clone(),
    };

    // TODO: Call the gRPC service implementation
    tracing::info!("Video upload request: user_id={}, title={}", payload.user_id, payload.title);

    Ok(HttpResponse::Created().json(UploadVideoResponse {
        video_id: Uuid::new_v4().to_string(),
        upload_url: "https://s3.example.com/presigned-url".to_string(),
        upload_session_id: Uuid::new_v4().to_string(),
    }))
}

/// Get video metadata
pub async fn get_video_metadata(
    query: web::Query<GetVideoMetadataQuery>,
) -> ActixResult<HttpResponse> {
    let _request = GetVideoMetadataRequest {
        video_id: query.video_id.clone(),
    };

    // TODO: Call the gRPC service implementation
    tracing::debug!("Getting metadata for video: {}", query.video_id);

    Ok(HttpResponse::Ok().json(VideoMetadataResponse {
        id: query.video_id.clone(),
        user_id: "user_placeholder".to_string(),
        title: "Video Title".to_string(),
        description: "Video Description".to_string(),
        duration: 0,
    }))
}

/// Start transcoding a video
pub async fn transcode_video(
    payload: web::Json<TranscodeVideoPayload>,
) -> ActixResult<HttpResponse> {
    let _request = TranscodeVideoRequest {
        video_id: payload.video_id.clone(),
        target_resolutions: payload.target_resolutions.clone(),
        ffmpeg_options: std::collections::HashMap::new(),
    };

    tracing::info!("Transcoding video: {}", payload.video_id);

    Ok(HttpResponse::Ok().json(TranscodeVideoResponse {
        job_id: Uuid::new_v4().to_string(),
        video_id: payload.video_id.clone(),
        status: "queued".to_string(),
    }))
}

/// Get transcoding progress
pub async fn get_transcoding_progress(
    query: web::Query<GetTranscodingProgressQuery>,
) -> ActixResult<HttpResponse> {
    let _request = GetTranscodingProgressRequest {
        job_id: query.job_id.clone(),
    };

    tracing::debug!("Getting progress for job: {}", query.job_id);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "job_id": query.job_id,
        "status": "processing",
        "progress_percent": 50,
        "current_resolution": "1080p",
    })))
}

/// List videos for a user
pub async fn list_videos(
    query: web::Query<ListVideosQuery>,
) -> ActixResult<HttpResponse> {
    let _request = ListVideosRequest {
        user_id: query.user_id.clone(),
        limit: query.limit.unwrap_or(20),
        cursor: query.cursor.clone().unwrap_or_default(),
        sort_by: query.sort_by.clone().unwrap_or_default(),
    };

    tracing::debug!("Listing videos for user: {}", query.user_id);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "videos": [],
        "next_cursor": "",
        "has_more": false,
    })))
}

/// Delete a video
pub async fn delete_video(
    payload: web::Json<DeleteVideoPayload>,
) -> ActixResult<HttpResponse> {
    let _request = DeleteVideoRequest {
        video_id: payload.video_id.clone(),
        user_id: payload.user_id.clone(),
    };

    tracing::info!("Deleting video: {}", payload.video_id);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "video_id": payload.video_id,
        "success": true,
    })))
}

/// Configure routes for video service
pub fn configure_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1/videos")
            .route("", web::post().to(upload_video))
            .route("/{video_id}", web::get().to(get_video_metadata))
            .route("/{video_id}/transcode", web::post().to(transcode_video))
            .route("/{video_id}/progress", web::get().to(get_transcoding_progress))
            .route("/user/{user_id}", web::get().to(list_videos))
            .route("/{video_id}", web::delete().to(delete_video))
    );
}
