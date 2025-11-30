//! E2EE API Handlers
//!
//! REST endpoints for end-to-end encryption key management using vodozemac.
//! Implements Matrix-compatible Olm/Megolm protocols for true E2EE.
//!
//! **Architecture Notes**:
//! - Uses vodozemac OlmService for 1:1 Double Ratchet encryption
//! - Uses vodozemac MegolmService for efficient group encryption
//! - Device keys are Curve25519 identity keys from Olm accounts
//! - One-time keys enable forward secrecy in session establishment
//! - To-device messages carry Olm-encrypted room keys for Megolm

use crate::error::AppError;
use crate::middleware::guards::User;
use crate::state::AppState;
use actix_web::{delete, get, post, web, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info, instrument, warn};
use utoipa::ToSchema;
use uuid::Uuid;

// ============================================================================
// Request/Response Types
// ============================================================================

/// Register device request
#[derive(Debug, Deserialize, ToSchema)]
pub struct RegisterDeviceRequest {
    /// Client-generated device ID (e.g., "iPhone-ABC123")
    pub device_id: String,
    /// Human-readable device name (e.g., "Alice's iPhone")
    pub device_name: Option<String>,
}

/// Register device response
#[derive(Debug, Serialize, ToSchema)]
pub struct RegisterDeviceResponse {
    pub device_id: String,
    /// X25519 public key (base64, 32 bytes)
    pub identity_key: String,
    /// Ed25519 signing key placeholder (base64) - future use
    pub signing_key: String,
}

/// Upload one-time keys request
#[derive(Debug, Deserialize, ToSchema)]
pub struct UploadKeysRequest {
    /// Number of one-time prekeys to generate
    pub count: usize,
}

/// Upload one-time keys response
#[derive(Debug, Serialize, ToSchema)]
pub struct UploadKeysResponse {
    pub uploaded_count: usize,
    pub total_count: i32,
}

/// Claim one-time keys request
#[derive(Debug, Deserialize, ToSchema)]
pub struct ClaimKeysRequest {
    /// Map of user_id -> [device_ids] to claim keys for
    pub one_time_keys: HashMap<String, Vec<String>>,
}

/// Claimed key info
#[derive(Debug, Serialize, ToSchema)]
pub struct ClaimedKey {
    pub device_id: String,
    pub key_id: String,
    /// One-time prekey (base64)
    pub key: String,
    /// X25519 identity key (base64)
    pub identity_key: String,
    /// Signing key placeholder (base64)
    pub signing_key: String,
}

/// Claim one-time keys response
#[derive(Debug, Serialize, ToSchema)]
pub struct ClaimKeysResponse {
    /// Map of user_id -> device_id -> key_info
    pub one_time_keys: HashMap<String, HashMap<String, ClaimedKey>>,
    /// Devices that had no keys available
    pub failures: Vec<String>,
}

/// Query device keys request
#[derive(Debug, Deserialize, ToSchema)]
pub struct QueryKeysRequest {
    /// User IDs to query devices for
    pub user_ids: Vec<String>,
}

/// Device key info
#[derive(Debug, Serialize, ToSchema)]
pub struct DeviceKeyInfo {
    pub device_id: String,
    pub device_name: Option<String>,
    /// X25519 identity key (base64)
    pub identity_key: String,
    /// Signing key placeholder (base64)
    pub signing_key: String,
    /// Verification status (future: cross-signing)
    pub verified: bool,
}

/// Query device keys response
#[derive(Debug, Serialize, ToSchema)]
pub struct QueryKeysResponse {
    /// Map of user_id -> [device_keys]
    pub device_keys: HashMap<String, Vec<DeviceKeyInfo>>,
}

/// To-device message
#[derive(Debug, Serialize, ToSchema)]
pub struct ToDeviceMessage {
    pub id: String,
    pub sender_user_id: String,
    pub sender_device_id: String,
    pub message_type: String,
    /// Encrypted content (base64)
    pub content: String,
    pub created_at: String,
}

/// Get to-device messages response
#[derive(Debug, Serialize, ToSchema)]
pub struct ToDeviceMessagesResponse {
    pub messages: Vec<ToDeviceMessage>,
    /// Next batch token for pagination (future)
    pub next_batch: Option<String>,
}

/// Query parameters for to-device messages
#[derive(Debug, Deserialize)]
pub struct ToDeviceQuery {
    pub since: Option<String>,
    pub limit: Option<i32>,
}

// ============================================================================
// Handler Functions
// ============================================================================

/// POST /api/v1/e2ee/devices - Register a new device
///
/// Creates a new Olm account for this device with Curve25519 identity key.
/// Returns the public identity key for establishing E2EE sessions.
#[utoipa::path(
    post,
    path = "/api/v1/e2ee/devices",
    request_body = RegisterDeviceRequest,
    responses(
        (status = 200, description = "Device registered", body = RegisterDeviceResponse),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal error")
    ),
    tag = "E2EE"
)]
#[post("/devices")]
#[instrument(skip(state), fields(user_id = %user.id, device_id = %body.device_id))]
pub async fn register_device(
    state: web::Data<AppState>,
    user: User,
    body: web::Json<RegisterDeviceRequest>,
) -> Result<HttpResponse, AppError> {
    // Get OlmService (vodozemac-based)
    let olm = state.olm_service.as_ref()
        .ok_or_else(|| {
            warn!("E2EE not available - OLM_ACCOUNT_KEY not configured");
            AppError::ServiceUnavailable("E2EE service not configured".to_string())
        })?;

    // Create Olm account (generates Curve25519 + Ed25519 keypairs)
    let device_keys = olm
        .create_account(user.id, &body.device_id, body.device_name.as_deref())
        .await
        .map_err(|e| {
            warn!(error = %e, "Failed to create Olm account");
            AppError::Database(format!("Failed to register device: {}", e))
        })?;

    info!(
        user_id = %user.id,
        device_id = %body.device_id,
        "Device registered with Olm account"
    );

    Ok(HttpResponse::Ok().json(RegisterDeviceResponse {
        device_id: device_keys.device_id,
        identity_key: device_keys.identity_key.to_base64(),
        signing_key: device_keys.signing_key.to_base64(),
    }))
}

/// POST /api/v1/e2ee/keys/upload - Upload one-time prekeys
///
/// Generates Curve25519 one-time keys for session establishment.
/// These enable asynchronous key agreement (recipient offline).
#[utoipa::path(
    post,
    path = "/api/v1/e2ee/keys/upload",
    request_body = UploadKeysRequest,
    responses(
        (status = 200, description = "Keys uploaded", body = UploadKeysResponse),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal error")
    ),
    tag = "E2EE"
)]
#[post("/keys/upload")]
#[instrument(skip(state, req), fields(user_id = %user.id))]
pub async fn upload_keys(
    state: web::Data<AppState>,
    user: User,
    req: HttpRequest,
    body: web::Json<UploadKeysRequest>,
) -> Result<HttpResponse, AppError> {
    let device_id = extract_device_id(&req)?;

    let olm = state.olm_service.as_ref()
        .ok_or_else(|| AppError::ServiceUnavailable("E2EE service not configured".to_string()))?;

    // Generate and store one-time keys
    let uploaded = olm
        .generate_one_time_keys(&device_id, body.count)
        .await
        .map_err(|e| {
            warn!(error = %e, "Failed to generate one-time keys");
            AppError::Database(format!("Failed to upload keys: {}", e))
        })?;

    // Get current count of unused keys
    let total_count = olm
        .get_one_time_key_count(&device_id)
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;

    debug!(
        device_id = %device_id,
        uploaded,
        total_count,
        "Uploaded one-time keys"
    );

    Ok(HttpResponse::Ok().json(UploadKeysResponse {
        uploaded_count: uploaded,
        total_count: total_count as i32,
    }))
}

/// POST /api/v1/e2ee/keys/claim - Claim one-time keys from other devices
///
/// Retrieves one-time prekeys for establishing sessions with target devices.
/// Each key can only be claimed once (single-use prekeys).
#[utoipa::path(
    post,
    path = "/api/v1/e2ee/keys/claim",
    request_body = ClaimKeysRequest,
    responses(
        (status = 200, description = "Keys claimed", body = ClaimKeysResponse),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal error")
    ),
    tag = "E2EE"
)]
#[post("/keys/claim")]
#[instrument(skip(state, req), fields(user_id = %user.id))]
pub async fn claim_keys(
    state: web::Data<AppState>,
    user: User,
    req: HttpRequest,
    body: web::Json<ClaimKeysRequest>,
) -> Result<HttpResponse, AppError> {
    let our_device_id = extract_device_id(&req)?;

    let olm = state.olm_service.as_ref()
        .ok_or_else(|| AppError::ServiceUnavailable("E2EE service not configured".to_string()))?;

    let mut result: HashMap<String, HashMap<String, ClaimedKey>> = HashMap::new();
    let mut failures = Vec::new();

    for (target_user_id_str, device_ids) in &body.one_time_keys {
        let target_user_id = Uuid::parse_str(target_user_id_str)
            .map_err(|_| AppError::BadRequest("Invalid user ID".to_string()))?;

        let mut user_keys = HashMap::new();

        for target_device_id in device_ids {
            // Claim one-time key from target device
            match olm.claim_one_time_key(target_device_id, &our_device_id).await {
                Ok((key_id, one_time_key)) => {
                    // Get device's identity keys
                    let device_keys = olm
                        .get_device_keys(target_user_id)
                        .await
                        .map_err(|e| AppError::Database(e.to_string()))?;

                    if let Some(device) = device_keys.iter().find(|d| d.device_id == *target_device_id) {
                        user_keys.insert(
                            target_device_id.clone(),
                            ClaimedKey {
                                device_id: target_device_id.clone(),
                                key_id,
                                key: one_time_key.to_base64(),
                                identity_key: device.identity_key.to_base64(),
                                signing_key: device.signing_key.to_base64(),
                            },
                        );
                    } else {
                        warn!(device_id = %target_device_id, "Device not found after claiming key");
                        failures.push(target_device_id.clone());
                    }
                }
                Err(e) => {
                    warn!(error = %e, device_id = %target_device_id, "Failed to claim one-time key");
                    failures.push(target_device_id.clone());
                }
            }
        }

        if !user_keys.is_empty() {
            result.insert(target_user_id_str.clone(), user_keys);
        }
    }

    debug!(
        our_device = %our_device_id,
        claimed = result.len(),
        failures = failures.len(),
        "Claimed one-time keys"
    );

    Ok(HttpResponse::Ok().json(ClaimKeysResponse {
        one_time_keys: result,
        failures,
    }))
}

/// POST /api/v1/e2ee/keys/query - Query device keys for users
///
/// Returns all registered devices and their identity keys for specified users.
/// Used for device discovery before initiating encrypted conversations.
#[utoipa::path(
    post,
    path = "/api/v1/e2ee/keys/query",
    request_body = QueryKeysRequest,
    responses(
        (status = 200, description = "Device keys", body = QueryKeysResponse),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal error")
    ),
    tag = "E2EE"
)]
#[post("/keys/query")]
#[instrument(skip(state), fields(user_id = %user.id))]
pub async fn query_keys(
    state: web::Data<AppState>,
    user: User,
    body: web::Json<QueryKeysRequest>,
) -> Result<HttpResponse, AppError> {
    let olm = state.olm_service.as_ref()
        .ok_or_else(|| AppError::ServiceUnavailable("E2EE service not configured".to_string()))?;

    let mut result: HashMap<String, Vec<DeviceKeyInfo>> = HashMap::new();

    for user_id_str in &body.user_ids {
        let target_user_id = Uuid::parse_str(user_id_str)
            .map_err(|_| AppError::BadRequest("Invalid user ID".to_string()))?;

        // Get all device keys for this user
        let device_keys = olm
            .get_device_keys(target_user_id)
            .await
            .map_err(|e| AppError::Database(e.to_string()))?;

        let devices: Vec<DeviceKeyInfo> = device_keys
            .into_iter()
            .map(|dk| DeviceKeyInfo {
                device_id: dk.device_id,
                device_name: None, // TODO: Fetch from user_devices table
                identity_key: dk.identity_key.to_base64(),
                signing_key: dk.signing_key.to_base64(),
                verified: false, // TODO: Implement cross-signing verification
            })
            .collect();

        result.insert(user_id_str.clone(), devices);
    }

    debug!(user_count = body.user_ids.len(), "Queried device keys");

    Ok(HttpResponse::Ok().json(QueryKeysResponse {
        device_keys: result,
    }))
}

/// GET /api/v1/e2ee/to-device - Get pending to-device messages
///
/// Retrieves encrypted messages sent directly to this device (not conversation).
/// Used for key negotiation, device verification, and out-of-band signaling.
///
/// **Note**: Requires implementing to-device message storage in database.
#[utoipa::path(
    get,
    path = "/api/v1/e2ee/to-device",
    params(
        ("since" = Option<String>, Query, description = "Batch token for pagination"),
        ("limit" = Option<i32>, Query, description = "Max messages to return")
    ),
    responses(
        (status = 200, description = "To-device messages", body = ToDeviceMessagesResponse),
        (status = 401, description = "Unauthorized"),
        (status = 500, description = "Internal error")
    ),
    tag = "E2EE"
)]
#[get("/to-device")]
#[instrument(skip(state, req), fields(user_id = %user.id))]
pub async fn get_to_device_messages(
    state: web::Data<AppState>,
    user: User,
    req: HttpRequest,
    query: web::Query<ToDeviceQuery>,
) -> Result<HttpResponse, AppError> {
    let device_id = extract_device_id(&req)?;
    let limit = query.limit.unwrap_or(100).min(1000);

    // TODO: Implement to-device message retrieval from database
    warn!(
        user_id = %user.id,
        device_id = %device_id,
        limit,
        "To-device message retrieval not yet implemented"
    );

    // Placeholder: Return empty list
    Ok(HttpResponse::Ok().json(ToDeviceMessagesResponse {
        messages: Vec::new(),
        next_batch: None,
    }))
}

/// DELETE /api/v1/e2ee/to-device/{message_id} - Acknowledge message receipt
///
/// Marks a to-device message as delivered and removes it from the queue.
#[utoipa::path(
    delete,
    path = "/api/v1/e2ee/to-device/{message_id}",
    params(
        ("message_id" = String, Path, description = "Message ID to acknowledge")
    ),
    responses(
        (status = 204, description = "Message acknowledged"),
        (status = 401, description = "Unauthorized"),
        (status = 404, description = "Message not found")
    ),
    tag = "E2EE"
)]
#[delete("/to-device/{message_id}")]
#[instrument(skip(state), fields(user_id = %user.id, message_id = %message_id))]
pub async fn ack_to_device_message(
    state: web::Data<AppState>,
    user: User,
    message_id: web::Path<String>,
) -> Result<HttpResponse, AppError> {
    let msg_uuid = Uuid::parse_str(&message_id)
        .map_err(|_| AppError::BadRequest("Invalid message ID".to_string()))?;

    // TODO: Implement message acknowledgment
    warn!(
        user_id = %user.id,
        message_id = %msg_uuid,
        "To-device message acknowledgment not yet implemented"
    );

    Ok(HttpResponse::NoContent().finish())
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Extract device ID from X-Device-ID header
fn extract_device_id(req: &HttpRequest) -> Result<String, AppError> {
    req.headers()
        .get("X-Device-ID")
        .and_then(|h| h.to_str().ok())
        .map(|s| s.to_string())
        .ok_or_else(|| {
            AppError::BadRequest("Missing X-Device-ID header".to_string())
        })
}

// ============================================================================
// Route Configuration
// ============================================================================

/// Configure E2EE routes
///
/// Mount this at `/api/v1/e2ee` scope in main.rs
pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/e2ee")
            .service(register_device)
            .service(upload_keys)
            .service(claim_keys)
            .service(query_keys)
            .service(get_to_device_messages)
            .service(ack_to_device_message),
    );
}

// ============================================================================
// TODO: Required E2eeService Enhancements
// ============================================================================

/*
The following methods need to be added to E2eeService:

1. One-Time Key Management:
   ```rust
   /// Generate and store one-time prekeys for a device
   pub async fn generate_one_time_keys(
       &self,
       pool: &Pool<Postgres>,
       user_id: Uuid,
       device_id: &str,
       count: usize,
   ) -> Result<usize, AppError>;

   /// Get count of available one-time keys for a device
   pub async fn get_one_time_key_count(
       &self,
       pool: &Pool<Postgres>,
       user_id: Uuid,
       device_id: &str,
   ) -> Result<i32, AppError>;

   /// Claim a one-time key (single-use, atomic operation)
   pub async fn claim_one_time_key(
       &self,
       pool: &Pool<Postgres>,
       target_user_id: Uuid,
       target_device_id: &str,
       claiming_user_id: Uuid,
       claiming_device_id: &str,
   ) -> Result<(String, Vec<u8>), AppError>; // (key_id, public_key)
   ```

2. Device Key Queries:
   ```rust
   /// Get all devices and their public keys for a user
   pub async fn get_all_device_keys(
       &self,
       pool: &Pool<Postgres>,
       user_id: Uuid,
   ) -> Result<Vec<DeviceKeyRecord>, AppError>;
   ```

   Where DeviceKeyRecord:
   ```rust
   pub struct DeviceKeyRecord {
       pub device_id: String,
       pub device_name: Option<String>,
       pub public_key: Vec<u8>,
       pub created_at: chrono::DateTime<chrono::Utc>,
   }
   ```

3. To-Device Messaging:
   ```rust
   /// Store a to-device message
   pub async fn store_to_device_message(
       &self,
       pool: &Pool<Postgres>,
       sender_user_id: Uuid,
       sender_device_id: &str,
       recipient_user_id: Uuid,
       recipient_device_id: &str,
       message_type: &str,
       content: &[u8],
   ) -> Result<Uuid, AppError>;

   /// Get to-device messages for a device
   pub async fn get_to_device_messages(
       &self,
       pool: &Pool<Postgres>,
       user_id: Uuid,
       device_id: &str,
       limit: i32,
   ) -> Result<Vec<ToDeviceMessageRecord>, AppError>;

   /// Mark messages as delivered (atomic delete)
   pub async fn mark_messages_delivered(
       &self,
       pool: &Pool<Postgres>,
       message_ids: &[Uuid],
   ) -> Result<(), AppError>;
   ```

   Where ToDeviceMessageRecord:
   ```rust
   pub struct ToDeviceMessageRecord {
       pub id: Uuid,
       pub sender_user_id: Uuid,
       pub sender_device_id: String,
       pub message_type: String,
       pub content: Vec<u8>,
       pub created_at: chrono::DateTime<chrono::Utc>,
   }
   ```

4. Database Schema (migration needed):
   ```sql
   -- One-time keys table
   CREATE TABLE one_time_keys (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
       device_id TEXT NOT NULL,
       key_id TEXT NOT NULL UNIQUE,
       public_key TEXT NOT NULL,
       claimed BOOLEAN DEFAULT FALSE,
       claimed_by_user_id UUID REFERENCES users(id),
       claimed_by_device_id TEXT,
       claimed_at TIMESTAMPTZ,
       created_at TIMESTAMPTZ DEFAULT NOW(),
       UNIQUE(user_id, device_id, key_id)
   );
   CREATE INDEX idx_one_time_keys_device ON one_time_keys(user_id, device_id, claimed)
       WHERE NOT claimed;

   -- To-device messages table
   CREATE TABLE to_device_messages (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
       sender_device_id TEXT NOT NULL,
       recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
       recipient_device_id TEXT NOT NULL,
       message_type TEXT NOT NULL,
       content BYTEA NOT NULL,
       created_at TIMESTAMPTZ DEFAULT NOW()
   );
   CREATE INDEX idx_to_device_recipient ON to_device_messages(
       recipient_user_id, recipient_device_id, created_at DESC
   );

   -- Add device_name to device_keys table
   ALTER TABLE device_keys ADD COLUMN IF NOT EXISTS device_name TEXT;
   ```
*/
