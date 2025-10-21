//! REST API Handlers for E2E Encrypted Messaging
//!
//! Phase 5 Feature 2: Message sending, key exchange, and public key management

use crate::error::AppError;
use crate::middleware::jwt_auth::UserId;
use crate::services::messaging::MessageService;
use actix_web::{web, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

// ============================================
// Request/Response DTOs
// ============================================

#[derive(Debug, Deserialize)]
pub struct RegisterPublicKeyRequest {
    pub public_key: String,
}

#[derive(Debug, Serialize)]
pub struct RegisterPublicKeyResponse {
    pub user_id: Uuid,
    pub public_key: String,
    pub registered_at: String,
    pub rotation_interval_days: u32,
    pub next_rotation_at: String,
}

#[derive(Debug, Deserialize)]
pub struct InitiateKeyExchangeRequest {
    pub recipient_id: Uuid,
    pub initiator_public_key: String,
}

#[derive(Debug, Serialize)]
pub struct InitiateKeyExchangeResponse {
    pub id: Uuid,
    pub initiator_id: Uuid,
    pub recipient_id: Uuid,
    pub initiator_public_key: String,
    pub status: String,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
pub struct CompleteKeyExchangeRequest {
    pub recipient_public_key: String,
}

#[derive(Debug, Serialize)]
pub struct CompleteKeyExchangeResponse {
    pub success: bool,
    pub message: String,
}

#[derive(Debug, Deserialize)]
pub struct SendMessageRequest {
    pub recipient_id: Uuid,
    pub encrypted_content: String,
    pub nonce: String,
}

#[derive(Debug, Serialize)]
pub struct SendMessageResponse {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub recipient_id: Uuid,
    pub encrypted_content: String,
    pub nonce: String,
    pub sender_public_key: String,
    pub delivered: bool,
    pub read: bool,
    pub created_at: String,
}

#[derive(Debug, Serialize)]
pub struct GetPublicKeyResponse {
    pub user_id: Uuid,
    pub public_key: String,
    pub registered_at: String,
}

#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub recipient_id: Uuid,
    pub encrypted_content: String,
    pub nonce: String,
    pub sender_public_key: String,
    pub delivered: bool,
    pub read: bool,
    pub created_at: String,
}

// ============================================
// API Handlers
// ============================================

/// POST /api/v1/users/me/public-key
/// Register or update user's public key
pub async fn register_public_key(
    user: UserId,
    pool: web::Data<PgPool>,
    req: web::Json<RegisterPublicKeyRequest>,
) -> Result<HttpResponse, AppError> {
    let service = MessageService::new(pool.get_ref().clone());

    let public_key_record = service
        .register_public_key(user.0, &req.public_key)
        .await?;

    let response = RegisterPublicKeyResponse {
        user_id: public_key_record.user_id,
        public_key: public_key_record.public_key,
        registered_at: public_key_record.registered_at.to_rfc3339(),
        rotation_interval_days: public_key_record.rotation_interval_days,
        next_rotation_at: public_key_record.next_rotation_at.to_rfc3339(),
    };

    Ok(HttpResponse::Ok().json(response))
}

/// POST /api/v1/key-exchange/initiate
/// Initiate key exchange with another user
pub async fn initiate_key_exchange(
    user: UserId,
    pool: web::Data<PgPool>,
    req: web::Json<InitiateKeyExchangeRequest>,
) -> Result<HttpResponse, AppError> {
    let service = MessageService::new(pool.get_ref().clone());

    let exchange = service
        .initiate_key_exchange(user.0, req.recipient_id, &req.initiator_public_key)
        .await?;

    let response = InitiateKeyExchangeResponse {
        id: exchange.id,
        initiator_id: exchange.initiator_id,
        recipient_id: exchange.recipient_id,
        initiator_public_key: exchange.initiator_public_key,
        status: format!("{:?}", exchange.status).to_lowercase(),
        created_at: exchange.created_at.to_rfc3339(),
    };

    Ok(HttpResponse::Created().json(response))
}

/// POST /api/v1/key-exchange/{id}/complete
/// Complete a key exchange
pub async fn complete_key_exchange(
    pool: web::Data<PgPool>,
    exchange_id: web::Path<Uuid>,
    req: web::Json<CompleteKeyExchangeRequest>,
) -> Result<HttpResponse, AppError> {
    let service = MessageService::new(pool.get_ref().clone());

    service
        .complete_key_exchange(*exchange_id, &req.recipient_public_key)
        .await?;

    let response = CompleteKeyExchangeResponse {
        success: true,
        message: "Key exchange completed successfully".to_string(),
    };

    Ok(HttpResponse::Ok().json(response))
}

/// POST /api/v1/messages/send
/// Send an encrypted message
pub async fn send_message(
    user: UserId,
    pool: web::Data<PgPool>,
    req: web::Json<SendMessageRequest>,
) -> Result<HttpResponse, AppError> {
    let service = MessageService::new(pool.get_ref().clone());

    let message = service
        .send_encrypted_message(
            user.0,
            req.recipient_id,
            &req.encrypted_content,
            &req.nonce,
        )
        .await?;

    let response = SendMessageResponse {
        id: message.id,
        sender_id: message.sender_id,
        recipient_id: message.recipient_id,
        encrypted_content: message.encrypted_content,
        nonce: message.nonce,
        sender_public_key: message.sender_public_key,
        delivered: message.delivered,
        read: message.read,
        created_at: message.created_at.to_rfc3339(),
    };

    Ok(HttpResponse::Created().json(response))
}

/// GET /api/v1/messages/{id}
/// Get a specific message (must be sender or recipient)
pub async fn get_message(
    user: UserId,
    pool: web::Data<PgPool>,
    message_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let service = MessageService::new(pool.get_ref().clone());

    let message = service.get_message(*message_id, user.0).await?;

    let response = MessageResponse {
        id: message.id,
        sender_id: message.sender_id,
        recipient_id: message.recipient_id,
        encrypted_content: message.encrypted_content,
        nonce: message.nonce,
        sender_public_key: message.sender_public_key,
        delivered: message.delivered,
        read: message.read,
        created_at: message.created_at.to_rfc3339(),
    };

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v1/users/{user_id}/public-key
/// Get a user's public key
pub async fn get_public_key(
    pool: web::Data<PgPool>,
    user_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let service = MessageService::new(pool.get_ref().clone());

    let public_key = service
        .get_public_key(*user_id)
        .await?
        .ok_or_else(|| AppError::NotFound("Public key not found".to_string()))?;

    let response = GetPublicKeyResponse {
        user_id: public_key.user_id,
        public_key: public_key.public_key,
        registered_at: public_key.registered_at.to_rfc3339(),
    };

    Ok(HttpResponse::Ok().json(response))
}

/// POST /api/v1/messages/{id}/delivered
/// Mark message as delivered
pub async fn mark_delivered(
    pool: web::Data<PgPool>,
    message_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let service = MessageService::new(pool.get_ref().clone());
    service.mark_message_delivered(*message_id).await?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "success": true,
        "message": "Message marked as delivered"
    })))
}

/// POST /api/v1/messages/{id}/read
/// Mark message as read
pub async fn mark_read(
    pool: web::Data<PgPool>,
    message_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let service = MessageService::new(pool.get_ref().clone());
    service.mark_message_read(*message_id).await?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "success": true,
        "message": "Message marked as read"
    })))
}

// ============================================
// Route Configuration
// ============================================

pub fn configure_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1")
            .route("/users/me/public-key", web::post().to(register_public_key))
            .route("/key-exchange/initiate", web::post().to(initiate_key_exchange))
            .route("/key-exchange/{id}/complete", web::post().to(complete_key_exchange))
            .route("/messages/send", web::post().to(send_message))
            .route("/messages/{id}", web::get().to(get_message))
            .route("/messages/{id}/delivered", web::post().to(mark_delivered))
            .route("/messages/{id}/read", web::post().to(mark_read))
            .route("/users/{user_id}/public-key", web::get().to(get_public_key)),
    );
}
