use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use actix_web::{body, test, web};
use tonic::{transport::Server, Request, Response, Status};
use tokio::sync::Notify;
use tokio_stream::wrappers::TcpListenerStream;
use user_service::grpc::nova::content::{
    content_service_server::{ContentService, ContentServiceServer},
    BatchInvalidateFeedRequest, CreatePostRequest, CreatePostResponse, GetCommentsRequest,
    GetCommentsResponse, GetFeedRequest, GetFeedResponse, GetPostRequest, GetPostResponse,
    GetUserBookmarksRequest, GetUserBookmarksResponse, InvalidateFeedEventRequest,
    InvalidateFeedResponse, LikePostRequest, LikePostResponse, WarmFeedRequest,
};
use user_service::grpc::{ContentServiceClient, GrpcClientConfig, HealthChecker};
use user_service::handlers::feed::{get_feed, FeedHandlerState, FeedQueryParams};
use user_service::middleware::jwt_auth::UserId;
use user_service::models::FeedResponse;
use uuid::Uuid;

#[derive(Clone)]
struct MockContentService {
    expected_user: String,
    response: GetFeedResponse,
    notify: Arc<Notify>,
}

impl MockContentService {
    fn new(expected_user: Uuid, posts: Vec<Uuid>) -> Self {
        Self {
            expected_user: expected_user.to_string(),
            response: GetFeedResponse {
                post_ids: posts.into_iter().map(|id| id.to_string()).collect(),
                cursor: "Mg==".into(), // base64(2)
                has_more: true,
                total_count: 40,
                error: String::new(),
            },
            notify: Arc::new(Notify::new()),
        }
    }
}

#[tonic::async_trait]
impl ContentService for MockContentService {
    async fn get_post(
        &self,
        _request: Request<GetPostRequest>,
    ) -> Result<Response<GetPostResponse>, Status> {
        Err(Status::unimplemented("get_post"))
    }

    async fn create_post(
        &self,
        _request: Request<CreatePostRequest>,
    ) -> Result<Response<CreatePostResponse>, Status> {
        Err(Status::unimplemented("create_post"))
    }

    async fn get_comments(
        &self,
        _request: Request<GetCommentsRequest>,
    ) -> Result<Response<GetCommentsResponse>, Status> {
        Err(Status::unimplemented("get_comments"))
    }

    async fn like_post(
        &self,
        _request: Request<LikePostRequest>,
    ) -> Result<Response<LikePostResponse>, Status> {
        Err(Status::unimplemented("like_post"))
    }

    async fn get_user_bookmarks(
        &self,
        _request: Request<GetUserBookmarksRequest>,
    ) -> Result<Response<GetUserBookmarksResponse>, Status> {
        Err(Status::unimplemented("get_user_bookmarks"))
    }

    async fn get_feed(
        &self,
        request: Request<GetFeedRequest>,
    ) -> Result<Response<GetFeedResponse>, Status> {
        let req = request.into_inner();
        if req.user_id != self.expected_user {
            return Err(Status::invalid_argument("unexpected user id"));
        }
        self.notify.notify_one();
        Ok(Response::new(self.response.clone()))
    }

    async fn invalidate_feed_event(
        &self,
        _request: Request<InvalidateFeedEventRequest>,
    ) -> Result<Response<InvalidateFeedResponse>, Status> {
        Err(Status::unimplemented("invalidate_feed_event"))
    }

    async fn batch_invalidate_feed(
        &self,
        _request: Request<BatchInvalidateFeedRequest>,
    ) -> Result<Response<InvalidateFeedResponse>, Status> {
        Err(Status::unimplemented("batch_invalidate_feed"))
    }

    async fn warm_feed(
        &self,
        _request: Request<WarmFeedRequest>,
    ) -> Result<Response<InvalidateFeedResponse>, Status> {
        Err(Status::unimplemented("warm_feed"))
    }
}

#[actix_rt::test]
async fn feed_handler_proxies_to_content_service() {
    let user_id = Uuid::new_v4();
    let post_ids = vec![Uuid::new_v4(), Uuid::new_v4()];
    let mock_service = MockContentService::new(user_id, post_ids.clone());
    let notify = mock_service.notify.clone();

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind gRPC port");
    let addr: SocketAddr = listener.local_addr().unwrap();
    let incoming = TcpListenerStream::new(listener);
    let grpc_service = ContentServiceServer::new(mock_service.clone());

    tokio::spawn(async move {
        Server::builder()
            .add_service(grpc_service)
            .serve_with_incoming(incoming)
            .await
            .expect("start mock content-service");
    });

    let grpc_cfg = GrpcClientConfig {
        content_service_url: format!("http://{}", addr),
        media_service_url: "http://127.0.0.1:50052".into(),
        connection_timeout_secs: 5,
        request_timeout_secs: 5,
        max_concurrent_streams: 16,
        enable_health_check: false,
        health_check_interval_secs: 30,
        pool_size: 1,
    };

    let health_checker = Arc::new(HealthChecker::new());
    let content_client = Arc::new(
        ContentServiceClient::new(&grpc_cfg, health_checker)
            .await
            .expect("create content client"),
    );
    let state = FeedHandlerState {
        content_client,
    };

    let query = web::Query(FeedQueryParams {
        algo: "ch".into(),
        limit: 20,
        cursor: None,
    });
    let mut req = test::TestRequest::default()
        .to_http_request();
    req.extensions_mut().insert(UserId(user_id));

    let resp = get_feed(query, req, web::Data::new(state))
        .await
        .expect("handler response")
        .map_into_boxed_body();

    let bytes = body::to_bytes(resp.into_body())
        .await
        .expect("read body");
    let feed: FeedResponse = serde_json::from_slice(&bytes).expect("deserialize feed");
    assert_eq!(feed.posts, post_ids);
    assert_eq!(feed.cursor.unwrap(), "Mg==");
    assert!(feed.has_more);

    let notified = tokio::time::timeout(Duration::from_secs(1), notify.notified())
        .await
        .is_ok();
    assert!(notified, "gRPC service was not contacted");
}

#[derive(Clone, Default)]
struct FailingContentService;

#[tonic::async_trait]
impl ContentService for FailingContentService {
    async fn get_post(
        &self,
        _request: Request<GetPostRequest>,
    ) -> Result<Response<GetPostResponse>, Status> {
        Err(Status::unimplemented("get_post"))
    }

    async fn create_post(
        &self,
        _request: Request<CreatePostRequest>,
    ) -> Result<Response<CreatePostResponse>, Status> {
        Err(Status::unimplemented("create_post"))
    }

    async fn get_comments(
        &self,
        _request: Request<GetCommentsRequest>,
    ) -> Result<Response<GetCommentsResponse>, Status> {
        Err(Status::unimplemented("get_comments"))
    }

    async fn like_post(
        &self,
        _request: Request<LikePostRequest>,
    ) -> Result<Response<LikePostResponse>, Status> {
        Err(Status::unimplemented("like_post"))
    }

    async fn get_user_bookmarks(
        &self,
        _request: Request<GetUserBookmarksRequest>,
    ) -> Result<Response<GetUserBookmarksResponse>, Status> {
        Err(Status::unimplemented("get_user_bookmarks"))
    }

    async fn get_feed(
        &self,
        _request: Request<GetFeedRequest>,
    ) -> Result<Response<GetFeedResponse>, Status> {
        Err(Status::internal("mock failure"))
    }

    async fn invalidate_feed_event(
        &self,
        _request: Request<InvalidateFeedEventRequest>,
    ) -> Result<Response<InvalidateFeedResponse>, Status> {
        Err(Status::unimplemented("invalidate_feed_event"))
    }

    async fn batch_invalidate_feed(
        &self,
        _request: Request<BatchInvalidateFeedRequest>,
    ) -> Result<Response<InvalidateFeedResponse>, Status> {
        Err(Status::unimplemented("batch_invalidate_feed"))
    }

    async fn warm_feed(
        &self,
        _request: Request<WarmFeedRequest>,
    ) -> Result<Response<InvalidateFeedResponse>, Status> {
        Err(Status::unimplemented("warm_feed"))
    }
}

#[actix_rt::test]
async fn feed_handler_returns_empty_on_grpc_error() {
    let user_id = Uuid::new_v4();

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind gRPC port");
    let addr: SocketAddr = listener.local_addr().unwrap();
    let incoming = TcpListenerStream::new(listener);

    tokio::spawn(async move {
        Server::builder()
            .add_service(ContentServiceServer::new(FailingContentService::default()))
            .serve_with_incoming(incoming)
            .await
            .expect("start failing mock");
    });

    let grpc_cfg = GrpcClientConfig {
        content_service_url: format!("http://{}", addr),
        media_service_url: "http://127.0.0.1:50052".into(),
        connection_timeout_secs: 1,
        request_timeout_secs: 1,
        max_concurrent_streams: 4,
        enable_health_check: false,
        health_check_interval_secs: 30,
        pool_size: 1,
    };

    let health_checker = Arc::new(HealthChecker::new());
    let content_client = Arc::new(
        ContentServiceClient::new(&grpc_cfg, health_checker)
            .await
            .expect("create content client"),
    );
    let state = FeedHandlerState { content_client };

    let query = web::Query(FeedQueryParams {
        algo: "ch".into(),
        limit: 20,
        cursor: None,
    });
    let mut req = test::TestRequest::default().to_http_request();
    req.extensions_mut().insert(UserId(user_id));

    let result = get_feed(query, req, web::Data::new(state)).await;
    assert!(result.is_err(), "expected feed handler to error on gRPC failure");
}
