/// gRPC server implementation for identity-service
///
/// Implements all 16 RPCs from auth_service.proto:
/// - Authentication: Register, Login, Refresh
/// - Token validation: VerifyToken
/// - User queries: GetUser, GetUsersByIds, GetUserByEmail, CheckUserExists, ListUsers
/// - Authorization: CheckPermission, GetUserPermissions
/// - Security: RecordFailedLogin
/// - Profile: UpdateUserProfile
/// - E2EE: UpsertUserPublicKey, GetUserPublicKey
use crate::db;
use crate::error::IdentityError;
use crate::security::{generate_token_pair, hash_password, validate_token, verify_password};
use crate::services::{EmailService, KafkaEventProducer, TwoFaService};
use chrono::Utc;
use redis_utils::SharedConnectionManager;
use sqlx::PgPool;
use tonic::{Request, Response, Status};
use tracing::{error, info, warn};
use uuid::Uuid;

// Import generated protobuf types
pub mod nova {
    pub mod common {
        pub mod v2 {
            tonic::include_proto!("nova.common.v2");
        }
        pub use v2::*;
    }
    pub mod auth_service {
        pub mod v2 {
            tonic::include_proto!("nova.identity_service.v2");
        }
        pub use v2::*;
    }
}

use nova::auth_service::auth_service_server::AuthService;
use nova::auth_service::*;

/// Identity service gRPC server
#[derive(Clone)]
pub struct IdentityServiceServer {
    db: PgPool,
    redis: SharedConnectionManager,
    email: EmailService,
    two_fa: TwoFaService,
    kafka: Option<KafkaEventProducer>,
}

impl IdentityServiceServer {
    pub fn new(
        db: PgPool,
        redis: SharedConnectionManager,
        email: EmailService,
        kafka: Option<KafkaEventProducer>,
    ) -> Self {
        let two_fa = TwoFaService::new(db.clone(), redis.clone(), kafka.clone());
        Self {
            db,
            redis,
            email,
            two_fa,
            kafka,
        }
    }
}

#[tonic::async_trait]
impl AuthService for IdentityServiceServer {
    /// Register new user with email, username, password
    async fn register(
        &self,
        request: Request<RegisterRequest>,
    ) -> std::result::Result<Response<RegisterResponse>, Status> {
        let req = request.into_inner();

        // Validate email and username
        if !crate::validators::validate_email(&req.email) {
            return Err(Status::invalid_argument("Invalid email format"));
        }
        if !crate::validators::validate_username(&req.username) {
            return Err(Status::invalid_argument("Invalid username format"));
        }

        // Check if user already exists
        if db::users::find_by_email(&self.db, &req.email)
            .await
            .map_err(to_status)?
            .is_some()
        {
            return Err(Status::already_exists("Email already registered"));
        }

        // Hash password (includes strength validation)
        let password_hash = hash_password(&req.password).map_err(to_status)?;

        // Create user
        let user = db::users::create_user(&self.db, &req.email, &req.username, &password_hash)
            .await
            .map_err(to_status)?;

        // Generate token pair
        let tokens =
            generate_token_pair(user.id, &user.email, &user.username).map_err(anyhow_to_status)?;

        // Publish UserCreated event
        if let Some(producer) = &self.kafka {
            if let Err(err) = producer
                .publish_user_created(user.id, &user.email, &user.username)
                .await
            {
                warn!("Failed to publish UserCreated event: {:?}", err);
            }
        }

        info!(user_id = %user.id, email = %user.email, "User registered successfully");

        Ok(Response::new(RegisterResponse {
            user_id: user.id.to_string(),
            token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_in: tokens.expires_in,
        }))
    }

    /// Authenticate user with email and password
    async fn login(
        &self,
        request: Request<LoginRequest>,
    ) -> std::result::Result<Response<LoginResponse>, Status> {
        let req = request.into_inner();

        // Find user by email or username (supports both for login)
        let user = db::users::find_by_email_or_username(&self.db, &req.email)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::unauthenticated("Invalid username or password"))?;

        // Check if account is locked
        if let Some(locked_until) = user.locked_until {
            if locked_until > Utc::now() {
                return Err(Status::permission_denied(format!(
                    "Account locked until {}",
                    locked_until
                )));
            }
        }

        // Verify password
        let password_valid =
            verify_password(&req.password, &user.password_hash).map_err(to_status)?;

        if !password_valid {
            // Record failed login attempt
            db::users::record_failed_login(&self.db, user.id, 5, 900)
                .await
                .map_err(to_status)?;

            return Err(Status::unauthenticated("Invalid username or password"));
        }

        // Reset failed login attempts
        db::users::reset_failed_login(&self.db, user.id)
            .await
            .map_err(to_status)?;

        // Generate token pair
        let tokens =
            generate_token_pair(user.id, &user.email, &user.username).map_err(anyhow_to_status)?;

        info!(user_id = %user.id, "User logged in successfully");

        Ok(Response::new(LoginResponse {
            user_id: user.id.to_string(),
            token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_in: tokens.expires_in,
        }))
    }

    /// Refresh access token using refresh token
    async fn refresh(
        &self,
        request: Request<RefreshTokenRequest>,
    ) -> std::result::Result<Response<RefreshTokenResponse>, Status> {
        let req = request.into_inner();

        // Validate refresh token
        let token_data = validate_token(&req.refresh_token).map_err(anyhow_to_status)?;

        // Parse user ID from token claims
        let user_id = Uuid::parse_str(&token_data.claims.sub)
            .map_err(|_| Status::invalid_argument("Invalid user ID in token"))?;

        // Fetch user to get latest info
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        // Generate new token pair
        let tokens =
            generate_token_pair(user.id, &user.email, &user.username).map_err(anyhow_to_status)?;

        Ok(Response::new(RefreshTokenResponse {
            token: tokens.access_token,
            expires_in: tokens.expires_in,
        }))
    }

    /// Get user by ID
    async fn get_user(
        &self,
        request: Request<GetUserRequest>,
    ) -> std::result::Result<Response<GetUserResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        Ok(Response::new(GetUserResponse {
            user: Some(user_model_to_proto(&user)),
            error: None,
        }))
    }

    /// Get multiple users by IDs (batch operation)
    async fn get_users_by_ids(
        &self,
        request: Request<GetUsersByIdsRequest>,
    ) -> std::result::Result<Response<GetUsersByIdsResponse>, Status> {
        let req = request.into_inner();

        let user_ids: Vec<Uuid> = req
            .user_ids
            .iter()
            .filter_map(|id| Uuid::parse_str(id).ok())
            .collect();

        if user_ids.is_empty() {
            return Ok(Response::new(GetUsersByIdsResponse {
                users: vec![],
                error: None,
            }));
        }

        let users = db::users::find_by_ids(&self.db, &user_ids)
            .await
            .map_err(to_status)?;

        Ok(Response::new(GetUsersByIdsResponse {
            users: users.into_iter().map(|u| user_model_to_proto(&u)).collect(),
            error: None,
        }))
    }

    /// Verify JWT token validity
    async fn verify_token(
        &self,
        request: Request<VerifyTokenRequest>,
    ) -> std::result::Result<Response<VerifyTokenResponse>, Status> {
        let req = request.into_inner();

        match validate_token(&req.token) {
            Ok(token_data) => Ok(Response::new(VerifyTokenResponse {
                is_valid: true,
                user_id: token_data.claims.sub.clone(),
                email: token_data.claims.email.clone(),
                username: token_data.claims.username.clone(),
                expires_at: token_data.claims.exp,
                is_revoked: false,
                error: None,
            })),
            Err(err) => {
                let err_msg = err.to_string();
                let is_revoked = err_msg.contains("revoked") || err_msg.contains("Revoked");
                Ok(Response::new(VerifyTokenResponse {
                    is_valid: false,
                    user_id: String::new(),
                    email: String::new(),
                    username: String::new(),
                    expires_at: 0,
                    is_revoked,
                    error: None,
                }))
            }
        }
    }

    /// Check if user exists
    async fn check_user_exists(
        &self,
        request: Request<CheckUserExistsRequest>,
    ) -> std::result::Result<Response<CheckUserExistsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let exists = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .is_some();

        Ok(Response::new(CheckUserExistsResponse { exists }))
    }

    /// Get user by email address
    async fn get_user_by_email(
        &self,
        request: Request<GetUserByEmailRequest>,
    ) -> std::result::Result<Response<GetUserByEmailResponse>, Status> {
        let req = request.into_inner();

        let user = db::users::find_by_email(&self.db, &req.email)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        Ok(Response::new(GetUserByEmailResponse {
            user: Some(user_model_to_proto(&user)),
            error: None,
        }))
    }

    /// List users with pagination and search
    async fn list_users(
        &self,
        request: Request<ListUsersRequest>,
    ) -> std::result::Result<Response<ListUsersResponse>, Status> {
        let req = request.into_inner();

        let limit = req.limit.clamp(1, 100) as i64;
        let offset = req.offset.max(0) as i64;

        let users = if req.search.is_empty() {
            db::users::list_users(&self.db, limit, offset)
                .await
                .map_err(to_status)?
        } else {
            db::users::search_users(&self.db, &req.search, limit)
                .await
                .map_err(to_status)?
        };

        let total_count = users.len() as i32;

        Ok(Response::new(ListUsersResponse {
            users: users.into_iter().map(|u| user_model_to_proto(&u)).collect(),
            total_count,
            error: None,
        }))
    }

    /// Check if user has specific permission
    async fn check_permission(
        &self,
        request: Request<CheckPermissionRequest>,
    ) -> std::result::Result<Response<CheckPermissionResponse>, Status> {
        let _req = request.into_inner();

        // TODO: Implement RBAC permission checking
        // For now, return false (requires role/permission system)
        Ok(Response::new(CheckPermissionResponse {
            has_permission: false,
            error: None,
        }))
    }

    /// Get all permissions for a user
    async fn get_user_permissions(
        &self,
        request: Request<GetUserPermissionsRequest>,
    ) -> std::result::Result<Response<GetUserPermissionsResponse>, Status> {
        let _req = request.into_inner();

        // TODO: Implement RBAC permission system
        // For now, return empty lists
        Ok(Response::new(GetUserPermissionsResponse {
            permissions: vec![],
            roles: vec![],
            error: None,
        }))
    }

    /// Record failed login attempt
    async fn record_failed_login(
        &self,
        request: Request<RecordFailedLoginRequest>,
    ) -> std::result::Result<Response<RecordFailedLoginResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let user = db::users::record_failed_login(
            &self.db,
            user_id,
            req.max_attempts,
            req.lock_duration_secs as i64,
        )
        .await
        .map_err(to_status)?;

        let is_locked = user
            .locked_until
            .map(|locked_until| locked_until > Utc::now())
            .unwrap_or(false);

        Ok(Response::new(RecordFailedLoginResponse {
            failed_attempts: user.failed_login_attempts,
            is_locked,
            locked_until: user.locked_until.map(|dt| dt.timestamp()),
            error: None,
        }))
    }

    /// Update mutable user profile fields
    async fn update_user_profile(
        &self,
        request: Request<UpdateUserProfileRequest>,
    ) -> std::result::Result<Response<UpdateUserProfileResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        // Update profile fields
        let fields = db::users::UpdateUserProfileFields {
            display_name: req.display_name,
            bio: req.bio,
            avatar_url: req.avatar_url,
            cover_photo_url: req.cover_photo_url,
            location: req.location,
            private_account: req.private_account,
        };

        db::users::update_user_profile(&self.db, user_id, fields)
            .await
            .map_err(to_status)?;

        // Fetch updated user
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        Ok(Response::new(UpdateUserProfileResponse {
            profile: Some(UserProfile {
                user_id: user.id.to_string(),
                username: user.username.clone(),
                email: Some(user.email.clone()),
                display_name: user.display_name.clone(),
                bio: user.bio.clone(),
                avatar_url: user.avatar_url.clone(),
                cover_photo_url: user.cover_photo_url.clone(),
                location: user.location.clone(),
                private_account: user.private_account,
                created_at: user.created_at.timestamp(),
                updated_at: user.updated_at.timestamp(),
            }),
            error: None,
        }))
    }

    /// Store user public key for E2EE
    async fn upsert_user_public_key(
        &self,
        request: Request<UpsertUserPublicKeyRequest>,
    ) -> std::result::Result<Response<UpsertUserPublicKeyResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        db::users::upsert_user_public_key(&self.db, user_id, &req.public_key)
            .await
            .map_err(to_status)?;

        Ok(Response::new(UpsertUserPublicKeyResponse {
            success: true,
            error: None,
        }))
    }

    /// Retrieve user public key for E2EE
    async fn get_user_public_key(
        &self,
        request: Request<GetUserPublicKeyRequest>,
    ) -> std::result::Result<Response<GetUserPublicKeyResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let public_key = db::users::get_user_public_key(&self.db, user_id)
            .await
            .map_err(to_status)?;

        Ok(Response::new(GetUserPublicKeyResponse {
            found: public_key.is_some(),
            public_key,
            error: None,
        }))
    }
}

// ===== Helper Functions =====

fn to_status(err: IdentityError) -> Status {
    error!("Identity error: {:?}", err);
    match err {
        IdentityError::UserNotFound => Status::not_found("User not found"),
        IdentityError::EmailAlreadyExists => Status::already_exists("Email already registered"),
        IdentityError::UsernameAlreadyExists => Status::already_exists("Username already taken"),
        IdentityError::InvalidCredentials => Status::unauthenticated("Invalid credentials"),
        IdentityError::InvalidToken => Status::unauthenticated("Invalid token"),
        IdentityError::TokenRevoked => Status::unauthenticated("Token revoked"),
        IdentityError::TokenExpired => Status::unauthenticated("Token expired"),
        IdentityError::WeakPassword(_) => Status::invalid_argument("Password too weak"),
        IdentityError::InvalidEmail(_) => Status::invalid_argument("Invalid email format"),
        IdentityError::InvalidUsername(_) => Status::invalid_argument("Invalid username"),
        IdentityError::TwoFANotEnabled => Status::failed_precondition("2FA not enabled"),
        IdentityError::TwoFARequired => Status::unauthenticated("2FA required"),
        IdentityError::InvalidTwoFACode => Status::invalid_argument("Invalid 2FA code"),
        IdentityError::PasswordResetTokenExpired => {
            Status::invalid_argument("Password reset token expired")
        }
        IdentityError::InvalidPasswordResetToken => {
            Status::invalid_argument("Invalid password reset token")
        }
        IdentityError::SessionNotFound => Status::not_found("Session not found"),
        IdentityError::AccountLocked(until) => {
            Status::permission_denied(format!("Account locked until: {}", until))
        }
        IdentityError::OAuthError(msg) => Status::internal(format!("OAuth error: {}", msg)),
        IdentityError::InvalidOAuthState => Status::invalid_argument("Invalid OAuth state"),
        IdentityError::InvalidOAuthProvider => Status::invalid_argument("Invalid OAuth provider"),
        IdentityError::Database(msg) => Status::internal(format!("Database error: {}", msg)),
        IdentityError::Redis(msg) => Status::internal(format!("Redis error: {}", msg)),
        IdentityError::JwtError(msg) => Status::internal(format!("JWT error: {}", msg)),
        IdentityError::Validation(msg) => {
            Status::invalid_argument(format!("Validation error: {}", msg))
        }
        IdentityError::Internal(msg) => Status::internal(msg),
    }
}

/// Convert anyhow::Error to gRPC Status
/// Used for crypto-core functions that return anyhow::Error
fn anyhow_to_status(err: anyhow::Error) -> Status {
    let msg = err.to_string();
    // Map specific JWT errors
    if msg.contains("Token validation failed") || msg.contains("Invalid token") {
        Status::unauthenticated("Invalid or expired token")
    } else if msg.contains("not initialized") {
        Status::internal("JWT system not initialized")
    } else {
        error!("Anyhow error: {}", msg);
        Status::internal("Internal server error")
    }
}

fn user_model_to_proto(user: &crate::models::User) -> User {
    User {
        id: user.id.to_string(),
        email: user.email.clone(),
        username: user.username.clone(),
        created_at: user.created_at.timestamp(),
        is_active: user.deleted_at.is_none(),
        failed_login_attempts: user.failed_login_attempts,
        locked_until: user.locked_until.map(|dt| dt.timestamp()),
    }
}
