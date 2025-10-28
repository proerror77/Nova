// gRPC service implementation for content service
use tonic::{Request, Response, Status};

// Import generated proto code
pub mod nova {
    pub mod content {
        tonic::include_proto!("nova.content");
    }
}

use nova::content::content_service_server::ContentService;
use nova::content::*;

/// ContentService gRPC implementation
pub struct ContentServiceImpl;

#[tonic::async_trait]
impl ContentService for ContentServiceImpl {
    /// Get a post by ID
    async fn get_post(
        &self,
        request: Request<GetPostRequest>,
    ) -> Result<Response<GetPostResponse>, Status> {
        let req = request.into_inner();

        tracing::info!("gRPC: Getting post with ID: {}", req.post_id);

        // TODO: Implement actual database lookup
        // For now, return an error
        Err(Status::unimplemented("get_post not yet implemented"))
    }

    /// Create a new post
    async fn create_post(
        &self,
        request: Request<CreatePostRequest>,
    ) -> Result<Response<CreatePostResponse>, Status> {
        let req = request.into_inner();

        tracing::info!("gRPC: Creating post from user: {}", req.creator_id);

        // TODO: Implement actual post creation
        Err(Status::unimplemented("create_post not yet implemented"))
    }

    /// Get comments for a post
    async fn get_comments(
        &self,
        request: Request<GetCommentsRequest>,
    ) -> Result<Response<GetCommentsResponse>, Status> {
        let req = request.into_inner();

        tracing::info!(
            "gRPC: Getting comments for post: {} (limit: {}, offset: {})",
            req.post_id,
            req.limit,
            req.offset
        );

        // TODO: Implement actual comment retrieval
        Err(Status::unimplemented("get_comments not yet implemented"))
    }

    /// Like a post
    async fn like_post(
        &self,
        request: Request<LikePostRequest>,
    ) -> Result<Response<LikePostResponse>, Status> {
        let req = request.into_inner();

        tracing::info!(
            "gRPC: User {} liking post {}",
            req.user_id,
            req.post_id
        );

        // TODO: Implement actual like functionality
        Err(Status::unimplemented("like_post not yet implemented"))
    }

    /// Get user bookmarks
    async fn get_user_bookmarks(
        &self,
        request: Request<GetUserBookmarksRequest>,
    ) -> Result<Response<GetUserBookmarksResponse>, Status> {
        let req = request.into_inner();

        tracing::info!(
            "gRPC: Getting bookmarks for user: {} (limit: {}, offset: {})",
            req.user_id,
            req.limit,
            req.offset
        );

        // TODO: Implement actual bookmark retrieval
        Err(Status::unimplemented(
            "get_user_bookmarks not yet implemented",
        ))
    }
}

/// Create a gRPC server for content service
pub async fn start_grpc_server(addr: std::net::SocketAddr) -> Result<(), Box<dyn std::error::Error>> {
    use nova::content::content_service_server::ContentServiceServer;
    use tonic::transport::Server;

    tracing::info!("Starting gRPC server at {}", addr);

    let service = ContentServiceImpl;
    Server::builder()
        .add_service(ContentServiceServer::new(service))
        .serve(addr)
        .await?;

    Ok(())
}
