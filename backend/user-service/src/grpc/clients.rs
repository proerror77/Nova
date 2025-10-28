//! gRPC client implementations for inter-service communication

use crate::grpc::config::GrpcClientConfig;
use crate::grpc::health::{HealthChecker, HealthStatus};
use crate::grpc::nova::content::content_service_client::ContentServiceClient as TonicContentServiceClient;
use crate::grpc::nova::content::*;
use crate::grpc::nova::media::media_service_client::MediaServiceClient as TonicMediaServiceClient;
use crate::grpc::nova::media::*;
use std::ops::{Deref, DerefMut};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};
use tonic::transport::Channel;

/// Lightweight async pool for tonic gRPC clients.
struct GrpcClientPool<T> {
    clients: Mutex<Vec<T>>,
    semaphore: Arc<Semaphore>,
}

impl<T> GrpcClientPool<T> {
    fn new(initial_clients: Vec<T>) -> Arc<Self> {
        assert!(
            !initial_clients.is_empty(),
            "gRPC client pool requires at least one connection"
        );
        let capacity = initial_clients.len();
        Arc::new(Self {
            clients: Mutex::new(initial_clients),
            semaphore: Arc::new(Semaphore::new(capacity)),
        })
    }

    async fn acquire(self: &Arc<Self>) -> GrpcClientGuard<T> {
        let permit = self
            .semaphore
            .clone()
            .acquire_owned()
            .await
            .expect("gRPC client pool semaphore closed");
        let client = {
            let mut guard = self
                .clients
                .lock()
                .expect("gRPC client pool mutex poisoned");
            guard
                .pop()
                .expect("gRPC client pool exhausted despite semaphore permit")
        };

        GrpcClientGuard {
            pool: Arc::clone(self),
            client: Some(client),
            permit,
        }
    }
}

struct GrpcClientGuard<T> {
    pool: Arc<GrpcClientPool<T>>,
    client: Option<T>,
    permit: OwnedSemaphorePermit,
}

impl<T> Deref for GrpcClientGuard<T> {
    type Target = T;

    fn deref(&self) -> &Self::Target {
        self.client
            .as_ref()
            .expect("gRPC pooled client unexpectedly missing")
    }
}

impl<T> DerefMut for GrpcClientGuard<T> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.client
            .as_mut()
            .expect("gRPC pooled client unexpectedly missing")
    }
}

impl<T> Drop for GrpcClientGuard<T> {
    fn drop(&mut self) {
        if let Some(client) = self.client.take() {
            if let Ok(mut clients) = self.pool.clients.lock() {
                clients.push(client);
            } else {
                tracing::warn!("Failed to return gRPC client to pool due to poisoned mutex");
            }
        }
        // Dropping the permit automatically releases capacity back to the semaphore.
    }
}

/// Content Service gRPC client wrapper
#[derive(Clone)]
pub struct ContentServiceClient {
    client_pool: Arc<GrpcClientPool<TonicContentServiceClient<Channel>>>,
    health_checker: Arc<HealthChecker>,
    request_timeout: Duration,
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

        let pool_size = config.pool_size();
        let endpoint = Channel::from_shared(config.content_service_url.clone())?
            .connect_timeout(config.connection_timeout())
            .tcp_nodelay(true);

        let mut clients = Vec::with_capacity(pool_size);
        for _ in 0..pool_size {
            let channel = endpoint.clone().connect().await?;
            clients.push(TonicContentServiceClient::new(channel));
        }
        let client_pool = GrpcClientPool::new(clients);

        tracing::info!("Content service gRPC client connected successfully");
        health_checker
            .set_content_service_health(HealthStatus::Healthy)
            .await;

        Ok(Self {
            client_pool,
            health_checker,
            request_timeout: config.request_timeout(),
        })
    }

    /// Get personalized feed via content-service
    pub async fn get_feed(
        &self,
        request: GetFeedRequest,
    ) -> Result<GetFeedResponse, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let mut req = tonic::Request::new(request);
        req.set_timeout(self.request_timeout);

        match client.get_feed(req).await {
            Ok(response) => {
                self.health_checker
                    .set_content_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error fetching feed from content-service: {}", e);
                self.health_checker
                    .set_content_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Invalidate feed cache/event via content-service
    pub async fn invalidate_feed_event(
        &self,
        request: InvalidateFeedEventRequest,
    ) -> Result<InvalidateFeedResponse, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let mut req = tonic::Request::new(request);
        req.set_timeout(self.request_timeout);

        match client.invalidate_feed_event(req).await {
            Ok(response) => {
                self.health_checker
                    .set_content_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error invalidating feed via content-service: {}", e);
                self.health_checker
                    .set_content_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Batch invalidate feed caches via content-service
    pub async fn batch_invalidate_feed(
        &self,
        request: BatchInvalidateFeedRequest,
    ) -> Result<InvalidateFeedResponse, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let mut req = tonic::Request::new(request);
        req.set_timeout(self.request_timeout);

        match client.batch_invalidate_feed(req).await {
            Ok(response) => {
                self.health_checker
                    .set_content_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error batch invalidating feed via content-service: {}", e);
                self.health_checker
                    .set_content_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Warm feed cache via content-service
    pub async fn warm_feed(
        &self,
        request: WarmFeedRequest,
    ) -> Result<InvalidateFeedResponse, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let mut req = tonic::Request::new(request);
        req.set_timeout(self.request_timeout);

        match client.warm_feed(req).await {
            Ok(response) => {
                self.health_checker
                    .set_content_service_health(HealthStatus::Healthy)
                    .await;
                Ok(response.into_inner())
            }
            Err(e) => {
                tracing::error!("Error warming feed via content-service: {}", e);
                self.health_checker
                    .set_content_service_health(HealthStatus::Unavailable)
                    .await;
                Err(e)
            }
        }
    }

    /// Get a post by ID
    pub async fn get_post(&self, post_id: String) -> Result<GetPostResponse, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(GetPostRequest { post_id });
        request.set_timeout(self.request_timeout);

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
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(CreatePostRequest {
            creator_id,
            content,
        });
        request.set_timeout(self.request_timeout);

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
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(GetCommentsRequest {
            post_id,
            limit,
            offset,
        });
        request.set_timeout(self.request_timeout);

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
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(LikePostRequest { user_id, post_id });
        request.set_timeout(self.request_timeout);

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
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(GetUserBookmarksRequest {
            user_id,
            limit,
            offset,
        });
        request.set_timeout(self.request_timeout);

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
    client_pool: Arc<GrpcClientPool<TonicMediaServiceClient<Channel>>>,
    health_checker: Arc<HealthChecker>,
    request_timeout: Duration,
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

        let pool_size = config.pool_size();
        let endpoint = Channel::from_shared(config.media_service_url.clone())?
            .connect_timeout(config.connection_timeout())
            .tcp_nodelay(true);

        let mut clients = Vec::with_capacity(pool_size);
        for _ in 0..pool_size {
            let channel = endpoint.clone().connect().await?;
            clients.push(TonicMediaServiceClient::new(channel));
        }
        let client_pool = GrpcClientPool::new(clients);

        tracing::info!("Media service gRPC client connected successfully");
        health_checker
            .set_media_service_health(HealthStatus::Healthy)
            .await;

        Ok(Self {
            client_pool,
            health_checker,
            request_timeout: config.request_timeout(),
        })
    }

    /// Get a video by ID
    pub async fn get_video(&self, video_id: String) -> Result<GetVideoResponse, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(GetVideoRequest { video_id });
        request.set_timeout(self.request_timeout);

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
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(GetUserVideosRequest { user_id, limit });
        request.set_timeout(self.request_timeout);

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
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(CreateVideoRequest {
            creator_id,
            title,
            description,
            visibility,
        });
        request.set_timeout(self.request_timeout);

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
    pub async fn get_upload(&self, upload_id: String) -> Result<GetUploadResponse, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(GetUploadRequest { upload_id });
        request.set_timeout(self.request_timeout);

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
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(UpdateUploadProgressRequest {
            upload_id,
            uploaded_size,
        });
        request.set_timeout(self.request_timeout);

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
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(StartUploadRequest {
            user_id,
            file_name,
            file_size,
            content_type,
        });
        request.set_timeout(self.request_timeout);

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
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(CompleteUploadRequest { upload_id });
        request.set_timeout(self.request_timeout);

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
