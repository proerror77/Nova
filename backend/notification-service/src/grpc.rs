// gRPC server for NotificationService (stub implementation)
use tonic::{Request, Response, Status};

pub mod nova {
    pub mod common {
        pub mod v1 {
            tonic::include_proto!("nova.common.v1");
        }
        pub use v1::*;
    }
    pub mod notification_service {
        pub mod v1 {
            tonic::include_proto!("nova.notification_service.v1");
        }
        pub use v1::*;
    }
}

use nova::notification_service::v1::notification_service_server::NotificationService;
use nova::notification_service::v1::*;

#[derive(Clone, Default)]
pub struct NotificationServiceImpl;

#[tonic::async_trait]
impl NotificationService for NotificationServiceImpl {
    async fn get_notifications(
        &self,
        _request: Request<GetNotificationsRequest>,
    ) -> Result<Response<GetNotificationsResponse>, Status> {
        Err(Status::unimplemented("get_notifications is not implemented yet"))
    }

    async fn get_notification(
        &self,
        _request: Request<GetNotificationRequest>,
    ) -> Result<Response<GetNotificationResponse>, Status> {
        Err(Status::unimplemented("get_notification is not implemented yet"))
    }

    async fn create_notification(
        &self,
        _request: Request<CreateNotificationRequest>,
    ) -> Result<Response<CreateNotificationResponse>, Status> {
        Err(Status::unimplemented("create_notification is not implemented yet"))
    }

    async fn mark_notification_as_read(
        &self,
        _request: Request<MarkNotificationAsReadRequest>,
    ) -> Result<Response<MarkNotificationAsReadResponse>, Status> {
        Err(Status::unimplemented("mark_notification_as_read is not implemented yet"))
    }

    async fn mark_all_notifications_as_read(
        &self,
        _request: Request<MarkAllNotificationsAsReadRequest>,
    ) -> Result<Response<MarkAllNotificationsAsReadResponse>, Status> {
        Err(Status::unimplemented(
            "mark_all_notifications_as_read is not implemented yet",
        ))
    }

    async fn delete_notification(
        &self,
        _request: Request<DeleteNotificationRequest>,
    ) -> Result<Response<DeleteNotificationResponse>, Status> {
        Err(Status::unimplemented("delete_notification is not implemented yet"))
    }

    async fn get_notification_preferences(
        &self,
        _request: Request<GetNotificationPreferencesRequest>,
    ) -> Result<Response<GetNotificationPreferencesResponse>, Status> {
        Err(Status::unimplemented(
            "get_notification_preferences is not implemented yet",
        ))
    }

    async fn update_notification_preferences(
        &self,
        _request: Request<UpdateNotificationPreferencesRequest>,
    ) -> Result<Response<UpdateNotificationPreferencesResponse>, Status> {
        Err(Status::unimplemented(
            "update_notification_preferences is not implemented yet",
        ))
    }

    async fn register_push_token(
        &self,
        _request: Request<RegisterPushTokenRequest>,
    ) -> Result<Response<RegisterPushTokenResponse>, Status> {
        Err(Status::unimplemented("register_push_token is not implemented yet"))
    }

    async fn unregister_push_token(
        &self,
        _request: Request<UnregisterPushTokenRequest>,
    ) -> Result<Response<UnregisterPushTokenResponse>, Status> {
        Err(Status::unimplemented(
            "unregister_push_token is not implemented yet",
        ))
    }

    async fn get_unread_count(
        &self,
        _request: Request<GetUnreadCountRequest>,
    ) -> Result<Response<GetUnreadCountResponse>, Status> {
        Err(Status::unimplemented("get_unread_count is not implemented yet"))
    }

    async fn batch_create_notifications(
        &self,
        _request: Request<BatchCreateNotificationsRequest>,
    ) -> Result<Response<BatchCreateNotificationsResponse>, Status> {
        Err(Status::unimplemented(
            "batch_create_notifications is not implemented yet",
        ))
    }

    async fn get_notification_stats(
        &self,
        _request: Request<GetNotificationStatsRequest>,
    ) -> Result<Response<GetNotificationStatsResponse>, Status> {
        Err(Status::unimplemented("get_notification_stats is not implemented yet"))
    }
}

