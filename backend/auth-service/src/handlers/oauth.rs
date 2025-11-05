/// OAuth handlers
use actix_web::{web, HttpResponse};
use serde::Serialize;
use uuid::Uuid;

use crate::{
    error::AuthError,
    models::oauth::{CompleteOAuthFlowRequest, OAuthProvider, StartOAuthFlowRequest},
    AppState,
};

/// OAuth flow start response
#[derive(Debug, Serialize)]
pub struct StartOAuthFlowResponse {
    pub auth_url: String,
    pub state: String,
}

/// OAuth completion response with tokens
#[derive(Debug, Serialize)]
pub struct OAuthLoginResponse {
    pub user_id: Uuid,
    pub email: String,
    pub access_token: String,
    pub refresh_token: String,
    pub is_new_user: bool,
}

/// Start OAuth authorization flow
pub async fn start_oauth_flow(
    state: web::Data<AppState>,
    payload: web::Json<StartOAuthFlowRequest>,
) -> Result<HttpResponse, AuthError> {
    let provider =
        OAuthProvider::from_str(&payload.provider).ok_or(AuthError::InvalidOAuthProvider)?;

    let (state_token, auth_url) = state
        .oauth_service
        .start_flow(provider, payload.redirect_uri.clone())
        .await?;

    Ok(HttpResponse::Ok().json(StartOAuthFlowResponse {
        auth_url,
        state: state_token,
    }))
}

/// Complete OAuth authorization flow
pub async fn complete_oauth_flow(
    state: web::Data<AppState>,
    payload: web::Json<CompleteOAuthFlowRequest>,
) -> Result<HttpResponse, AuthError> {
    let provider =
        OAuthProvider::from_str(&payload.provider).ok_or(AuthError::InvalidOAuthProvider)?;

    let login = state
        .oauth_service
        .complete_flow(provider, &payload.code, &payload.state)
        .await?;

    Ok(HttpResponse::Ok().json(OAuthLoginResponse {
        user_id: login.user_id,
        email: login.email,
        access_token: login.access_token,
        refresh_token: login.refresh_token,
        is_new_user: login.is_new_user,
    }))
}
