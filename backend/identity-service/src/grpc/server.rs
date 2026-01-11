/// gRPC server implementation for identity-service
///
/// Implements all RPCs from identity_service.proto:
/// - Authentication: Register, Login, Refresh
/// - Token validation: VerifyToken
/// - User queries: GetUser, GetUsersByIds, GetUserByEmail, CheckUserExists, ListUsers
/// - Authorization: CheckPermission, GetUserPermissions
/// - Security: RecordFailedLogin
/// - Profile: UpdateUserProfile
/// - E2EE: UpsertUserPublicKey, GetUserPublicKey
/// - OAuth/SSO: StartOAuthFlow, CompleteOAuthFlow, ListOAuthConnections, UnlinkOAuthProvider
/// - Account Management: ListAccounts, SwitchAccount, CreateAliasAccount, UpdateAliasAccount, GetAliasAccount, DeleteAliasAccount
/// - Passkey/WebAuthn: StartPasskeyRegistration, CompletePasskeyRegistration, StartPasskeyAuthentication, CompletePasskeyAuthentication, ListPasskeys, RevokePasskey, RenamePasskey
use crate::config::{OAuthSettings, PasskeySettings};
use crate::db;
use crate::error::IdentityError;
use crate::security::{generate_token_pair, hash_password, validate_token, verify_password};
use crate::services::{
    EmailAuthService, EmailService, InviteDeliveryConfig, InviteDeliveryService,
    KafkaEventProducer, OAuthService, PasskeyService, PhoneAuthService, TwoFaService,
    ZitadelService,
};
use chrono::{TimeZone, Utc};
use redis_utils::SharedConnectionManager;
use sqlx::PgPool;
use tonic::{Request, Response, Status};
use tracing::{error, info, warn};
use uuid::Uuid;

use prost_types;
use std::collections::HashSet;

// Import generated protobuf types
pub mod nova {
    pub mod auth_service {
        tonic::include_proto!("nova.auth_service");
    }
}

use nova::auth_service::auth_service_server::AuthService;
use nova::auth_service::*;

/// Identity service gRPC server
#[derive(Clone)]
pub struct IdentityServiceServer {
    db: PgPool,
    #[allow(dead_code)] // Used internally by OAuthService
    redis: SharedConnectionManager,
    email: EmailService,
    #[allow(dead_code)] // Reserved for 2FA implementation
    _two_fa: TwoFaService,
    kafka: Option<KafkaEventProducer>,
    invite_delivery: std::sync::Arc<InviteDeliveryService>,
    oauth: OAuthService,
    phone_auth: PhoneAuthService,
    email_auth: EmailAuthService,
    passkey: std::sync::Arc<PasskeyService>,
}

impl IdentityServiceServer {
    pub fn new(
        db: PgPool,
        redis: SharedConnectionManager,
        email: EmailService,
        kafka: Option<KafkaEventProducer>,
        sns_client: Option<aws_sdk_sns::Client>,
        oauth_settings: OAuthSettings,
        passkey_settings: PasskeySettings,
    ) -> Result<Self, IdentityError> {
        let two_fa = TwoFaService::new(db.clone(), redis.clone(), kafka.clone());
        let invite_delivery = std::sync::Arc::new(InviteDeliveryService::new(
            db.clone(),
            sns_client.clone(),
            email.clone(),
            InviteDeliveryConfig::default(),
        ));
        let oauth = OAuthService::new(oauth_settings, db.clone(), redis.clone(), kafka.clone());
        let phone_auth = PhoneAuthService::new(db.clone(), redis.clone(), sns_client);
        let email_auth = EmailAuthService::new(db.clone(), redis.clone(), email.clone());

        // Initialize PasskeyService
        let passkey = PasskeyService::new(
            db.clone(),
            redis.clone(),
            kafka.clone(),
            passkey_settings,
            None, // ZitadelService is optional
        )?;

        Ok(Self {
            db,
            redis,
            email,
            _two_fa: two_fa,
            kafka,
            invite_delivery,
            oauth,
            phone_auth,
            email_auth,
            passkey: std::sync::Arc::new(passkey),
        })
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
        if let Some(existing) = db::users::find_by_email(&self.db, &req.email)
            .await
            .map_err(to_status)?
        {
            // If password matches an existing account, treat this as idempotent
            // registration and simply return a fresh token pair instead of an error.
            if verify_password(&req.password, &existing.password_hash).map_err(to_status)? {
                let tokens = generate_token_pair(
                    existing.id,
                    &existing.email,
                    &existing.username,
                    Some("primary"),
                    None,
                )
                .map_err(anyhow_to_status)?;

                info!(
                    user_id = %existing.id,
                    email = %existing.email,
                    "Idempotent register: user already exists, returning new token pair"
                );

                return Ok(Response::new(RegisterResponse {
                    user_id: existing.id.to_string(),
                    token: tokens.access_token,
                    refresh_token: tokens.refresh_token,
                    expires_in: tokens.expires_in,
                }));
            }

            // Different password: keep existing behavior and surface already-exists error.
            return Err(Status::already_exists("Email already registered"));
        }

        // 4. Hash password (includes strength validation)
        let password_hash = hash_password(&req.password).map_err(to_status)?;

        // 5. Create user with display_name (use username as fallback if not provided)
        let display_name = req.display_name.as_ref().filter(|s| !s.is_empty());
        let user = db::users::create_user(
            &self.db,
            &req.email,
            &req.username,
            &password_hash,
            display_name.map(|s| s.as_str()),
        )
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
            generate_token_pair(user.id, &user.email, &user.username, Some("primary"), None)
                .map_err(anyhow_to_status)?;

        // Create session for device tracking (if device_id is provided)
        if !req.device_id.is_empty() {
            let device_type = if req.device_type.is_empty() {
                None
            } else {
                Some(req.device_type.as_str())
            };

            // Parse OS name and version from os_version field (e.g., "iOS 18.0" -> "iOS", "18.0")
            let (os_name, os_version) = if req.os_version.is_empty() {
                (None, None)
            } else {
                let parts: Vec<&str> = req.os_version.splitn(2, ' ').collect();
                if parts.len() == 2 {
                    (Some(parts[0]), Some(parts[1]))
                } else {
                    (Some(req.os_version.as_str()), None)
                }
            };

            match db::sessions::create_session(
                &self.db,
                user.id,
                &req.device_id,
                if req.device_name.is_empty() {
                    None
                } else {
                    Some(req.device_name.as_str())
                },
                device_type,
                os_name,
                os_version,
                None, // browser_name (not applicable for mobile)
                None, // browser_version
                None, // ip_address (could be extracted from request metadata)
                if req.user_agent.is_empty() {
                    None
                } else {
                    Some(req.user_agent.as_str())
                },
                None, // location_country
                None, // location_city
            )
            .await
            {
                Ok(session) => {
                    info!(
                        user_id = %user.id,
                        session_id = %session.id,
                        device_id = %req.device_id,
                        "Session created for registered device"
                    );
                }
                Err(e) => {
                    // Log error but don't fail registration - session creation is secondary
                    warn!(
                        user_id = %user.id,
                        device_id = %req.device_id,
                        error = %e,
                        "Failed to create session for registered device"
                    );
                }
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
            generate_token_pair(user.id, &user.email, &user.username, Some("primary"), None)
                .map_err(anyhow_to_status)?;

        // Create session for device tracking (if device_id is provided)
        if !req.device_id.is_empty() {
            // Determine device type from the device_type field or default based on device_name
            let device_type = if !req.device_type.is_empty() {
                Some(req.device_type.as_str())
            } else {
                None
            };

            // Parse OS name and version from os_version field (e.g., "iOS 18.0" -> "iOS", "18.0")
            let (os_name, os_version) = if !req.os_version.is_empty() {
                let parts: Vec<&str> = req.os_version.splitn(2, ' ').collect();
                if parts.len() == 2 {
                    (Some(parts[0]), Some(parts[1]))
                } else {
                    (Some(req.os_version.as_str()), None)
                }
            } else {
                (None, None)
            };

            match db::sessions::create_session(
                &self.db,
                user.id,
                &req.device_id,
                if req.device_name.is_empty() {
                    None
                } else {
                    Some(&req.device_name)
                },
                device_type,
                os_name,
                os_version,
                None, // browser_name (not applicable for mobile)
                None, // browser_version
                None, // ip_address (could be extracted from request metadata)
                if req.user_agent.is_empty() {
                    None
                } else {
                    Some(&req.user_agent)
                },
                None, // location_country
                None, // location_city
            )
            .await
            {
                Ok(session) => {
                    info!(
                        user_id = %user.id,
                        session_id = %session.id,
                        device_id = %req.device_id,
                        "Session created for device"
                    );
                }
                Err(e) => {
                    // Log error but don't fail login - session creation is secondary
                    warn!(
                        user_id = %user.id,
                        device_id = %req.device_id,
                        error = %e,
                        "Failed to create session for device"
                    );
                }
            }
        }

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
            generate_token_pair(user.id, &user.email, &user.username, Some("primary"), None)
                .map_err(anyhow_to_status)?;

        Ok(Response::new(RefreshTokenResponse {
            token: tokens.access_token,
            expires_in: tokens.expires_in,
            refresh_token: tokens.refresh_token, // Rotation: issue new refresh token each time (like IG/Twitter)
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

    /// Add email to waitlist (public - no auth required)
    /// Issue #255: "Don't have an invite?" email collection
    async fn add_to_waitlist(
        &self,
        request: Request<AddToWaitlistRequest>,
    ) -> std::result::Result<Response<AddToWaitlistResponse>, Status> {
        let req = request.into_inner();

        if req.email.is_empty() {
            return Err(Status::invalid_argument("Email is required"));
        }

        // Basic email validation
        if !req.email.contains('@') || !req.email.contains('.') {
            return Err(Status::invalid_argument("Invalid email format"));
        }

        let (is_new, _id) = db::waitlist::add_to_waitlist(
            &self.db,
            &req.email,
            req.ip_address.as_deref(),
            req.user_agent.as_deref(),
            req.source.as_deref(),
        )
        .await
        .map_err(to_status)?;

        let message = if is_new {
            Some("Successfully added to waitlist".to_string())
        } else {
            Some("Email already on waitlist".to_string())
        };

        Ok(Response::new(AddToWaitlistResponse {
            success: true,
            is_new,
            message,
        }))
    }

    /// List waitlist entries (admin only)
    async fn list_waitlist(
        &self,
        request: Request<ListWaitlistRequest>,
    ) -> std::result::Result<Response<ListWaitlistResponse>, Status> {
        let req = request.into_inner();

        let limit = if req.limit > 0 { req.limit as i64 } else { 50 };
        let offset = req.offset as i64;

        let (entries, total) =
            db::waitlist::list_waitlist(&self.db, req.status.as_deref(), limit, offset)
                .await
                .map_err(to_status)?;

        let proto_entries: Vec<WaitlistEntry> = entries
            .into_iter()
            .map(|e| WaitlistEntry {
                id: e.id.to_string(),
                email: e.email,
                status: e.status,
                source: e.source,
                created_at: e.created_at.timestamp(),
                invited_at: e.invited_at.map(|dt| dt.timestamp()),
            })
            .collect();

        Ok(Response::new(ListWaitlistResponse {
            entries: proto_entries,
            total,
        }))
    }

    /// Get waitlist statistics (admin only)
    async fn get_waitlist_stats(
        &self,
        _request: Request<GetWaitlistStatsRequest>,
    ) -> std::result::Result<Response<GetWaitlistStatsResponse>, Status> {
        let stats = db::waitlist::get_waitlist_stats(&self.db)
            .await
            .map_err(to_status)?;

        Ok(Response::new(GetWaitlistStatsResponse {
            total: stats.total,
            pending: stats.pending,
            invited: stats.invited,
            registered: stats.registered,
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

    /// Get multiple user profiles by IDs (batch operation)
    async fn get_user_profiles_by_ids(
        &self,
        request: Request<GetUserProfilesByIdsRequest>,
    ) -> std::result::Result<Response<GetUserProfilesByIdsResponse>, Status> {
        let req = request.into_inner();

        let user_ids: Vec<Uuid> = req
            .user_ids
            .iter()
            .filter_map(|id| Uuid::parse_str(id).ok())
            .collect();

        if user_ids.is_empty() {
            return Ok(Response::new(GetUserProfilesByIdsResponse {
                profiles: vec![],
                error: None,
            }));
        }

        // Fetch users from database
        let users = db::users::find_by_ids(&self.db, &user_ids)
            .await
            .map_err(to_status)?;

        // Convert to UserProfile proto messages
        let profiles: Vec<UserProfile> = users
            .into_iter()
            .map(|user| UserProfile {
                user_id: user.id.to_string(),
                username: user.username.clone(),
                email: Some(user.email.clone()),
                display_name: user.display_name.clone(),
                bio: user.bio.clone(),
                avatar_url: user.avatar_url.clone(),
                cover_photo_url: user.cover_photo_url.clone(),
                location: user.location.clone(),
                is_private: user.private_account, // Proto renamed field
                created_at: user.created_at.timestamp(),
                updated_at: user.updated_at.timestamp(),
                first_name: user.first_name.clone(),
                last_name: user.last_name.clone(),
                date_of_birth: user.date_of_birth.map(|d| d.format("%Y-%m-%d").to_string()),
                gender: user
                    .gender
                    .map(|g| match g {
                        crate::models::user::Gender::Male => 1,   // GENDER_MALE
                        crate::models::user::Gender::Female => 2, // GENDER_FEMALE
                        crate::models::user::Gender::Other => 3,  // GENDER_OTHER
                        crate::models::user::Gender::PreferNotToSay => 4, // GENDER_PREFER_NOT_TO_SAY
                    })
                    .unwrap_or(0), // GENDER_UNSPECIFIED
            })
            .collect();

        Ok(Response::new(GetUserProfilesByIdsResponse {
            profiles,
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

    /// Get user by username
    async fn get_user_by_username(
        &self,
        request: Request<GetUserByUsernameRequest>,
    ) -> std::result::Result<Response<GetUserByUsernameResponse>, Status> {
        let req = request.into_inner();

        let user = db::users::find_by_username(&self.db, &req.username)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        Ok(Response::new(GetUserByUsernameResponse {
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

        // Parse date_of_birth if provided
        let date_of_birth = req.date_of_birth.as_ref().and_then(|d| {
            chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d")
                .map_err(|e| {
                    warn!(user_id = %user_id, error = %e, "Invalid date_of_birth format");
                    e
                })
                .ok()
        });

        // Parse gender from proto enum (i32) if provided
        let gender = match req.gender {
            1 => Some(crate::models::user::Gender::Male), // GENDER_MALE
            2 => Some(crate::models::user::Gender::Female), // GENDER_FEMALE
            3 => Some(crate::models::user::Gender::Other), // GENDER_OTHER
            4 => Some(crate::models::user::Gender::PreferNotToSay), // GENDER_PREFER_NOT_TO_SAY
            _ => None,                                    // GENDER_UNSPECIFIED or invalid
        };

        // Update profile fields
        let fields = db::users::UpdateUserProfileFields {
            display_name: req.display_name,
            bio: req.bio,
            avatar_url: req.avatar_url,
            cover_photo_url: req.cover_photo_url,
            location: req.location,
            private_account: req.is_private, // Proto field renamed from private_account to is_private
            // Extended profile fields
            first_name: req.first_name,
            last_name: req.last_name,
            date_of_birth,
            gender,
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
                is_private: user.private_account, // Proto renamed field
                created_at: user.created_at.timestamp(),
                updated_at: user.updated_at.timestamp(),
                // Extended profile fields
                first_name: user.first_name.clone(),
                last_name: user.last_name.clone(),
                date_of_birth: user.date_of_birth.map(|d| d.format("%Y-%m-%d").to_string()),
                gender: user
                    .gender
                    .map(|g| match g {
                        crate::models::user::Gender::Male => 1,   // GENDER_MALE
                        crate::models::user::Gender::Female => 2, // GENDER_FEMALE
                        crate::models::user::Gender::Other => 3,  // GENDER_OTHER
                        crate::models::user::Gender::PreferNotToSay => 4, // GENDER_PREFER_NOT_TO_SAY
                    })
                    .unwrap_or(0), // GENDER_UNSPECIFIED
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

        // Convert dm_permission from proto enum (i32) to database string
        let dm_permission_str = req.dm_permission.map(|dm| match dm {
            1 => "anyone".to_string(),    // DM_PERMISSION_ANYONE
            2 => "followers".to_string(), // DM_PERMISSION_FOLLOWERS
            3 => "mutuals".to_string(),   // DM_PERMISSION_MUTUALS
            4 => "nobody".to_string(),    // DM_PERMISSION_NOBODY
            _ => "anyone".to_string(),    // Default to open messaging
        });

        // Convert privacy_level from proto enum (i32) to database string
        let privacy_level_str = req.privacy_level.map(|pl| match pl {
            1 => "public".to_string(),       // PRIVACY_LEVEL_PUBLIC
            2 => "friends_only".to_string(), // PRIVACY_LEVEL_FRIENDS_ONLY
            3 => "private".to_string(),      // PRIVACY_LEVEL_PRIVATE
            _ => "public".to_string(),       // Default
        });

        let fields = db::user_settings::UpdateUserSettingsFields {
            dm_permission: dm_permission_str,
            email_notifications: req.email_notifications,
            push_notifications: req.push_notifications,
            marketing_emails: req.marketing_emails,
            timezone: req.timezone,
            language: req.language,
            dark_mode: req.dark_mode,
            privacy_level: privacy_level_str,
            allow_messages: None, // Deprecated - merged into dm_permission
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

    // ========== OAuth/SSO ==========

    /// Start OAuth flow - returns authorization URL
    async fn start_o_auth_flow(
        &self,
        request: Request<StartOAuthFlowRequest>,
    ) -> std::result::Result<Response<StartOAuthFlowResponse>, Status> {
        let req = request.into_inner();

        let provider = proto_provider_to_oauth(req.provider())
            .ok_or_else(|| Status::invalid_argument("Invalid or unsupported OAuth provider"))?;

        // Extract device info for session tracking (stored with OAuth state)
        let device_info = if req.device_id.is_some() || req.device_name.is_some() {
            Some(crate::services::oauth::OAuthDeviceInfo {
                device_id: req.device_id,
                device_name: req.device_name,
                device_type: req.device_type,
                os_version: req.os_version,
                user_agent: req.user_agent,
            })
        } else {
            None
        };

        let result = self
            .oauth
            .start_flow(provider, &req.redirect_uri, device_info)
            .await
            .map_err(to_status)?;

        info!(provider = ?provider, "OAuth flow started");

        Ok(Response::new(StartOAuthFlowResponse {
            authorization_url: result.url,
            state: result.state,
        }))
    }

    /// Complete OAuth flow - exchange authorization code for tokens
    async fn complete_o_auth_flow(
        &self,
        request: Request<CompleteOAuthFlowRequest>,
    ) -> std::result::Result<Response<CompleteOAuthFlowResponse>, Status> {
        let req = request.into_inner();

        // For new users via OAuth, we require an invite code (Nova is invite-only)
        // The invite code is validated during user creation in OAuthService::upsert_user
        let invite_code = req.invite_code.as_deref();

        let result = self
            .oauth
            .complete_flow(&req.state, &req.code, &req.redirect_uri, invite_code)
            .await
            .map_err(to_status)?;

        // Generate token pair for the user
        let tokens = generate_token_pair(
            result.user.id,
            &result.user.email,
            &result.user.username,
            Some("primary"),
            None,
        )
        .map_err(anyhow_to_status)?;

        // Create session for device tracking (if device_id was provided during start_flow)
        if let Some(ref device_info) = result.device_info {
            if let Some(ref device_id) = device_info.device_id {
                if !device_id.is_empty() {
                    // Determine device type
                    let device_type = device_info.device_type.as_deref();

                    // Parse OS name and version from os_version field (e.g., "iOS 18.0" -> "iOS", "18.0")
                    let (os_name, os_version) = if let Some(ref os_ver) = device_info.os_version {
                        if !os_ver.is_empty() {
                            let parts: Vec<&str> = os_ver.splitn(2, ' ').collect();
                            if parts.len() == 2 {
                                (Some(parts[0]), Some(parts[1]))
                            } else {
                                (Some(os_ver.as_str()), None)
                            }
                        } else {
                            (None, None)
                        }
                    } else {
                        (None, None)
                    };

                    match db::sessions::create_session(
                        &self.db,
                        result.user.id,
                        device_id,
                        device_info.device_name.as_deref(),
                        device_type,
                        os_name,
                        os_version,
                        None, // browser_name (not applicable for mobile)
                        None, // browser_version
                        None, // ip_address (could be extracted from request metadata)
                        device_info.user_agent.as_deref(),
                        None, // location_country
                        None, // location_city
                    )
                    .await
                    {
                        Ok(session) => {
                            info!(
                                user_id = %result.user.id,
                                session_id = %session.id,
                                device_id = %device_id,
                                "Session created for OAuth device"
                            );
                        }
                        Err(e) => {
                            // Log error but don't fail the sign-in
                            tracing::warn!(
                                user_id = %result.user.id,
                                device_id = %device_id,
                                error = %e,
                                "Failed to create session for OAuth device"
                            );
                        }
                    }
                }
            }
        }

        info!(
            user_id = %result.user.id,
            is_new_user = result.is_new_user,
            "OAuth flow completed"
        );

        Ok(Response::new(CompleteOAuthFlowResponse {
            user_id: result.user.id.to_string(),
            token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_in: tokens.expires_in,
            username: result.user.username,
            email: result.user.email,
            is_new_user: result.is_new_user,
        }))
    }

    /// List linked OAuth providers for a user
    async fn list_o_auth_connections(
        &self,
        request: Request<ListOAuthConnectionsRequest>,
    ) -> std::result::Result<Response<ListOAuthConnectionsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let connections = db::oauth::find_by_user_id(&self.db, user_id)
            .await
            .map_err(to_status)?;

        let proto_connections: Vec<OAuthConnectionInfo> = connections
            .into_iter()
            .map(|conn| OAuthConnectionInfo {
                id: conn.id.to_string(),
                provider: oauth_provider_str_to_proto(&conn.provider).into(),
                provider_user_id: conn.provider_user_id,
                email: conn.email,
                name: conn.name,
                picture_url: conn.picture_url,
                connected_at: conn.created_at.timestamp(),
                last_used_at: conn.updated_at.timestamp(),
            })
            .collect();

        Ok(Response::new(ListOAuthConnectionsResponse {
            connections: proto_connections,
        }))
    }

    /// Unlink an OAuth provider from user account
    async fn unlink_o_auth_provider(
        &self,
        request: Request<UnlinkOAuthProviderRequest>,
    ) -> std::result::Result<Response<UnlinkOAuthProviderResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let provider_str = proto_provider_to_str(req.provider())
            .ok_or_else(|| Status::invalid_argument("Invalid OAuth provider"))?;

        // Check if user has other authentication methods before unlinking
        // (either password or other OAuth connections)
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        let connections = db::oauth::find_by_user_id(&self.db, user_id)
            .await
            .map_err(to_status)?;

        let other_oauth_count = connections
            .iter()
            .filter(|c| c.provider != provider_str)
            .count();

        let has_password = !user.password_hash.is_empty();

        if other_oauth_count == 0 && !has_password {
            return Ok(Response::new(UnlinkOAuthProviderResponse {
                success: false,
                error: Some(
                    "Cannot unlink the only authentication method. Please set a password or link another OAuth provider first.".to_string()
                ),
            }));
        }

        // Find and delete the connection
        let connection = connections
            .iter()
            .find(|c| c.provider == provider_str)
            .ok_or_else(|| Status::not_found("OAuth connection not found"))?;

        db::oauth::delete_connection(&self.db, connection.id)
            .await
            .map_err(to_status)?;

        info!(
            user_id = %user_id,
            provider = %provider_str,
            "OAuth provider unlinked"
        );

        Ok(Response::new(UnlinkOAuthProviderResponse {
            success: true,
            error: None,
        }))
    }

    /// Apple native sign-in (for iOS apps using ASAuthorizationAppleIDCredential)
    ///
    /// This handles the native Apple Sign-In flow where iOS provides the identity token directly.
    async fn apple_native_sign_in(
        &self,
        request: Request<AppleNativeSignInRequest>,
    ) -> std::result::Result<Response<AppleNativeSignInResponse>, Status> {
        let req = request.into_inner();

        // For new users via OAuth, we require an invite code (Nova is invite-only)
        let invite_code = req.invite_code.as_deref();

        let result = self
            .oauth
            .apple_native_sign_in(
                &req.identity_token,
                &req.user_identifier,
                req.email.as_deref(),
                req.given_name.as_deref(),
                req.family_name.as_deref(),
                invite_code,
            )
            .await
            .map_err(to_status)?;

        // Generate token pair for the user
        let tokens = generate_token_pair(
            result.user.id,
            &result.user.email,
            &result.user.username,
            Some("primary"),
            None,
        )
        .map_err(anyhow_to_status)?;

        // Create session for device tracking (if device_id is provided)
        if let Some(device_id) = &req.device_id {
            if !device_id.is_empty() {
                // Determine device type
                let device_type = req.device_type.as_deref();

                // Parse OS name and version from os_version field (e.g., "iOS 18.0" -> "iOS", "18.0")
                let (os_name, os_version) = if let Some(os_ver) = &req.os_version {
                    if !os_ver.is_empty() {
                        let parts: Vec<&str> = os_ver.splitn(2, ' ').collect();
                        if parts.len() == 2 {
                            (Some(parts[0]), Some(parts[1]))
                        } else {
                            (Some(os_ver.as_str()), None)
                        }
                    } else {
                        (None, None)
                    }
                } else {
                    (None, None)
                };

                match db::sessions::create_session(
                    &self.db,
                    result.user.id,
                    device_id,
                    req.device_name.as_deref(),
                    device_type,
                    os_name,
                    os_version,
                    None, // browser_name (not applicable for mobile)
                    None, // browser_version
                    None, // ip_address (could be extracted from request metadata)
                    req.user_agent.as_deref(),
                    None, // location_country
                    None, // location_city
                )
                .await
                {
                    Ok(session) => {
                        info!(
                            user_id = %result.user.id,
                            session_id = %session.id,
                            device_id = %device_id,
                            "Session created for Apple Sign-In device"
                        );
                    }
                    Err(e) => {
                        // Log error but don't fail the sign-in
                        tracing::warn!(
                            user_id = %result.user.id,
                            device_id = %device_id,
                            error = %e,
                            "Failed to create session for Apple Sign-In device"
                        );
                    }
                }
            }
        }

        info!(
            user_id = %result.user.id,
            is_new_user = result.is_new_user,
            "Apple native sign-in completed"
        );

        Ok(Response::new(AppleNativeSignInResponse {
            user_id: result.user.id.to_string(),
            token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_in: tokens.expires_in,
            username: result.user.username,
            email: result.user.email,
            is_new_user: result.is_new_user,
        }))
    }

    // ========== Password Reset ==========

    /// Request password reset email
    ///
    /// This endpoint is public (no auth required).
    /// Always returns success to prevent email enumeration attacks.
    async fn request_password_reset(
        &self,
        request: Request<RequestPasswordResetRequest>,
    ) -> std::result::Result<Response<PasswordResetResponse>, Status> {
        let req = request.into_inner();

        // Validate email format
        if !crate::validators::validate_email(&req.email) {
            // Still return OK to prevent enumeration
            info!(email = %req.email, "Password reset requested for invalid email format");
            return Ok(Response::new(PasswordResetResponse { success: true }));
        }

        // Try to find user by email
        match db::users::find_by_email(&self.db, &req.email).await {
            Ok(Some(user)) => {
                // Check rate limiting (1 request per 2 minutes)
                match db::password_reset::has_recent_request(&self.db, user.id, 2).await {
                    Ok(true) => {
                        info!(
                            user_id = %user.id,
                            email = %req.email,
                            "Password reset rate limited"
                        );
                        // Still return OK to prevent enumeration
                        return Ok(Response::new(PasswordResetResponse { success: true }));
                    }
                    Ok(false) => {}
                    Err(e) => {
                        error!(error = %e, "Failed to check rate limit");
                        // Continue anyway
                    }
                }

                // Create reset token
                match db::password_reset::create_reset_token(&self.db, user.id, None).await {
                    Ok(token_result) => {
                        // Send email
                        if let Err(e) = self
                            .email
                            .send_password_reset_email(&req.email, &token_result.token)
                            .await
                        {
                            error!(
                                user_id = %user.id,
                                error = %e,
                                "Failed to send password reset email"
                            );
                        } else {
                            info!(
                                user_id = %user.id,
                                email = %req.email,
                                expires_at = %token_result.expires_at,
                                "Password reset email sent"
                            );
                        }
                    }
                    Err(e) => {
                        error!(
                            user_id = %user.id,
                            error = %e,
                            "Failed to create password reset token"
                        );
                    }
                }
            }
            Ok(None) => {
                // User not found - log but don't reveal
                info!(email = %req.email, "Password reset requested for non-existent email");
            }
            Err(e) => {
                error!(error = %e, "Database error during password reset request");
            }
        }

        // Always return success to prevent email enumeration
        Ok(Response::new(PasswordResetResponse { success: true }))
    }

    /// Reset password using token from email
    ///
    /// This endpoint is public (no auth required).
    async fn reset_password(
        &self,
        request: Request<ResetPasswordRequest>,
    ) -> std::result::Result<Response<PasswordResetResponse>, Status> {
        let req = request.into_inner();

        // Validate token format
        if req.reset_token.is_empty() {
            return Err(Status::invalid_argument("Reset token is required"));
        }

        // Validate new password
        if req.new_password.len() < 8 {
            return Err(Status::invalid_argument(
                "Password must be at least 8 characters",
            ));
        }

        // Validate token and get user ID
        let user_id = db::password_reset::validate_reset_token(&self.db, &req.reset_token)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::invalid_argument("Invalid or expired reset token"))?;

        // Hash new password (includes strength validation)
        let password_hash = hash_password(&req.new_password).map_err(to_status)?;

        // Update password
        db::users::update_password(&self.db, user_id, &password_hash)
            .await
            .map_err(to_status)?;

        // Mark token as used
        db::password_reset::mark_token_used(&self.db, &req.reset_token)
            .await
            .map_err(to_status)?;

        // Invalidate all other reset tokens for this user
        db::password_reset::invalidate_user_tokens(&self.db, user_id)
            .await
            .map_err(to_status)?;

        info!(user_id = %user_id, "Password reset successfully");

        Ok(Response::new(PasswordResetResponse { success: true }))
    }

    // ========== Phone Authentication ==========

    /// Send OTP verification code to phone number
    async fn send_phone_code(
        &self,
        request: Request<SendPhoneCodeRequest>,
    ) -> std::result::Result<Response<SendPhoneCodeResponse>, Status> {
        let req = request.into_inner();

        // Validate phone number format (E.164)
        if !req.phone_number.starts_with('+') || req.phone_number.len() < 10 {
            return Err(Status::invalid_argument(
                "Invalid phone number format. Must be E.164 format (e.g., +886912345678)",
            ));
        }

        // Send verification code via PhoneAuthService
        match self.phone_auth.send_code(&req.phone_number).await {
            Ok(expires_in) => {
                // Mask phone number for logging (show last 4 digits only)
                let masked = format!(
                    "{}****{}",
                    &req.phone_number[..4],
                    &req.phone_number[req.phone_number.len().saturating_sub(4)..]
                );
                info!(phone = %masked, "Phone verification code sent");

                Ok(Response::new(SendPhoneCodeResponse {
                    success: true,
                    message: Some("Verification code sent".to_string()),
                    expires_in,
                }))
            }
            Err(IdentityError::RateLimited(msg)) => {
                warn!(phone = "masked", error = %msg, "Phone code rate limited");
                Ok(Response::new(SendPhoneCodeResponse {
                    success: false,
                    message: Some(msg),
                    expires_in: 0,
                }))
            }
            Err(e) => {
                error!(error = %e, "Failed to send phone verification code");
                Err(to_status(e))
            }
        }
    }

    /// Verify OTP code and return verification token
    async fn verify_phone_code(
        &self,
        request: Request<VerifyPhoneCodeRequest>,
    ) -> std::result::Result<Response<VerifyPhoneCodeResponse>, Status> {
        let req = request.into_inner();

        // Validate inputs
        if req.phone_number.is_empty() || req.code.is_empty() {
            return Err(Status::invalid_argument(
                "Phone number and code are required",
            ));
        }

        // Verify code via PhoneAuthService
        match self
            .phone_auth
            .verify_code(&req.phone_number, &req.code)
            .await
        {
            Ok(verification_token) => {
                info!(phone = "masked", "Phone verification successful");
                Ok(Response::new(VerifyPhoneCodeResponse {
                    success: true,
                    verification_token: Some(verification_token),
                    message: Some("Phone verified successfully".to_string()),
                }))
            }
            Err(IdentityError::InvalidToken) => Ok(Response::new(VerifyPhoneCodeResponse {
                success: false,
                verification_token: None,
                message: Some("Invalid or expired verification code".to_string()),
            })),
            Err(e) => {
                error!(error = %e, "Phone verification failed");
                Err(to_status(e))
            }
        }
    }

    /// Register new user with phone number
    async fn phone_register(
        &self,
        request: Request<PhoneRegisterRequest>,
    ) -> std::result::Result<Response<PhoneRegisterResponse>, Status> {
        let req = request.into_inner();

        // Validate inputs
        if req.phone_number.is_empty() || req.verification_token.is_empty() {
            return Err(Status::invalid_argument(
                "Phone number and verification token are required",
            ));
        }
        if req.username.is_empty() || req.password.is_empty() {
            return Err(Status::invalid_argument(
                "Username and password are required",
            ));
        }

        // Register user via PhoneAuthService (includes validation and event publishing)
        let result = self
            .phone_auth
            .register(
                &req.phone_number,
                &req.verification_token,
                &req.username,
                &req.password,
                req.display_name.as_deref(),
            )
            .await
            .map_err(to_status)?;

        // Create session for device tracking (if device_id is provided)
        if !req.device_id.is_empty() {
            let device_type = if req.device_type.is_empty() {
                None
            } else {
                Some(req.device_type.as_str())
            };

            let (os_name, os_version) = if req.os_version.is_empty() {
                (None, None)
            } else {
                let parts: Vec<&str> = req.os_version.splitn(2, ' ').collect();
                if parts.len() == 2 {
                    (Some(parts[0]), Some(parts[1]))
                } else {
                    (Some(req.os_version.as_str()), None)
                }
            };

            match db::sessions::create_session(
                &self.db,
                result.user_id,
                &req.device_id,
                if req.device_name.is_empty() {
                    None
                } else {
                    Some(req.device_name.as_str())
                },
                device_type,
                os_name,
                os_version,
                None, // browser_name (not applicable for mobile)
                None, // browser_version
                None, // ip_address (could be extracted from request metadata)
                if req.user_agent.is_empty() {
                    None
                } else {
                    Some(req.user_agent.as_str())
                },
                None, // location_country
                None, // location_city
            )
            .await
            {
                Ok(session) => {
                    info!(
                        user_id = %result.user_id,
                        session_id = %session.id,
                        device_id = %req.device_id,
                        "Session created for phone-registered device"
                    );
                }
                Err(e) => {
                    warn!(
                        user_id = %result.user_id,
                        device_id = %req.device_id,
                        error = %e,
                        "Failed to create session for phone-registered device"
                    );
                }
            }
        }

        info!(
            user_id = %result.user_id,
            username = %result.username,
            "User registered successfully via phone"
        );

        Ok(Response::new(PhoneRegisterResponse {
            user_id: result.user_id.to_string(),
            token: result.access_token,
            refresh_token: result.refresh_token,
            expires_in: result.expires_in,
            username: result.username,
            is_new_user: result.is_new_user,
        }))
    }

    /// Login with phone number
    async fn phone_login(
        &self,
        request: Request<PhoneLoginRequest>,
    ) -> std::result::Result<Response<PhoneLoginResponse>, Status> {
        let req = request.into_inner();

        // Validate inputs
        if req.phone_number.is_empty() || req.verification_token.is_empty() {
            return Err(Status::invalid_argument(
                "Phone number and verification token are required",
            ));
        }

        // Login via PhoneAuthService (includes token generation and last login update)
        let result = self
            .phone_auth
            .login(&req.phone_number, &req.verification_token)
            .await
            .map_err(to_status)?;

        // Create session for device tracking (if device_id is provided)
        if !req.device_id.is_empty() {
            let device_type = if req.device_type.is_empty() {
                None
            } else {
                Some(req.device_type.as_str())
            };

            let (os_name, os_version) = if req.os_version.is_empty() {
                (None, None)
            } else {
                let parts: Vec<&str> = req.os_version.splitn(2, ' ').collect();
                if parts.len() == 2 {
                    (Some(parts[0]), Some(parts[1]))
                } else {
                    (Some(req.os_version.as_str()), None)
                }
            };

            match db::sessions::create_session(
                &self.db,
                result.user_id,
                &req.device_id,
                if req.device_name.is_empty() {
                    None
                } else {
                    Some(req.device_name.as_str())
                },
                device_type,
                os_name,
                os_version,
                None, // browser_name (not applicable for mobile)
                None, // browser_version
                None, // ip_address (could be extracted from request metadata)
                if req.user_agent.is_empty() {
                    None
                } else {
                    Some(req.user_agent.as_str())
                },
                None, // location_country
                None, // location_city
            )
            .await
            {
                Ok(session) => {
                    info!(
                        user_id = %result.user_id,
                        session_id = %session.id,
                        device_id = %req.device_id,
                        "Session created for phone login device"
                    );
                }
                Err(e) => {
                    warn!(
                        user_id = %result.user_id,
                        device_id = %req.device_id,
                        error = %e,
                        "Failed to create session for phone login device"
                    );
                }
            }
        }

        info!(
            user_id = %result.user_id,
            username = %result.username,
            "User logged in successfully via phone"
        );

        Ok(Response::new(PhoneLoginResponse {
            user_id: result.user_id.to_string(),
            token: result.access_token,
            refresh_token: result.refresh_token,
            expires_in: result.expires_in,
            username: result.username,
        }))
    }

    // ========== Email Authentication (Email OTP) ==========

    /// Send OTP code to email address
    async fn send_email_code(
        &self,
        request: Request<SendEmailCodeRequest>,
    ) -> std::result::Result<Response<SendEmailCodeResponse>, Status> {
        let req = request.into_inner();

        // Validate email format
        if req.email.is_empty() || !req.email.contains('@') {
            return Err(Status::invalid_argument("Invalid email address format"));
        }

        // Send verification code via EmailAuthService
        match self.email_auth.send_code(&req.email).await {
            Ok(expires_in) => {
                // Mask email for logging
                let masked = if let Some(at_pos) = req.email.find('@') {
                    let local = &req.email[..at_pos];
                    let domain = &req.email[at_pos..];
                    if local.len() <= 2 {
                        format!("**{}", domain)
                    } else {
                        format!("{}***{}", &local[..1], domain)
                    }
                } else {
                    "***@***".to_string()
                };
                info!(email = %masked, "Email verification code sent");

                Ok(Response::new(SendEmailCodeResponse {
                    success: true,
                    message: Some("Verification code sent to your email".to_string()),
                    expires_in,
                }))
            }
            Err(IdentityError::RateLimited(msg)) => {
                warn!(email = "masked", error = %msg, "Email code rate limited");
                Ok(Response::new(SendEmailCodeResponse {
                    success: false,
                    message: Some(msg),
                    expires_in: 0,
                }))
            }
            Err(e) => {
                error!(error = %e, "Failed to send email verification code");
                Err(to_status(e))
            }
        }
    }

    /// Verify email OTP code and return verification token
    async fn verify_email_code(
        &self,
        request: Request<VerifyEmailCodeRequest>,
    ) -> std::result::Result<Response<VerifyEmailCodeResponse>, Status> {
        let req = request.into_inner();

        // Validate inputs
        if req.email.is_empty() || req.code.is_empty() {
            return Err(Status::invalid_argument(
                "Email and code are required",
            ));
        }

        // Verify code via EmailAuthService
        match self
            .email_auth
            .verify_code(&req.email, &req.code)
            .await
        {
            Ok(verification_token) => {
                info!(email = "masked", "Email verification successful");
                Ok(Response::new(VerifyEmailCodeResponse {
                    success: true,
                    verification_token: Some(verification_token),
                    message: Some("Email verified successfully".to_string()),
                }))
            }
            Err(IdentityError::Validation(_)) => Ok(Response::new(VerifyEmailCodeResponse {
                success: false,
                verification_token: None,
                message: Some("Invalid or expired verification code".to_string()),
            })),
            Err(e) => {
                error!(error = %e, "Email verification failed");
                Err(to_status(e))
            }
        }
    }

    /// Register new user with verified email
    async fn email_register(
        &self,
        request: Request<EmailRegisterRequest>,
    ) -> std::result::Result<Response<EmailRegisterResponse>, Status> {
        let req = request.into_inner();

        // Validate inputs
        if req.email.is_empty() || req.verification_token.is_empty() {
            return Err(Status::invalid_argument(
                "Email and verification token are required",
            ));
        }
        if req.username.is_empty() || req.password.is_empty() {
            return Err(Status::invalid_argument(
                "Username and password are required",
            ));
        }

        // Register user via EmailAuthService
        let result = self
            .email_auth
            .register(
                &req.email,
                &req.verification_token,
                &req.username,
                &req.password,
                req.display_name.as_deref(),
                req.invite_code.as_deref(),
            )
            .await
            .map_err(to_status)?;

        // Create session for device tracking (if device_id is provided)
        if !req.device_id.is_empty() {
            let device_type = if req.device_type.is_empty() {
                None
            } else {
                Some(req.device_type.as_str())
            };

            let (os_name, os_version) = if req.os_version.is_empty() {
                (None, None)
            } else {
                let parts: Vec<&str> = req.os_version.splitn(2, ' ').collect();
                if parts.len() == 2 {
                    (Some(parts[0]), Some(parts[1]))
                } else {
                    (Some(req.os_version.as_str()), None)
                }
            };

            match db::sessions::create_session(
                &self.db,
                result.user_id,
                &req.device_id,
                if req.device_name.is_empty() {
                    None
                } else {
                    Some(req.device_name.as_str())
                },
                device_type,
                os_name,
                os_version,
                None, // browser_name (not applicable for mobile)
                None, // browser_version
                None, // ip_address (could be extracted from request metadata)
                if req.user_agent.is_empty() {
                    None
                } else {
                    Some(req.user_agent.as_str())
                },
                None, // location_country
                None, // location_city
            )
            .await
            {
                Ok(session) => {
                    info!(
                        user_id = %result.user_id,
                        session_id = %session.id,
                        device_id = %req.device_id,
                        "Session created for email-registered device"
                    );
                }
                Err(e) => {
                    warn!(
                        user_id = %result.user_id,
                        device_id = %req.device_id,
                        error = %e,
                        "Failed to create session for email-registered device"
                    );
                }
            }
        }

        info!(
            user_id = %result.user_id,
            username = %result.username,
            "User registered successfully via email OTP"
        );

        Ok(Response::new(EmailRegisterResponse {
            user_id: result.user_id.to_string(),
            token: result.access_token,
            refresh_token: result.refresh_token,
            expires_in: result.expires_in,
            username: result.username,
            is_new_user: result.is_new_user,
        }))
    }

    /// Login with verified email
    async fn email_login(
        &self,
        request: Request<EmailLoginRequest>,
    ) -> std::result::Result<Response<EmailLoginResponse>, Status> {
        let req = request.into_inner();

        // Validate inputs
        if req.email.is_empty() || req.verification_token.is_empty() {
            return Err(Status::invalid_argument(
                "Email and verification token are required",
            ));
        }

        // Login via EmailAuthService
        let result = self
            .email_auth
            .login(&req.email, &req.verification_token)
            .await
            .map_err(to_status)?;

        // Create session for device tracking (if device_id is provided)
        if !req.device_id.is_empty() {
            let device_type = if req.device_type.is_empty() {
                None
            } else {
                Some(req.device_type.as_str())
            };

            let (os_name, os_version) = if req.os_version.is_empty() {
                (None, None)
            } else {
                let parts: Vec<&str> = req.os_version.splitn(2, ' ').collect();
                if parts.len() == 2 {
                    (Some(parts[0]), Some(parts[1]))
                } else {
                    (Some(req.os_version.as_str()), None)
                }
            };

            match db::sessions::create_session(
                &self.db,
                result.user_id,
                &req.device_id,
                if req.device_name.is_empty() {
                    None
                } else {
                    Some(req.device_name.as_str())
                },
                device_type,
                os_name,
                os_version,
                None, // browser_name (not applicable for mobile)
                None, // browser_version
                None, // ip_address (could be extracted from request metadata)
                if req.user_agent.is_empty() {
                    None
                } else {
                    Some(req.user_agent.as_str())
                },
                None, // location_country
                None, // location_city
            )
            .await
            {
                Ok(session) => {
                    info!(
                        user_id = %result.user_id,
                        session_id = %session.id,
                        device_id = %req.device_id,
                        "Session created for email login device"
                    );
                }
                Err(e) => {
                    warn!(
                        user_id = %result.user_id,
                        device_id = %req.device_id,
                        error = %e,
                        "Failed to create session for email login device"
                    );
                }
            }
        }

        info!(
            user_id = %result.user_id,
            username = %result.username,
            "User logged in successfully via email OTP"
        );

        Ok(Response::new(EmailLoginResponse {
            user_id: result.user_id.to_string(),
            token: result.access_token,
            refresh_token: result.refresh_token,
            expires_in: result.expires_in,
            username: result.username,
        }))
    }

    // ========== Account Management (Multi-account & Alias) ==========

    // ========== Account Management (Multi-account & Alias) ==========

    /// List all accounts for a user (primary + aliases)
    async fn list_accounts(
        &self,
        request: Request<ListAccountsRequest>,
    ) -> std::result::Result<Response<ListAccountsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        // Get primary user account
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        // Get all alias accounts
        let aliases = db::accounts::list_by_user(&self.db, user_id)
            .await
            .map_err(to_status)?;

        // Build accounts list (primary first)
        let mut accounts = Vec::with_capacity(1 + aliases.len());

        // Add primary account
        let is_primary_active = aliases.iter().all(|a| !a.is_active);
        accounts.push(Account {
            id: user.id.to_string(),
            user_id: user.id.to_string(),
            username: user.username.clone(),
            display_name: user.display_name.clone().unwrap_or_default(),
            avatar_url: user.avatar_url.clone().unwrap_or_default(),
            is_primary: true,
            is_active: is_primary_active,
            is_alias: false,
            last_active_at: user.updated_at.timestamp(),
            created_at: user.created_at.timestamp(),
            alias_name: String::new(),
            date_of_birth: String::new(),
            gender: Gender::Unspecified.into(),
            profession: String::new(),
            location: String::new(),
        });

        // Add alias accounts
        for alias in &aliases {
            accounts.push(alias_record_to_proto(alias, &user));
        }

        // Determine current account ID
        let current_account_id = if is_primary_active {
            user.id.to_string()
        } else {
            aliases
                .iter()
                .find(|a| a.is_active)
                .map(|a| a.id.to_string())
                .unwrap_or_else(|| user.id.to_string())
        };

        Ok(Response::new(ListAccountsResponse {
            accounts,
            current_account_id,
        }))
    }

    /// Switch to a different account (returns new tokens)
    async fn switch_account(
        &self,
        request: Request<SwitchAccountRequest>,
    ) -> std::result::Result<Response<SwitchAccountResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;
        let target_account_id = Uuid::parse_str(&req.target_account_id)
            .map_err(|_| Status::invalid_argument("Invalid target account ID format"))?;

        // Get primary user
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        // Check if switching to primary account
        if target_account_id == user_id {
            // Switch to primary account
            db::accounts::deactivate_all_aliases(&self.db, user_id)
                .await
                .map_err(to_status)?;
            db::accounts::update_user_current_account(&self.db, user_id, None, "primary")
                .await
                .map_err(to_status)?;

            // Generate new tokens
            let tokens =
                generate_token_pair(user.id, &user.email, &user.username, Some("primary"), None)
                    .map_err(anyhow_to_status)?;

            info!(user_id = %user_id, "Switched to primary account");

            return Ok(Response::new(SwitchAccountResponse {
                success: true,
                access_token: tokens.access_token,
                refresh_token: tokens.refresh_token,
                account: Some(Account {
                    id: user.id.to_string(),
                    user_id: user.id.to_string(),
                    username: user.username.clone(),
                    display_name: user.display_name.clone().unwrap_or_default(),
                    avatar_url: user.avatar_url.clone().unwrap_or_default(),
                    is_primary: true,
                    is_active: true,
                    is_alias: false,
                    last_active_at: Utc::now().timestamp(),
                    created_at: user.created_at.timestamp(),
                    alias_name: String::new(),
                    date_of_birth: String::new(),
                    gender: Gender::Unspecified.into(),
                    profession: String::new(),
                    location: String::new(),
                }),
            }));
        }

        // Switch to alias account
        let alias = db::accounts::find_by_id_and_user(&self.db, target_account_id, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("Alias account not found or not owned by user"))?;

        // Set the alias as active
        db::accounts::set_active_alias(&self.db, target_account_id, user_id)
            .await
            .map_err(to_status)?;
        db::accounts::update_user_current_account(
            &self.db,
            user_id,
            Some(target_account_id),
            "alias",
        )
        .await
        .map_err(to_status)?;

        // Generate new tokens with alias account info
        let tokens = generate_token_pair(
            user.id,
            &user.email,
            &user.username,
            Some("alias"),
            Some(target_account_id),
        )
        .map_err(anyhow_to_status)?;

        info!(
            user_id = %user_id,
            alias_id = %target_account_id,
            alias_name = %alias.alias_name,
            "Switched to alias account"
        );

        Ok(Response::new(SwitchAccountResponse {
            success: true,
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            account: Some(alias_record_to_proto(&alias, &user)),
        }))
    }

    /// Create a new alias account
    async fn create_alias_account(
        &self,
        request: Request<CreateAliasAccountRequest>,
    ) -> std::result::Result<Response<CreateAliasAccountResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        // Validate alias name
        if req.alias_name.trim().is_empty() {
            return Err(Status::invalid_argument("Alias name is required"));
        }

        // Get user for context
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        // Parse date_of_birth if provided
        let date_of_birth = if req.date_of_birth.is_empty() {
            None
        } else {
            Some(
                chrono::NaiveDate::parse_from_str(&req.date_of_birth, "%Y-%m-%d")
                    .map_err(|_| Status::invalid_argument("Invalid date format. Use YYYY-MM-DD"))?,
            )
        };

        // Convert proto Gender to model Gender
        let gender = proto_gender_to_model(req.gender());

        // Create alias account
        let fields = db::accounts::CreateAliasAccountFields {
            user_id,
            alias_name: req.alias_name.trim().to_string(),
            avatar_url: if req.avatar_url.is_empty() {
                None
            } else {
                Some(req.avatar_url)
            },
            date_of_birth,
            gender,
            profession: if req.profession.is_empty() {
                None
            } else {
                Some(req.profession)
            },
            location: if req.location.is_empty() {
                None
            } else {
                Some(req.location)
            },
        };

        let alias = db::accounts::create_alias_account(&self.db, fields)
            .await
            .map_err(to_status)?;

        info!(
            user_id = %user_id,
            alias_id = %alias.id,
            alias_name = %alias.alias_name,
            "Alias account created"
        );

        Ok(Response::new(CreateAliasAccountResponse {
            account: Some(alias_record_to_proto(&alias, &user)),
        }))
    }

    /// Update an existing alias account
    async fn update_alias_account(
        &self,
        request: Request<UpdateAliasAccountRequest>,
    ) -> std::result::Result<Response<UpdateAliasAccountResponse>, Status> {
        let req = request.into_inner();
        let account_id = Uuid::parse_str(&req.account_id)
            .map_err(|_| Status::invalid_argument("Invalid account ID format"))?;
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        // Get user for context
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        // Parse date_of_birth if provided
        let date_of_birth = if req.date_of_birth.is_empty() {
            None
        } else {
            Some(
                chrono::NaiveDate::parse_from_str(&req.date_of_birth, "%Y-%m-%d")
                    .map_err(|_| Status::invalid_argument("Invalid date format. Use YYYY-MM-DD"))?,
            )
        };

        // Convert proto Gender to model Gender
        let gender = proto_gender_to_model(req.gender());

        // Build update fields
        let fields = db::accounts::UpdateAliasAccountFields {
            alias_name: if req.alias_name.is_empty() {
                None
            } else {
                Some(req.alias_name)
            },
            avatar_url: if req.avatar_url.is_empty() {
                None
            } else {
                Some(req.avatar_url)
            },
            date_of_birth,
            gender,
            profession: if req.profession.is_empty() {
                None
            } else {
                Some(req.profession)
            },
            location: if req.location.is_empty() {
                None
            } else {
                Some(req.location)
            },
        };

        let alias = db::accounts::update_alias_account(&self.db, account_id, user_id, fields)
            .await
            .map_err(to_status)?;

        info!(
            user_id = %user_id,
            alias_id = %account_id,
            "Alias account updated"
        );

        Ok(Response::new(UpdateAliasAccountResponse {
            account: Some(alias_record_to_proto(&alias, &user)),
        }))
    }

    /// Get alias account details
    async fn get_alias_account(
        &self,
        request: Request<GetAliasAccountRequest>,
    ) -> std::result::Result<Response<GetAliasAccountResponse>, Status> {
        let req = request.into_inner();
        let account_id = Uuid::parse_str(&req.account_id)
            .map_err(|_| Status::invalid_argument("Invalid account ID format"))?;
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        // Get user for context
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        // Get alias account
        let alias = db::accounts::find_by_id_and_user(&self.db, account_id, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("Alias account not found or not owned by user"))?;

        Ok(Response::new(GetAliasAccountResponse {
            account: Some(alias_record_to_proto(&alias, &user)),
        }))
    }

    /// Delete an alias account (soft delete)
    async fn delete_alias_account(
        &self,
        request: Request<DeleteAliasAccountRequest>,
    ) -> std::result::Result<Response<DeleteAliasAccountResponse>, Status> {
        let req = request.into_inner();
        let account_id = Uuid::parse_str(&req.account_id)
            .map_err(|_| Status::invalid_argument("Invalid account ID format"))?;
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        // Delete alias account
        db::accounts::delete_alias_account(&self.db, account_id, user_id)
            .await
            .map_err(to_status)?;

        // If this was the active account, switch back to primary
        db::accounts::update_user_current_account(&self.db, user_id, None, "primary")
            .await
            .map_err(to_status)?;

        info!(
            user_id = %user_id,
            alias_id = %account_id,
            "Alias account deleted"
        );

        Ok(Response::new(DeleteAliasAccountResponse { success: true }))
    }

    // ========== Passkey/WebAuthn Methods ==========

    async fn start_passkey_registration(
        &self,
        request: Request<StartPasskeyRegistrationRequest>,
    ) -> std::result::Result<Response<StartPasskeyRegistrationResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        // Get user
        let user = db::users::find_by_id(&self.db, user_id)
            .await
            .map_err(to_status)?
            .ok_or_else(|| Status::not_found("User not found"))?;

        // Start registration
        let (ccr, challenge_id) = self
            .passkey
            .start_registration(
                &user,
                if req.credential_name.is_empty() {
                    None
                } else {
                    Some(req.credential_name)
                },
                if req.device_type.is_empty() {
                    None
                } else {
                    Some(req.device_type)
                },
                if req.os_version.is_empty() {
                    None
                } else {
                    Some(req.os_version)
                },
            )
            .await
            .map_err(to_status)?;

        // Serialize options to JSON
        let options_json = serde_json::to_string(&ccr)
            .map_err(|e| Status::internal(format!("Failed to serialize options: {}", e)))?;

        Ok(Response::new(StartPasskeyRegistrationResponse {
            challenge_id,
            options_json,
        }))
    }

    async fn complete_passkey_registration(
        &self,
        request: Request<CompletePasskeyRegistrationRequest>,
    ) -> std::result::Result<Response<CompletePasskeyRegistrationResponse>, Status> {
        let req = request.into_inner();

        // Parse attestation response
        let attestation: webauthn_rs::prelude::RegisterPublicKeyCredential =
            serde_json::from_str(&req.attestation_json).map_err(|e| {
                Status::invalid_argument(format!("Invalid attestation JSON: {}", e))
            })?;

        // Complete registration
        let result = self
            .passkey
            .complete_registration(&req.challenge_id, attestation)
            .await
            .map_err(to_status)?;

        Ok(Response::new(CompletePasskeyRegistrationResponse {
            credential_id: result.credential_id.to_string(),
            credential_name: result.credential_name.unwrap_or_default(),
        }))
    }

    async fn start_passkey_authentication(
        &self,
        request: Request<StartPasskeyAuthenticationRequest>,
    ) -> std::result::Result<Response<StartPasskeyAuthenticationResponse>, Status> {
        let req = request.into_inner();
        let user_id = if req.user_id.is_empty() {
            None
        } else {
            Some(
                Uuid::parse_str(&req.user_id)
                    .map_err(|_| Status::invalid_argument("Invalid user ID format"))?,
            )
        };

        // Start authentication
        let (rcr, challenge_id) = self
            .passkey
            .start_authentication(user_id)
            .await
            .map_err(to_status)?;

        // Serialize options to JSON
        let options_json = serde_json::to_string(&rcr)
            .map_err(|e| Status::internal(format!("Failed to serialize options: {}", e)))?;

        Ok(Response::new(StartPasskeyAuthenticationResponse {
            challenge_id,
            options_json,
        }))
    }

    async fn complete_passkey_authentication(
        &self,
        request: Request<CompletePasskeyAuthenticationRequest>,
    ) -> std::result::Result<Response<CompletePasskeyAuthenticationResponse>, Status> {
        let req = request.into_inner();

        // Parse assertion response
        let assertion: webauthn_rs::prelude::PublicKeyCredential =
            serde_json::from_str(&req.assertion_json)
                .map_err(|e| Status::invalid_argument(format!("Invalid assertion JSON: {}", e)))?;

        // Complete authentication
        let result = self
            .passkey
            .complete_authentication(&req.challenge_id, assertion)
            .await
            .map_err(to_status)?;

        // Generate tokens for the authenticated user
        let tokens = generate_token_pair(
            result.user.id,
            &result.user.email,
            &result.user.username,
            Some("primary"),
            None,
        )
        .map_err(anyhow_to_status)?;

        Ok(Response::new(CompletePasskeyAuthenticationResponse {
            user_id: result.user.id.to_string(),
            credential_id: result.credential_id.to_string(),
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_at: chrono::Utc::now().timestamp() + 3600, // 1 hour
            username: result.user.username.clone(),
            email: result.user.email.clone(),
        }))
    }

    async fn list_passkeys(
        &self,
        request: Request<ListPasskeysRequest>,
    ) -> std::result::Result<Response<ListPasskeysResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        let credentials = self
            .passkey
            .list_credentials(user_id)
            .await
            .map_err(to_status)?;

        let passkeys: Vec<PasskeyCredential> = credentials
            .into_iter()
            .map(|c| PasskeyCredential {
                id: c.id.to_string(),
                credential_name: c.credential_name.unwrap_or_default(),
                device_type: c.device_type.unwrap_or_default(),
                os_version: c.os_version.unwrap_or_default(),
                backup_eligible: c.backup_eligible,
                backup_state: c.backup_state,
                transports: c.transports,
                created_at: Some(prost_types::Timestamp {
                    seconds: c.created_at.timestamp(),
                    nanos: 0,
                }),
                last_used_at: c.last_used_at.map(|t| prost_types::Timestamp {
                    seconds: t.timestamp(),
                    nanos: 0,
                }),
                is_active: c.is_active,
            })
            .collect();

        Ok(Response::new(ListPasskeysResponse { passkeys }))
    }

    async fn revoke_passkey(
        &self,
        request: Request<RevokePasskeyRequest>,
    ) -> std::result::Result<Response<()>, Status> {
        let req = request.into_inner();
        let credential_id = Uuid::parse_str(&req.credential_id)
            .map_err(|_| Status::invalid_argument("Invalid credential ID format"))?;
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        self.passkey
            .revoke_credential(
                credential_id,
                user_id,
                if req.reason.is_empty() {
                    None
                } else {
                    Some(&req.reason)
                },
            )
            .await
            .map_err(to_status)?;

        Ok(Response::new(()))
    }

    async fn rename_passkey(
        &self,
        request: Request<RenamePasskeyRequest>,
    ) -> std::result::Result<Response<()>, Status> {
        let req = request.into_inner();
        let credential_id = Uuid::parse_str(&req.credential_id)
            .map_err(|_| Status::invalid_argument("Invalid credential ID format"))?;
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID format"))?;

        self.passkey
            .rename_credential(credential_id, user_id, &req.new_name)
            .await
            .map_err(to_status)?;

        Ok(Response::new(()))
    }

    async fn batch_resolve_usernames(
        &self,
        request: Request<BatchResolveUsernamesRequest>,
    ) -> std::result::Result<Response<BatchResolveUsernamesResponse>, Status> {
        let req = request.into_inner();

        // Validate input - limit to 100 usernames
        if req.usernames.len() > 100 {
            return Err(Status::invalid_argument(
                "Maximum 100 usernames allowed per request",
            ));
        }

        let username_map = db::users::find_by_usernames(&self.db, &req.usernames)
            .await
            .map_err(to_status)?;

        let users: Vec<ResolvedUser> = req
            .usernames
            .iter()
            .map(|username| {
                let lower_username = username.to_lowercase();
                ResolvedUser {
                    username: username.clone(),
                    user_id: username_map
                        .get(&lower_username)
                        .map(|id| id.to_string())
                        .unwrap_or_default(),
                    found: username_map.contains_key(&lower_username),
                }
            })
            .collect();

        Ok(Response::new(BatchResolveUsernamesResponse { users }))
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
        IdentityError::RateLimited(msg) => {
            Status::resource_exhausted(format!("Rate limited: {}", msg))
        }
        IdentityError::Database(msg) => Status::internal(format!("Database error: {}", msg)),
        IdentityError::Redis(msg) => Status::internal(format!("Redis error: {}", msg)),
        IdentityError::JwtError(msg) => Status::internal(format!("JWT error: {}", msg)),
        IdentityError::Validation(msg) => {
            Status::invalid_argument(format!("Validation error: {}", msg))
        }
        IdentityError::NotFoundError(msg) => Status::not_found(msg),
        IdentityError::Internal(msg) => Status::internal(msg),
        IdentityError::Configuration(msg) => {
            Status::internal(format!("Configuration error: {}", msg))
        }
        // Passkey errors
        IdentityError::PasskeyRegistrationFailed(msg) => {
            Status::internal(format!("Passkey registration failed: {}", msg))
        }
        IdentityError::PasskeyAuthenticationFailed(msg) => {
            Status::unauthenticated(format!("Passkey authentication failed: {}", msg))
        }
        IdentityError::PasskeyChallengeExpired => {
            Status::invalid_argument("Passkey challenge expired")
        }
        IdentityError::InvalidPasskeyChallenge => {
            Status::invalid_argument("Invalid passkey challenge")
        }
        IdentityError::PasskeyAlreadyRegistered => {
            Status::already_exists("Passkey already registered")
        }
        IdentityError::NoPasskeyCredentials => Status::not_found("No passkey credentials found"),
        IdentityError::PasskeyCredentialNotFound => {
            Status::not_found("Passkey credential not found")
        }
        // Zitadel errors
        IdentityError::ZitadelError(msg) => Status::internal(format!("Zitadel error: {}", msg)),
        // OAuth invite code errors
        IdentityError::InviteCodeRequired => Status::failed_precondition("INVITE_CODE_REQUIRED"),
        IdentityError::InvalidInviteCode(msg) => {
            Status::invalid_argument(format!("Invalid invite code: {}", msg))
        }
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
    // Convert dm_permission from database string to proto enum (i32)
    let dm_permission_i32 = match settings.dm_permission.to_lowercase().as_str() {
        "anyone" => 1,    // DM_PERMISSION_ANYONE
        "followers" => 2, // DM_PERMISSION_FOLLOWERS
        "mutuals" => 3,   // DM_PERMISSION_MUTUALS
        "nobody" => 4,    // DM_PERMISSION_NOBODY
        _ => 1,           // Default to anyone (open messaging)
    };

    // Convert privacy_level from database string to proto enum (i32)
    let privacy_level_i32 = match settings.privacy_level.to_lowercase().as_str() {
        "public" => 1,       // PRIVACY_LEVEL_PUBLIC
        "friends_only" => 2, // PRIVACY_LEVEL_FRIENDS_ONLY
        "private" => 3,      // PRIVACY_LEVEL_PRIVATE
        _ => 1,              // Default to public
    };

    UserSettings {
        user_id: settings.user_id.to_string(),
        dm_permission: dm_permission_i32,
        email_notifications: settings.email_notifications,
        push_notifications: settings.push_notifications,
        marketing_emails: settings.marketing_emails,
        timezone: settings.timezone.clone(),
        language: settings.language.clone(),
        dark_mode: settings.dark_mode,
        privacy_level: privacy_level_i32,
        show_online_status: settings.show_online_status,
        created_at: settings.created_at.timestamp(),
        updated_at: settings.updated_at.timestamp(),
    }
}

// ===== OAuth Helper Functions =====

/// Convert proto OAuthProvider enum to service OAuthProvider
fn proto_provider_to_oauth(provider: OAuthProvider) -> Option<crate::services::OAuthProvider> {
    match provider {
        OAuthProvider::OauthProviderGoogle => Some(crate::services::OAuthProvider::Google),
        OAuthProvider::OauthProviderApple => Some(crate::services::OAuthProvider::Apple),
        OAuthProvider::OauthProviderUnspecified => None,
    }
}

/// Convert proto OAuthProvider enum to string
fn proto_provider_to_str(provider: OAuthProvider) -> Option<&'static str> {
    match provider {
        OAuthProvider::OauthProviderGoogle => Some("google"),
        OAuthProvider::OauthProviderApple => Some("apple"),
        OAuthProvider::OauthProviderUnspecified => None,
    }
}

/// Convert provider string to proto OAuthProvider enum
fn oauth_provider_str_to_proto(provider: &str) -> OAuthProvider {
    match provider.to_lowercase().as_str() {
        "google" => OAuthProvider::OauthProviderGoogle,
        "apple" => OAuthProvider::OauthProviderApple,
        _ => OAuthProvider::OauthProviderUnspecified,
    }
}

// ===== Account Management Helper Functions =====

/// Convert AliasAccountRecord to Account proto message
fn alias_record_to_proto(
    alias: &db::accounts::AliasAccountRecord,
    user: &crate::models::User,
) -> Account {
    Account {
        id: alias.id.to_string(),
        user_id: alias.user_id.to_string(),
        username: user.username.clone(),
        display_name: alias.alias_name.clone(),
        avatar_url: alias.avatar_url.clone().unwrap_or_default(),
        is_primary: false,
        is_active: alias.is_active,
        is_alias: true,
        last_active_at: alias.updated_at.timestamp(),
        created_at: alias.created_at.timestamp(),
        alias_name: alias.alias_name.clone(),
        date_of_birth: alias
            .date_of_birth
            .map(|d| d.format("%Y-%m-%d").to_string())
            .unwrap_or_default(),
        gender: model_gender_to_proto(alias.gender.as_ref()).into(),
        profession: alias.profession.clone().unwrap_or_default(),
        location: alias.location.clone().unwrap_or_default(),
    }
}

/// Convert proto Gender enum to model Gender
fn proto_gender_to_model(gender: Gender) -> Option<crate::models::user::Gender> {
    match gender {
        Gender::Male => Some(crate::models::user::Gender::Male),
        Gender::Female => Some(crate::models::user::Gender::Female),
        Gender::Other => Some(crate::models::user::Gender::Other),
        Gender::PreferNotToSay => Some(crate::models::user::Gender::PreferNotToSay),
        Gender::Unspecified => None,
    }
}

/// Convert model Gender to proto Gender enum
fn model_gender_to_proto(gender: Option<&crate::models::user::Gender>) -> Gender {
    match gender {
        Some(crate::models::user::Gender::Male) => Gender::Male,
        Some(crate::models::user::Gender::Female) => Gender::Female,
        Some(crate::models::user::Gender::Other) => Gender::Other,
        Some(crate::models::user::Gender::PreferNotToSay) => Gender::PreferNotToSay,
        None => Gender::Unspecified,
    }
}
