/// gRPC service implementations
use tonic::{Request, Response, Status};
use uuid::Uuid;

use crate::{nova::auth::v1::auth_service_server::AuthService, nova::auth::v1::*, AppState};

/// gRPC AuthService implementation
pub struct AuthServiceImpl {
    #[allow(dead_code)]
    state: AppState,
}

impl AuthServiceImpl {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }
}

#[tonic::async_trait]
impl AuthService for AuthServiceImpl {
    /// Register new user
    async fn register(
        &self,
        request: Request<RegisterRequest>,
    ) -> Result<Response<AuthResponse>, Status> {
        let req = request.into_inner();

        // Validate input
        if req.email.is_empty() || req.username.is_empty() || req.password.is_empty() {
            return Err(Status::invalid_argument("Missing required fields"));
        }

        // Hash password
        match crate::security::password::hash_password(&req.password) {
            Ok(_) => {
                // TODO: Save user to database
                let user_id = Uuid::new_v4();

                let token_pair =
                    crate::security::jwt::generate_token_pair(user_id, &req.email, &req.username)
                        .map_err(|e| Status::internal(e.to_string()))?;

                Ok(Response::new(AuthResponse {
                    user_id: user_id.to_string(),
                    username: req.username,
                    email: req.email,
                    access_token: token_pair.access_token,
                    refresh_token: token_pair.refresh_token,
                    access_token_expires_at: (chrono::Utc::now().timestamp() + 900) as i64,
                    refresh_token_expires_at: (chrono::Utc::now().timestamp() + 604800) as i64,
                    two_fa_required: false,
                }))
            }
            Err(e) => Err(Status::invalid_argument(e.to_string())),
        }
    }

    /// Login user
    async fn login(
        &self,
        request: Request<LoginRequest>,
    ) -> Result<Response<AuthResponse>, Status> {
        let _req = request.into_inner();

        // TODO: Find user by email in database
        // TODO: Verify password
        // TODO: Return tokens

        Err(Status::unauthenticated("Invalid credentials"))
    }

    /// Validate token
    async fn validate_token(
        &self,
        request: Request<ValidateTokenRequest>,
    ) -> Result<Response<ValidateTokenResponse>, Status> {
        let req = request.into_inner();

        match crate::security::jwt::validate_token(&req.token) {
            Ok(token_data) => Ok(Response::new(ValidateTokenResponse {
                valid: true,
                claims: Some(TokenClaims {
                    user_id: token_data.claims.sub,
                    email: token_data.claims.email,
                    username: token_data.claims.username,
                    roles: vec![],
                    issued_at: token_data.claims.iat as i64,
                    expires_at: token_data.claims.exp as i64,
                }),
                error: String::new(),
            })),
            Err(e) => Ok(Response::new(ValidateTokenResponse {
                valid: false,
                claims: None,
                error: e.to_string(),
            })),
        }
    }

    /// Refresh access token
    async fn refresh_token(
        &self,
        request: Request<RefreshTokenRequest>,
    ) -> Result<Response<AuthResponse>, Status> {
        let req = request.into_inner();

        match crate::security::jwt::validate_token(&req.refresh_token) {
            Ok(token_data) => {
                if token_data.claims.token_type != "refresh" {
                    return Err(Status::invalid_argument("Invalid token type"));
                }

                let user_id = Uuid::parse_str(&token_data.claims.sub)
                    .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

                let new_pair = crate::security::jwt::generate_token_pair(
                    user_id,
                    &token_data.claims.email,
                    &token_data.claims.username,
                )
                .map_err(|e| Status::internal(e.to_string()))?;

                Ok(Response::new(AuthResponse {
                    user_id: user_id.to_string(),
                    username: token_data.claims.username,
                    email: token_data.claims.email,
                    access_token: new_pair.access_token,
                    refresh_token: new_pair.refresh_token,
                    access_token_expires_at: (chrono::Utc::now().timestamp() + 900) as i64,
                    refresh_token_expires_at: (chrono::Utc::now().timestamp() + 604800) as i64,
                    two_fa_required: false,
                }))
            }
            Err(e) => Err(Status::unauthenticated(e.to_string())),
        }
    }

    /// Logout user
    async fn logout(
        &self,
        _request: Request<LogoutRequest>,
    ) -> Result<Response<LogoutResponse>, Status> {
        // TODO: Add token to blacklist in Redis
        // TODO: Revoke session

        Ok(Response::new(LogoutResponse { success: true }))
    }

    /// Request password reset
    async fn request_password_reset(
        &self,
        _request: Request<RequestPasswordResetRequest>,
    ) -> Result<Response<RequestPasswordResetResponse>, Status> {
        // TODO: Find user by email
        // TODO: Generate reset token
        // TODO: Send email

        Ok(Response::new(RequestPasswordResetResponse {
            success: true,
            message: "Password reset email sent".to_string(),
        }))
    }

    /// Reset password
    async fn reset_password(
        &self,
        _request: Request<ResetPasswordRequest>,
    ) -> Result<Response<ResetPasswordResponse>, Status> {
        // TODO: Validate reset token
        // TODO: Update password
        // TODO: Revoke all tokens

        Ok(Response::new(ResetPasswordResponse {
            success: true,
            message: "Password reset successfully".to_string(),
        }))
    }

    /// Change password
    async fn change_password(
        &self,
        _request: Request<ChangePasswordRequest>,
    ) -> Result<Response<ChangePasswordResponse>, Status> {
        // TODO: Verify old password
        // TODO: Update password
        // TODO: Revoke all tokens

        Ok(Response::new(ChangePasswordResponse {
            success: true,
            message: "Password changed successfully".to_string(),
        }))
    }

    /// Start OAuth flow
    async fn start_o_auth_flow(
        &self,
        _request: Request<StartOAuthFlowRequest>,
    ) -> Result<Response<StartOAuthFlowResponse>, Status> {
        // TODO: Validate provider
        // TODO: Generate state token
        // TODO: Build authorization URL

        let state = uuid::Uuid::new_v4().to_string();

        Ok(Response::new(StartOAuthFlowResponse {
            auth_url: format!("https://oauth.example.com/auth?state={}", state),
            state,
            expires_at: chrono::Utc::now().timestamp() + 600,
        }))
    }

    /// Complete OAuth flow
    async fn complete_o_auth_flow(
        &self,
        _request: Request<CompleteOAuthFlowRequest>,
    ) -> Result<Response<AuthResponse>, Status> {
        // TODO: Verify state token
        // TODO: Exchange code for tokens
        // TODO: Get user info
        // TODO: Create/update user
        // TODO: Return our tokens

        let user_id = Uuid::new_v4();

        Ok(Response::new(AuthResponse {
            user_id: user_id.to_string(),
            username: "oauth_user".to_string(),
            email: "user@example.com".to_string(),
            access_token: "stub_access_token".to_string(),
            refresh_token: "stub_refresh_token".to_string(),
            access_token_expires_at: chrono::Utc::now().timestamp() + 900,
            refresh_token_expires_at: chrono::Utc::now().timestamp() + 604800,
            two_fa_required: false,
        }))
    }

    /// Create session
    async fn create_session(
        &self,
        _request: Request<CreateSessionRequest>,
    ) -> Result<Response<SessionResponse>, Status> {
        // TODO: Create session in Redis
        // TODO: Store device info

        Ok(Response::new(SessionResponse {
            session: Some(SessionInfo {
                session_id: uuid::Uuid::new_v4().to_string(),
                user_id: String::new(),
                device_id: String::new(),
                device_name: String::new(),
                ip_address: String::new(),
                user_agent: String::new(),
                created_at: chrono::Utc::now().timestamp(),
                last_activity_at: chrono::Utc::now().timestamp(),
                expires_at: chrono::Utc::now().timestamp() + 2592000, // 30 days
            }),
        }))
    }

    /// Get session
    async fn get_session(
        &self,
        _request: Request<GetSessionRequest>,
    ) -> Result<Response<SessionResponse>, Status> {
        // TODO: Retrieve session from Redis

        Err(Status::not_found("Session not found"))
    }

    /// Revoke session
    async fn revoke_session(
        &self,
        _request: Request<RevokeSessionRequest>,
    ) -> Result<Response<RevokeSessionResponse>, Status> {
        // TODO: Remove session from Redis

        Ok(Response::new(RevokeSessionResponse { success: true }))
    }

    /// List sessions
    async fn list_sessions(
        &self,
        _request: Request<ListSessionsRequest>,
    ) -> Result<Response<ListSessionsResponse>, Status> {
        // TODO: Retrieve all sessions for user from Redis

        Ok(Response::new(ListSessionsResponse { sessions: vec![] }))
    }

    /// Request 2FA setup
    async fn request_two_fa_setup(
        &self,
        _request: Request<RequestTwoFaSetupRequest>,
    ) -> Result<Response<RequestTwoFaSetupResponse>, Status> {
        // Generate TOTP secret
        let (secret, qr_code_url) =
            crate::security::totp::TOTPGenerator::generate_secret_and_uri("user@example.com")
                .map_err(|e| Status::internal(e.to_string()))?;

        Ok(Response::new(RequestTwoFaSetupResponse {
            secret,
            qr_code_url,
        }))
    }

    /// Verify 2FA code
    async fn verify_two_fa(
        &self,
        request: Request<VerifyTwoFaRequest>,
    ) -> Result<Response<VerifyTwoFaResponse>, Status> {
        let req = request.into_inner();

        // TODO: Get TOTP secret from database
        // TODO: Verify code

        match crate::security::totp::TOTPGenerator::verify_code("dummy_secret", &req.code) {
            Ok(true) => {
                let backup_codes = crate::security::totp::TOTPGenerator::generate_backup_codes();
                Ok(Response::new(VerifyTwoFaResponse {
                    success: true,
                    backup_codes,
                }))
            }
            Ok(false) => Err(Status::unauthenticated("Invalid 2FA code")),
            Err(e) => Err(Status::internal(e.to_string())),
        }
    }

    /// Disable 2FA
    async fn disable_two_fa(
        &self,
        _request: Request<DisableTwoFaRequest>,
    ) -> Result<Response<DisableTwoFaResponse>, Status> {
        // TODO: Verify password
        // TODO: Disable 2FA in database

        Ok(Response::new(DisableTwoFaResponse { success: true }))
    }
}
