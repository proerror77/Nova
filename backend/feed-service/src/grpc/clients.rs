/// gRPC clients for calling other services
use tonic::transport::{Channel, Endpoint};
use tonic::{Request, Status};

use super::nova::content::{
    content_service_client::ContentServiceClient as GrpcContentClient, GetFeedRequest,
    GetFeedResponse, InvalidateFeedEventRequest, InvalidateFeedEventResponse,
};

/// Content Service gRPC Client
#[derive(Clone)]
pub struct ContentServiceClient {
    client: GrpcContentClient<Channel>,
}

impl ContentServiceClient {
    /// Create new ContentServiceClient
    pub async fn new(addr: String) -> Result<Self, Box<dyn std::error::Error>> {
        let endpoint = Endpoint::from_shared(addr)?;
        let channel = endpoint.connect().await?;
        let client = GrpcContentClient::new(channel);

        Ok(Self { client })
    }

    /// Get feed for user
    pub async fn get_feed(
        &self,
        request: GetFeedRequest,
    ) -> Result<GetFeedResponse, std::io::Error> {
        let mut client = self.client.clone();
        client.get_feed(request).await
    }

    /// Invalidate feed event
    pub async fn invalidate_feed_event(
        &self,
        request: InvalidateFeedEventRequest,
    ) -> Result<InvalidateFeedEventResponse, std::io::Error> {
        let mut client = self.client.clone();
        client.invalidate_feed_event(request).await
    }
}

/// User Service gRPC Client (for future use)
#[derive(Clone)]
pub struct UserServiceClient {
    // TODO: implement when proto is ready
}

impl UserServiceClient {
    pub async fn new(_addr: String) -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {})
    }
}
