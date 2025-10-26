use crate::{error::AppError, middleware::guards::User, state::AppState};
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct CreateAttachmentRequest {
    pub file_name: String,
    pub file_type: Option<String>, // MIME type
    pub file_size: i32,            // bytes
    pub s3_key: String,            // S3 object key for retrieval
}

#[derive(Serialize)]
pub struct AttachmentResponse {
    pub id: Uuid,
    pub message_id: Uuid,
    pub file_name: String,
    pub file_type: Option<String>,
    pub file_size: i32,
    pub s3_key: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Serialize)]
pub struct AttachmentsListResponse {
    pub message_id: Uuid,
    pub attachments: Vec<AttachmentResponse>,
    pub count: usize,
}

/// POST /conversations/{id}/messages/{message_id}/attachments
/// Create/upload a file attachment for a message
///
/// Permission: User must be the message sender or a conversation admin
pub async fn upload_attachment(
    State(state): State<AppState>,
    user: User,
    Path((conversation_id, message_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<CreateAttachmentRequest>,
) -> Result<Json<AttachmentResponse>, AppError> {
    // Validate input
    if body.file_name.is_empty() || body.file_name.len() > 255 {
        return Err(AppError::BadRequest("Invalid file name".into()));
    }

    if body.file_size <= 0 || body.file_size > 100_000_000 {
        // 100MB limit
        return Err(AppError::BadRequest("Invalid file size".into()));
    }

    if body.s3_key.is_empty() || body.s3_key.len() > 500 {
        return Err(AppError::BadRequest("Invalid S3 key".into()));
    }

    // Verify user is member of conversation
    let member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // Verify message exists and user has permission to attach
    let message_row = sqlx::query("SELECT sender_id, conversation_id FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| AppError::StartServer(format!("Failed to verify message: {e}")))?
        .ok_or(AppError::NotFound)?;

    let sender_id: uuid::Uuid = message_row.get("sender_id");
    let msg_conversation_id: uuid::Uuid = message_row.get("conversation_id");

    // Ensure message belongs to this conversation
    if msg_conversation_id != conversation_id {
        return Err(AppError::Forbidden);
    }

    // Check permission: message sender or conversation admin
    let is_sender = sender_id == user.id;
    if !is_sender && !member.is_admin() {
        return Err(AppError::Forbidden);
    }

    // Create attachment record
    let id = Uuid::new_v4();
    let now = Utc::now();

    sqlx::query(
        r#"
        INSERT INTO message_attachments (id, message_id, file_name, file_type, file_size, s3_key, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        "#
    )
    .bind(id)
    .bind(message_id)
    .bind(&body.file_name)
    .bind(&body.file_type)
    .bind(body.file_size)
    .bind(&body.s3_key)
    .bind(now)
    .execute(&state.db)
    .await
    .map_err(|e| AppError::StartServer(format!("Failed to create attachment: {e}")))?;

    Ok(Json(AttachmentResponse {
        id,
        message_id,
        file_name: body.file_name,
        file_type: body.file_type,
        file_size: body.file_size,
        s3_key: body.s3_key,
        created_at: now,
    }))
}

/// GET /messages/{id}/attachments
/// Get all attachments for a message
///
/// Permission: User must be a member of the conversation containing this message
pub async fn get_attachments(
    State(state): State<AppState>,
    user: User,
    Path(message_id): Path<Uuid>,
) -> Result<Json<AttachmentsListResponse>, AppError> {
    // Get message's conversation to verify user access
    let message_row = sqlx::query("SELECT conversation_id FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| AppError::StartServer(format!("Failed to fetch message: {e}")))?
        .ok_or(AppError::NotFound)?;

    let conversation_id: Uuid = message_row.get("conversation_id");

    // Verify user is member of conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    let attachments = sqlx::query_as::<
        _,
        (
            Uuid,
            Uuid,
            String,
            Option<String>,
            i32,
            String,
            DateTime<Utc>,
        ),
    >(
        r#"
        SELECT id, message_id, file_name, file_type, file_size, s3_key, created_at
        FROM message_attachments
        WHERE message_id = $1
        ORDER BY created_at DESC
        "#,
    )
    .bind(message_id)
    .fetch_all(&state.db)
    .await
    .map_err(|e| AppError::StartServer(format!("Failed to fetch attachments: {e}")))?;

    let attachment_list: Vec<AttachmentResponse> = attachments
        .into_iter()
        .map(
            |(id, msg_id, file_name, file_type, file_size, s3_key, created_at)| {
                AttachmentResponse {
                    id,
                    message_id: msg_id,
                    file_name,
                    file_type,
                    file_size,
                    s3_key,
                    created_at,
                }
            },
        )
        .collect();

    let count = attachment_list.len();

    Ok(Json(AttachmentsListResponse {
        message_id,
        attachments: attachment_list,
        count,
    }))
}

/// DELETE /messages/{id}/attachments/{attachment_id}
/// Delete a file attachment
///
/// Permission: User must be the message sender or a conversation admin
pub async fn delete_attachment(
    State(state): State<AppState>,
    user: User,
    Path((message_id, attachment_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    // Get attachment and message details for authorization
    let attachment_row =
        sqlx::query("SELECT ma.message_id FROM message_attachments ma WHERE ma.id = $1")
            .bind(attachment_id)
            .fetch_optional(&state.db)
            .await
            .map_err(|e| AppError::StartServer(format!("Failed to fetch attachment: {e}")))?
            .ok_or(AppError::NotFound)?;

    // Verify message matches
    let msg_id: Uuid = attachment_row.get("message_id");
    if msg_id != message_id {
        return Err(AppError::NotFound);
    }

    // Get message details to verify user permission
    let message_row = sqlx::query("SELECT sender_id, conversation_id FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| AppError::StartServer(format!("Failed to fetch message: {e}")))?
        .ok_or(AppError::NotFound)?;

    let sender_id: Uuid = message_row.get("sender_id");
    let conversation_id: Uuid = message_row.get("conversation_id");

    // Verify user is member of conversation
    let member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // Check permission: message sender or conversation admin
    let is_sender = sender_id == user.id;
    if !is_sender && !member.is_admin() {
        return Err(AppError::Forbidden);
    }

    let affected = sqlx::query("DELETE FROM message_attachments WHERE id = $1")
        .bind(attachment_id)
        .execute(&state.db)
        .await
        .map_err(|e| AppError::StartServer(format!("Failed to delete attachment: {e}")))?
        .rows_affected();

    if affected == 0 {
        return Err(AppError::NotFound);
    }

    Ok(StatusCode::NO_CONTENT)
}
