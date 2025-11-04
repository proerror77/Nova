use actix_web::{web, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::error::AppError;
use crate::middleware::guards::User;
use crate::services::message_service::MessageService;
use crate::state::AppState;
use crate::websocket::events::{broadcast_event, WebSocketEvent};
use aws_sdk_s3::config::Region;
use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::Client as S3Client;
use base64::{engine::general_purpose, Engine as _};
use std::time::Duration;

#[derive(Deserialize)]
pub struct SendMessageRequest {
    pub plaintext: String,
    pub idempotency_key: Option<String>,
}

#[derive(Serialize)]
pub struct SendMessageResponse {
    pub id: Uuid,
    pub sequence_number: i64,
}

pub async fn send_message(
    state: web::Data<AppState>,
    user: User, // Authenticated user from JWT
    id: web::Path<Uuid>,
    body: web::Json<SendMessageRequest>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = id.into_inner();

    // Verify user is member of conversation and has permission to send
    let member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    member.can_send()?;

    let (msg_id, seq) = MessageService::send_message_db(
        &state.db,
        &state.encryption,
        conversation_id,
        user.id,
        body.plaintext.as_bytes(),
        body.idempotency_key.as_deref(),
    )
    .await?;

    // Broadcast message.new event using unified event system
    let event = WebSocketEvent::MessageNew {
        id: msg_id,
        sender_id: user.id,
        sequence_number: seq,
        conversation_id,
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        user.id,
        event,
    )
    .await;

    Ok(HttpResponse::Ok().json(SendMessageResponse {
        id: msg_id,
        sequence_number: seq,
    }))
}

#[derive(Serialize)]
pub struct MessageDto {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub sequence_number: i64,
    pub created_at: String,
    pub content: String,
    pub encrypted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub encrypted_payload: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nonce: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recalled_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    pub version_number: i32,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub reactions: Vec<MessageReaction>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub attachments: Vec<MessageAttachment>,
}

#[derive(Serialize)]
pub struct MessageReaction {
    pub emoji: String,
    pub count: i64,
    pub user_reacted: bool,
}

#[derive(Serialize)]
pub struct MessageAttachment {
    pub id: Uuid,
    pub file_name: String,
    pub file_type: Option<String>,
    pub file_size: i32,
    pub s3_key: String,
}

#[derive(Deserialize)]
pub struct SendAudioMessageRequest {
    pub audio_url: String,   // S3 URL or presigned URL to audio file
    pub duration_ms: u32,    // Duration in milliseconds
    pub audio_codec: String, // opus, aac, mp3, wav, etc.
    pub idempotency_key: Option<String>,
}

#[derive(Serialize)]
pub struct AudioMessageDto {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub sequence_number: i64,
    pub created_at: String,
    pub audio_url: String,
    pub duration_ms: u32,
    pub audio_codec: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transcription: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transcription_language: Option<String>,
}

#[derive(Deserialize)]
pub struct PaginationQuery {
    #[serde(default = "default_limit")]
    pub limit: i64,
    #[serde(default)]
    pub offset: i64,
    #[serde(default = "default_include_recalled")]
    pub include_recalled: bool,
}

fn default_limit() -> i64 {
    50
}

fn default_include_recalled() -> bool {
    false
}

pub async fn get_message_history(
    state: web::Data<AppState>,
    user: User,
    id: web::Path<Uuid>,
    pagination: web::Query<PaginationQuery>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = id.into_inner();

    // Verify user is member of conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    let rows = MessageService::get_message_history_with_details(
        &state.db,
        &state.encryption,
        conversation_id,
        user.id,
        pagination.limit,
        pagination.offset,
        pagination.include_recalled,
    )
    .await?;
    Ok(HttpResponse::Ok().json(rows))
}

#[derive(Deserialize)]
pub struct UpdateMessageRequest {
    pub plaintext: String,
    pub version_number: i32,    // Required for optimistic locking
    pub reason: Option<String>, // Optional edit reason for audit trail
}

/// Update message with optimistic locking (version control)
///
/// Business rules:
/// - Only message sender can edit (admins cannot edit others' messages)
/// - Edit window: 24 hours after creation
/// - Version number must match current version (prevents lost updates)
/// - On conflict: returns 409 with server version
/// - Edit history is automatically recorded via database trigger
// ============================================================================
// Message Update Helpers
// ============================================================================

/// Encapsulates validation logic for message editing
struct MessageEditValidator {
    conversation_id: Uuid,
    sender_id: Uuid,
    current_version: i32,
    created_at: chrono::DateTime<chrono::Utc>,
    privacy_mode: crate::services::conversation_service::PrivacyMode,
    old_content: String,
}

const MAX_EDIT_MINUTES: i64 = 1440; // 24 hours

impl MessageEditValidator {
    /// Validate ownership - only sender can edit their own messages
    fn verify_ownership(&self, user_id: Uuid) -> Result<(), AppError> {
        if self.sender_id != user_id {
            return Err(AppError::Forbidden);
        }
        Ok(())
    }

    /// Validate edit window - must edit within 24 hours
    fn verify_edit_window(&self) -> Result<(), AppError> {
        let elapsed_minutes = (chrono::Utc::now() - self.created_at).num_minutes();
        if elapsed_minutes > MAX_EDIT_MINUTES {
            return Err(AppError::EditWindowExpired {
                max_edit_minutes: MAX_EDIT_MINUTES,
            });
        }
        Ok(())
    }

    /// Verify optimistic lock - client version must match server
    fn verify_version(&self, client_version: i32) -> Result<(), AppError> {
        if client_version != self.current_version {
            return Err(AppError::VersionConflict {
                current_version: self.current_version,
                client_version,
                server_content: self.old_content.clone(),
            });
        }
        Ok(())
    }
}

/// Prepare content for storage based on privacy mode
async fn prepare_content_payload(
    encryption_service: &crate::services::encryption::EncryptionService,
    conversation_id: Uuid,
    plaintext: &[u8],
    privacy_mode: crate::services::conversation_service::PrivacyMode,
) -> Result<(String, Option<Vec<u8>>, Option<Vec<u8>>, i32), AppError> {
    if matches!(
        privacy_mode,
        crate::services::conversation_service::PrivacyMode::StrictE2e
    ) {
        let (ciphertext, nonce) = encryption_service.encrypt(conversation_id, plaintext)?;
        Ok((String::new(), Some(ciphertext), Some(nonce.to_vec()), 1))
    } else {
        Ok((
            String::from_utf8_lossy(plaintext).to_string(),
            None,
            None,
            0,
        ))
    }
}

/// Validate audio message parameters
/// - Duration must be between 1ms and 10 minutes (600000ms)
/// - Codec must be one of the supported formats
fn validate_audio_message(duration_ms: i64, audio_codec: &str) -> Result<(), AppError> {
    // Validate audio duration (0 < duration <= 10 minutes)
    if duration_ms == 0 || duration_ms > 600_000 {
        return Err(crate::error::AppError::Config(
            "Audio duration must be between 1 and 600000 milliseconds (10 minutes)".into(),
        ));
    }

    // Validate audio codec
    const VALID_CODECS: &[&str] = &["opus", "aac", "mp3", "wav", "flac", "ogg"];
    if !VALID_CODECS.contains(&audio_codec) {
        return Err(crate::error::AppError::Config(format!(
            "Unsupported audio codec: {}. Supported: {:?}",
            audio_codec, VALID_CODECS
        )));
    }

    Ok(())
}

// ============================================================================

pub async fn update_message(
    state: web::Data<AppState>,
    user: User,
    message_id: web::Path<Uuid>,
    body: web::Json<UpdateMessageRequest>,
) -> Result<HttpResponse, AppError> {
    let message_id = message_id.into_inner();

    // Start transaction for atomic operation
    let mut tx = state.db.begin().await?;

    // 1. Get message with FOR UPDATE lock (prevents concurrent modifications)
    let msg_row = sqlx::query(
        "SELECT m.conversation_id, m.sender_id, m.version_number, m.created_at, m.content,
                m.content_encrypted, m.content_nonce, c.privacy_mode::text AS privacy_mode
         FROM messages m
         JOIN conversations c ON c.id = m.conversation_id
         WHERE m.id = $1
         FOR UPDATE",
    )
    .bind(message_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound)?;

    let conversation_id: Uuid = msg_row.get("conversation_id");
    let sender_id: Uuid = msg_row.get("sender_id");
    let current_version: i32 = msg_row.get("version_number");
    let created_at: chrono::DateTime<chrono::Utc> = msg_row.get("created_at");
    let privacy_str: String = msg_row.get("privacy_mode");
    let privacy_mode = match privacy_str.as_str() {
        "strict_e2e" => crate::services::conversation_service::PrivacyMode::StrictE2e,
        _ => crate::services::conversation_service::PrivacyMode::SearchEnabled,
    };

    let mut old_content: String = msg_row.get("content");
    let ciphertext: Option<Vec<u8>> = msg_row
        .try_get::<Option<Vec<u8>>, _>("content_encrypted")
        .ok()
        .flatten();

    if matches!(
        privacy_mode,
        crate::services::conversation_service::PrivacyMode::StrictE2e
    ) {
        old_content = ciphertext
            .as_ref()
            .map(|c| general_purpose::STANDARD.encode(c))
            .unwrap_or_else(|| "[Encrypted message unavailable]".to_string());
    }

    let validator = MessageEditValidator {
        conversation_id,
        sender_id,
        current_version,
        created_at,
        privacy_mode,
        old_content,
    };

    // 2-5. Run all validations
    validator.verify_ownership(user.id)?;
    validator.verify_edit_window()?;
    validator.verify_version(body.version_number)?;

    // 3. Verify user is member of conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // 6. Prepare encrypted payload
    let (new_content_value, encrypted_payload, nonce_payload, encryption_version) =
        prepare_content_payload(
            &state.encryption,
            conversation_id,
            body.plaintext.as_bytes(),
            privacy_mode,
        )
        .await?;

    // 7. Update message with version increment (CAS - Compare-And-Swap)
    let updated = sqlx::query(
        r#"
        UPDATE messages
        SET
            content = $1,
            content_encrypted = $2,
            content_nonce = $3,
            encryption_version = $4,
            version_number = version_number + 1,
            updated_at = NOW()
        WHERE id = $5 AND version_number = $6
        RETURNING version_number
        "#,
    )
    .bind(&new_content_value)
    .bind(encrypted_payload.as_ref().map(|v| v.as_slice()))
    .bind(nonce_payload.as_ref().map(|v| v.as_slice()))
    .bind(encryption_version)
    .bind(message_id)
    .bind(current_version)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::VersionConflict {
        current_version: current_version + 1,
        client_version: body.version_number,
        server_content: validator.old_content,
    })?;

    let new_version: i32 = updated.get("version_number");

    // 8. Commit transaction
    tx.commit().await?;

    // 9. Broadcast message.edited event
    let event = WebSocketEvent::MessageEdited {
        conversation_id,
        message_id,
        version_number: new_version,
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        user.id,
        event,
    )
    .await;

    Ok(HttpResponse::NoContent().finish())
}

pub async fn delete_message(
    state: web::Data<AppState>,
    user: User,
    message_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let message_id = message_id.into_inner();
    // TOCTOU fix: Use atomic transaction for permission check + delete
    let mut tx = state.db.begin().await?;

    // Get message details to verify permissions and find conversation
    let msg_row = sqlx::query("SELECT conversation_id, sender_id FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get message: {e}")))?
        .ok_or(crate::error::AppError::NotFound)?;

    let conversation_id: Uuid = msg_row.get("conversation_id");
    let sender_id: Uuid = msg_row.get("sender_id");

    // Verify user is member of conversation
    let member = crate::middleware::guards::ConversationMember::verify(
        &state.db, // Use main DB pool for member check
        user.id,
        conversation_id,
    )
    .await?;

    // Verify user is the message sender or is an admin
    let is_own_message = sender_id == user.id;
    member.can_delete_message(is_own_message)?;

    // Delete message atomically with permission verification
    let deleted = sqlx::query(
        "UPDATE messages SET deleted_at = NOW()
         WHERE id = $1 AND sender_id = $2
         RETURNING id, conversation_id",
    )
    .bind(message_id)
    .bind(user.id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("delete message: {e}")))?
    .ok_or(crate::error::AppError::Forbidden)?; // Fails if user is not the sender

    tx.commit().await?;

    let deleted_conversation_id: Uuid = deleted.get("conversation_id");

    // Broadcast message.deleted event using unified event system
    let event = WebSocketEvent::MessageDeleted {
        conversation_id: deleted_conversation_id,
        message_id,
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        deleted_conversation_id,
        user.id,
        event,
    )
    .await;

    Ok(HttpResponse::NoContent().finish())
}

#[derive(Deserialize)]
pub struct SearchQuery {
    #[serde(default)]
    pub q: String,
    #[serde(default = "default_limit")]
    pub limit: i64,
    #[serde(default)]
    pub offset: i64,
    #[serde(default)]
    pub sort_by: Option<String>,
}

/// GET /conversations/:id/messages/search
/// Search messages within a conversation
///
/// Query parameters:
/// - q: Search query string (required)
/// - limit: Max results per page (default: 50, max: 500)
/// - offset: Number of results to skip (default: 0)
/// - sort_by: Sort order (recent|oldest|relevance, default: recent)
///
/// ARCHITECTURE NOTE (2025-10-26):
/// Message search is implemented using PostgreSQL full-text search (FTS).
/// - Messages are indexed via generated column `content_tsv`
/// - GIN index on `content_tsv` enables efficient lookups
/// - Database-level encryption (TDE) provides at-rest protection
/// - See: backend/ENCRYPTION_ARCHITECTURE.md for design rationale
pub async fn search_messages(
    state: web::Data<AppState>,
    user: User,
    conversation_id: web::Path<Uuid>,
    search: web::Query<SearchQuery>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = conversation_id.into_inner();
    // Verify user is member of conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // Validate search query is not empty
    if search.q.trim().is_empty() {
        return Ok(HttpResponse::Ok().json(Vec::<MessageDto>::new()));
    }

    // Execute search
    let (results, _total) = MessageService::search_messages(
        &state.db,
        conversation_id,
        &search.q,
        search.limit,
        search.offset,
        search.sort_by.as_deref(),
    )
    .await?;

    Ok(HttpResponse::Ok().json(results))
}

#[derive(Serialize)]
pub struct RecallMessageResponse {
    pub message_id: Uuid,
    pub recalled_at: String,
    pub status: String, // Always "recalled"
}

/// Recall (unsend) a message within 2 hours of sending
///
/// Business rules:
/// - Only message sender or conversation admin can recall
/// - Message must be within 2 hours of creation
/// - Already recalled messages cannot be recalled again
/// - Recall event is broadcast to all conversation members via WebSocket
/// - Audit log entry is created in message_recalls table
pub async fn recall_message(
    state: web::Data<AppState>,
    user: User,
    path: web::Path<(Uuid, Uuid)>,
) -> Result<HttpResponse, AppError> {
    let (conversation_id, message_id) = path.into_inner();
    // 1. Verify user is member of conversation and get permissions
    let member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // 2. Get message and verify it belongs to this conversation
    let msg_row = sqlx::query(
        "SELECT sender_id, created_at, recalled_at FROM messages WHERE id = $1 AND conversation_id = $2"
    )
    .bind(message_id)
    .bind(conversation_id)
    .fetch_optional(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("fetch message: {e}")))?
    .ok_or(crate::error::AppError::NotFound)?;

    let sender_id: Uuid = msg_row.get("sender_id");
    let created_at: chrono::DateTime<chrono::Utc> = msg_row.get("created_at");
    let recalled_at: Option<chrono::DateTime<chrono::Utc>> = msg_row.get("recalled_at");

    // 3. Verify user has permission to recall (sender or admin)
    let is_own_message = sender_id == user.id;
    if !is_own_message && !member.is_admin() {
        return Err(crate::error::AppError::Forbidden);
    }

    // 4. Check if message is already recalled
    if recalled_at.is_some() {
        return Err(crate::error::AppError::AlreadyRecalled);
    }

    // 5. Check 2-hour recall window
    const RECALL_WINDOW_MINUTES: i64 = 120;
    let now = chrono::Utc::now();
    let elapsed_minutes = (now - created_at).num_minutes();

    if elapsed_minutes > RECALL_WINDOW_MINUTES {
        return Err(crate::error::AppError::RecallWindowExpired {
            created_at,
            max_recall_minutes: RECALL_WINDOW_MINUTES,
        });
    }

    // 6. Execute recall in transaction (update message + insert audit log)
    let mut tx = state.db.begin().await?;

    // Update message to mark as recalled
    sqlx::query("UPDATE messages SET recalled_at = $1 WHERE id = $2")
        .bind(now)
        .bind(message_id)
        .execute(&mut *tx)
        .await?;

    // Insert audit log entry
    sqlx::query(
        "INSERT INTO message_recalls (message_id, recalled_by_user_id, recalled_at) VALUES ($1, $2, $3)"
    )
    .bind(message_id)
    .bind(user.id)
    .bind(now)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    // 7. Broadcast message.recalled event using unified event system
    let event = WebSocketEvent::MessageRecalled {
        conversation_id,
        message_id,
        recalled_by: user.id,
        recalled_at: now.to_rfc3339(),
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        user.id,
        event,
    )
    .await;

    // 8. Return success response
    Ok(HttpResponse::Ok().json(RecallMessageResponse {
        message_id,
        recalled_at: now.to_rfc3339(),
        status: "recalled".to_string(),
    }))
}

// MARK: - Message Forward

#[derive(serde::Deserialize)]
pub struct ForwardMessageRequest {
    pub target_conversation_id: uuid::Uuid,
    pub custom_note: Option<String>,
}

#[derive(serde::Serialize)]
pub struct ForwardMessageResponse {
    pub forwarded_message_id: uuid::Uuid,
    pub target_conversation_id: uuid::Uuid,
    pub forwarded_at: String,
}

pub async fn forward_message(
    state: web::Data<AppState>,
    user: User,
    path: web::Path<(Uuid, Uuid)>,
    body: web::Json<ForwardMessageRequest>,
) -> Result<HttpResponse, AppError> {
    let (conversation_id, message_id) = path.into_inner();
    // 1) Verify membership in source conversation
    let _source_member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // 2) Verify membership in target conversation
    let _target_member = crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        body.target_conversation_id,
    )
    .await?;

    // 3) Fetch original message content (plaintext)
    let original_content: String = sqlx::query_scalar(
        "SELECT content FROM messages WHERE id = $1 AND conversation_id = $2 AND deleted_at IS NULL",
    )
    .bind(message_id)
    .bind(conversation_id)
    .fetch_optional(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("fetch original message: {e}")))?
    .ok_or(crate::error::AppError::NotFound)?;

    // 4) Create new message in target conversation with same content
    let (new_message_id, _seq) = crate::services::message_service::MessageService::send_message_db(
        &state.db,
        &state.encryption,
        body.target_conversation_id,
        user.id,
        original_content.as_bytes(),
        None,
    )
    .await?;

    // 5) Optionally create a custom note message in target conversation
    if let Some(note) = &body.custom_note {
        let _ = crate::services::message_service::MessageService::send_message_db(
            &state.db,
            &state.encryption,
            body.target_conversation_id,
            user.id,
            note.as_bytes(),
            None,
        )
        .await?;
    }

    // 6) Broadcast message.new for forwarded message
    let now = chrono::Utc::now();
    let event = WebSocketEvent::MessageNew {
        id: new_message_id,
        sender_id: user.id,
        sequence_number: 0, // unknown here; clients can refresh
        conversation_id: body.target_conversation_id,
    };
    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        body.target_conversation_id,
        user.id,
        event,
    )
    .await;

    Ok(HttpResponse::Ok().json(ForwardMessageResponse {
        forwarded_message_id: new_message_id,
        target_conversation_id: body.target_conversation_id,
        forwarded_at: now.to_rfc3339(),
    }))
}

/// Send an audio message to a conversation
/// POST /conversations/{id}/messages/audio
pub async fn send_audio_message(
    state: web::Data<AppState>,
    user: User, // Authenticated user from JWT
    id: web::Path<Uuid>,
    body: web::Json<SendAudioMessageRequest>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = id.into_inner();

    // Verify user is member of conversation and has permission to send
    let member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    member.can_send()?;

    // Validate audio parameters (duration and codec)
    validate_audio_message(body.duration_ms, &body.audio_codec)?;

    // Store the audio message
    let (msg_id, seq) = MessageService::send_audio_message_db(
        &state.db,
        &state.encryption,
        conversation_id,
        user.id,
        &body.audio_url,
        body.duration_ms,
        &body.audio_codec,
        body.idempotency_key.as_deref(),
    )
    .await?;

    // Broadcast message.audio_sent event
    let event = WebSocketEvent::AudioMessageSent {
        id: msg_id,
        sender_id: user.id,
        sequence_number: seq,
        conversation_id,
        duration_ms: body.duration_ms,
        audio_codec: body.audio_codec.clone(),
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        user.id,
        event,
    )
    .await;

    // Fetch the created message details
    let created_at = chrono::Utc::now();

    let response = AudioMessageDto {
        id: msg_id,
        sender_id: user.id,
        sequence_number: seq,
        created_at: created_at.to_rfc3339(),
        audio_url: body.audio_url.clone(),
        duration_ms: body.duration_ms,
        audio_codec: body.audio_codec.clone(),
        transcription: None,
        transcription_language: None,
    };

    Ok(HttpResponse::Created().json(response))
}

// ======= Audio Upload Presigned URL =======

#[derive(Deserialize)]
pub struct AudioPresignedUrlRequest {
    pub file_name: String,
    pub content_type: String,
}

#[derive(Serialize)]
pub struct AudioPresignedUrlResponse {
    pub presigned_url: String,
    pub expiration: i64,
    pub s3_key: String,
}

/// Generate presigned URL for audio message upload to S3
///
/// This endpoint allows iOS clients to upload audio files directly to S3
/// without requiring AWS credentials. Returns a presigned URL valid for 1 hour.
pub async fn get_audio_presigned_url(
    state: web::Data<AppState>,
    user: User,
    id: web::Path<Uuid>,
    body: web::Json<AudioPresignedUrlRequest>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = id.into_inner();

    // Verify user is member of conversation and has permission to send
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // Validate request
    if body.file_name.is_empty() {
        return Err(crate::error::AppError::BadRequest(
            "file_name cannot be empty".into(),
        ));
    }

    if body.content_type.is_empty() {
        return Err(crate::error::AppError::BadRequest(
            "content_type cannot be empty".into(),
        ));
    }

    // Validate content type is audio
    if !body.content_type.starts_with("audio/") {
        return Err(crate::error::AppError::BadRequest(
            "content_type must be audio/* (e.g., audio/m4a, audio/mpeg)".into(),
        ));
    }

    // Generate unique S3 key with user ID and timestamp to prevent collisions
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let s3_key = format!("audio/{}/{}/{}", conversation_id, user.id, timestamp);

    // Expiration time: 1 hour from now (in seconds)
    let expiration_secs = 3600u64;

    // Build AWS SDK config (region + optional custom endpoint)
    let sdk_cfg = aws_config::from_env()
        .region(Region::new(state.config.s3.region.clone()))
        .load()
        .await;

    let mut s3_conf_builder = aws_sdk_s3::config::Builder::from(&sdk_cfg);
    if let Some(endpoint) = &state.config.s3.endpoint {
        s3_conf_builder = s3_conf_builder.endpoint_url(endpoint);
    }
    let s3_client = S3Client::from_conf(s3_conf_builder.build());

    let presign_cfg = PresigningConfig::builder()
        .expires_in(Duration::from_secs(expiration_secs))
        .build()
        .map_err(|e| AppError::Internal(format!("Failed to create presign config: {e}")))?;

    let presigned = s3_client
        .put_object()
        .bucket(&state.config.s3.bucket)
        .key(&s3_key)
        .content_type(&body.content_type)
        .presigned(presign_cfg)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to generate presigned URL: {e}")))?;

    let presigned_url = presigned.uri().to_string();

    tracing::info!(
        conversation_id = %conversation_id,
        user_id = %user.id,
        s3_key = %s3_key,
        expiration = expiration_secs as i64,
        "Generated presigned URL for audio upload"
    );

    Ok(HttpResponse::Ok().json(AudioPresignedUrlResponse {
        presigned_url,
        expiration: expiration_secs as i64,
        s3_key,
    }))
}
