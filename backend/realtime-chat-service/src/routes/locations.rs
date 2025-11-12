/// Location sharing endpoints
///
/// Handles real-time location sharing in conversations.
/// Supports sharing, updating, and stopping location broadcasts.
use crate::error::AppError;
use crate::middleware::guards::User;
use crate::models::location::*;
use crate::services::location_service::LocationService;
use crate::websocket::events::{broadcast_event, WebSocketEvent};
use uuid::Uuid;

use crate::state::AppState;
use actix_web::{delete, get, post, web, HttpResponse};

/// Share or update location in a conversation
///
/// Starts sharing location or updates existing share in a conversation.
/// Only one active location per user per conversation.
///
/// **Endpoint**: `POST /conversations/:id/location`
#[post("/conversations/{conversation_id}/location")]
pub async fn share_location(
    state: web::Data<AppState>,
    user: User,
    conversation_id: web::Path<Uuid>,
    request: web::Json<ShareLocationRequest>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = conversation_id.into_inner();
    let location =
        LocationService::start_sharing(&state.db, user.id, conversation_id, request.into_inner())
            .await?;

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

    Ok(HttpResponse::Ok().json(location))
}

/// Get all active locations in a conversation
///
/// Returns all users currently sharing location in this conversation.
///
/// **Endpoint**: `GET /conversations/:id/locations`
pub async fn get_conversation_locations(
    state: web::Data<AppState>,
    conversation_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = conversation_id.into_inner();
    let locations = LocationService::get_conversation_locations(&state.db, conversation_id).await?;

    Ok(HttpResponse::Ok().json(locations))
}

/// Get a specific user's location in a conversation
///
/// Returns the active location share for a specific user in a conversation.
/// Returns 404 if user is not sharing location.
///
/// **Endpoint**: `GET /conversations/:id/location/:user_id`
pub async fn get_user_location(
    state: web::Data<AppState>,
    path: web::Path<(Uuid, Uuid)>,
) -> Result<HttpResponse, AppError> {
    let (conversation_id, target_user_id) = path.into_inner();
    let location =
        LocationService::get_user_location(&state.db, target_user_id, conversation_id).await?;

    match location {
        Some(loc) => Ok(HttpResponse::Ok().json(loc)),
        None => Err(AppError::NotFound),
    }
}

/// Stop sharing location
///
/// Stops the active location share in a conversation.
///
/// **Endpoint**: `POST /conversations/:id/location/stop`
#[delete("/conversations/{conversation_id}/location")]
pub async fn stop_sharing_location(
    state: web::Data<AppState>,
    user: User,
    conversation_id: web::Path<Uuid>,
    request: web::Json<StopSharingRequest>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = conversation_id.into_inner();
    LocationService::stop_sharing(&state.db, user.id, conversation_id, request.into_inner())
        .await?;

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

    Ok(HttpResponse::Ok().json(serde_json::json!({ "status": "stopped" })))
}

/// Get location permissions
///
/// Returns the current user's location sharing settings.
///
/// **Endpoint**: `GET /location/permissions`
pub async fn get_location_permissions(
    state: web::Data<AppState>,
    user: User,
) -> Result<HttpResponse, AppError> {
    let perm = LocationService::get_or_create_permission(&state.db, user.id).await?;

    Ok(HttpResponse::Ok().json(LocationPermissionResponse::from(perm)))
}

/// Update location permissions
///
/// Updates the current user's location sharing settings.
///
/// **Endpoint**: `PUT /location/permissions`
pub async fn update_location_permissions(
    state: web::Data<AppState>,
    user: User,
    request: web::Json<UpdateLocationPermissionsRequest>,
) -> Result<HttpResponse, AppError> {
    let perm =
        LocationService::update_permissions(&state.db, user.id, request.into_inner()).await?;

    Ok(HttpResponse::Ok().json(LocationPermissionResponse::from(perm)))
}

/// Get location sharing statistics
///
/// Returns statistics about location sharing in a conversation.
///
/// **Endpoint**: `GET /conversations/:id/location/stats`
pub async fn get_location_stats(
    state: web::Data<AppState>,
    conversation_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = conversation_id.into_inner();
    let stats = LocationService::get_sharing_stats(&state.db, conversation_id).await?;

    Ok(HttpResponse::Ok().json(stats))
}

// TODO: Implement get_nearby_users - find users near a location
#[get("/nearby-users")]
pub async fn get_nearby_users(
    _state: web::Data<AppState>,
    _user: User,
) -> Result<HttpResponse, AppError> {
    // TODO: Implement nearby users query
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "users": []
    })))
}
