// gRPC server for EventsService (stub implementation)
use tonic::{Request, Response, Status};

pub mod nova {
    pub mod common {
        pub mod v1 {
            tonic::include_proto!("nova.common.v1");
        }
        pub use v1::*;
    }
    pub mod events_service {
        pub mod v1 {
            tonic::include_proto!("nova.events_service.v1");
        }
        pub use v1::*;
    }
}

use nova::events_service::v1::events_service_server::EventsService;
use nova::events_service::v1::*;

#[derive(Clone, Default)]
pub struct EventsServiceImpl;

#[tonic::async_trait]
impl EventsService for EventsServiceImpl {
    async fn publish_event(
        &self,
        _request: Request<PublishEventRequest>,
    ) -> Result<Response<PublishEventResponse>, Status> {
        Err(Status::unimplemented("publish_event not implemented"))
    }

    async fn publish_events(
        &self,
        _request: Request<PublishEventsRequest>,
    ) -> Result<Response<PublishEventsResponse>, Status> {
        Err(Status::unimplemented("publish_events not implemented"))
    }

    async fn get_event(
        &self,
        _request: Request<GetEventRequest>,
    ) -> Result<Response<GetEventResponse>, Status> {
        Err(Status::unimplemented("get_event not implemented"))
    }

    async fn get_events_by_aggregate(
        &self,
        _request: Request<GetEventsByAggregateRequest>,
    ) -> Result<Response<GetEventsByAggregateResponse>, Status> {
        Err(Status::unimplemented("get_events_by_aggregate not implemented"))
    }

    async fn get_events_by_type(
        &self,
        _request: Request<GetEventsByTypeRequest>,
    ) -> Result<Response<GetEventsByTypeResponse>, Status> {
        Err(Status::unimplemented("get_events_by_type not implemented"))
    }

    async fn subscribe_to_events(
        &self,
        _request: Request<SubscribeToEventsRequest>,
    ) -> Result<Response<SubscribeToEventsResponse>, Status> {
        Err(Status::unimplemented("subscribe_to_events not implemented"))
    }

    async fn unsubscribe_from_events(
        &self,
        _request: Request<UnsubscribeFromEventsRequest>,
    ) -> Result<Response<UnsubscribeFromEventsResponse>, Status> {
        Err(Status::unimplemented("unsubscribe_from_events not implemented"))
    }

    async fn get_subscriptions(
        &self,
        _request: Request<GetSubscriptionsRequest>,
    ) -> Result<Response<GetSubscriptionsResponse>, Status> {
        Err(Status::unimplemented("get_subscriptions not implemented"))
    }

    async fn register_event_schema(
        &self,
        _request: Request<RegisterEventSchemaRequest>,
    ) -> Result<Response<RegisterEventSchemaResponse>, Status> {
        Err(Status::unimplemented("register_event_schema not implemented"))
    }

    async fn get_event_schema(
        &self,
        _request: Request<GetEventSchemaRequest>,
    ) -> Result<Response<GetEventSchemaResponse>, Status> {
        Err(Status::unimplemented("get_event_schema not implemented"))
    }

    async fn get_outbox_events(
        &self,
        _request: Request<GetOutboxEventsRequest>,
    ) -> Result<Response<GetOutboxEventsResponse>, Status> {
        Err(Status::unimplemented("get_outbox_events not implemented"))
    }

    async fn mark_outbox_event_published(
        &self,
        _request: Request<MarkOutboxEventPublishedRequest>,
    ) -> Result<Response<MarkOutboxEventPublishedResponse>, Status> {
        Err(Status::unimplemented(
            "mark_outbox_event_published not implemented",
        ))
    }

    async fn retry_outbox_event(
        &self,
        _request: Request<RetryOutboxEventRequest>,
    ) -> Result<Response<RetryOutboxEventResponse>, Status> {
        Err(Status::unimplemented("retry_outbox_event not implemented"))
    }

    async fn get_event_stats(
        &self,
        _request: Request<GetEventStatsRequest>,
    ) -> Result<Response<GetEventStatsResponse>, Status> {
        Err(Status::unimplemented("get_event_stats not implemented"))
    }
}

