use axum::{extract::State, http::StatusCode, response::IntoResponse, Json};
use serde_json::json;
use std::sync::Arc;

use crate::{
    models::{
        EmailVerificationRequest, LoginRequest, LogoutRequest, RegisterRequest, TokenRefreshRequest,
    },
    services::AuthService,
    AppState,
};

pub async fn register(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterRequest>,
) -> impl IntoResponse {
    let service = AuthService::new(state.db.clone(), "dev_secret".to_string());

    match service
        .register(&payload.email, &payload.username, &payload.password)
        .await
    {
        Ok(_) => (
            StatusCode::CREATED,
            Json(json!({
                "message": "User registered successfully. Please verify your email."
            })),
        )
            .into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn login(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginRequest>,
) -> impl IntoResponse {
    let service = AuthService::new(state.db.clone(), "dev_secret".to_string());

    match service.login(&payload.email, &payload.password).await {
        Ok(response) => (StatusCode::OK, Json(response)).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn verify_email(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<EmailVerificationRequest>,
) -> impl IntoResponse {
    // Extract user_id from JWT (simplified, should use middleware)
    let user_id = uuid::Uuid::new_v4();

    let service = AuthService::new(state.db.clone(), "dev_secret".to_string());

    match service.verify_email(user_id, &payload.token).await {
        Ok(_) => (
            StatusCode::OK,
            Json(json!({
                "message": "Email verified successfully"
            })),
        )
            .into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn refresh_token(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<TokenRefreshRequest>,
) -> impl IntoResponse {
    let service = AuthService::new(state.db.clone(), "dev_secret".to_string());

    match service.refresh_token(&payload.refresh_token).await {
        Ok(response) => (StatusCode::OK, Json(response)).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn logout(
    State(state): State<Arc<AppState>>,
    Json(_payload): Json<LogoutRequest>,
) -> impl IntoResponse {
    // Extract user_id from JWT (simplified, should use middleware)
    let user_id = uuid::Uuid::new_v4();

    let service = AuthService::new(state.db.clone(), "dev_secret".to_string());

    match service.logout(user_id).await {
        Ok(_) => (
            StatusCode::OK,
            Json(json!({
                "message": "Logged out successfully"
            })),
        )
            .into_response(),
        Err(e) => e.into_response(),
    }
}
