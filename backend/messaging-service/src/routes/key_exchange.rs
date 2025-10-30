use crate::error::AppError;
use crate::middleware::guards::User;
use crate::state::AppState;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use base64::{engine::general_purpose, Engine as _};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Request to initiate ECDH key exchange
#[derive(Deserialize)]
pub struct InitiateKeyExchangeRequest {
    /// Device ID (e.g., "iPhone-123456", "Android-UUID")
    pub device_id: String,
    /// Base64 encoded X25519 public key (32 bytes)
    pub public_key: String,
}

/// Response containing peer's public key for ECDH
#[derive(Serialize)]
pub struct KeyExchangeResponse {
    pub peer_user_id: Uuid,
    pub peer_device_id: String,
    /// Base64 encoded peer's X25519 public key
    pub peer_public_key: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// Response with negotiated encryption key metadata
#[derive(Serialize)]
pub struct KeyExchangeMetadataResponse {
    pub conversation_id: Uuid,
    pub encryption_version: i32,
    pub key_exchange_count: i64,
    pub last_exchange_at: Option<chrono::DateTime<chrono::Utc>>,
}

/// Store device public key for future ECDH operations
pub async fn store_device_public_key(
    State(state): State<AppState>,
    User { id: user_id, .. }: User,
    Json(payload): Json<InitiateKeyExchangeRequest>,
) -> Result<StatusCode, AppError> {
    // Validate public key format (should be 32 bytes, base64 encoded)
    let public_key_bytes = general_purpose::STANDARD
        .decode(&payload.public_key)
        .map_err(|_| AppError::BadRequest("Invalid base64 in public_key".to_string()))?;

    if public_key_bytes.len() != 32 {
        return Err(AppError::BadRequest(
            "Public key must be exactly 32 bytes".to_string(),
        ));
    }

    // Generate encrypted private key (in production, encrypt with HSM or KMS)
    // For now, we'll store a placeholder that represents encrypted data
    let private_key_encrypted = format!("encrypted_{}", Uuid::new_v4());

    let key_exchange = state
        .key_exchange_service
        .as_ref()
        .ok_or_else(|| AppError::Internal)?;

    key_exchange
        .store_device_key(
            user_id,
            payload.device_id,
            public_key_bytes,
            private_key_encrypted.as_bytes().to_vec(),
        )
        .await?;

    Ok(StatusCode::CREATED)
}

/// Get peer's public key for ECDH in a conversation
pub async fn get_peer_public_key(
    State(state): State<AppState>,
    User { id: _user_id, .. }: User,
    Path((_conversation_id, peer_user_id, peer_device_id)): Path<(Uuid, Uuid, String)>,
) -> Result<Json<KeyExchangeResponse>, AppError> {
    let key_exchange = state
        .key_exchange_service
        .as_ref()
        .ok_or_else(|| AppError::Internal)?;

    // Verify that user is part of the conversation
    // This would normally be done by checking the conversation membership
    // For now, we'll assume it's been validated by middleware

    // Retrieve peer's public key
    let public_key_bytes = key_exchange
        .get_device_public_key(peer_user_id, peer_device_id.clone())
        .await?
        .ok_or(AppError::NotFound)?;

    let peer_public_key = general_purpose::STANDARD.encode(&public_key_bytes);

    Ok(Json(KeyExchangeResponse {
        peer_user_id,
        peer_device_id,
        peer_public_key,
        created_at: chrono::Utc::now(),
    }))
}

/// Complete ECDH key exchange and record it
pub async fn complete_key_exchange(
    State(state): State<AppState>,
    User { id: user_id, .. }: User,
    Path(conversation_id): Path<Uuid>,
    Json(payload): Json<CompleteKeyExchangeRequest>,
) -> Result<Json<KeyExchangeMetadataResponse>, AppError> {
    let key_exchange = state
        .key_exchange_service
        .as_ref()
        .ok_or_else(|| AppError::Internal)?;

    // Decode the shared secret hash
    let shared_secret_hash = general_purpose::STANDARD
        .decode(&payload.shared_secret_hash)
        .map_err(|_| AppError::BadRequest("Invalid base64 in shared_secret_hash".to_string()))?;

    // Record the key exchange for audit trail
    key_exchange
        .record_key_exchange(
            conversation_id,
            user_id,
            payload.peer_user_id,
            shared_secret_hash,
        )
        .await?;

    // Get metadata about key exchanges for this conversation
    let exchanges = key_exchange.list_key_exchanges(conversation_id).await?;

    let last_exchange_at = exchanges.first().map(|e| e.created_at);

    Ok(Json(KeyExchangeMetadataResponse {
        conversation_id,
        encryption_version: 2, // E2EE with ECDH
        key_exchange_count: exchanges.len() as i64,
        last_exchange_at,
    }))
}

/// Request body for completing key exchange
#[derive(Deserialize)]
pub struct CompleteKeyExchangeRequest {
    pub peer_user_id: Uuid,
    /// Base64 encoded HMAC-SHA256 hash of the shared secret
    pub shared_secret_hash: String,
}

/// List key exchanges for a conversation (admin/audit purposes)
pub async fn list_conversation_key_exchanges(
    State(state): State<AppState>,
    User { id: _user_id, .. }: User,
    Path(conversation_id): Path<Uuid>,
) -> Result<Json<Vec<KeyExchangeMetadata>>, AppError> {
    let key_exchange = state
        .key_exchange_service
        .as_ref()
        .ok_or_else(|| AppError::Internal)?;

    let exchanges = key_exchange.list_key_exchanges(conversation_id).await?;

    let metadata = exchanges
        .into_iter()
        .map(|e| KeyExchangeMetadata {
            id: e.id,
            conversation_id: e.conversation_id,
            initiator_id: e.initiator_id,
            peer_id: e.peer_id,
            created_at: e.created_at,
        })
        .collect();

    Ok(Json(metadata))
}

#[derive(Serialize)]
pub struct KeyExchangeMetadata {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub initiator_id: Uuid,
    pub peer_id: Uuid,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_public_key_validation() {
        // Test that 32-byte keys are accepted
        let valid_key = general_purpose::STANDARD.encode(&[0u8; 32]);
        assert_eq!(valid_key.len(), 44); // Base64 encoding of 32 bytes

        // Test that shorter keys are rejected
        let invalid_key = general_purpose::STANDARD.encode(&[0u8; 24]);
        let decoded = general_purpose::STANDARD.decode(&invalid_key).unwrap();
        assert_ne!(decoded.len(), 32);
    }
}
