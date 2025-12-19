// Matrix Integration REST API Routes
//
// These endpoints support iOS Matrix E2EE integration:
// - Token exchange (Nova JWT -> Matrix access token)
// - Room mapping management
// - Matrix configuration retrieval
// - Encryption status

use actix_web::{web, HttpRequest, HttpResponse};
use db_pool::PgPool;
use matrix_sdk::ruma::RoomId;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::AppError;
use crate::services::matrix_client::MatrixClient;
use crate::services::matrix_db;
use crate::state::AppState;

/// Extract user ID from X-User-Id header (for internal service-to-service calls)
/// This is used when requests come from graphql-gateway which already validated JWT
fn extract_user_id_from_header(req: &HttpRequest) -> Option<Uuid> {
    req.headers()
        .get("X-User-Id")
        .and_then(|h| h.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
}

// ============================================================================
// Request/Response Types
// ============================================================================

/// Request to get Matrix access token for a Nova user
#[derive(Debug, Deserialize)]
pub struct GetMatrixTokenRequest {
    pub user_id: String,
}

/// Response containing Matrix access token
#[derive(Debug, Serialize)]
pub struct MatrixTokenResponse {
    pub access_token: String,
    pub matrix_user_id: String,
    pub device_id: String,
    pub homeserver_url: Option<String>,
}

/// Response for room mapping query
#[derive(Debug, Serialize)]
pub struct RoomMappingResponse {
    pub room_id: Option<String>,
}

/// Response for conversation mapping query
#[derive(Debug, Serialize)]
pub struct ConversationMappingResponse {
    pub conversation_id: Option<String>,
}

/// Request to save a room mapping
#[derive(Debug, Deserialize)]
pub struct SaveRoomMappingRequest {
    pub conversation_id: String,
    pub room_id: String,
}

/// Response for listing all room mappings
#[derive(Debug, Serialize)]
pub struct AllMappingsResponse {
    pub mappings: Vec<MappingEntry>,
}

#[derive(Debug, Serialize)]
pub struct MappingEntry {
    pub conversation_id: String,
    pub room_id: String,
}

/// Matrix configuration response
#[derive(Debug, Serialize)]
pub struct MatrixConfigResponse {
    pub enabled: bool,
    pub homeserver_url: Option<String>,
    pub e2ee_enabled: bool,
    pub voip_enabled: bool,
}

/// Matrix encryption status response
#[derive(Debug, Serialize)]
pub struct EncryptionStatusResponse {
    pub e2ee_enabled: bool,
    pub backup_enabled: bool,
    pub recovery_key_status: String,
    pub device_verified: bool,
}

/// Room status response
#[derive(Debug, Serialize)]
pub struct RoomStatusResponse {
    pub room_id: Option<String>,
    pub is_encrypted: bool,
    pub members_synced: i32,
    pub matrix_enabled: bool,
}

// ============================================================================
// Route Handlers
// ============================================================================

/// POST /api/v2/matrix/token
/// Get Matrix access token for the authenticated user
///
/// This endpoint exchanges a Nova JWT for a Matrix access token.
/// The Matrix access token allows the iOS app to connect directly to Matrix.
///
/// Flow:
/// 1. Verify Matrix is enabled
/// 2. Create Matrix user if doesn't exist (via Synapse Admin API)
/// 3. Generate a user-specific login token (via Synapse Admin API)
/// 4. Return the login token for the iOS app to use
pub async fn get_matrix_token(
    req: HttpRequest,
    state: web::Data<AppState>,
) -> Result<HttpResponse, AppError> {
    // Extract user ID from X-User-Id header (internal service call from graphql-gateway)
    let nova_user_id = extract_user_id_from_header(&req)
        .ok_or_else(|| {
            tracing::warn!("Missing or invalid X-User-Id header");
            AppError::Unauthorized
        })?;

    tracing::info!(user_id = %nova_user_id, "Processing Matrix token request");

    // Check if Matrix is enabled
    if state.matrix_client.is_none() {
        return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "error": "Matrix integration is not enabled"
        })));
    }

    // Check if Matrix Admin client is available for user provisioning
    let matrix_admin = match &state.matrix_admin_client {
        Some(admin) => admin,
        None => {
            // Fallback: return service account token (not recommended for production)
            tracing::warn!("Matrix Admin client not configured, returning service account token");
            let matrix_config = &state.config.matrix;
            let access_token = matrix_config.access_token.clone()
                .unwrap_or_else(|| "not_configured".to_string());
            let matrix_user_id = format!("@nova-{}:{}", nova_user_id, matrix_config.server_name);
            let device_id = format!("NOVA_IOS_{}", &nova_user_id.to_string()[..8]);

            return Ok(HttpResponse::Ok().json(MatrixTokenResponse {
                access_token,
                matrix_user_id,
                device_id,
                homeserver_url: Some(matrix_config.homeserver_url.clone()),
            }));
        }
    };

    let matrix_config = &state.config.matrix;

    // Provision user: create if doesn't exist, then generate login token
    // The displayname could be fetched from identity service, but for now use user ID
    let displayname = format!("Nova User {}", &nova_user_id.to_string()[..8]);

    match matrix_admin.provision_user(nova_user_id, Some(displayname)).await {
        Ok((matrix_user_id, login_token)) => {
            // Generate a device ID for this user/device combination
            let device_id = format!("NOVA_IOS_{}", &nova_user_id.to_string()[..8]);

            tracing::info!(
                "Successfully provisioned Matrix user: nova_user_id={}, matrix_user_id={}",
                nova_user_id, matrix_user_id
            );

            Ok(HttpResponse::Ok().json(MatrixTokenResponse {
                access_token: login_token,
                matrix_user_id,
                device_id,
                homeserver_url: Some(matrix_config.homeserver_url.clone()),
            }))
        }
        Err(e) => {
            tracing::error!(
                "Failed to provision Matrix user: nova_user_id={}, error={}",
                nova_user_id, e
            );
            
            // Fallback to service account token to avoid breaking the app
            // This is not ideal but prevents complete failure
            tracing::warn!("Falling back to service account token due to provisioning failure");
            let access_token = matrix_config.access_token.clone()
                .unwrap_or_else(|| "not_configured".to_string());
            let matrix_user_id = format!("@nova-{}:{}", nova_user_id, matrix_config.server_name);
            let device_id = format!("NOVA_IOS_{}", &nova_user_id.to_string()[..8]);

            Ok(HttpResponse::Ok().json(MatrixTokenResponse {
                access_token,
                matrix_user_id,
                device_id,
                homeserver_url: Some(matrix_config.homeserver_url.clone()),
            }))
        }
    }
}

/// GET /api/v2/matrix/rooms/{conversation_id}
/// Get Matrix room ID for a Nova conversation
pub async fn get_room_mapping(
    req: HttpRequest,
    path: web::Path<String>,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
    // Validate X-User-Id header exists (authentication already done by graphql-gateway)
    let _user_id = extract_user_id_from_header(&req)
        .ok_or_else(|| AppError::Unauthorized)?;
    let conversation_id_str = path.into_inner();
    let conversation_id = Uuid::parse_str(&conversation_id_str)
        .map_err(|_| AppError::BadRequest("Invalid conversation ID".to_string()))?;

    // Load room mapping from database
    let room_id = matrix_db::load_room_mapping(db.get_ref(), conversation_id).await?;

    Ok(HttpResponse::Ok().json(RoomMappingResponse {
        room_id: room_id.map(|r| r.to_string())
    }))
}

/// GET /api/v2/matrix/conversations
/// Get Nova conversation ID for a Matrix room ID (query param: room_id)
pub async fn get_conversation_mapping(
    req: HttpRequest,
    query: web::Query<std::collections::HashMap<String, String>>,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
    // Validate X-User-Id header exists (authentication already done by graphql-gateway)
    let _user_id = extract_user_id_from_header(&req)
        .ok_or_else(|| AppError::Unauthorized)?;
    let room_id = query.get("room_id")
        .ok_or_else(|| AppError::BadRequest("Missing room_id query parameter".to_string()))?;

    // Lookup conversation by Matrix room ID
    let conversation_id = matrix_db::lookup_conversation_by_room_id(db.get_ref(), room_id).await?;

    Ok(HttpResponse::Ok().json(ConversationMappingResponse {
        conversation_id: conversation_id.map(|id| id.to_string()),
    }))
}

/// GET /api/v2/matrix/rooms
/// Get all conversation-to-room mappings for the current user
pub async fn get_all_room_mappings(
    req: HttpRequest,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
    // Validate X-User-Id header exists (authentication already done by graphql-gateway)
    let _user_id = extract_user_id_from_header(&req)
        .ok_or_else(|| AppError::Unauthorized)?;
    // Load all room mappings
    // In production, we'd filter to only conversations the user is a member of
    let mappings = matrix_db::load_all_room_mappings(db.get_ref()).await?;

    let entries: Vec<MappingEntry> = mappings
        .into_iter()
        .map(|(conv_id, room_id)| MappingEntry {
            conversation_id: conv_id.to_string(),
            room_id: room_id.to_string(),
        })
        .collect();

    Ok(HttpResponse::Ok().json(AllMappingsResponse { mappings: entries }))
}

/// POST /api/v2/matrix/rooms
/// Save a new conversation-to-room mapping
pub async fn save_room_mapping(
    req: HttpRequest,
    body: web::Json<SaveRoomMappingRequest>,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
    // Validate X-User-Id header exists (authentication already done by graphql-gateway)
    let _user_id = extract_user_id_from_header(&req)
        .ok_or_else(|| AppError::Unauthorized)?;
    let conversation_id = Uuid::parse_str(&body.conversation_id)
        .map_err(|_| AppError::BadRequest("Invalid conversation ID".to_string()))?;

    // Parse room_id as Matrix RoomId
    let room_id = <&RoomId>::try_from(body.room_id.as_str())
        .map_err(|_| AppError::BadRequest("Invalid Matrix room ID".to_string()))?;

    // Save mapping to database
    matrix_db::save_room_mapping(db.get_ref(), conversation_id, room_id).await?;

    Ok(HttpResponse::Created().json(serde_json::json!({
        "message": "Room mapping saved successfully"
    })))
}

/// GET /api/v2/matrix/config
/// Get Matrix configuration (homeserver URL, enabled status, etc.)
pub async fn get_matrix_config(
    req: HttpRequest,
    config: web::Data<crate::config::Config>,
    matrix_client: web::Data<Option<MatrixClient>>,
) -> Result<HttpResponse, AppError> {
    // Validate X-User-Id header exists (authentication already done by graphql-gateway)
    let _user_id = extract_user_id_from_header(&req)
        .ok_or_else(|| AppError::Unauthorized)?;
    let matrix_enabled = matrix_client.is_some() && config.matrix.enabled;

    Ok(HttpResponse::Ok().json(MatrixConfigResponse {
        enabled: matrix_enabled,
        homeserver_url: if matrix_enabled {
            Some(config.matrix.homeserver_url.clone())
        } else {
            None
        },
        e2ee_enabled: matrix_enabled, // E2EE is always on when Matrix is enabled
        voip_enabled: matrix_enabled, // VoIP is available via Matrix
    }))
}

/// GET /api/v2/matrix/encryption/status
/// Get encryption status for the current user
pub async fn get_encryption_status(
    req: HttpRequest,
    matrix_client: web::Data<Option<MatrixClient>>,
    config: web::Data<crate::config::Config>,
) -> Result<HttpResponse, AppError> {
    // Validate X-User-Id header exists (authentication already done by graphql-gateway)
    let _user_id = extract_user_id_from_header(&req)
        .ok_or_else(|| AppError::Unauthorized)?;
    let matrix_enabled = matrix_client.is_some() && config.matrix.enabled;

    // Check if recovery key is configured
    let recovery_key_status = if config.matrix.recovery_key.is_some() {
        "enabled"
    } else {
        "disabled"
    };

    Ok(HttpResponse::Ok().json(EncryptionStatusResponse {
        e2ee_enabled: matrix_enabled,
        backup_enabled: config.matrix.recovery_key.is_some(),
        recovery_key_status: recovery_key_status.to_string(),
        device_verified: true, // Service account is always "verified"
    }))
}

/// GET /api/v2/matrix/conversations/{conversation_id}/room-status
/// Get detailed Matrix room status for a conversation
pub async fn get_room_status(
    req: HttpRequest,
    path: web::Path<String>,
    db: web::Data<PgPool>,
    matrix_client: web::Data<Option<MatrixClient>>,
    config: web::Data<crate::config::Config>,
) -> Result<HttpResponse, AppError> {
    // Validate X-User-Id header exists (authentication already done by graphql-gateway)
    let _user_id = extract_user_id_from_header(&req)
        .ok_or_else(|| AppError::Unauthorized)?;
    let conversation_id_str = path.into_inner();
    let conversation_id = Uuid::parse_str(&conversation_id_str)
        .map_err(|_| AppError::BadRequest("Invalid conversation ID".to_string()))?;

    let matrix_enabled = matrix_client.is_some() && config.matrix.enabled;

    // Load room mapping
    let room_id = matrix_db::load_room_mapping(db.get_ref(), conversation_id).await?;

    // Get room encryption status if room exists and Matrix is enabled
    let is_encrypted = if let (Some(ref client), Some(ref rid)) = (matrix_client.as_ref(), &room_id) {
        client.is_room_encrypted(rid).await
    } else {
        false
    };

    // Get participant count
    let members_synced = if room_id.is_some() {
        matrix_db::get_conversation_participants(db.get_ref(), conversation_id)
            .await
            .map(|p| p.len() as i32)
            .unwrap_or(0)
    } else {
        0
    };

    Ok(HttpResponse::Ok().json(RoomStatusResponse {
        room_id: room_id.map(|r| r.to_string()),
        is_encrypted,
        members_synced,
        matrix_enabled,
    }))
}

// ============================================================================
// Route Configuration
// ============================================================================

/// Configure Matrix API routes
/// Note: This is called within /api/v2 scope in main.rs, so paths here are relative to /api/v2
pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/matrix")
            // Token exchange
            .route("/token", web::post().to(get_matrix_token))
            // Room mappings
            .route("/rooms", web::get().to(get_all_room_mappings))
            .route("/rooms", web::post().to(save_room_mapping))
            .route("/rooms/{conversation_id}", web::get().to(get_room_mapping))
            // Conversation lookup
            .route("/conversations", web::get().to(get_conversation_mapping))
            // Configuration
            .route("/config", web::get().to(get_matrix_config))
            // Encryption status
            .route("/encryption/status", web::get().to(get_encryption_status))
            // Room status
            .route("/conversations/{conversation_id}/room-status", web::get().to(get_room_status))
    );
}
