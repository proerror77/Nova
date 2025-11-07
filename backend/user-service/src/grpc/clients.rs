//! gRPC client implementations for inter-service communication

use crate::grpc::config::GrpcClientConfig;
use crate::grpc::health::{HealthChecker, HealthStatus};
use crate::grpc::nova::auth_service::auth_service_client::AuthServiceClient as TonicAuthServiceClient;
use crate::grpc::nova::auth_service::*;
use crate::grpc::nova::content_service::content_service_client::ContentServiceClient as TonicContentServiceClient;
use crate::grpc::nova::content_service::*;
use crate::grpc::nova::media_service::media_service_client::MediaServiceClient as TonicMediaServiceClient;
use crate::grpc::nova::media_service::*;
use crate::grpc::nova::feed_service::recommendation_service_client::RecommendationServiceClient as TonicFeedServiceClient;
use crate::grpc::nova::feed_service::*;
use std::future::Future;
use std::ops::{Deref, DerefMut};
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};
use tokio::time::sleep;
use tonic::transport::{Channel, Endpoint};
use uuid::Uuid;

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

async fn connect_with_retry(
    endpoint: Endpoint,
    attempts: u32,
    backoff: Duration,
) -> Result<Channel, tonic::transport::Error> {
    let max_attempts = attempts.max(1);
    let mut last_err = None;

    for attempt in 0..max_attempts {
        match endpoint.clone().connect().await {
            Ok(channel) => return Ok(channel),
            Err(err) => {
                last_err = Some(err);
                if attempt + 1 < max_attempts {
                    let sleep_duration =
                        backoff.checked_mul((attempt + 1) as u32).unwrap_or(backoff);
                    tracing::warn!(
                        attempt = attempt + 1,
                        max_attempts,
                        "gRPC connection attempt failed; retrying"
                    );
                    sleep(sleep_duration).await;
                }
            }
        }
    }

    Err(last_err.expect("connect_with_retry should return error when attempts > 0"))
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
        let endpoint_url = config.endpoint_url(&config.content_service_url)?;
        let base_endpoint = Endpoint::from_shared(endpoint_url)?
            .connect_timeout(config.connection_timeout())
            .timeout(config.connection_timeout())
            .http2_keep_alive_interval(config.http2_keep_alive_interval())
            .keep_alive_while_idle(true)
            .tcp_keepalive(Some(config.http2_keep_alive_interval()))
            .keep_alive_timeout(config.connection_timeout())
            .tcp_nodelay(true)
            .concurrency_limit(config.max_concurrent_streams as usize);
        let endpoint = if let Some(tls) = config.tls_config_for(&config.content_service_url)? {
            base_endpoint.tls_config(tls)?
        } else {
            base_endpoint
        };

        let mut clients = Vec::with_capacity(pool_size);
        for _ in 0..pool_size {
            let channel = connect_with_retry(
                endpoint.clone(),
                config.connect_retry_attempts(),
                config.connect_retry_backoff(),
            )
            .await?;
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
    retry_attempts: u32,
    retry_backoff: Duration,
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
        let endpoint_url = config.endpoint_url(&config.media_service_url)?;
        let base_endpoint = Endpoint::from_shared(endpoint_url)?
            .connect_timeout(config.connection_timeout())
            .timeout(config.connection_timeout())
            .http2_keep_alive_interval(config.http2_keep_alive_interval())
            .keep_alive_while_idle(true)
            .tcp_keepalive(Some(config.http2_keep_alive_interval()))
            .keep_alive_timeout(config.connection_timeout())
            .tcp_nodelay(true)
            .concurrency_limit(config.max_concurrent_streams as usize);
        let endpoint = if let Some(tls) = config.tls_config_for(&config.media_service_url)? {
            base_endpoint.tls_config(tls)?
        } else {
            base_endpoint
        };

        let mut clients = Vec::with_capacity(pool_size);
        for _ in 0..pool_size {
            let channel = connect_with_retry(
                endpoint.clone(),
                config.connect_retry_attempts(),
                config.connect_retry_backoff(),
            )
            .await?;
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
            retry_attempts: config.connect_retry_attempts(),
            retry_backoff: config.connect_retry_backoff(),
        })
    }

    async fn call_with_retry<Req, Resp, F>(
        &self,
        request: Req,
        call: F,
        op_name: &str,
    ) -> Result<Resp, tonic::Status>
    where
        Req: Clone,
        F: for<'a> Fn(
            &'a mut TonicMediaServiceClient<Channel>,
            tonic::Request<Req>,
        ) -> Pin<
            Box<dyn Future<Output = Result<tonic::Response<Resp>, tonic::Status>> + Send + 'a>,
        >,
    {
        let attempts = self.retry_attempts.max(1);
        let mut last_err: Option<tonic::Status> = None;

        for attempt in 0..attempts {
            let mut client = self.client_pool.acquire().await;
            let mut req = tonic::Request::new(request.clone());
            req.set_timeout(self.request_timeout);

            match call(&mut client, req).await {
                Ok(response) => {
                    self.health_checker
                        .set_media_service_health(HealthStatus::Healthy)
                        .await;
                    return Ok(response.into_inner());
                }
                Err(e) => {
                    tracing::warn!(
                        attempt = attempt + 1,
                        max_attempts = attempts,
                        "Media-service {} failed: {}",
                        op_name,
                        e
                    );
                    self.health_checker
                        .set_media_service_health(HealthStatus::Unavailable)
                        .await;
                    last_err = Some(e);
                }
            }

            if attempt + 1 < attempts {
                sleep(self.retry_backoff * (attempt + 1)).await;
            }
        }

        Err(last_err.unwrap_or_else(|| tonic::Status::unavailable("media-service unavailable")))
    }

    /// Get a video by ID
    pub async fn get_video(&self, video_id: String) -> Result<GetVideoResponse, tonic::Status> {
        self.call_with_retry(
            GetVideoRequest { video_id },
            |client, req| Box::pin(async move { client.get_video(req).await }),
            "get_video",
        )
        .await
    }

    /// Get videos for a user
    pub async fn get_user_videos(
        &self,
        user_id: String,
        limit: i32,
    ) -> Result<GetUserVideosResponse, tonic::Status> {
        self.call_with_retry(
            GetUserVideosRequest { user_id, limit },
            |client, req| Box::pin(async move { client.get_user_videos(req).await }),
            "get_user_videos",
        )
        .await
    }

    /// Create a new video
    pub async fn create_video(
        &self,
        creator_id: String,
        title: String,
        description: String,
        visibility: String,
    ) -> Result<CreateVideoResponse, tonic::Status> {
        self.call_with_retry(
            CreateVideoRequest {
                creator_id,
                title,
                description,
                visibility,
            },
            |client, req| Box::pin(async move { client.create_video(req).await }),
            "create_video",
        )
        .await
    }

    /// Get upload details
    pub async fn get_upload(&self, upload_id: String) -> Result<GetUploadResponse, tonic::Status> {
        self.call_with_retry(
            GetUploadRequest { upload_id },
            |client, req| Box::pin(async move { client.get_upload(req).await }),
            "get_upload",
        )
        .await
    }

    /// Update upload progress
    pub async fn update_upload_progress(
        &self,
        upload_id: String,
        uploaded_size: i64,
    ) -> Result<UpdateUploadProgressResponse, tonic::Status> {
        self.call_with_retry(
            UpdateUploadProgressRequest {
                upload_id,
                uploaded_size,
            },
            |client, req| Box::pin(async move { client.update_upload_progress(req).await }),
            "update_upload_progress",
        )
        .await
    }

    /// Start a new upload
    pub async fn start_upload(
        &self,
        user_id: String,
        file_name: String,
        file_size: i64,
        content_type: String,
    ) -> Result<StartUploadResponse, tonic::Status> {
        self.call_with_retry(
            StartUploadRequest {
                user_id,
                file_name,
                file_size,
                content_type,
            },
            |client, req| Box::pin(async move { client.start_upload(req).await }),
            "start_upload",
        )
        .await
    }

    /// Complete an upload
    pub async fn complete_upload(
        &self,
        upload_id: String,
    ) -> Result<CompleteUploadResponse, tonic::Status> {
        self.call_with_retry(
            CompleteUploadRequest { upload_id },
            |client, req| Box::pin(async move { client.complete_upload(req).await }),
            "complete_upload",
        )
        .await
    }
}

/// User profile update parameters forwarded to auth-service
#[derive(Debug, Default, Clone, Copy)]
pub struct UserProfileUpdate<'a> {
    pub display_name: Option<&'a str>,
    pub bio: Option<&'a str>,
    pub avatar_url: Option<&'a str>,
    pub cover_photo_url: Option<&'a str>,
    pub location: Option<&'a str>,
    pub private_account: Option<bool>,
}

/// Auth service gRPC client wrapper (single writer for users table)
#[derive(Clone)]
pub struct AuthServiceClient {
    client_pool: Arc<GrpcClientPool<TonicAuthServiceClient<Channel>>>,
    health_checker: Arc<HealthChecker>,
    request_timeout: Duration,
    retry_attempts: u32,
    retry_backoff: Duration,
}

impl AuthServiceClient {
    /// Create new auth-service client with connection pool
    pub async fn new(
        config: &GrpcClientConfig,
        health_checker: Arc<HealthChecker>,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        tracing::info!(
            "Creating auth service gRPC client: {}",
            config.auth_service_url
        );

        let pool_size = config.pool_size();
        let endpoint_url = config.endpoint_url(&config.auth_service_url)?;
        let base_endpoint = Endpoint::from_shared(endpoint_url)?
            .connect_timeout(config.connection_timeout())
            .timeout(config.connection_timeout())
            .http2_keep_alive_interval(config.http2_keep_alive_interval())
            .keep_alive_while_idle(true)
            .tcp_keepalive(Some(config.http2_keep_alive_interval()))
            .keep_alive_timeout(config.connection_timeout())
            .tcp_nodelay(true)
            .concurrency_limit(config.max_concurrent_streams as usize);
        let endpoint = if let Some(tls) = config.tls_config_for(&config.auth_service_url)? {
            base_endpoint.tls_config(tls)?
        } else {
            base_endpoint
        };

        let mut clients = Vec::with_capacity(pool_size);
        for _ in 0..pool_size {
            let channel = connect_with_retry(
                endpoint.clone(),
                config.connect_retry_attempts(),
                config.connect_retry_backoff(),
            )
            .await?;
            clients.push(TonicAuthServiceClient::new(channel));
        }

        let client_pool = GrpcClientPool::new(clients);
        health_checker
            .set_auth_service_health(HealthStatus::Healthy)
            .await;

        Ok(Self {
            client_pool,
            health_checker,
            request_timeout: config.request_timeout(),
            retry_attempts: config.connect_retry_attempts(),
            retry_backoff: config.connect_retry_backoff(),
        })
    }

    /// Update profile fields via auth-service
    pub async fn update_user_profile(
        &self,
        user_id: Uuid,
        payload: UserProfileUpdate<'_>,
    ) -> Result<UserProfile, tonic::Status> {
        let attempts = self.retry_attempts.max(1);
        let mut last_err: Option<tonic::Status> = None;

        for attempt in 0..attempts {
            let mut client = self.client_pool.acquire().await;
            let mut request = tonic::Request::new(UpdateUserProfileRequest {
                user_id: user_id.to_string(),
                display_name: payload.display_name.map(|v| v.to_owned()),
                bio: payload.bio.map(|v| v.to_owned()),
                avatar_url: payload.avatar_url.map(|v| v.to_owned()),
                cover_photo_url: payload.cover_photo_url.map(|v| v.to_owned()),
                location: payload.location.map(|v| v.to_owned()),
                private_account: payload.private_account,
            });
            request.set_timeout(self.request_timeout);

            match client.update_user_profile(request).await {
                Ok(response) => {
                    let profile = response
                        .into_inner()
                        .profile
                        .ok_or_else(|| tonic::Status::internal("Missing profile data"))?;
                    self.health_checker
                        .set_auth_service_health(HealthStatus::Healthy)
                        .await;
                    return Ok(profile);
                }
                Err(err) => {
                    self.health_checker
                        .set_auth_service_health(HealthStatus::Unavailable)
                        .await;
                    last_err = Some(err);
                    if attempt + 1 < attempts {
                        let delay = self
                            .retry_backoff
                            .checked_mul((attempt + 1) as u32)
                            .unwrap_or(self.retry_backoff);
                        sleep(delay).await;
                    }
                }
            }
        }

        Err(last_err
            .unwrap_or_else(|| tonic::Status::internal("auth-service update_user_profile failed")))
    }

    /// Upsert a base64 public key via auth-service
    pub async fn upsert_public_key(
        &self,
        user_id: Uuid,
        public_key: &str,
    ) -> Result<(), tonic::Status> {
        let attempts = self.retry_attempts.max(1);
        let mut last_err: Option<tonic::Status> = None;

        for attempt in 0..attempts {
            let mut client = self.client_pool.acquire().await;
            let mut request = tonic::Request::new(UpsertUserPublicKeyRequest {
                user_id: user_id.to_string(),
                public_key: public_key.to_owned(),
            });
            request.set_timeout(self.request_timeout);

            match client.upsert_user_public_key(request).await {
                Ok(_) => {
                    self.health_checker
                        .set_auth_service_health(HealthStatus::Healthy)
                        .await;
                    return Ok(());
                }
                Err(err) => {
                    self.health_checker
                        .set_auth_service_health(HealthStatus::Unavailable)
                        .await;
                    last_err = Some(err);
                    if attempt + 1 < attempts {
                        let delay = self
                            .retry_backoff
                            .checked_mul((attempt + 1) as u32)
                            .unwrap_or(self.retry_backoff);
                        sleep(delay).await;
                    }
                }
            }
        }

        Err(last_err
            .unwrap_or_else(|| tonic::Status::internal("auth-service upsert_public_key failed")))
    }

    /// Fetch public key if present
    pub async fn get_public_key(&self, user_id: Uuid) -> Result<Option<String>, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let mut request = tonic::Request::new(GetUserPublicKeyRequest {
            user_id: user_id.to_string(),
        });
        request.set_timeout(self.request_timeout);

        let response = client.get_user_public_key(request).await;
        match response {
            Ok(resp) => {
                self.health_checker
                    .set_auth_service_health(HealthStatus::Healthy)
                    .await;
                let body = resp.into_inner();
                if !body.found {
                    return Ok(None);
                }
                Ok(body.public_key)
            }
            Err(err) => {
                self.health_checker
                    .set_auth_service_health(HealthStatus::Unavailable)
                    .await;
                Err(err)
            }
        }
    }
}

/// Feed Service gRPC client wrapper
#[derive(Clone)]
pub struct FeedServiceClient {
    client_pool: Arc<GrpcClientPool<TonicFeedServiceClient<Channel>>>,
    health_checker: Arc<HealthChecker>,
    request_timeout: Duration,
}

impl FeedServiceClient {
    /// Create a new feed service client
    pub async fn new(
        config: &GrpcClientConfig,
        health_checker: Arc<HealthChecker>,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        tracing::info!(
            "Creating feed service gRPC client: {}",
            config.feed_service_url
        );

        let pool_size = config.pool_size();
        let endpoint_url = config.endpoint_url(&config.feed_service_url)?;
        let base_endpoint = Endpoint::from_shared(endpoint_url)?
            .connect_timeout(config.connection_timeout())
            .timeout(config.connection_timeout())
            .http2_keep_alive_interval(config.http2_keep_alive_interval())
            .keep_alive_while_idle(true)
            .tcp_keepalive(Some(config.http2_keep_alive_interval()))
            .keep_alive_timeout(config.connection_timeout())
            .tcp_nodelay(true)
            .concurrency_limit(config.max_concurrent_streams as usize);
        let endpoint = if let Some(tls) = config.tls_config_for(&config.feed_service_url)? {
            base_endpoint.tls_config(tls)?
        } else {
            base_endpoint
        };

        let mut clients = Vec::with_capacity(pool_size);
        for _ in 0..pool_size {
            let channel = connect_with_retry(
                endpoint.clone(),
                config.connect_retry_attempts(),
                config.connect_retry_backoff(),
            )
            .await?;
            clients.push(TonicFeedServiceClient::new(channel));
        }
        let client_pool = GrpcClientPool::new(clients);

        tracing::info!("Feed service gRPC client connected successfully");
        health_checker
            .set_feed_service_health(HealthStatus::Healthy)
            .await;

        Ok(Self {
            client_pool,
            health_checker,
            request_timeout: config.request_timeout(),
        })
    }

    /// Get personalized feed for a user
    pub async fn get_feed(&self, request: GetFeedRequest) -> Result<GetFeedResponse, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let mut tonic_request = tonic::Request::new(request);
        tonic_request.set_timeout(self.request_timeout);

        let response = client.get_feed(tonic_request).await;
        match response {
            Ok(resp) => {
                self.health_checker
                    .set_feed_service_health(HealthStatus::Healthy)
                    .await;
                Ok(resp.into_inner())
            }
            Err(err) => {
                self.health_checker
                    .set_feed_service_health(HealthStatus::Unavailable)
                    .await;
                Err(err)
            }
        }
    }

    /// Invalidate feed cache for a user
    pub async fn invalidate_feed_cache(
        &self,
        user_id: String,
        event_type: String,
    ) -> Result<InvalidateFeedCacheResponse, tonic::Status> {
        let mut client = self.client_pool.acquire().await;
        let request = InvalidateFeedCacheRequest {
            user_id,
            event_type,
        };
        let mut tonic_request = tonic::Request::new(request);
        tonic_request.set_timeout(self.request_timeout);

        let response = client.invalidate_feed_cache(tonic_request).await;
        match response {
            Ok(resp) => {
                self.health_checker
                    .set_feed_service_health(HealthStatus::Healthy)
                    .await;
                Ok(resp.into_inner())
            }
            Err(err) => {
                self.health_checker
                    .set_feed_service_health(HealthStatus::Unavailable)
                    .await;
                Err(err)
            }
        }
    }
}
