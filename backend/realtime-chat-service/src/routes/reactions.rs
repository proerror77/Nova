use crate::{
    error::AppError,
    middleware::guards::User,
    state::AppState,
    websocket::events::{broadcast_event, WebSocketEvent},
};
use actix_web::{delete, get, post, web, HttpResponse};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct AddReactionRequest {
    pub emoji: String, // Unicode emoji or emoji code
}

#[derive(Serialize)]
pub struct ReactionCount {
    pub emoji: String,
    pub count: i64,
    pub user_reacted: bool, // Whether current user has this reaction
}

#[derive(Serialize)]
pub struct ReactionsResponse {
    pub message_id: Uuid,
    pub reactions: Vec<ReactionCount>,
}

/// POST /messages/{id}/reactions
/// Add or update a reaction to a message
#[post("/messages/{id}/reactions")]
pub async fn add_reaction(
    state: web::Data<AppState>,
    message_id: web::Path<Uuid>,
    user: User,
    body: web::Json<AddReactionRequest>,
) -> Result<HttpResponse, AppError> {
    let message_id = message_id.into_inner();
    let user_id = user.id;

    // Validate emoji length (basic check)
    if body.emoji.is_empty() || body.emoji.len() > 20 {
        return Err(AppError::BadRequest("Invalid emoji".into()));
    }

    // Get conversation_id for the message (for broadcasting on conversation channel)
    let client = state.db.get().await
        .map_err(|e| AppError::StartServer(format!("fetch message: {e}")))?;

    let message_row = client.query_opt("SELECT conversation_id FROM messages WHERE id = $1", &[&message_id])
        .await
        .map_err(|e| AppError::StartServer(format!("fetch message: {e}")))?
        .ok_or(AppError::NotFound)?;

    let conversation_id: Uuid = message_row.get("conversation_id");

    // Add or update reaction (ON CONFLICT updates the reaction)
    client.execute(
        r#"
        INSERT INTO message_reactions (message_id, user_id, emoji)
        VALUES ($1, $2, $3)
        ON CONFLICT (message_id, user_id, emoji) DO NOTHING
        "#,
        &[&message_id, &user_id, &body.emoji]
    )
    .await
    .map_err(|e| AppError::StartServer(format!("Failed to add reaction: {e}")))?;

    // Broadcast reaction.added event using unified event system
    let event = WebSocketEvent::ReactionAdded {
        message_id,
        emoji: body.emoji.clone(),
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        user_id,
        event,
    )
    .await;

    Ok(HttpResponse::Created().finish())
}

/// GET /messages/{id}/reactions
/// Get all reactions for a message with counts and whether current user has reacted
#[get("/messages/{id}/reactions")]
pub async fn get_reactions(
    state: web::Data<AppState>,
    message_id: web::Path<Uuid>,
    user: User,
) -> Result<HttpResponse, AppError> {
    let message_id = message_id.into_inner();
    let user_id = user.id;

    // Fetch all reactions with counts for this message
    let client = state.db.get().await
        .map_err(|e| AppError::StartServer(format!("Failed to fetch reactions: {e}")))?;

    let reactions = client.query(
        r#"
        SELECT emoji, COUNT(*) as count
        FROM message_reactions
        WHERE message_id = $1
        GROUP BY emoji
        ORDER BY count DESC
        "#,
        &[&message_id]
    )
    .await
    .map_err(|e| AppError::StartServer(format!("Failed to fetch reactions: {e}")))?;

    let reactions: Vec<(String, i64)> = reactions.iter()
        .map(|row| (row.get(0), row.get(1)))
        .collect();

    // Fetch reactions by current user for this message
    let user_reactions = client.query(
        r#"
        SELECT DISTINCT emoji
        FROM message_reactions
        WHERE message_id = $1 AND user_id = $2
        "#,
        &[&message_id, &user_id]
    )
    .await
    .map_err(|e| AppError::StartServer(format!("Failed to fetch user reactions: {e}")))?;

    // Convert to HashSet for O(1) lookup
    let user_reactions_set: std::collections::HashSet<String> =
        user_reactions.iter().map(|row| row.get::<_, String>(0)).collect();

    // Build response with user_reacted flag
    let reaction_counts: Vec<ReactionCount> = reactions
        .into_iter()
        .map(|(emoji, count)| ReactionCount {
            emoji: emoji.clone(),
            count,
            user_reacted: user_reactions_set.contains(&emoji),
        })
        .collect();

    Ok(HttpResponse::Ok().json(ReactionsResponse {
        message_id,
        reactions: reaction_counts,
    }))
}

/// DELETE /messages/{id}/reactions/{user_id}
/// Remove a user's reactions from a message
///
/// Authorization:
/// - Users can only remove their own reactions
/// - OR conversation admins can remove any reaction
#[delete("/messages/{message_id}/reactions/{reaction_id}")]
pub async fn remove_reaction(
    state: web::Data<AppState>,
    user: User, // From auth middleware
    path: web::Path<(Uuid, Uuid)>,
    params: web::Query<HashMap<String, String>>,
) -> Result<HttpResponse, AppError> {
    let (message_id, target_user_id) = path.into_inner();

    // 1. Get message and conversation_id to check admin status
    let client = state.db.get().await
        .map_err(|e| AppError::StartServer(format!("fetch message: {e}")))?;

    let message_row = client.query_opt("SELECT conversation_id FROM messages WHERE id = $1", &[&message_id])
        .await
        .map_err(|e| AppError::StartServer(format!("fetch message: {e}")))?
        .ok_or(AppError::NotFound)?;

    let conversation_id: Uuid = message_row.get("conversation_id");

    // 2. Check authorization: either own reaction OR admin
    let is_own_reaction = user.id == target_user_id;

    if !is_own_reaction {
        // Verify requester is admin of conversation
        let member = crate::middleware::guards::ConversationMember::verify(
            &state.db,
            user.id,
            conversation_id,
        )
        .await?;

        if !member.is_admin() {
            return Err(AppError::Forbidden);
        }
    }

    // 3. Delete reaction(s)
    if let Some(emoji) = params.get("emoji") {
        // Delete specific emoji reaction
        let result = client.query_opt(
            "DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2 AND emoji = $3 RETURNING id",
            &[&message_id, &target_user_id, emoji]
        )
        .await
        .map_err(|e| AppError::StartServer(format!("Failed to remove reaction: {e}")))?;

        if result.is_none() {
            return Err(AppError::NotFound);
        }

        // Broadcast reaction.removed event using unified event system
        let event = WebSocketEvent::ReactionRemoved {
            message_id,
            emoji: emoji.clone(),
        };

        let _ = broadcast_event(
            &state.registry,
            &state.redis,
            conversation_id,
            user.id,
            event,
        )
        .await;
    } else {
        // Delete all reactions by this user for this message
        client.execute("DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2", &[&message_id, &target_user_id])
            .await
            .map_err(|e| AppError::StartServer(format!("Failed to remove reactions: {e}")))?;

        // Broadcast reaction.removed_all event using unified event system
        let event = WebSocketEvent::ReactionRemovedAll { message_id };

        let _ = broadcast_event(
            &state.registry,
            &state.redis,
            conversation_id,
            user.id,
            event,
        )
        .await;
    }

    Ok(HttpResponse::NoContent().finish())
}
