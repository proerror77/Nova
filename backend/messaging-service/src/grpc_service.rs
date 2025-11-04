use crate::error::AppError;
use crate::messaging::*;
use crate::state::AppState;
use tonic::{Request, Response, Status};
use crypto_core::grpc_correlation::extract_from_request;
use crypto_core::correlation::CorrelationContext;

/// gRPC service implementation for Nova Messaging Service
pub struct MessagingGrpcService {
    #[allow(dead_code)]
    state: AppState,
}

impl MessagingGrpcService {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }
}

/// Helper to extract correlation-id from incoming tonic Request and attach to context
fn attach_correlation_from<T>(req: &Request<T>) {
    let ctx = CorrelationContext::generate();
    extract_from_request(req, &ctx);
    // Optionally bind to tracing span here if using per-request spans
}

// Convert AppError to tonic::Status for gRPC responses
#[allow(dead_code)]
fn app_error_to_status(error: AppError) -> Status {
    match error {
        AppError::NotFound => Status::not_found("Resource not found"),
        AppError::BadRequest(msg) => Status::invalid_argument(msg),
        AppError::Unauthorized => Status::unauthenticated("Unauthorized"),
        AppError::Forbidden => Status::permission_denied("Forbidden"),
        AppError::VersionConflict { .. } => Status::already_exists("Version conflict"),
        AppError::AlreadyRecalled => Status::failed_precondition("Message already recalled"),
        AppError::RecallWindowExpired { .. } => {
            Status::failed_precondition("Recall window expired")
        }
        AppError::EditWindowExpired { .. } => Status::failed_precondition("Edit window expired"),
        AppError::Internal => Status::internal("Internal server error"),
        _ => Status::internal("Unknown error"),
    }
}

/// gRPC service stub - contains skeleton implementations
/// Full implementation requires integrating with existing services
#[tonic::async_trait]
pub trait MessagingRpc {
    async fn send_message(
        &self,
        request: Request<SendMessageRequest>,
    ) -> Result<Response<SendMessageResponse>, Status>;

    async fn get_message(
        &self,
        request: Request<GetMessageRequest>,
    ) -> Result<Response<GetMessageResponse>, Status>;

    async fn get_message_history(
        &self,
        request: Request<GetMessageHistoryRequest>,
    ) -> Result<Response<GetMessageHistoryResponse>, Status>;

    async fn create_conversation(
        &self,
        request: Request<CreateConversationRequest>,
    ) -> Result<Response<CreateConversationResponse>, Status>;

    async fn get_conversation(
        &self,
        request: Request<GetConversationRequest>,
    ) -> Result<Response<GetConversationResponse>, Status>;

    async fn get_unread_count(
        &self,
        request: Request<GetUnreadCountRequest>,
    ) -> Result<Response<GetUnreadCountResponse>, Status>;

    async fn add_reaction(
        &self,
        request: Request<AddReactionRequest>,
    ) -> Result<Response<AddReactionResponse>, Status>;

    async fn store_device_public_key(
        &self,
        request: Request<StoreDevicePublicKeyRequest>,
    ) -> Result<Response<StoreDevicePublicKeyResponse>, Status>;

    async fn get_peer_public_key(
        &self,
        request: Request<GetPeerPublicKeyRequest>,
    ) -> Result<Response<GetPeerPublicKeyResponse>, Status>;

    async fn register_device_token(
        &self,
        request: Request<RegisterDeviceTokenRequest>,
    ) -> Result<Response<RegisterDeviceTokenResponse>, Status>;
}

/// Example implementations (stubs for demonstration)
impl MessagingGrpcService {
    /// Send a message via gRPC
    pub async fn grpc_send_message(
        &self,
        req: SendMessageRequest,
    ) -> Result<SendMessageResponse, AppError> {
        // Correlation: in real server, call attach_correlation_from(&tonic::Request)
        // Integration point: call message_service.send_message()
        // This would convert between gRPC types and internal models

        let message_id = uuid::Uuid::new_v4().to_string();

        // Placeholder response
        Ok(SendMessageResponse {
            message: Some(Message {
                id: message_id,
                conversation_id: req.conversation_id,
                sender_id: req.sender_id,
                content: req.content,
                content_encrypted: req.content_encrypted,
                content_nonce: req.content_nonce,
                encryption_version: req.encryption_version,
                sequence_number: 0,
                idempotency_key: req.idempotency_key,
                created_at: chrono::Utc::now().timestamp(),
                updated_at: chrono::Utc::now().timestamp(),
                deleted_at: 0,
                reaction_count: 0,
            }),
            error: String::new(),
        })
    }

    /// Create a conversation via gRPC
    pub async fn grpc_create_conversation(
        &self,
        req: CreateConversationRequest,
    ) -> Result<CreateConversationResponse, AppError> {
        // Correlation: in real server, call attach_correlation_from(&tonic::Request)
        // Integration point: call conversation_service.create_conversation()

        // Placeholder response
        Ok(CreateConversationResponse {
            conversation: Some(Conversation {
                id: uuid::Uuid::new_v4().to_string(),
                kind: req.kind,
                name: req.name,
                description: req.description,
                avatar_url: req.avatar_url,
                member_count: req.member_ids.len() as i32 + 1,
                privacy_mode: req.privacy_mode,
                last_message_id: String::new(),
                created_at: chrono::Utc::now().timestamp(),
                updated_at: chrono::Utc::now().timestamp(),
            }),
            error: String::new(),
        })
    }

    /// Get unread message count via gRPC
    pub async fn grpc_get_unread_count(
        &self,
        _req: GetUnreadCountRequest,
    ) -> Result<GetUnreadCountResponse, AppError> {
        // Integration point: query unread counts from database

        // Placeholder response
        Ok(GetUnreadCountResponse {
            total: 0,
            by_conversation: std::collections::HashMap::new(),
            error: String::new(),
        })
    }

    /// Store device public key for ECDH via gRPC
    pub async fn grpc_store_device_public_key(
        &self,
        _req: StoreDevicePublicKeyRequest,
    ) -> Result<StoreDevicePublicKeyResponse, AppError> {
        // Integration point: call key_exchange_service.store_device_key()

        Ok(StoreDevicePublicKeyResponse {
            success: true,
            error: String::new(),
        })
    }

    /// Register device token for push notifications via gRPC
    pub async fn grpc_register_device_token(
        &self,
        _req: RegisterDeviceTokenRequest,
    ) -> Result<RegisterDeviceTokenResponse, AppError> {
        // Integration point: store device token in database

        Ok(RegisterDeviceTokenResponse {
            success: true,
            error: String::new(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_conversion() {
        let app_err = AppError::NotFound;
        let status = app_error_to_status(app_err);
        assert_eq!(status.code(), tonic::Code::NotFound);
    }

    #[test]
    fn test_bad_request_conversion() {
        let app_err = AppError::BadRequest("Invalid input".to_string());
        let status = app_error_to_status(app_err);
        assert_eq!(status.code(), tonic::Code::InvalidArgument);
    }
}
