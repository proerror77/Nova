use axum::{extract::{Path, State, Query}, Json, http::StatusCode};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use std::collections::HashMap;
use crate::{state::AppState, websocket::pubsub, error::AppError};

#[derive(Deserialize)]
pub struct AddReactionRequest {
    pub emoji: String,  // Unicode emoji or emoji code
}

#[derive(Serialize)]
pub struct ReactionCount {
    pub emoji: String,
    pub count: i64,
    pub user_reacted: bool,  // Whether current user has this reaction
}

#[derive(Serialize)]
pub struct ReactionsResponse {
    pub message_id: Uuid,
    pub reactions: Vec<ReactionCount>,
}

/// POST /messages/{id}/reactions
/// Add or update a reaction to a message
pub async fn add_reaction(
    State(state): State<AppState>,
    Path(message_id): Path<Uuid>,
    Json(body): Json<AddReactionRequest>,
) -> Result<StatusCode, AppError> {
    // Validate emoji length (basic check)
    if body.emoji.is_empty() || body.emoji.len() > 20 {
        return Err(AppError::BadRequest("Invalid emoji".into()));
    }

    // Add or update reaction (ON CONFLICT updates the reaction)
    sqlx::query(
        r#"
        INSERT INTO message_reactions (message_id, user_id, emoji)
        VALUES ($1, $2, $3)
        ON CONFLICT (message_id, user_id, emoji) DO NOTHING
        "#
    )
    .bind(message_id)
    .bind(Uuid::nil())  // Will be set by middleware with actual user_id
    .bind(&body.emoji)
    .execute(&state.db)
    .await
    .map_err(|e| AppError::StartServer(format!("Failed to add reaction: {e}")))?;

    // Broadcast reaction event
    let payload = serde_json::json!({
        "type": "reaction_added",
        "message_id": message_id,
        "emoji": body.emoji,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }).to_string();

    state.registry.broadcast(message_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = pubsub::publish(&state.redis, message_id, &payload).await;

    Ok(StatusCode::CREATED)
}

/// GET /messages/{id}/reactions
/// Get all reactions for a message with counts
pub async fn get_reactions(
    State(state): State<AppState>,
    Path(message_id): Path<Uuid>,
) -> Result<Json<ReactionsResponse>, AppError> {
    let reactions = sqlx::query_as::<_, (String, i64)>(
        r#"
        SELECT emoji, COUNT(*) as count
        FROM message_reactions
        WHERE message_id = $1
        GROUP BY emoji
        ORDER BY count DESC
        "#
    )
    .bind(message_id)
    .fetch_all(&state.db)
    .await
    .map_err(|e| AppError::StartServer(format!("Failed to fetch reactions: {e}")))?;

    let reaction_counts: Vec<ReactionCount> = reactions
        .into_iter()
        .map(|(emoji, count)| ReactionCount {
            emoji,
            count,
            user_reacted: false,  // TODO: Check if current user has this reaction
        })
        .collect();

    Ok(Json(ReactionsResponse {
        message_id,
        reactions: reaction_counts,
    }))
}

/// DELETE /messages/{id}/reactions/{user_id}
/// Remove a user's reactions from a message
pub async fn remove_reaction(
    State(state): State<AppState>,
    Path((message_id, user_id)): Path<(Uuid, Uuid)>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<StatusCode, AppError> {
    // If emoji query param provided, delete only that reaction
    if let Some(emoji) = params.get("emoji") {
        sqlx::query(
            "DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2 AND emoji = $3"
        )
        .bind(message_id)
        .bind(user_id)
        .bind(emoji)
        .execute(&state.db)
        .await
        .map_err(|e| AppError::StartServer(format!("Failed to remove reaction: {e}")))?;

        // Broadcast reaction removed event
        let payload = serde_json::json!({
            "type": "reaction_removed",
            "message_id": message_id,
            "user_id": user_id,
            "emoji": emoji,
            "timestamp": chrono::Utc::now().to_rfc3339(),
        }).to_string();

        state.registry.broadcast(message_id, axum::extract::ws::Message::Text(payload.clone())).await;
        let _ = pubsub::publish(&state.redis, message_id, &payload).await;
    } else {
        // Delete all reactions by this user for this message
        sqlx::query(
            "DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2"
        )
        .bind(message_id)
        .bind(user_id)
        .execute(&state.db)
        .await
        .map_err(|e| AppError::StartServer(format!("Failed to remove reactions: {e}")))?;

        // Broadcast reactions removed event
        let payload = serde_json::json!({
            "type": "reactions_removed",
            "message_id": message_id,
            "user_id": user_id,
            "timestamp": chrono::Utc::now().to_rfc3339(),
        }).to_string();

        state.registry.broadcast(message_id, axum::extract::ws::Message::Text(payload.clone())).await;
        let _ = pubsub::publish(&state.redis, message_id, &payload).await;
    }

    Ok(StatusCode::NO_CONTENT)
}
