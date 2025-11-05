/// gRPC service implementations for Auth Service
/// Based on Phase 0 proto definitions (nova.auth_service)
/// This is a core foundational service that provides user identity and authentication
use tonic::{Request, Response, Status};

use crate::{
    metrics::{
        inc_account_lockouts, inc_login_failures, inc_login_requests, inc_register_requests,
    },
    nova::{
        auth_service::auth_service_server::AuthService,
        auth_service::*,
        common::v1::ErrorStatus,
    },
    security::{generate_token_pair, hash_password, token_revocation, verify_password},
    AppState,
};
use chrono::{DateTime, Utc};
use tracing::{error, info, warn};

/// gRPC AuthService implementation
/// Manages user authentication, identity, and token validation
pub struct AuthServiceImpl {
    state: AppState,
}

impl AuthServiceImpl {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }
}

#[inline]
fn ok_error() -> Option<ErrorStatus> {
    None
}

#[inline]
fn make_error(code: &'static str, message: impl Into<String>) -> Option<ErrorStatus> {
    Some(ErrorStatus {
        code: code.to_string(),
        message: message.into(),
        metadata: Default::default(),
    })
}

#[inline]
fn ts(value: DateTime<Utc>) -> i64 {
    value.timestamp()
}

#[inline]
fn ts_opt(value: Option<DateTime<Utc>>) -> Option<i64> {
    value.map(|dt| dt.timestamp())
}

#[tonic::async_trait]
impl AuthService for AuthServiceImpl {
    /// User Registration: Create new account with email, username, password
    /// Per 009-A spec: validates input, hashes password, creates user, returns JWT token
    async fn register(
        &self,
        request: Request<RegisterRequest>,
    ) -> Result<Response<RegisterResponse>, Status> {
        // T050: Increment register requests counter
        inc_register_requests();

        let req = request.into_inner();

        // Validate email format (basic check, full validation in 005-p1-input-validation)
        if req.email.is_empty() || !req.email.contains('@') {
            warn!(event = "invalid_email_format", email = %req.email);
            return Err(Status::invalid_argument("invalid_email_format"));
        }

        // Validate username (3-32 chars)
        if req.username.len() < 3 || req.username.len() > 32 {
            warn!(event = "invalid_username_length", username = %req.username);
            return Err(Status::invalid_argument("username_invalid_length"));
        }

        // Hash password (includes zxcvbn validation via 005)
        let password_hash = hash_password(&req.password).map_err(|_| {
            warn!(event = "weak_password", email = %req.email);
            Status::invalid_argument("weak_password")
        })?;

        // Check if email already exists
        let email_exists = crate::db::users::email_exists(&self.state.db, &req.email)
            .await
            .map_err(|_| Status::internal("Failed to check email"))?;

        if email_exists {
            warn!(event = "duplicate_email_registration", email = %req.email);
            return Err(Status::already_exists("email_already_registered"));
        }

        // Create user in database
        let user = crate::db::users::create_user(
            &self.state.db,
            &req.email,
            &req.username,
            &password_hash,
        )
        .await
        .map_err(|_| Status::internal("Failed to create user"))?;

        // Generate JWT token pair (access + refresh)
        let token_response = generate_token_pair(user.id, &user.email, &user.username)
            .map_err(|_| Status::internal("Failed to generate token"))?;

        info!(event = "user_registration_success", user_id = %user.id, email = %user.email);

        Ok(Response::new(RegisterResponse {
            user_id: user.id.to_string(),
            token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            expires_in: token_response.expires_in as i64,
        }))
    }

    /// User Login: Authenticate with email and password
    /// Per 009-A spec: validates credentials, enforces 5-attempt lockout, returns JWT token
    async fn login(
        &self,
        request: Request<LoginRequest>,
    ) -> Result<Response<LoginResponse>, Status> {
        // T050: Increment login requests counter
        inc_login_requests();

        let req = request.into_inner();

        // Validate email format
        if req.email.is_empty() || !req.email.contains('@') {
            warn!(event = "invalid_email_format", email = %req.email);
            return Err(Status::invalid_argument("invalid_email_format"));
        }

        // Find user by email
        let user = crate::db::users::find_by_email(&self.state.db, &req.email)
            .await
            .map_err(|_| Status::internal("Failed to find user"))?
            .ok_or_else(|| {
                // T050: Increment login failures for missing user
                inc_login_failures();
                warn!(event = "login_failed_user_not_found", email = %req.email);
                Status::unauthenticated("invalid_credentials")
            })?;

        // Check if account is locked
        if user.is_locked() {
            let locked_until = user
                .locked_until
                .map(|dt| dt.to_rfc3339())
                .unwrap_or_default();
            warn!(event = "login_failed_account_locked", user_id = %user.id, locked_until = %locked_until);
            return Err(Status::permission_denied(format!(
                "account_locked_until_{}",
                locked_until
            )));
        }

        // Verify password
        verify_password(&req.password, &user.password_hash)
            .map_err(|_| {
                // T050: Increment login failures counter
                inc_login_failures();

                let user_id = user.id;
                let user_email = user.email.clone();
                warn!(event = "login_failed_wrong_password", user_id = %user_id, email = %user_email);

                // Record failed attempt (fire-and-forget, don't block on errors)
                // This also triggers account lockout after 5 failed attempts
                let db = self.state.db.clone();
                tokio::spawn(async move {
                    let _ = crate::db::users::record_failed_login(&db, user_id, 5, 900).await;
                    // Fetch updated user to check if account was just locked
                    if let Ok(Some(updated_user)) = crate::db::users::find_by_id(&db, user_id).await {
                        // T050: Increment account lockouts counter when account becomes locked
                        if updated_user.failed_login_attempts >= 5 && updated_user.is_locked() {
                            inc_account_lockouts();
                            warn!(event = "account_locked_due_to_failed_attempts", user_id = %user_id, email = %user_email, attempts = updated_user.failed_login_attempts);
                        }
                    }
                });
                Status::unauthenticated("invalid_credentials")
            })?;

        // Clear failed login attempts on success
        let _ = crate::db::users::record_successful_login(&self.state.db, user.id).await;

        // Generate JWT token pair
        let token_response = generate_token_pair(user.id, &user.email, &user.username)
            .map_err(|_| Status::internal("Failed to generate token"))?;

        info!(event = "user_login_success", user_id = %user.id, email = %user.email);

        Ok(Response::new(LoginResponse {
            user_id: user.id.to_string(),
            token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            expires_in: token_response.expires_in as i64,
        }))
    }

    /// Token Refresh: Exchange refresh_token for new access_token
    /// Per 009-A spec: validates refresh token, returns new access token
    async fn refresh(
        &self,
        request: Request<RefreshTokenRequest>,
    ) -> Result<Response<RefreshTokenResponse>, Status> {
        let req = request.into_inner();

        if req.refresh_token.is_empty() {
            return Err(Status::unauthenticated("refresh_token_required"));
        }

        // Validate refresh token and extract claims
        let token_data = crate::security::validate_token(&req.refresh_token)
            .map_err(|_| Status::unauthenticated("refresh_token_invalid_or_expired"))?;

        let claims = token_data.claims;

        if claims.token_type != "refresh" {
            return Err(Status::unauthenticated("refresh_token_invalid_or_expired"));
        }

        let redis_revoked =
            token_revocation::is_token_revoked(&self.state.redis, &req.refresh_token)
                .await
                .map_err(|e| {
                    error!(
                        error = %e,
                        "Failed to check refresh token revocation in redis"
                    );
                    Status::internal("token_revocation_check_failed")
                })?;
        if redis_revoked {
            return Err(Status::unauthenticated("refresh_token_revoked"));
        }

        let token_hash = token_revocation::hash_token(&req.refresh_token);
        let db_revoked = crate::db::token_revocation::is_token_revoked(&self.state.db, &token_hash)
            .await
            .map_err(|e| {
                error!(
                    error = %e,
                    "Failed to check refresh token revocation in database"
                );
                Status::internal("token_revocation_check_failed")
            })?;
        if db_revoked {
            return Err(Status::unauthenticated("refresh_token_revoked"));
        }

        if let Some(jti) = &claims.jti {
            let jti_revoked = crate::db::token_revocation::is_jti_revoked(&self.state.db, jti)
                .await
                .map_err(|e| {
                    error!(
                        error = %e,
                        "Failed to check refresh token jti revocation in database"
                    );
                    Status::internal("token_revocation_check_failed")
                })?;
            if jti_revoked {
                return Err(Status::unauthenticated("refresh_token_revoked"));
            }
        }

        // Parse user_id UUID from claims.sub
        let user_id = uuid::Uuid::parse_str(&claims.sub)
            .map_err(|_| Status::internal("Invalid user_id in token"))?;

        let user_revoked =
            token_revocation::check_user_token_revocation(&self.state.redis, user_id, claims.iat)
                .await
                .map_err(|e| {
                    error!(
                        error = %e,
                        "Failed to check user-wide token revocation in redis"
                    );
                    Status::internal("token_revocation_check_failed")
                })?;

        if user_revoked {
            return Err(Status::unauthenticated("refresh_token_revoked"));
        }

        // Generate new access token with updated expiration
        let token_response = generate_token_pair(user_id, &claims.email, &claims.username)
            .map_err(|_| Status::internal("Failed to generate token"))?;

        Ok(Response::new(RefreshTokenResponse {
            token: token_response.access_token,
            expires_in: token_response.expires_in as i64,
        }))
    }

    /// Get single user by ID
    /// Called by other services to retrieve user information
    async fn get_user(
        &self,
        request: Request<GetUserRequest>,
    ) -> Result<Response<GetUserResponse>, Status> {
        let req = request.into_inner();

        // Query user from database
        let query_result = sqlx::query_as::<_, (
            String,
            String,
            String,
            DateTime<Utc>,
            bool,
            i32,
            Option<DateTime<Utc>>,
        )>(
            "SELECT id, email, username, created_at, is_active, failed_login_attempts, locked_until FROM users WHERE id = $1 AND deleted_at IS NULL"
        )
        .bind(req.user_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match query_result {
            Some((
                id,
                email,
                username,
                created_at,
                is_active,
                failed_login_attempts,
                locked_until,
            )) => Ok(Response::new(GetUserResponse {
                user: Some(User {
                    id,
                    email,
                    username,
                    created_at: ts(created_at),
                    is_active,
                    failed_login_attempts,
                    locked_until: ts_opt(locked_until),
                }),
                error: ok_error(),
            })),
            None => Err(Status::not_found("User not found")),
        }
    }

    /// Get multiple users in a single batch request
    /// Efficient batch operation for inter-service calls
    async fn get_users_by_ids(
        &self,
        request: Request<GetUsersByIdsRequest>,
    ) -> Result<Response<GetUsersByIdsResponse>, Status> {
        let req = request.into_inner();

        if req.user_ids.is_empty() {
            return Err(Status::invalid_argument("user_ids must not be empty"));
        }

        // Query users by IDs
        let query_result = sqlx::query_as::<_, (
            String,
            String,
            String,
            DateTime<Utc>,
            bool,
            i32,
            Option<DateTime<Utc>>,
        )>(
            "SELECT id, email, username, created_at, is_active, failed_login_attempts, locked_until FROM users WHERE id = ANY($1) AND deleted_at IS NULL"
        )
        .bind(&req.user_ids)
        .fetch_all(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        let users = query_result
            .into_iter()
            .map(
                |(
                    id,
                    email,
                    username,
                    created_at,
                    is_active,
                    failed_login_attempts,
                    locked_until,
                )| User {
                    id,
                    email,
                    username,
                    created_at: ts(created_at),
                    is_active,
                    failed_login_attempts,
                    locked_until: ts_opt(locked_until),
                },
            )
            .collect();

        Ok(Response::new(GetUsersByIdsResponse {
            users,
            error: ok_error(),
        }))
    }

    /// Verify JWT token validity
    /// Core security operation called by all services for request validation
    async fn verify_token(
        &self,
        request: Request<VerifyTokenRequest>,
    ) -> Result<Response<VerifyTokenResponse>, Status> {
        let req = request.into_inner();
        let token_data = match crate::security::jwt::validate_token(&req.token) {
            Ok(data) => data,
            Err(_e) => {
                return Ok(Response::new(VerifyTokenResponse {
                    is_valid: false,
                    user_id: String::new(),
                    email: String::new(),
                    username: String::new(),
                    expires_at: 0,
                    is_revoked: false,
                    error: make_error("TOKEN_INVALID", "Invalid or expired token"),
                }))
            }
        };

        let claims = token_data.claims.clone();

        let redis_revoked = token_revocation::is_token_revoked(&self.state.redis, &req.token)
            .await
            .map_err(|e| {
                error!(
                    error = %e,
                    "Failed to check token revocation in redis during verify_token"
                );
                Status::internal("token_revocation_check_failed")
            })?;

        let token_hash = token_revocation::hash_token(&req.token);
        let db_revoked = crate::db::token_revocation::is_token_revoked(&self.state.db, &token_hash)
            .await
            .map_err(|e| {
                error!(
                    error = %e,
                    "Failed to check token revocation in database during verify_token"
                );
                Status::internal("token_revocation_check_failed")
            })?;

        let mut is_revoked = redis_revoked || db_revoked;

        if let Some(jti) = &claims.jti {
            let jti_revoked = crate::db::token_revocation::is_jti_revoked(&self.state.db, jti)
                .await
                .map_err(|e| {
                    error!(
                        error = %e,
                        "Failed to check token jti revocation in database during verify_token"
                    );
                    Status::internal("token_revocation_check_failed")
                })?;
            is_revoked |= jti_revoked;
        }

        if let Ok(user_uuid) = uuid::Uuid::parse_str(&claims.sub) {
            let user_revoked = token_revocation::check_user_token_revocation(
                &self.state.redis,
                user_uuid,
                claims.iat,
            )
            .await
            .map_err(|e| {
                error!(
                    error = %e,
                    "Failed to check user token revocation window during verify_token"
                );
                Status::internal("token_revocation_check_failed")
            })?;

            if user_revoked {
                is_revoked = true;
            }
        }

        let error = if is_revoked {
            make_error("TOKEN_REVOKED", "Token has been revoked")
        } else {
            ok_error()
        };

        Ok(Response::new(VerifyTokenResponse {
            is_valid: !is_revoked,
            user_id: claims.sub,
            email: claims.email,
            username: claims.username,
            expires_at: claims.exp,
            is_revoked,
            error,
        }))
    }

    /// Check if user exists
    /// Lightweight operation for availability checks
    async fn check_user_exists(
        &self,
        request: Request<CheckUserExistsRequest>,
    ) -> Result<Response<CheckUserExistsResponse>, Status> {
        let req = request.into_inner();

        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL)",
        )
        .bind(req.user_id)
        .fetch_one(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        Ok(Response::new(CheckUserExistsResponse { exists }))
    }

    /// Get user by email address
    /// Used for login and user lookup operations
    async fn get_user_by_email(
        &self,
        request: Request<GetUserByEmailRequest>,
    ) -> Result<Response<GetUserByEmailResponse>, Status> {
        let req = request.into_inner();

        if req.email.is_empty() {
            return Err(Status::invalid_argument("email must not be empty"));
        }

        let query_result = sqlx::query_as::<_, (
            String,
            String,
            String,
            DateTime<Utc>,
            bool,
            i32,
            Option<DateTime<Utc>>,
        )>(
            "SELECT id, email, username, created_at, is_active, failed_login_attempts, locked_until FROM users WHERE email = $1 AND deleted_at IS NULL"
        )
        .bind(req.email)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match query_result {
            Some((
                id,
                email,
                username,
                created_at,
                is_active,
                failed_login_attempts,
                locked_until,
            )) => Ok(Response::new(GetUserByEmailResponse {
                user: Some(User {
                    id,
                    email,
                    username,
                    created_at: ts(created_at),
                    is_active,
                    failed_login_attempts,
                    locked_until: ts_opt(locked_until),
                }),
                error: ok_error(),
            })),
            None => Ok(Response::new(GetUserByEmailResponse {
                user: None,
                error: make_error("NOT_FOUND", "User not found"),
            })),
        }
    }

    /// List users with pagination and search
    /// Administrative and discovery operation
    async fn list_users(
        &self,
        request: Request<ListUsersRequest>,
    ) -> Result<Response<ListUsersResponse>, Status> {
        let req = request.into_inner();

        let limit = (req.limit as i64).min(100).max(1);
        let offset = (req.offset as i64).max(0);

        let total =
            sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM users WHERE deleted_at IS NULL")
                .fetch_one(&self.state.db)
                .await
                .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        let query_result = sqlx::query_as::<_, (
            String,
            String,
            String,
            DateTime<Utc>,
            bool,
            i32,
            Option<DateTime<Utc>>,
        )>(
            "SELECT id, email, username, created_at, is_active, failed_login_attempts, locked_until FROM users WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT $1 OFFSET $2"
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        let users = query_result
            .into_iter()
            .map(
                |(
                    id,
                    email,
                    username,
                    created_at,
                    is_active,
                    failed_login_attempts,
                    locked_until,
                )| User {
                    id,
                    email,
                    username,
                    created_at: ts(created_at),
                    is_active,
                    failed_login_attempts,
                    locked_until: ts_opt(locked_until),
                },
            )
            .collect();

        Ok(Response::new(ListUsersResponse {
            users,
            total_count: total as i32,
            error: ok_error(),
        }))
    }

    /// Check if user has specific permission
    /// Authorization check for protected operations
    async fn check_permission(
        &self,
        request: Request<CheckPermissionRequest>,
    ) -> Result<Response<CheckPermissionResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() || req.permission.is_empty() {
            return Err(Status::invalid_argument(
                "user_id and permission must not be empty",
            ));
        }

        // Check if user has permission via user_permissions table
        let has_permission = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM user_permissions WHERE user_id = $1 AND permission = $2)",
        )
        .bind(&req.user_id)
        .bind(&req.permission)
        .fetch_one(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        Ok(Response::new(CheckPermissionResponse {
            has_permission,
            error: ok_error(),
        }))
    }

    /// Get all permissions for a user
    /// Authorization setup for role-based access control
    async fn get_user_permissions(
        &self,
        request: Request<GetUserPermissionsRequest>,
    ) -> Result<Response<GetUserPermissionsResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id must not be empty"));
        }

        let permissions = sqlx::query_scalar::<_, String>(
            "SELECT permission FROM user_permissions WHERE user_id = $1 ORDER BY permission",
        )
        .bind(&req.user_id)
        .fetch_all(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        // TODO: fetch roles from user_roles table if present; fallback empty
        let roles: Vec<String> = Vec::new();
        Ok(Response::new(GetUserPermissionsResponse {
            permissions,
            roles,
            error: ok_error(),
        }))
    }

    /// Record a failed login attempt (for rate limiting)
    /// Security operation to prevent brute force attacks
    async fn record_failed_login(
        &self,
        request: Request<RecordFailedLoginRequest>,
    ) -> Result<Response<RecordFailedLoginResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id must not be empty"));
        }

        // Configurable max attempts and lock duration
        let max_attempts: i32 = if req.max_attempts > 0 {
            req.max_attempts
        } else {
            5
        };
        let lock_secs: i64 = if req.lock_duration_secs > 0 {
            req.lock_duration_secs as i64
        } else {
            900
        };

        let (failed_attempts, is_locked, locked_until): (i32, bool, Option<DateTime<Utc>>) = sqlx::query_as(
            r#"
            UPDATE users
            SET failed_login_attempts = failed_login_attempts + 1,
                locked_until = CASE
                    WHEN $2 > 0 AND failed_login_attempts + 1 >= $2
                    THEN CURRENT_TIMESTAMP + ($3 || ' seconds')::interval
                    ELSE locked_until
                END
            WHERE id = $1
            RETURNING 
                failed_login_attempts,
                (locked_until IS NOT NULL AND locked_until > CURRENT_TIMESTAMP) AS is_locked,
                locked_until
            "#,
        )
        .bind(&req.user_id)
        .bind(max_attempts)
        .bind(lock_secs.to_string())
        .fetch_one(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        Ok(Response::new(RecordFailedLoginResponse {
            failed_attempts,
            is_locked,
            locked_until: ts_opt(locked_until),
            error: ok_error(),
        }))
    }

    /// Update mutable profile fields (single writer semantics)
    async fn update_user_profile(
        &self,
        request: Request<UpdateUserProfileRequest>,
    ) -> Result<Response<UpdateUserProfileResponse>, Status> {
        let req = request.into_inner();
        let UpdateUserProfileRequest {
            user_id,
            display_name,
            bio,
            avatar_url,
            cover_photo_url,
            location,
            private_account,
        } = req;

        let user_id = uuid::Uuid::parse_str(&user_id)
            .map_err(|_| Status::invalid_argument("invalid_user_id"))?;

        let fields = crate::db::users::UpdateUserProfileFields {
            display_name,
            bio,
            avatar_url,
            cover_photo_url,
            location,
            private_account,
        };

        let profile = crate::db::users::update_user_profile(&self.state.db, user_id, fields)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, user_id = %user_id, "Failed to update user profile");
                Status::internal("failed_to_update_profile")
            })?;

        let response = UpdateUserProfileResponse {
            profile: Some(UserProfile {
                user_id: profile.id.to_string(),
                username: profile.username.clone(),
                email: Some(profile.email.clone()),
                display_name: profile.display_name.clone(),
                bio: profile.bio.clone(),
                avatar_url: profile.avatar_url.clone(),
                cover_photo_url: profile.cover_photo_url.clone(),
                location: profile.location.clone(),
                private_account: profile.private_account,
                created_at: profile.created_at.timestamp(),
                updated_at: profile.updated_at.timestamp(),
            }),
            error: ok_error(),
        };

        Ok(Response::new(response))
    }

    /// Upsert a user's public key for E2EE messaging flows
    async fn upsert_user_public_key(
        &self,
        request: Request<UpsertUserPublicKeyRequest>,
    ) -> Result<Response<UpsertUserPublicKeyResponse>, Status> {
        let req = request.into_inner();

        let user_id = uuid::Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("invalid_user_id"))?;

        if req.public_key.trim().is_empty() {
            return Err(Status::invalid_argument("public_key_required"));
        }

        crate::db::users::upsert_user_public_key(&self.state.db, user_id, &req.public_key)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, user_id = %user_id, "Failed to upsert public key");
                Status::internal("failed_to_upsert_public_key")
            })?;

        Ok(Response::new(UpsertUserPublicKeyResponse {
            success: true,
            error: ok_error(),
        }))
    }

    /// Fetch a user's stored public key if one exists
    async fn get_user_public_key(
        &self,
        request: Request<GetUserPublicKeyRequest>,
    ) -> Result<Response<GetUserPublicKeyResponse>, Status> {
        let req = request.into_inner();

        let user_id = uuid::Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("invalid_user_id"))?;

        let public_key = crate::db::users::get_user_public_key(&self.state.db, user_id)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, user_id = %user_id, "Failed to fetch public key");
                Status::internal("failed_to_fetch_public_key")
            })?;

        let error = if public_key.is_some() {
            ok_error()
        } else {
            make_error("NOT_FOUND", "Public key not found")
        };

        let response = GetUserPublicKeyResponse {
            found: public_key.is_some(),
            public_key,
            error,
        };

        Ok(Response::new(response))
    }
}
