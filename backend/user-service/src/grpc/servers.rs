//! gRPC server implementations for microservices
//!
//! This module provides gRPC server implementations that wrap the existing business logic
//! from the user-service. These servers act as an adapter layer, allowing other microservices
//! to call the functionality via gRPC instead of having duplicate code.
//!
//! Architecture:
//! - RecommendationService: Wraps recommendation_v2 business logic
//! - VideoService: Wraps video processing and transcoding logic
//! - StreamingService: Wraps live streaming functionality

use std::sync::Arc;
use tonic::{Response, Status};
use uuid::Uuid;

use crate::grpc::clients::MediaServiceClient;
use crate::grpc::nova::media::Video as MediaVideo;
use crate::grpc::nova::video::v1::{
    video_service_server::VideoService as VideoServiceTrait, DeleteVideoRequest,
    DeleteVideoResponse, GetTranscodingProgressRequest, GetVideoMetadataRequest, ListVideosRequest,
    ListVideosResponse, TranscodeVideoRequest, TranscodeVideoResponse, TranscodingProgress,
    UploadVideoRequest, UploadVideoResponse, VideoMetadata, VideoSummary,
};

/// VideoServer implements the gRPC VideoService.
/// It proxies calls to media-service, which owns video storage and processing.
#[derive(Clone)]
pub struct VideoServer {
    media_client: Arc<MediaServiceClient>,
    s3_client: Arc<aws_sdk_s3::Client>,
    s3_config: Arc<crate::config::S3Config>,
}

impl VideoServer {
    pub fn new(
        media_client: Arc<MediaServiceClient>,
        s3_client: Arc<aws_sdk_s3::Client>,
        s3_config: Arc<crate::config::S3Config>,
    ) -> Self {
        Self {
            media_client,
            s3_client,
            s3_config,
        }
    }
}

#[tonic::async_trait]
impl VideoServiceTrait for VideoServer {
    async fn upload_video(
        &self,
        request: tonic::Request<UploadVideoRequest>,
    ) -> Result<Response<UploadVideoResponse>, Status> {
        let req = request.into_inner();

        let file_name = sanitize_file_name(&req.file_name);
        let content_type = if req.mime_type.trim().is_empty() {
            "application/octet-stream".to_string()
        } else {
            req.mime_type.clone()
        };

        let start_response = self
            .media_client
            .start_upload(
                req.user_id.clone(),
                file_name.clone(),
                req.file_size,
                content_type.clone(),
            )
            .await
            .map_err(|e| map_media_status("start_upload", e))?;

        let upload = start_response
            .upload
            .ok_or_else(|| Status::internal("media-service returned no upload payload"))?;

        let upload_uuid = Uuid::parse_str(&upload.id).unwrap_or_else(|_| Uuid::new_v4());
        let s3_key = format!("uploads/{}/{}", upload_uuid, file_name);

        let presigned_url = crate::services::storage::generate_presigned_put_url(
            &self.s3_client,
            &self.s3_config,
            &s3_key,
            &content_type,
            std::time::Duration::from_secs(self.s3_config.presigned_url_expiry_secs),
        )
        .await
        .map_err(|e| Status::internal(format!("failed_to_generate_presigned_url: {}", e)))?;

        let video_id = if upload.video_id.is_empty() {
            upload.id.clone()
        } else {
            upload.video_id.clone()
        };

        Ok(Response::new(UploadVideoResponse {
            video_id,
            upload_url: presigned_url,
            upload_session_id: upload.id,
        }))
    }

    async fn get_video_metadata(
        &self,
        request: tonic::Request<GetVideoMetadataRequest>,
    ) -> Result<Response<VideoMetadata>, Status> {
        let req = request.into_inner();
        let response = self
            .media_client
            .get_video(req.video_id.clone())
            .await
            .map_err(|e| map_media_status("get_video", e))?;

        if !response.found {
            return Err(Status::not_found("video not found"));
        }

        let media_video = response
            .video
            .ok_or_else(|| Status::internal("media-service returned empty video payload"))?;

        Ok(Response::new(convert_media_video_to_metadata(media_video)))
    }

    async fn transcode_video(
        &self,
        _request: tonic::Request<TranscodeVideoRequest>,
    ) -> Result<Response<TranscodeVideoResponse>, Status> {
        Err(Status::unimplemented(
            "Transcoding is handled by media-service's dedicated API",
        ))
    }

    async fn get_transcoding_progress(
        &self,
        _request: tonic::Request<GetTranscodingProgressRequest>,
    ) -> Result<Response<TranscodingProgress>, Status> {
        Err(Status::unimplemented(
            "Transcoding progress is handled by media-service",
        ))
    }

    async fn list_videos(
        &self,
        request: tonic::Request<ListVideosRequest>,
    ) -> Result<Response<ListVideosResponse>, Status> {
        let req = request.into_inner();
        let response = self
            .media_client
            .get_user_videos(req.user_id.clone(), req.limit as i32)
            .await
            .map_err(|e| map_media_status("get_user_videos", e))?;

        let videos = response
            .videos
            .into_iter()
            .map(convert_media_video_to_summary)
            .collect();

        Ok(Response::new(ListVideosResponse {
            videos,
            next_cursor: String::new(),
            has_more: false,
        }))
    }

    async fn delete_video(
        &self,
        _request: tonic::Request<DeleteVideoRequest>,
    ) -> Result<Response<DeleteVideoResponse>, Status> {
        Err(Status::unimplemented(
            "Video deletion must be routed to media-service",
        ))
    }
}

fn convert_media_video_to_metadata(video: MediaVideo) -> VideoMetadata {
    VideoMetadata {
        id: video.id,
        user_id: video.creator_id,
        title: video.title,
        description: video.description,
        duration: video.duration_seconds,
        width: 0,
        height: 0,
        mime_type: "video/mp4".to_string(),
        created_at: video.created_at,
        updated_at: video.created_at,
        thumbnail_url: video.thumbnail_url,
        status: video.status,
        quality: None,
    }
}

fn convert_media_video_to_summary(video: MediaVideo) -> VideoSummary {
    VideoSummary {
        id: video.id,
        title: video.title,
        thumbnail_url: video.thumbnail_url,
        duration: video.duration_seconds,
        created_at: video.created_at,
        status: video.status,
    }
}

fn map_media_status(operation: &str, status: tonic::Status) -> Status {
    let message = format!("media-service {operation} failed: {}", status.message());
    Status::new(status.code(), message)
}

fn sanitize_file_name(name: &str) -> String {
    let sanitized: String = name
        .chars()
        .map(|c| match c {
            'a'..='z' | 'A'..='Z' | '0'..='9' | '.' | '-' | '_' => c,
            _ => '_',
        })
        .collect();

    if sanitized.trim_matches('_').is_empty() {
        format!("upload-{}", Uuid::new_v4())
    } else {
        sanitized
    }
}
