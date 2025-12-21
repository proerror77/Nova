//! Passkey (WebAuthn/FIDO2) REST API endpoints for mobile clients
//!
//! Handles passwordless authentication flows using WebAuthn/Passkeys.
//!
//! Registration flow (requires authenticated user):
//! 1. Client calls /start with JWT to get challenge
//! 2. iOS AuthenticationServices creates passkey credential
//! 3. Client calls /complete with attestation response
//!
//! Authentication flow (no auth required):
//! 1. Client calls /authenticate/start to get challenge
//! 2. iOS AuthenticationServices signs challenge
//! 3. Client calls /authenticate/complete with assertion response
//! 4. Backend returns JWT tokens

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use super::models::ErrorResponse;
use crate::clients::proto::auth::{
    CompletePasskeyAuthenticationRequest as GrpcCompletePasskeyAuthRequest,
    CompletePasskeyRegistrationRequest as GrpcCompletePasskeyRegRequest,
    ListPasskeysRequest as GrpcListPasskeysRequest,
    RenamePasskeyRequest as GrpcRenamePasskeyRequest,
    RevokePasskeyRequest as GrpcRevokePasskeyRequest,
    StartPasskeyAuthenticationRequest as GrpcStartPasskeyAuthRequest,
    StartPasskeyRegistrationRequest as GrpcStartPasskeyRegRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct StartRegistrationRequest {
    /// Optional friendly name for the passkey (e.g., "iPhone 15 Pro")
    pub credential_name: Option<String>,
    /// Device type (e.g., "iPhone", "iPad")
    pub device_type: Option<String>,
    /// OS version (e.g., "18.0")
    pub os_version: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct StartRegistrationResponse {
    /// Challenge ID for correlation
    pub challenge_id: String,
    /// PublicKeyCredentialCreationOptions as JSON string
    pub options: String,
}

#[derive(Debug, Deserialize)]
pub struct CompleteRegistrationRequest {
    /// Challenge ID from start response
    pub challenge_id: String,
    /// Attestation response from authenticator as JSON string
    pub attestation_response: String,
    /// Optional friendly name
    pub credential_name: Option<String>,
    /// Device type
    pub device_type: Option<String>,
    /// OS version
    pub os_version: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct CompleteRegistrationResponse {
    /// UUID of the registered credential
    pub credential_id: String,
    /// Friendly name of the credential
    pub credential_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct StartAuthenticationRequest {
    /// Optional user ID (for non-discoverable flow)
    /// Leave empty for discoverable/AutoFill flow
    pub user_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct StartAuthenticationResponse {
    /// Challenge ID for correlation
    pub challenge_id: String,
    /// PublicKeyCredentialRequestOptions as JSON string
    pub options: String,
}

#[derive(Debug, Deserialize)]
pub struct CompleteAuthenticationRequest {
    /// Challenge ID from start response
    pub challenge_id: String,
    /// Assertion response from authenticator as JSON string
    pub assertion_response: String,
}

#[derive(Debug, Serialize)]
pub struct CompleteAuthenticationResponse {
    /// User ID
    pub user_id: String,
    /// JWT access token
    pub token: String,
    /// JWT refresh token
    pub refresh_token: Option<String>,
    /// Token expiration (Unix timestamp)
    pub expires_in: i64,
    /// Used credential UUID
    pub credential_id: String,
    /// User profile
    pub user: Option<PasskeyUserProfile>,
}

#[derive(Debug, Serialize)]
pub struct PasskeyUserProfile {
    pub id: String,
    pub username: String,
    pub email: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PasskeyInfo {
    pub id: String,
    pub credential_name: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
    pub backup_eligible: bool,
    pub backup_state: bool,
    pub transports: Vec<String>,
    pub created_at: i64,
    pub last_used_at: Option<i64>,
    pub is_active: bool,
}

#[derive(Debug, Serialize)]
pub struct ListPasskeysResponse {
    pub passkeys: Vec<PasskeyInfo>,
}

#[derive(Debug, Deserialize)]
pub struct RenamePasskeyRequest {
    pub new_name: String,
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Extract authenticated user from request extensions
fn get_authenticated_user(req: &HttpRequest) -> Option<String> {
    req.extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .map(|u| u.0.to_string())
}

// ============================================================================
// Registration Endpoints
// ============================================================================

/// Start passkey registration - returns challenge and options
///
/// POST /api/v2/auth/passkey/register/start
///
/// Requires: JWT Authorization header
pub async fn start_registration(
    req: HttpRequest,
    body: web::Json<StartRegistrationRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match get_authenticated_user(&req) {
        Some(id) => id,
        None => {
            return Ok(HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                "unauthorized",
                "Authentication required",
            )))
        }
    };

    info!(
        user_id = %user_id,
        credential_name = ?body.credential_name,
        "POST /api/v2/auth/passkey/register/start"
    );

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcStartPasskeyRegRequest {
        user_id: user_id.clone(),
        credential_name: body.credential_name.clone().unwrap_or_default(),
        device_type: body.device_type.clone().unwrap_or_default(),
        os_version: body.os_version.clone().unwrap_or_default(),
    });

    match auth_client
        .start_passkey_registration(grpc_request)
        .await
    {
        Ok(response) => {
            let res = response.into_inner();
            info!(
                user_id = %user_id,
                challenge_id = %res.challenge_id,
                "Passkey registration started"
            );
            Ok(HttpResponse::Ok().json(StartRegistrationResponse {
                challenge_id: res.challenge_id,
                options: res.options_json,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to start passkey registration"
            );
            Ok(HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "passkey_start_failed",
                &format!("Failed to start passkey registration: {}", status.message()),
            )))
        }
    }
}

/// Complete passkey registration - verify attestation and store credential
///
/// POST /api/v2/auth/passkey/register/complete
///
/// Requires: JWT Authorization header
pub async fn complete_registration(
    req: HttpRequest,
    body: web::Json<CompleteRegistrationRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match get_authenticated_user(&req) {
        Some(id) => id,
        None => {
            return Ok(HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                "unauthorized",
                "Authentication required",
            )))
        }
    };

    info!(
        user_id = %user_id,
        challenge_id = %body.challenge_id,
        "POST /api/v2/auth/passkey/register/complete"
    );

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcCompletePasskeyRegRequest {
        challenge_id: body.challenge_id.clone(),
        attestation_json: body.attestation_response.clone(),
        credential_name: body.credential_name.clone().unwrap_or_default(),
        device_type: body.device_type.clone().unwrap_or_default(),
        os_version: body.os_version.clone().unwrap_or_default(),
    });

    match auth_client
        .complete_passkey_registration(grpc_request)
        .await
    {
        Ok(response) => {
            let res = response.into_inner();
            info!(
                user_id = %user_id,
                credential_id = %res.credential_id,
                "Passkey registration completed"
            );
            Ok(HttpResponse::Ok().json(CompleteRegistrationResponse {
                credential_id: res.credential_id,
                credential_name: if res.credential_name.is_empty() {
                    None
                } else {
                    Some(res.credential_name)
                },
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to complete passkey registration"
            );
            Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
                "passkey_registration_failed",
                &format!(
                    "Failed to complete passkey registration: {}",
                    status.message()
                ),
            )))
        }
    }
}

// ============================================================================
// Authentication Endpoints
// ============================================================================

/// Start passkey authentication - returns challenge and options
///
/// POST /api/v2/auth/passkey/authenticate/start
///
/// No authentication required (user is logging in)
pub async fn start_authentication(
    body: web::Json<StartAuthenticationRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(
        user_id = ?body.user_id,
        "POST /api/v2/auth/passkey/authenticate/start"
    );

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcStartPasskeyAuthRequest {
        user_id: body.user_id.clone().unwrap_or_default(),
    });

    match auth_client
        .start_passkey_authentication(grpc_request)
        .await
    {
        Ok(response) => {
            let res = response.into_inner();
            info!(
                challenge_id = %res.challenge_id,
                "Passkey authentication started"
            );
            Ok(HttpResponse::Ok().json(StartAuthenticationResponse {
                challenge_id: res.challenge_id,
                options: res.options_json,
            }))
        }
        Err(status) => {
            error!(
                error = %status,
                "Failed to start passkey authentication"
            );
            Ok(HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "passkey_auth_start_failed",
                &format!(
                    "Failed to start passkey authentication: {}",
                    status.message()
                ),
            )))
        }
    }
}

/// Complete passkey authentication - verify assertion and return tokens
///
/// POST /api/v2/auth/passkey/authenticate/complete
///
/// No authentication required (user is logging in)
pub async fn complete_authentication(
    body: web::Json<CompleteAuthenticationRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(
        challenge_id = %body.challenge_id,
        "POST /api/v2/auth/passkey/authenticate/complete"
    );

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcCompletePasskeyAuthRequest {
        challenge_id: body.challenge_id.clone(),
        assertion_json: body.assertion_response.clone(),
    });

    match auth_client
        .complete_passkey_authentication(grpc_request)
        .await
    {
        Ok(response) => {
            let res = response.into_inner();
            info!(
                user_id = %res.user_id,
                credential_id = %res.credential_id,
                "Passkey authentication completed"
            );
            Ok(HttpResponse::Ok().json(CompleteAuthenticationResponse {
                user_id: res.user_id.clone(),
                token: res.access_token,
                refresh_token: if res.refresh_token.is_empty() {
                    None
                } else {
                    Some(res.refresh_token)
                },
                expires_in: res.expires_at,
                credential_id: res.credential_id,
                user: Some(PasskeyUserProfile {
                    id: res.user_id,
                    username: res.username,
                    email: if res.email.is_empty() {
                        None
                    } else {
                        Some(res.email)
                    },
                }),
            }))
        }
        Err(status) => {
            error!(
                error = %status,
                "Failed to complete passkey authentication"
            );
            Ok(HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                "passkey_auth_failed",
                &format!(
                    "Failed to complete passkey authentication: {}",
                    status.message()
                ),
            )))
        }
    }
}

// ============================================================================
// Passkey Management Endpoints
// ============================================================================

/// List user's registered passkeys
///
/// GET /api/v2/auth/passkey/list
///
/// Requires: JWT Authorization header
pub async fn list_passkeys(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match get_authenticated_user(&req) {
        Some(id) => id,
        None => {
            return Ok(HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                "unauthorized",
                "Authentication required",
            )))
        }
    };

    info!(
        user_id = %user_id,
        "GET /api/v2/auth/passkey/list"
    );

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcListPasskeysRequest {
        user_id: user_id.clone(),
    });

    match auth_client.list_passkeys(grpc_request).await {
        Ok(response) => {
            let res = response.into_inner();
            let passkeys: Vec<PasskeyInfo> = res
                .passkeys
                .into_iter()
                .map(|p| {
                    // Convert proto timestamp to Unix timestamp
                    let created_at = p
                        .created_at
                        .map(|ts| ts.seconds)
                        .unwrap_or(0);
                    let last_used_at = p.last_used_at.map(|ts| ts.seconds);

                    PasskeyInfo {
                        id: p.id,
                        credential_name: if p.credential_name.is_empty() {
                            None
                        } else {
                            Some(p.credential_name)
                        },
                        device_type: if p.device_type.is_empty() {
                            None
                        } else {
                            Some(p.device_type)
                        },
                        os_version: if p.os_version.is_empty() {
                            None
                        } else {
                            Some(p.os_version)
                        },
                        backup_eligible: p.backup_eligible,
                        backup_state: p.backup_state,
                        transports: p.transports,
                        created_at,
                        last_used_at,
                        is_active: p.is_active,
                    }
                })
                .collect();

            info!(
                user_id = %user_id,
                count = passkeys.len(),
                "Listed passkeys"
            );
            Ok(HttpResponse::Ok().json(ListPasskeysResponse { passkeys }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to list passkeys"
            );
            Ok(HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                "list_passkeys_failed",
                &format!("Failed to list passkeys: {}", status.message()),
            )))
        }
    }
}

/// Revoke a passkey credential
///
/// DELETE /api/v2/auth/passkey/{credential_id}
///
/// Requires: JWT Authorization header
pub async fn revoke_passkey(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match get_authenticated_user(&req) {
        Some(id) => id,
        None => {
            return Ok(HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                "unauthorized",
                "Authentication required",
            )))
        }
    };

    let credential_id = path.into_inner();

    info!(
        user_id = %user_id,
        credential_id = %credential_id,
        "DELETE /api/v2/auth/passkey/{credential_id}"
    );

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcRevokePasskeyRequest {
        user_id: user_id.clone(),
        credential_id: credential_id.clone(),
        reason: "User requested revocation".to_string(),
    });

    match auth_client.revoke_passkey(grpc_request).await {
        Ok(_) => {
            info!(
                user_id = %user_id,
                credential_id = %credential_id,
                "Passkey revoked"
            );
            Ok(HttpResponse::NoContent().finish())
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                credential_id = %credential_id,
                error = %status,
                "Failed to revoke passkey"
            );
            Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
                "revoke_passkey_failed",
                &format!("Failed to revoke passkey: {}", status.message()),
            )))
        }
    }
}

/// Rename a passkey credential
///
/// PUT /api/v2/auth/passkey/{credential_id}/rename
///
/// Requires: JWT Authorization header
pub async fn rename_passkey(
    req: HttpRequest,
    path: web::Path<String>,
    body: web::Json<RenamePasskeyRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match get_authenticated_user(&req) {
        Some(id) => id,
        None => {
            return Ok(HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                "unauthorized",
                "Authentication required",
            )))
        }
    };

    let credential_id = path.into_inner();

    info!(
        user_id = %user_id,
        credential_id = %credential_id,
        new_name = %body.new_name,
        "PUT /api/v2/auth/passkey/{credential_id}/rename"
    );

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GrpcRenamePasskeyRequest {
        user_id: user_id.clone(),
        credential_id: credential_id.clone(),
        new_name: body.new_name.clone(),
    });

    match auth_client.rename_passkey(grpc_request).await {
        Ok(_) => {
            info!(
                user_id = %user_id,
                credential_id = %credential_id,
                new_name = %body.new_name,
                "Passkey renamed"
            );
            Ok(HttpResponse::NoContent().finish())
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                credential_id = %credential_id,
                error = %status,
                "Failed to rename passkey"
            );
            Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
                "rename_passkey_failed",
                &format!("Failed to rename passkey: {}", status.message()),
            )))
        }
    }
}
