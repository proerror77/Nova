/// OAuth Authentication API endpoints
///
/// POST /api/v2/auth/oauth/google/start - Start Google OAuth flow
/// POST /api/v2/auth/oauth/google/callback - Complete Google OAuth flow
/// POST /api/v2/auth/oauth/apple/start - Start Apple OAuth flow
/// POST /api/v2/auth/oauth/apple/callback - Complete Apple OAuth flow
/// POST /api/v2/auth/oauth/apple/native - Apple native Sign-In (iOS)
use actix_web::{web, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::auth::{
    CompleteOAuthFlowRequest as GrpcCompleteOAuthFlowRequest, OAuthProvider,
    StartOAuthFlowRequest as GrpcStartOAuthFlowRequest,
};
use crate::clients::ServiceClients;

use super::models::ErrorResponse;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct StartOAuthRequest {
    pub redirect_uri: String,
    #[serde(default)]
    pub invite_code: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct StartOAuthResponse {
    pub authorization_url: String,
    pub state: String,
}

#[derive(Debug, Deserialize)]
pub struct CompleteOAuthRequest {
    pub code: String,
    pub state: String,
    pub redirect_uri: String,
    #[serde(default)]
    pub invite_code: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct OAuthCallbackResponse {
    pub user_id: String,
    pub token: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    pub expires_in: i64,
    pub is_new_user: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user: Option<OAuthUserProfile>,
}

#[derive(Debug, Serialize)]
pub struct OAuthUserProfile {
    pub id: String,
    pub username: String,
    pub email: String,
}

#[derive(Debug, Deserialize)]
pub struct AppleNativeSignInRequest {
    pub authorization_code: String,
    pub identity_token: String,
    pub user_identifier: String,
    #[serde(default)]
    pub email: Option<String>,
    #[serde(default)]
    pub full_name: Option<AppleFullName>,
    #[serde(default)]
    pub invite_code: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct AppleFullName {
    pub given_name: Option<String>,
    pub family_name: Option<String>,
}

// ============================================================================
// Google OAuth Endpoints
// ============================================================================

/// POST /api/v2/auth/oauth/google/start
/// Start Google OAuth flow - returns authorization URL
pub async fn start_google_oauth(
    req: web::Json<StartOAuthRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(redirect_uri = %req.redirect_uri, "POST /api/v2/auth/oauth/google/start");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcStartOAuthFlowRequest {
        provider: OAuthProvider::OauthProviderGoogle as i32,
        redirect_uri: req.redirect_uri.clone(),
        invite_code: req.invite_code.clone(),
    });

    match auth_client.start_o_auth_flow(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();
            info!(state = %inner.state, "Google OAuth flow started");

            Ok(HttpResponse::Ok().json(StartOAuthResponse {
                authorization_url: inner.authorization_url,
                state: inner.state,
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed to start Google OAuth flow");
            Ok(HttpResponse::InternalServerError()
                .json(ErrorResponse::with_message("OAuth error", status.message())))
        }
    }
}

/// POST /api/v2/auth/oauth/google/callback
/// Complete Google OAuth flow - exchange code for tokens
pub async fn complete_google_oauth(
    req: web::Json<CompleteOAuthRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(state = %req.state, "POST /api/v2/auth/oauth/google/callback");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcCompleteOAuthFlowRequest {
        state: req.state.clone(),
        code: req.code.clone(),
        redirect_uri: req.redirect_uri.clone(),
        invite_code: req.invite_code.clone(),
    });

    match auth_client.complete_o_auth_flow(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();
            info!(
                user_id = %inner.user_id,
                is_new_user = inner.is_new_user,
                "Google OAuth completed"
            );

            Ok(HttpResponse::Ok().json(OAuthCallbackResponse {
                user_id: inner.user_id.clone(),
                token: inner.token,
                refresh_token: if inner.refresh_token.is_empty() {
                    None
                } else {
                    Some(inner.refresh_token)
                },
                expires_in: inner.expires_in,
                is_new_user: inner.is_new_user,
                user: Some(OAuthUserProfile {
                    id: inner.user_id,
                    username: inner.username,
                    email: inner.email,
                }),
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed to complete Google OAuth flow");

            let error_response = match status.code() {
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid OAuth request", status.message()),
                ),
                tonic::Code::Unauthenticated => HttpResponse::Unauthorized().json(
                    ErrorResponse::with_message("OAuth failed", status.message()),
                ),
                _ => HttpResponse::InternalServerError()
                    .json(ErrorResponse::with_message("OAuth error", status.message())),
            };

            Ok(error_response)
        }
    }
}

// ============================================================================
// Apple OAuth Endpoints
// ============================================================================

/// POST /api/v2/auth/oauth/apple/start
/// Start Apple OAuth flow - returns authorization URL
pub async fn start_apple_oauth(
    req: web::Json<StartOAuthRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(redirect_uri = %req.redirect_uri, "POST /api/v2/auth/oauth/apple/start");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcStartOAuthFlowRequest {
        provider: OAuthProvider::OauthProviderApple as i32,
        redirect_uri: req.redirect_uri.clone(),
        invite_code: req.invite_code.clone(),
    });

    match auth_client.start_o_auth_flow(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();
            info!(state = %inner.state, "Apple OAuth flow started");

            Ok(HttpResponse::Ok().json(StartOAuthResponse {
                authorization_url: inner.authorization_url,
                state: inner.state,
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed to start Apple OAuth flow");
            Ok(HttpResponse::InternalServerError()
                .json(ErrorResponse::with_message("OAuth error", status.message())))
        }
    }
}

/// POST /api/v2/auth/oauth/apple/callback
/// Complete Apple OAuth flow - exchange code for tokens
pub async fn complete_apple_oauth(
    req: web::Json<CompleteOAuthRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(state = %req.state, "POST /api/v2/auth/oauth/apple/callback");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcCompleteOAuthFlowRequest {
        state: req.state.clone(),
        code: req.code.clone(),
        redirect_uri: req.redirect_uri.clone(),
        invite_code: req.invite_code.clone(),
    });

    match auth_client.complete_o_auth_flow(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();
            info!(
                user_id = %inner.user_id,
                is_new_user = inner.is_new_user,
                "Apple OAuth completed"
            );

            Ok(HttpResponse::Ok().json(OAuthCallbackResponse {
                user_id: inner.user_id.clone(),
                token: inner.token,
                refresh_token: if inner.refresh_token.is_empty() {
                    None
                } else {
                    Some(inner.refresh_token)
                },
                expires_in: inner.expires_in,
                is_new_user: inner.is_new_user,
                user: Some(OAuthUserProfile {
                    id: inner.user_id,
                    username: inner.username,
                    email: inner.email,
                }),
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed to complete Apple OAuth flow");

            let error_response = match status.code() {
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid OAuth request", status.message()),
                ),
                tonic::Code::Unauthenticated => HttpResponse::Unauthorized().json(
                    ErrorResponse::with_message("OAuth failed", status.message()),
                ),
                _ => HttpResponse::InternalServerError()
                    .json(ErrorResponse::with_message("OAuth error", status.message())),
            };

            Ok(error_response)
        }
    }
}

/// POST /api/v2/auth/oauth/apple/native
/// Apple native Sign-In (for iOS app using ASAuthorizationController)
/// This endpoint handles the native Apple Sign-In flow without web redirect
///
/// TODO: Implement when AppleNativeSignIn gRPC method is added to identity-service proto
#[allow(dead_code)]
pub async fn apple_native_sign_in(
    req: web::Json<AppleNativeSignInRequest>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(
        user_identifier = %req.user_identifier,
        has_email = req.email.is_some(),
        "POST /api/v2/auth/oauth/apple/native"
    );

    // TODO: Implement when AppleNativeSignIn gRPC method is added to identity-service proto
    // For now, return not implemented
    Ok(
        HttpResponse::NotImplemented().json(ErrorResponse::with_message(
            "Not implemented",
            "Apple native sign-in is not yet implemented. Please use the web OAuth flow.",
        )),
    )
}
