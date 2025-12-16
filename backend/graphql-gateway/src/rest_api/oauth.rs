//! OAuth REST API endpoints for mobile clients
//!
//! Handles OAuth authentication flows (Google, Apple) for iOS/Android apps.
//! Uses a redirect-based flow where:
//! 1. Client calls /start to get authorization URL
//! 2. User authenticates in browser
//! 3. Provider redirects to /callback endpoint
//! 4. Backend exchanges code for tokens and redirects to app with custom URL scheme

use actix_web::{web, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::auth::{
    AppleNativeSignInRequest as GrpcAppleNativeSignInRequest, CompleteOAuthFlowRequest,
    OAuthProvider, StartOAuthFlowRequest,
};
use crate::clients::ServiceClients;
use crate::rest_api::models::ErrorResponse;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct OAuthStartRequest {
    pub redirect_uri: String,
}

#[derive(Debug, Serialize)]
pub struct OAuthStartResponse {
    pub authorization_url: String,
    pub state: String,
}

#[derive(Debug, Deserialize)]
pub struct OAuthCallbackQuery {
    pub code: String,
    pub state: String,
}

#[derive(Debug, Deserialize)]
pub struct OAuthCallbackRequest {
    pub code: String,
    pub state: String,
    pub redirect_uri: String,
}

#[derive(Debug, Serialize)]
pub struct OAuthCallbackResponse {
    pub user_id: String,
    pub token: String,
    pub refresh_token: Option<String>,
    pub expires_in: i64,
    pub is_new_user: bool,
    pub user: Option<UserProfileResponse>,
}

#[derive(Debug, Serialize)]
pub struct UserProfileResponse {
    pub id: String,
    pub username: String,
    pub email: Option<String>,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
}

// ============================================================================
// OAuth Start Endpoints
// ============================================================================

/// Start Google OAuth flow - returns authorization URL
///
/// POST /api/v2/auth/oauth/google/start
pub async fn google_oauth_start(
    clients: web::Data<ServiceClients>,
    body: web::Json<OAuthStartRequest>,
) -> Result<HttpResponse> {
    oauth_start(clients, OAuthProvider::OauthProviderGoogle, &body.redirect_uri).await
}

/// Start Apple OAuth flow - returns authorization URL
///
/// POST /api/v2/auth/oauth/apple/start
pub async fn apple_oauth_start(
    clients: web::Data<ServiceClients>,
    body: web::Json<OAuthStartRequest>,
) -> Result<HttpResponse> {
    oauth_start(clients, OAuthProvider::OauthProviderApple, &body.redirect_uri).await
}

async fn oauth_start(
    clients: web::Data<ServiceClients>,
    provider: OAuthProvider,
    redirect_uri: &str,
) -> Result<HttpResponse> {
    let provider_name = match provider {
        OAuthProvider::OauthProviderGoogle => "google",
        OAuthProvider::OauthProviderApple => "apple",
        _ => "unknown",
    };

    info!(provider = %provider_name, redirect_uri = %redirect_uri, "Starting OAuth flow");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(StartOAuthFlowRequest {
        provider: provider.into(),
        redirect_uri: redirect_uri.to_string(),
        invite_code: None,
    });

    match auth_client.start_o_auth_flow(grpc_request).await {
        Ok(response) => {
            let res = response.into_inner();
            info!(provider = %provider_name, "OAuth flow started successfully");
            Ok(HttpResponse::Ok().json(OAuthStartResponse {
                authorization_url: res.authorization_url,
                state: res.state,
            }))
        }
        Err(status) => {
            error!(provider = %provider_name, error = %status, "Failed to start OAuth flow");
            Ok(HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "oauth_start_failed",
                &format!("Failed to start OAuth flow: {}", status.message()),
            )))
        }
    }
}

// ============================================================================
// OAuth Callback Endpoints (POST - for client-side code exchange)
// ============================================================================

/// Complete Google OAuth flow - exchange code for tokens
///
/// POST /api/v2/auth/oauth/google/callback
pub async fn google_oauth_callback_post(
    clients: web::Data<ServiceClients>,
    body: web::Json<OAuthCallbackRequest>,
) -> Result<HttpResponse> {
    oauth_callback_post(clients, "google", &body).await
}

/// Complete Apple OAuth flow - exchange code for tokens
///
/// POST /api/v2/auth/oauth/apple/callback
pub async fn apple_oauth_callback_post(
    clients: web::Data<ServiceClients>,
    body: web::Json<OAuthCallbackRequest>,
) -> Result<HttpResponse> {
    oauth_callback_post(clients, "apple", &body).await
}

async fn oauth_callback_post(
    clients: web::Data<ServiceClients>,
    provider: &str,
    body: &OAuthCallbackRequest,
) -> Result<HttpResponse> {
    info!(provider = %provider, "Processing OAuth callback (POST)");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(CompleteOAuthFlowRequest {
        state: body.state.clone(),
        code: body.code.clone(),
        redirect_uri: body.redirect_uri.clone(),
        invite_code: None,
    });

    match auth_client.complete_o_auth_flow(grpc_request).await {
        Ok(response) => {
            let res = response.into_inner();
            info!(
                provider = %provider,
                user_id = %res.user_id,
                is_new_user = res.is_new_user,
                "OAuth flow completed successfully"
            );

            Ok(HttpResponse::Ok().json(OAuthCallbackResponse {
                user_id: res.user_id.clone(),
                token: res.token,
                refresh_token: Some(res.refresh_token),
                expires_in: res.expires_in,
                is_new_user: res.is_new_user,
                user: Some(UserProfileResponse {
                    id: res.user_id,
                    username: res.username,
                    email: Some(res.email),
                    display_name: None,
                    avatar_url: None,
                }),
            }))
        }
        Err(status) => {
            error!(provider = %provider, error = %status, "Failed to complete OAuth flow");
            Ok(HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "oauth_callback_failed",
                &format!("Failed to complete OAuth flow: {}", status.message()),
            )))
        }
    }
}

// ============================================================================
// OAuth Callback Endpoints (GET - for redirect-based flow)
// ============================================================================

/// Handle Google OAuth callback redirect from Google
/// Exchanges code for tokens and redirects to iOS app with custom URL scheme
///
/// GET /api/v2/auth/oauth/google/callback?code=xxx&state=xxx
pub async fn google_oauth_callback_get(
    clients: web::Data<ServiceClients>,
    query: web::Query<OAuthCallbackQuery>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    oauth_callback_redirect(clients, "google", &query).await
}

/// Handle Apple OAuth callback redirect
///
/// GET /api/v2/auth/oauth/apple/callback?code=xxx&state=xxx
pub async fn apple_oauth_callback_get(
    clients: web::Data<ServiceClients>,
    query: web::Query<OAuthCallbackQuery>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    oauth_callback_redirect(clients, "apple", &query).await
}

async fn oauth_callback_redirect(
    clients: web::Data<ServiceClients>,
    provider: &str,
    query: &OAuthCallbackQuery,
) -> Result<HttpResponse> {
    info!(provider = %provider, "Processing OAuth callback redirect (GET)");

    // The redirect_uri should match what was used in the start flow
    // For the redirect-based flow, we use the backend URL
    let redirect_uri = format!(
        "https://staging-api.icered.com/api/v2/auth/oauth/{}/callback",
        provider
    );

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(CompleteOAuthFlowRequest {
        state: query.state.clone(),
        code: query.code.clone(),
        redirect_uri,
        invite_code: None,
    });

    match auth_client.complete_o_auth_flow(grpc_request).await {
        Ok(response) => {
            let res = response.into_inner();
            info!(
                provider = %provider,
                user_id = %res.user_id,
                is_new_user = res.is_new_user,
                "OAuth flow completed, redirecting to app"
            );

            // Build redirect URL to iOS app with tokens
            let app_redirect = format!(
                "icered://oauth/{}/callback?user_id={}&token={}&refresh_token={}&expires_in={}&is_new_user={}&username={}&email={}",
                provider,
                urlencoding::encode(&res.user_id),
                urlencoding::encode(&res.token),
                urlencoding::encode(&res.refresh_token),
                res.expires_in,
                res.is_new_user,
                urlencoding::encode(&res.username),
                urlencoding::encode(&res.email),
            );

            Ok(HttpResponse::Found()
                .append_header(("Location", app_redirect))
                .finish())
        }
        Err(status) => {
            error!(provider = %provider, error = %status, "Failed to complete OAuth flow");

            // Redirect to app with error
            let error_redirect = format!(
                "icered://oauth/{}/callback?error={}&message={}",
                provider,
                urlencoding::encode("oauth_failed"),
                urlencoding::encode(status.message()),
            );

            Ok(HttpResponse::Found()
                .append_header(("Location", error_redirect))
                .finish())
        }
    }
}

// ============================================================================
// Apple Native Sign-In (for iOS ASAuthorizationAppleIDCredential)
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct AppleNativeSignInRequest {
    pub authorization_code: String,
    pub identity_token: String,
    pub user_identifier: String,
    pub email: Option<String>,
    pub full_name: Option<AppleFullName>,
}

#[derive(Debug, Deserialize)]
pub struct AppleFullName {
    pub given_name: Option<String>,
    pub family_name: Option<String>,
}

/// Handle Apple native sign-in from iOS
///
/// POST /api/v2/auth/oauth/apple/native
pub async fn apple_native_sign_in(
    clients: web::Data<ServiceClients>,
    body: web::Json<AppleNativeSignInRequest>,
) -> Result<HttpResponse> {
    info!("Processing Apple native sign-in");

    let given_name = body.full_name.as_ref().and_then(|n| n.given_name.clone());
    let family_name = body.full_name.as_ref().and_then(|n| n.family_name.clone());

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcAppleNativeSignInRequest {
        authorization_code: body.authorization_code.clone(),
        identity_token: body.identity_token.clone(),
        user_identifier: body.user_identifier.clone(),
        email: body.email.clone(),
        given_name,
        family_name,
        invite_code: None,
    });

    match auth_client.apple_native_sign_in(grpc_request).await {
        Ok(response) => {
            let res = response.into_inner();
            info!(
                user_id = %res.user_id,
                is_new_user = res.is_new_user,
                "Apple native sign-in completed"
            );

            Ok(HttpResponse::Ok().json(OAuthCallbackResponse {
                user_id: res.user_id.clone(),
                token: res.token,
                refresh_token: Some(res.refresh_token),
                expires_in: res.expires_in,
                is_new_user: res.is_new_user,
                user: Some(UserProfileResponse {
                    id: res.user_id,
                    username: res.username,
                    email: Some(res.email),
                    display_name: None,
                    avatar_url: None,
                }),
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed Apple native sign-in");
            Ok(HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "apple_signin_failed",
                &format!("Failed to sign in with Apple: {}", status.message()),
            )))
        }
    }
}
