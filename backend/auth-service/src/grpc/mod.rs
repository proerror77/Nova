/// gRPC service implementations for Auth Service
/// Based on Phase 0 proto definitions (nova.auth_service)
/// This is a core foundational service that provides user identity and authentication
use tonic::{Request, Response, Status};

use crate::{
    nova::auth_service::auth_service_server::AuthService, nova::auth_service::*, AppState,
    security::{hash_password, verify_password, generate_token_pair},
};

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

#[tonic::async_trait]
impl AuthService for AuthServiceImpl {
    /// User Registration: Create new account with email, username, password
    /// Per 009-A spec: validates input, hashes password, creates user, returns JWT token
    async fn register(
        &self,
        request: Request<RegisterRequest>,
    ) -> Result<Response<RegisterResponse>, Status> {
        let req = request.into_inner();

        // Validate email format (basic check, full validation in 005-p1-input-validation)
        if req.email.is_empty() || !req.email.contains('@') {
            return Err(Status::invalid_argument("invalid_email_format"));
        }

        // Validate username (3-32 chars)
        if req.username.len() < 3 || req.username.len() > 32 {
            return Err(Status::invalid_argument("username_invalid_length"));
        }

        // Hash password (includes zxcvbn validation via 005)
        let password_hash = hash_password(&req.password)
            .map_err(|_| Status::invalid_argument("weak_password"))?;

        // Check if email already exists
        let email_exists = crate::db::users::email_exists(&self.state.db, &req.email)
            .await
            .map_err(|_| Status::internal("Failed to check email"))?;

        if email_exists {
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
        let req = request.into_inner();

        // Validate email format
        if req.email.is_empty() || !req.email.contains('@') {
            return Err(Status::invalid_argument("invalid_email_format"));
        }

        // Find user by email
        let user = crate::db::users::find_by_email(&self.state.db, &req.email)
            .await
            .map_err(|_| Status::internal("Failed to find user"))?
            .ok_or_else(|| Status::unauthenticated("invalid_credentials"))?;

        // Check if account is locked
        if user.is_locked() {
            let locked_until = user
                .locked_until
                .map(|dt| dt.to_rfc3339())
                .unwrap_or_default();
            return Err(Status::permission_denied(format!(
                "account_locked_until_{}",
                locked_until
            )));
        }

        // Verify password
        verify_password(&req.password, &user.password_hash)
            .map_err(|_| {
                // Record failed attempt (fire-and-forget, don't block on errors)
                let db = self.state.db.clone();
                let user_id = user.id;
                tokio::spawn(async move {
                    let _ = crate::db::users::record_failed_login(&db, user_id, 5, 900).await;
                });
                Status::unauthenticated("invalid_credentials")
            })?;

        // Clear failed login attempts on success
        let _ = crate::db::users::record_successful_login(&self.state.db, user.id).await;

        // Generate JWT token pair
        let token_response = generate_token_pair(user.id, &user.email, &user.username)
            .map_err(|_| Status::internal("Failed to generate token"))?;

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

        // Parse user_id UUID from claims.sub
        let user_id = uuid::Uuid::parse_str(&claims.sub)
            .map_err(|_| Status::internal("Invalid user_id in token"))?;

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
        let query_result = sqlx::query_as::<_, (String, String, String, String, bool, i32, Option<String>)>(
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
                    created_at,
                    is_active,
                    failed_login_attempts,
                    locked_until: locked_until.unwrap_or_default(),
                }),
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
        let query_result = sqlx::query_as::<_, (String, String, String, String, bool, i32, Option<String>)>(
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
                    created_at,
                    is_active,
                    failed_login_attempts,
                    locked_until: locked_until.unwrap_or_default(),
                },
            )
            .collect();

        Ok(Response::new(GetUsersByIdsResponse { users }))
    }

    /// Verify JWT token validity
    /// Core security operation called by all services for request validation
    async fn verify_token(
        &self,
        request: Request<VerifyTokenRequest>,
    ) -> Result<Response<VerifyTokenResponse>, Status> {
        let req = request.into_inner();
        match crate::security::jwt::validate_token(&req.token) {
            Ok(token_data) => {
                let claims = token_data.claims;
                Ok(Response::new(VerifyTokenResponse {
                    is_valid: true,
                    user_id: claims.sub,
                    email: claims.email,
                    username: claims.username,
                    expires_at: claims.exp,
                    is_revoked: false,
                }))
            }
            Err(_e) => Ok(Response::new(VerifyTokenResponse {
                is_valid: false,
                user_id: String::new(),
                email: String::new(),
                username: String::new(),
                expires_at: 0,
                is_revoked: false,
            })),
        }
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

        let query_result = sqlx::query_as::<_, (String, String, String, String, bool, i32, Option<String>)>(
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
                    created_at,
                    is_active,
                    failed_login_attempts,
                    locked_until: locked_until.unwrap_or_default(),
                }),
            })),
            None => Ok(Response::new(GetUserByEmailResponse { user: None })),
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

        let query_result = sqlx::query_as::<_, (String, String, String, String, bool, i32, Option<String>)>(
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
                    created_at,
                    is_active,
                    failed_login_attempts,
                    locked_until: locked_until.unwrap_or_default(),
                },
            )
            .collect();

        Ok(Response::new(ListUsersResponse {
            users,
            total_count: total as i32,
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

        Ok(Response::new(CheckPermissionResponse { has_permission }))
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

        let (failed_attempts, is_locked, locked_until): (i32, bool, String) = sqlx::query_as(
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
                COALESCE(TO_CHAR(locked_until, 'YYYY-MM-DD"T"HH24:MI:SSOF')::text, '')
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
            locked_until,
        }))
    }
}
