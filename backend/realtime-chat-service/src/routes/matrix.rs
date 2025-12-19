// Matrix Integration REST API Routes
//
// These endpoints support iOS Matrix E2EE integration:
// - Token exchange (Nova JWT -> Matrix access token)
// - Room mapping management
// - Matrix configuration retrieval
// - Encryption status

use actix_web::{web, HttpResponse};
use db_pool::PgPool;
use matrix_sdk::ruma::RoomId;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::AppError;
use crate::middleware::guards::User;
use crate::services::matrix_client::MatrixClient;
use crate::services::matrix_db;

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
pub async fn get_matrix_token(
    user: User,
    matrix_client: web::Data<Option<MatrixClient>>,
    config: web::Data<crate::config::Config>,
) -> Result<HttpResponse, AppError> {
    // Check if Matrix is enabled
    let _matrix = match matrix_client.as_ref() {
        Some(client) => client,
        None => {
            return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "error": "Matrix integration is not enabled"
            })));
        }
    };

    // Get Matrix configuration
    let matrix_config = &config.matrix;

    // Generate Matrix user ID from Nova user ID
    // P0: Use server_name (not homeserver_url) to ensure consistent MXID generation
    // This matches the logic in matrix_admin.rs:user_id_to_mxid()
    let nova_user_id = user.id;
    let matrix_user_id = format!("@nova-{}:{}", nova_user_id, matrix_config.server_name);

    // In a production environment, we would:
    // 1. Check if user already has a Matrix account
    // 2. Create one if not (via admin API)
    // 3. Generate an access token for them
    //
    // For now, we return the service account token for simplicity
    // The iOS app will use this to send messages on behalf of the user

    let access_token = matrix_config.access_token.clone()
        .unwrap_or_else(|| "not_configured".to_string());

    // Generate a device ID for this user/device combination
    let device_id = format!("NOVA_IOS_{}", &nova_user_id.to_string()[..8]);

    Ok(HttpResponse::Ok().json(MatrixTokenResponse {
        access_token,
        matrix_user_id,
        device_id,
        homeserver_url: Some(matrix_config.homeserver_url.clone()),
    }))
}

/// GET /api/v2/matrix/rooms/{conversation_id}
/// Get Matrix room ID for a Nova conversation
pub async fn get_room_mapping(
    _user: User,
    path: web::Path<String>,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
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
    _user: User,
    query: web::Query<std::collections::HashMap<String, String>>,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
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
    _user: User,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
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
    _user: User,
    body: web::Json<SaveRoomMappingRequest>,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
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
    _user: User,
    config: web::Data<crate::config::Config>,
    matrix_client: web::Data<Option<MatrixClient>>,
) -> Result<HttpResponse, AppError> {
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
    _user: User,
    matrix_client: web::Data<Option<MatrixClient>>,
    config: web::Data<crate::config::Config>,
) -> Result<HttpResponse, AppError> {
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
    _user: User,
    path: web::Path<String>,
    db: web::Data<PgPool>,
    matrix_client: web::Data<Option<MatrixClient>>,
    config: web::Data<crate::config::Config>,
) -> Result<HttpResponse, AppError> {
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
