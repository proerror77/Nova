/// Location sharing endpoints
///
/// Handles real-time location sharing in conversations.
/// Supports sharing, updating, and stopping location broadcasts.
use crate::error::AppError;
use crate::middleware::guards::User;
use crate::models::location::*;
use crate::services::location_service::LocationService;
use crate::websocket::events::{broadcast_event, WebSocketEvent};
use axum::{
    extract::{Path, State},
    Json,
};
use uuid::Uuid;

use crate::state::AppState;

/// Share or update location in a conversation
///
/// Starts sharing location or updates existing share in a conversation.
/// Only one active location per user per conversation.
///
/// **Endpoint**: `POST /conversations/:id/location`
pub async fn share_location(
    State(state): State<AppState>,
    user: User,
    Path(conversation_id): Path<Uuid>,
    Json(request): Json<ShareLocationRequest>,
) -> Result<Json<SharedLocation>, AppError> {
    let location =
        LocationService::start_sharing(&state.db, user.id, conversation_id, request).await?;

    // Broadcast location shared event
    let event = WebSocketEvent::LocationShared {
        user_id: user.id,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy_meters: location.accuracy_meters,
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        user.id,
        event,
    )
    .await;

    Ok(Json(location))
}

/// Get all active locations in a conversation
///
/// Returns all users currently sharing location in this conversation.
///
/// **Endpoint**: `GET /conversations/:id/locations`
pub async fn get_conversation_locations(
    State(state): State<AppState>,
    Path(conversation_id): Path<Uuid>,
) -> Result<Json<ConversationLocations>, AppError> {
    let locations = LocationService::get_conversation_locations(&state.db, conversation_id).await?;

    Ok(Json(locations))
}

/// Get a specific user's location in a conversation
///
/// Returns the active location share for a specific user in a conversation.
/// Returns 404 if user is not sharing location.
///
/// **Endpoint**: `GET /conversations/:id/location/:user_id`
pub async fn get_user_location(
    State(state): State<AppState>,
    Path((conversation_id, target_user_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<SharedLocation>, AppError> {
    let location =
        LocationService::get_user_location(&state.db, target_user_id, conversation_id).await?;

    match location {
        Some(loc) => Ok(Json(loc)),
        None => Err(AppError::NotFound),
    }
}

/// Stop sharing location
///
/// Stops the active location share in a conversation.
///
/// **Endpoint**: `POST /conversations/:id/location/stop`
pub async fn stop_sharing_location(
    State(state): State<AppState>,
    user: User,
    Path(conversation_id): Path<Uuid>,
    Json(request): Json<StopSharingRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    LocationService::stop_sharing(&state.db, user.id, conversation_id, request).await?;

    // Broadcast location stopped event
    let event = WebSocketEvent::LocationStopped { user_id: user.id };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        user.id,
        event,
    )
    .await;

    Ok(Json(serde_json::json!({ "status": "stopped" })))
}

/// Get location permissions
///
/// Returns the current user's location sharing settings.
///
/// **Endpoint**: `GET /location/permissions`
pub async fn get_location_permissions(
    State(state): State<AppState>,
    user: User,
) -> Result<Json<LocationPermissionResponse>, AppError> {
    let perm = LocationService::get_or_create_permission(&state.db, user.id).await?;

    Ok(Json(LocationPermissionResponse::from(perm)))
}

/// Update location permissions
///
/// Updates the current user's location sharing settings.
///
/// **Endpoint**: `PUT /location/permissions`
pub async fn update_location_permissions(
    State(state): State<AppState>,
    user: User,
    Json(request): Json<UpdateLocationPermissionsRequest>,
) -> Result<Json<LocationPermissionResponse>, AppError> {
    let perm = LocationService::update_permissions(&state.db, user.id, request).await?;

    Ok(Json(LocationPermissionResponse::from(perm)))
}

/// Get location sharing statistics
///
/// Returns statistics about location sharing in a conversation.
///
/// **Endpoint**: `GET /conversations/:id/location/stats`
pub async fn get_location_stats(
    State(state): State<AppState>,
    Path(conversation_id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    let stats = LocationService::get_sharing_stats(&state.db, conversation_id).await?;

    Ok(Json(stats))
}
