use axum::{extract::{Path, State}, Json};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::{services::conversation_service::{ConversationService, ConversationDetails}, state::AppState};

#[derive(Serialize)]
pub struct ConversationResponse { 
    pub id: Uuid,
    pub member_count: i32,
    pub last_message_id: Option<Uuid>,
}

#[derive(Deserialize)]
pub struct CreateConversationRequest { pub user_a: Uuid, pub user_b: Uuid }

pub async fn create_conversation(
    State(state): State<AppState>,
    Json(body): Json<CreateConversationRequest>,
) -> Result<Json<ConversationResponse>, crate::error::AppError> {
    let id = ConversationService::create_direct_conversation(&state.db, body.user_a, body.user_b).await?;
    // fetch details for response
    let details = ConversationService::get_conversation_db(&state.db, id).await?;
    Ok(Json(ConversationResponse { id: details.id, member_count: details.member_count, last_message_id: details.last_message_id }))
}

pub async fn get_conversation(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<ConversationResponse>, crate::error::AppError> {
    let details = ConversationService::get_conversation_db(&state.db, id).await?;
    Ok(Json(ConversationResponse { id: details.id, member_count: details.member_count, last_message_id: details.last_message_id }))
}
