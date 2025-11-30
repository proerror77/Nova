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
use crate::services::{
    EmailService, InviteDeliveryConfig, InviteDeliveryService, KafkaEventProducer, TwoFaService,
};
use chrono::{TimeZone, Utc};
use redis_utils::SharedConnectionManager;
use sqlx::PgPool;
use tonic::{Request, Response, Status};
use tracing::{error, info, warn};
use uuid::Uuid;

use std::collections::HashSet;

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
    invite_delivery: std::sync::Arc<InviteDeliveryService>,
}

impl IdentityServiceServer {
    pub fn new(
        db: PgPool,
        redis: SharedConnectionManager,
        email: EmailService,
        kafka: Option<KafkaEventProducer>,
        sns_client: Option<aws_sdk_sns::Client>,
    ) -> Self {
        let two_fa = TwoFaService::new(db.clone(), redis.clone(), kafka.clone());
        let invite_delivery = std::sync::Arc::new(InviteDeliveryService::new(
            db.clone(),
            sns_client,
            email.clone(),
            InviteDeliveryConfig::default(),
        ));
        Self {
            db,
            redis,
            email,
            two_fa,
            kafka,
            invite_delivery,
        }
    }
}

#[tonic::async_trait]
impl AuthService for IdentityServiceServer {
    /// Register new user with email, username, password, and invite code
    async fn register(
        &self,
        request: Request<RegisterRequest>,
    ) -> std::result::Result<Response<RegisterResponse>, Status> {
        let req = request.into_inner();

        // 1. Validate invite code FIRST (invite-only registration)
        if req.invite_code.is_empty() {
            return Err(Status::invalid_argument(
                "Invite code is required. Nova is invite-only.",
            ));
        }

        let invite_validation = db::invitations::validate_invite(&self.db, &req.invite_code)
            .await
            .map_err(to_status)?;

        if !invite_validation.is_valid {
            let error_msg = match invite_validation.error.as_deref() {
                Some("not_found") => "Invalid invite code",
                Some("already_used") => "This invite code has already been used",
                Some("expired") => "This invite code has expired",
                _ => "Invalid invite code",
            };
            return Err(Status::invalid_argument(error_msg));
        }

        // 2. Validate email and username
        if !crate::validators::validate_email(&req.email) {
            return Err(Status::invalid_argument("Invalid email format"));
        }
        if !crate::validators::validate_username(&req.username) {
            return Err(Status::invalid_argument("Invalid username format"));
        }

        // 3. Check if user already exists
        if db::users::find_by_email(&self.db, &req.email)
            .await
            .map_err(to_status)?
            .is_some()
        {
            return Err(Status::already_exists("Email already registered"));
        }

        // 4. Hash password (includes strength validation)
        let password_hash = hash_password(&req.password).map_err(to_status)?;

        // 5. Create user
        let user = db::users::create_user(&self.db, &req.email, &req.username, &password_hash)
            .await
            .map_err(to_status)?;

        // 6. Redeem the invite code (this triggers referral chain setup via DB trigger)
        let redeemed = db::invitations::redeem_invite(&self.db, &req.invite_code, user.id)
            .await
            .map_err(to_status)?;

        if !redeemed {
            // This shouldn't happen if validation passed, but log it
            warn!(
                user_id = %user.id,
                invite_code = %req.invite_code,
                "Failed to redeem invite code after user creation"
            );
        } else {
            info!(
                user_id = %user.id,
                invite_code = %req.invite_code,
                inviter = ?invite_validation.issuer_username,
                "Invite code redeemed successfully"
            );
        }

        // 7. Generate token pair
        let tokens =
            generate_token_pair(user.id, &user.email, &user.username).map_err(anyhow_to_status)?;

        // 8. Publish UserCreated event
        if let Some(producer) = &self.kafka {
            if let Err(err) = producer
                .publish_user_created(user.id, &user.email, &user.username)
                .await
            {
                warn!("Failed to publish UserCreated event: {:?}", err);
            }
        }

        info!(
            user_id = %user.id,
            email = %user.email,
            referred_by = ?invite_validation.issuer_username,
            "User registered successfully via invite"
        );

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

    /// Generate invite code for onboarding
    async fn generate_invite(
        &self,
        request: Request<GenerateInviteRequest>,
    ) -> std::result::Result<Response<GenerateInviteResponse>, Status> {
        let req = request.into_inner();
        let issuer_id = Uuid::parse_str(&req.issuer_user_id)
            .map_err(|_| Status::invalid_argument("Invalid issuer_user_id"))?;

        // Ensure issuer exists
        db::users::find_by_id(&self.db, issuer_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("Issuer not found"))?;

        let expires_at = req
            .expires_at
            .and_then(|ts| Utc.timestamp_opt(ts, 0).single());

        let invite = db::invitations::create_invite(
            &self.db,
            issuer_id,
            req.target_email,
            req.target_phone,
            expires_at,
        )
        .await
        .map_err(to_status)?;

        let base_url = std::env::var("INVITE_BASE_URL")
            .unwrap_or_else(|_| "https://nova.app/invite".to_string());
        let invite_url = format!("{}/{}", base_url.trim_end_matches('/'), invite.code);

        Ok(Response::new(GenerateInviteResponse {
            code: invite.code,
            invite_url,
            expires_at: invite.expires_at.timestamp(),
        }))
    }

    /// Redeem invite code (idempotent)
    async fn redeem_invite(
        &self,
        request: Request<RedeemInviteRequest>,
    ) -> std::result::Result<Response<RedeemInviteResponse>, Status> {
        let req = request.into_inner();
        let new_user_id = Uuid::parse_str(&req.new_user_id)
            .map_err(|_| Status::invalid_argument("Invalid new_user_id"))?;

        let invite = db::invitations::get_invite(&self.db, &req.code)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("Invite not found"))?;

        if invite.redeemed_at.is_some() {
            return Ok(Response::new(RedeemInviteResponse { success: false }));
        }

        if invite.expires_at < Utc::now() {
            return Err(Status::failed_precondition("Invite expired"));
        }

        // Mark as redeemed
        let redeemed = db::invitations::redeem_invite(&self.db, &req.code, new_user_id)
            .await
            .map_err(to_status)?;

        Ok(Response::new(RedeemInviteResponse { success: redeemed }))
    }

    /// List invitations created by a user
    async fn list_invitations(
        &self,
        request: Request<ListInvitationsRequest>,
    ) -> std::result::Result<Response<ListInvitationsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        let limit = req.limit.unwrap_or(50).clamp(1, 100) as i64;
        let offset = req.offset.unwrap_or(0).max(0) as i64;

        let (invites, total) =
            db::invitations::list_user_invitations(&self.db, user_id, limit, offset)
                .await
                .map_err(to_status)?;

        let base_url = std::env::var("INVITE_BASE_URL")
            .unwrap_or_else(|_| "https://nova.app/invite".to_string());

        let invitation_infos: Vec<InvitationInfo> = invites
            .into_iter()
            .map(|inv| InvitationInfo {
                code: inv.code.clone(),
                invite_url: format!("{}/{}", base_url.trim_end_matches('/'), inv.code),
                created_at: inv.created_at.timestamp(),
                expires_at: inv.expires_at.timestamp(),
                is_redeemed: inv.redeemed_at.is_some(),
                redeemed_by_user_id: inv.redeemed_by.map(|id| id.to_string()),
                redeemed_at: inv.redeemed_at.map(|dt| dt.timestamp()),
            })
            .collect();

        Ok(Response::new(ListInvitationsResponse {
            invitations: invitation_infos,
            total: total as i32,
        }))
    }

    /// Get invitation statistics for a user
    async fn get_invitation_stats(
        &self,
        request: Request<GetInvitationStatsRequest>,
    ) -> std::result::Result<Response<GetInvitationStatsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        let stats = db::invitations::get_invitation_stats(&self.db, user_id)
            .await
            .map_err(to_status)?;

        Ok(Response::new(GetInvitationStatsResponse {
            total_generated: stats.total_generated,
            total_redeemed: stats.total_redeemed,
            total_pending: stats.total_pending,
            total_expired: stats.total_expired,
        }))
    }

    /// Get invite quota for a user
    async fn get_invite_quota(
        &self,
        request: Request<GetInviteQuotaRequest>,
    ) -> std::result::Result<Response<GetInviteQuotaResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        let quota = db::invitations::get_invite_quota(&self.db, user_id)
            .await
            .map_err(to_status)?;

        Ok(Response::new(GetInviteQuotaResponse {
            total_quota: quota.total_quota,
            used_quota: quota.used_quota,
            remaining_quota: quota.remaining_quota,
            successful_referrals: quota.successful_referrals,
        }))
    }

    /// Send invite via SMS, Email, or Link
    async fn send_invite(
        &self,
        request: Request<SendInviteRequest>,
    ) -> std::result::Result<Response<SendInviteResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        // Check quota
        if !db::invitations::can_create_invite(&self.db, user_id)
            .await
            .map_err(to_status)?
        {
            return Ok(Response::new(SendInviteResponse {
                success: false,
                invite_code: String::new(),
                invite_url: String::new(),
                share_text: String::new(),
                delivery_id: None,
                error: Some("No remaining invite quota".into()),
            }));
        }

        // Get user info for personalized message
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        // Create invite code
        let invite = db::invitations::create_invite(&self.db, user_id, None, None, None)
            .await
            .map_err(to_status)?;

        // Send via the specified channel
        let result = self
            .invite_delivery
            .send_invite(
                &invite,
                &req.channel,
                req.recipient.as_deref(),
                Some(&user.username),
                req.message.as_deref(),
            )
            .await
            .map_err(to_status)?;

        Ok(Response::new(SendInviteResponse {
            success: result.success,
            invite_code: result.invite_code,
            invite_url: result.invite_url,
            share_text: result.share_text,
            delivery_id: result.delivery_id,
            error: result.error,
        }))
    }

    /// Validate invite code (public - no auth required)
    async fn validate_invite(
        &self,
        request: Request<ValidateInviteRequest>,
    ) -> std::result::Result<Response<ValidateInviteResponse>, Status> {
        let req = request.into_inner();

        if req.code.is_empty() {
            return Err(Status::invalid_argument("Invite code is required"));
        }

        let validation = db::invitations::validate_invite(&self.db, &req.code)
            .await
            .map_err(to_status)?;

        Ok(Response::new(ValidateInviteResponse {
            is_valid: validation.is_valid,
            issuer_username: validation.issuer_username,
            expires_at: validation.expires_at.map(|dt| dt.timestamp()),
            error: validation.error,
        }))
    }

    /// Get referral chain info for a user
    async fn get_referral_info(
        &self,
        request: Request<GetReferralInfoRequest>,
    ) -> std::result::Result<Response<GetReferralInfoResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        let info = db::invitations::get_referral_info(&self.db, user_id)
            .await
            .map_err(to_status)?;

        let referred_by = info.referred_by.map(|r| ReferralUser {
            user_id: r.user_id.to_string(),
            username: r.username,
            avatar_url: r.avatar_url,
            joined_at: r.joined_at.timestamp(),
            status: r.status,
        });

        let referrals: Vec<ReferralUser> = info
            .referrals
            .into_iter()
            .map(|r| ReferralUser {
                user_id: r.user_id.to_string(),
                username: r.username,
                avatar_url: r.avatar_url,
                joined_at: r.joined_at.timestamp(),
                status: r.status,
            })
            .collect();

        Ok(Response::new(GetReferralInfoResponse {
            referred_by,
            referrals,
            total_referrals: info.total_referrals,
            active_referrals: info.active_referrals,
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

    /// List active devices for a user (sessions)
    async fn list_devices(
        &self,
        request: Request<ListDevicesRequest>,
    ) -> std::result::Result<Response<ListDevicesResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let limit = req.limit.clamp(1, 100) as i64;
        let offset = req.offset.max(0) as i64;

        let (devices, total) = db::devices::list_devices(&self.db, user_id, limit, offset)
            .await
            .map_err(to_status)?;

        let mut proto_devices: Vec<Device> = devices
            .into_iter()
            .enumerate()
            .map(|(idx, d)| Device {
                id: d.device_id,
                name: d.device_name.unwrap_or_else(|| "unknown".into()),
                device_type: d.device_type.unwrap_or_else(|| "unknown".into()),
                os: d
                    .os_name
                    .map(|os| {
                        if let Some(ver) = d.os_version.clone() {
                            format!("{} {}", os, ver)
                        } else {
                            os
                        }
                    })
                    .unwrap_or_else(|| "unknown".into()),
                last_active: d.last_activity_at.timestamp(),
                is_current: idx == 0,
            })
            .collect();

        // If a device exists, ensure the most recent marks as current
        if let Some(first) = proto_devices.first_mut() {
            first.is_current = true;
        }

        Ok(Response::new(ListDevicesResponse {
            devices: proto_devices,
            total: total as i32,
        }))
    }

    /// Logout device(s) by revoking sessions
    async fn logout_device(
        &self,
        request: Request<LogoutDeviceRequest>,
    ) -> std::result::Result<Response<LogoutDeviceResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let device_id = if req.device_id.is_empty() {
            None
        } else {
            Some(req.device_id.as_str())
        };

        let affected = db::devices::logout_device(&self.db, user_id, device_id, req.all)
            .await
            .map_err(to_status)?;

        Ok(Response::new(LogoutDeviceResponse {
            success: affected > 0,
        }))
    }

    /// Get current device (most recent session)
    async fn get_current_device(
        &self,
        request: Request<GetCurrentDeviceRequest>,
    ) -> std::result::Result<Response<GetCurrentDeviceResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let device = db::devices::get_current_device(&self.db, user_id, req.device_id.as_deref())
            .await
            .map_err(to_status)?;

        let proto_device = device.map(|d| Device {
            id: d.device_id,
            name: d.device_name.unwrap_or_else(|| "unknown".into()),
            device_type: d.device_type.unwrap_or_else(|| "unknown".into()),
            os: d
                .os_name
                .map(|os| {
                    if let Some(ver) = d.os_version {
                        format!("{} {}", os, ver)
                    } else {
                        os
                    }
                })
                .unwrap_or_else(|| "unknown".into()),
            last_active: d.last_activity_at.timestamp(),
            is_current: true,
        });

        Ok(Response::new(GetCurrentDeviceResponse {
            device: proto_device,
        }))
    }

    /// List user channel subscriptions
    async fn list_user_channels(
        &self,
        request: Request<ListUserChannelsRequest>,
    ) -> std::result::Result<Response<ListUserChannelsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let channels = db::user_channels::list_user_channels(&self.db, user_id)
            .await
            .map_err(to_status)?;

        Ok(Response::new(ListUserChannelsResponse {
            channel_ids: channels,
        }))
    }

    /// Update user channel subscriptions
    async fn update_user_channels(
        &self,
        request: Request<UpdateUserChannelsRequest>,
    ) -> std::result::Result<Response<UpdateUserChannelsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        // dedupe to avoid churn
        let subscribe: HashSet<String> = req.subscribe_ids.into_iter().collect();
        let unsubscribe: HashSet<String> = req.unsubscribe_ids.into_iter().collect();

        let channels = db::user_channels::update_user_channels(
            &self.db,
            user_id,
            &subscribe.into_iter().collect::<Vec<_>>(),
            &unsubscribe.into_iter().collect::<Vec<_>>(),
        )
        .await
        .map_err(to_status)?;

        Ok(Response::new(UpdateUserChannelsResponse {
            channel_ids: channels,
        }))
    }

    /// Get user settings (P0: user-service migration)
    async fn get_user_settings(
        &self,
        request: Request<GetUserSettingsRequest>,
    ) -> std::result::Result<Response<GetUserSettingsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let settings = db::user_settings::get_user_settings(&self.db, user_id)
            .await
            .map_err(to_status)?;

        Ok(Response::new(GetUserSettingsResponse {
            settings: Some(settings_to_proto(&settings)),
            error: None,
        }))
    }

    /// Update user settings (P0: user-service migration)
    async fn update_user_settings(
        &self,
        request: Request<UpdateUserSettingsRequest>,
    ) -> std::result::Result<Response<UpdateUserSettingsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        // Validate dm_permission if provided
        if let Some(ref dm) = req.dm_permission {
            if !["anyone", "followers", "mutuals", "nobody"].contains(&dm.as_str()) {
                return Err(Status::invalid_argument(
                    "Invalid dm_permission: must be 'anyone', 'followers', 'mutuals', or 'nobody'",
                ));
            }
        }

        // Validate privacy_level if provided
        if let Some(ref pl) = req.privacy_level {
            if !["public", "friends_only", "private"].contains(&pl.as_str()) {
                return Err(Status::invalid_argument(
                    "Invalid privacy_level: must be 'public', 'friends_only', or 'private'",
                ));
            }
        }

        let fields = db::user_settings::UpdateUserSettingsFields {
            dm_permission: req.dm_permission,
            email_notifications: req.email_notifications,
            push_notifications: req.push_notifications,
            marketing_emails: req.marketing_emails,
            timezone: req.timezone,
            language: req.language,
            dark_mode: req.dark_mode,
            privacy_level: req.privacy_level,
            allow_messages: req.allow_messages,
            show_online_status: req.show_online_status,
        };

        let settings = db::user_settings::update_user_settings(&self.db, user_id, fields)
            .await
            .map_err(to_status)?;

        info!(user_id = %user_id, "User settings updated");

        Ok(Response::new(UpdateUserSettingsResponse {
            settings: Some(settings_to_proto(&settings)),
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

fn settings_to_proto(settings: &db::user_settings::UserSettingsRecord) -> UserSettings {
    UserSettings {
        user_id: settings.user_id.to_string(),
        dm_permission: settings.dm_permission.clone(),
        email_notifications: settings.email_notifications,
        push_notifications: settings.push_notifications,
        marketing_emails: settings.marketing_emails,
        timezone: settings.timezone.clone(),
        language: settings.language.clone(),
        dark_mode: settings.dark_mode,
        privacy_level: settings.privacy_level.clone(),
        allow_messages: settings.allow_messages,
        show_online_status: settings.show_online_status,
        created_at: settings.created_at.timestamp(),
        updated_at: settings.updated_at.timestamp(),
    }
}
