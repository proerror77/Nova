//! gRPC client implementations for inter-service communication

use crate::grpc::config::GrpcClientConfig;
use crate::grpc::health::{HealthChecker, HealthStatus};
use crate::grpc::nova::content::content_service_client::ContentServiceClient as TonicContentServiceClient;
use crate::grpc::nova::content::*;
use crate::grpc::nova::media::media_service_client::MediaServiceClient as TonicMediaServiceClient;
use crate::grpc::nova::media::*;
use std::sync::Arc;
use tonic::transport::Channel;

/// Content Service gRPC client wrapper
#[derive(Clone)]
pub struct ContentServiceClient {
    client: TonicContentServiceClient<Channel>,
    health_checker: Arc<HealthChecker>,
}

impl ContentServiceClient {
    /// Create a new content service client
    pub async fn new(
        config: &GrpcClientConfig,
        health_checker: Arc<HealthChecker>,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        tracing::info!(
            "Creating content service gRPC client: {}",
            config.content_service_url
        );

        // Create the gRPC channel
        let channel = Channel::from_shared(config.content_service_url.clone())?
            .connect_timeout(config.connection_timeout())
            .connect()
            .await?;

        let client = TonicContentServiceClient::new(channel);

        tracing::info!("Content service gRPC client connected successfully");
        health_checker
            .set_content_service_health(HealthStatus::Healthy)
            .await;

        Ok(Self {
            client,
            health_checker,
        })
    }

    /// Get a post by ID
    pub async fn get_post(
        &self,
        post_id: String,
    ) -> Result<GetPostResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(GetPostRequest { post_id });

        match client.get_post(request).await {
            Ok(response) => {
                tracing::debug!("Got post response from content-service");
                self.health_checker
                    .set_content_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error getting post from content-service: {}", e);
                self.health_checker
                    .set_content_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Create a new post
    pub async fn create_post(
        &self,
        creator_id: String,
        content: String,
    ) -> Result<CreatePostResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(CreatePostRequest {
            creator_id,
            content,
        });

        match client.create_post(request).await {
            Ok(response) => {
                tracing::debug!("Post created via content-service gRPC");
                self.health_checker
                    .set_content_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error creating post via content-service: {}", e);
                self.health_checker
                    .set_content_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Get comments for a post
    pub async fn get_comments(
        &self,
        post_id: String,
        limit: i32,
        offset: i32,
    ) -> Result<GetCommentsResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(GetCommentsRequest {
            post_id,
            limit,
            offset,
        });

        match client.get_comments(request).await {
            Ok(response) => {
                tracing::debug!("Got comments response from content-service");
                self.health_checker
                    .set_content_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error getting comments from content-service: {}", e);
                self.health_checker
                    .set_content_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Like a post
    pub async fn like_post(
        &self,
        user_id: String,
        post_id: String,
    ) -> Result<LikePostResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(LikePostRequest { user_id, post_id });

        match client.like_post(request).await {
            Ok(response) => {
                tracing::debug!("Post liked via content-service gRPC");
                self.health_checker
                    .set_content_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error liking post via content-service: {}", e);
                self.health_checker
                    .set_content_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Get user bookmarks
    pub async fn get_user_bookmarks(
        &self,
        user_id: String,
        limit: i32,
        offset: i32,
    ) -> Result<GetUserBookmarksResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(GetUserBookmarksRequest {
            user_id,
            limit,
            offset,
        });

        match client.get_user_bookmarks(request).await {
            Ok(response) => {
                tracing::debug!("Got user bookmarks from content-service");
                self.health_checker
                    .set_content_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error getting user bookmarks from content-service: {}", e);
                self.health_checker
                    .set_content_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }
}

/// Media Service gRPC client wrapper
#[derive(Clone)]
pub struct MediaServiceClient {
    client: TonicMediaServiceClient<Channel>,
    health_checker: Arc<HealthChecker>,
}

impl MediaServiceClient {
    /// Create a new media service client
    pub async fn new(
        config: &GrpcClientConfig,
        health_checker: Arc<HealthChecker>,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        tracing::info!(
            "Creating media service gRPC client: {}",
            config.media_service_url
        );

        // Create the gRPC channel
        let channel = Channel::from_shared(config.media_service_url.clone())?
            .connect_timeout(config.connection_timeout())
            .connect()
            .await?;

        let client = TonicMediaServiceClient::new(channel);

        tracing::info!("Media service gRPC client connected successfully");
        health_checker
            .set_media_service_health(HealthStatus::Healthy)
            .await;

        Ok(Self {
            client,
            health_checker,
        })
    }

    /// Get a video by ID
    pub async fn get_video(
        &self,
        video_id: String,
    ) -> Result<GetVideoResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(GetVideoRequest { video_id });

        match client.get_video(request).await {
            Ok(response) => {
                tracing::debug!("Got video response from media-service");
                self.health_checker
                    .set_media_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error getting video from media-service: {}", e);
                self.health_checker
                    .set_media_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Get videos for a user
    pub async fn get_user_videos(
        &self,
        user_id: String,
        limit: i32,
    ) -> Result<GetUserVideosResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(GetUserVideosRequest { user_id, limit });

        match client.get_user_videos(request).await {
            Ok(response) => {
                tracing::debug!("Got user videos response from media-service");
                self.health_checker
                    .set_media_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error getting user videos from media-service: {}", e);
                self.health_checker
                    .set_media_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Create a new video
    pub async fn create_video(
        &self,
        creator_id: String,
        title: String,
        description: String,
        visibility: String,
    ) -> Result<CreateVideoResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(CreateVideoRequest {
            creator_id,
            title,
            description,
            visibility,
        });

        match client.create_video(request).await {
            Ok(response) => {
                tracing::debug!("Video created via media-service gRPC");
                self.health_checker
                    .set_media_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error creating video via media-service: {}", e);
                self.health_checker
                    .set_media_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Get upload details
    pub async fn get_upload(
        &self,
        upload_id: String,
    ) -> Result<GetUploadResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(GetUploadRequest { upload_id });

        match client.get_upload(request).await {
            Ok(response) => {
                tracing::debug!("Got upload response from media-service");
                self.health_checker
                    .set_media_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error getting upload from media-service: {}", e);
                self.health_checker
                    .set_media_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Update upload progress
    pub async fn update_upload_progress(
        &self,
        upload_id: String,
        uploaded_size: i64,
    ) -> Result<UpdateUploadProgressResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(UpdateUploadProgressRequest {
            upload_id,
            uploaded_size,
        });

        match client.update_upload_progress(request).await {
            Ok(response) => {
                tracing::debug!("Upload progress updated via media-service gRPC");
                self.health_checker
                    .set_media_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error updating upload progress via media-service: {}", e);
                self.health_checker
                    .set_media_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Start a new upload
    pub async fn start_upload(
        &self,
        user_id: String,
        file_name: String,
        file_size: i64,
        content_type: String,
    ) -> Result<StartUploadResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(StartUploadRequest {
            user_id,
            file_name,
            file_size,
            content_type,
        });

        match client.start_upload(request).await {
            Ok(response) => {
                tracing::debug!("Upload started via media-service gRPC");
                self.health_checker
                    .set_media_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error starting upload via media-service: {}", e);
                self.health_checker
                    .set_media_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Complete an upload
    pub async fn complete_upload(
        &self,
        upload_id: String,
    ) -> Result<CompleteUploadResponse, tonic::Status> {
        let mut client = self.client.clone();
        let request = tonic::Request::new(CompleteUploadRequest { upload_id });

        match client.complete_upload(request).await {
            Ok(response) => {
                tracing::debug!("Upload completed via media-service gRPC");
                self.health_checker
                    .set_media_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error completing upload via media-service: {}", e);
                self.health_checker
                    .set_media_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }
}
