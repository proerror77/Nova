/// gRPC server implementation for Nova User Service
///
/// Implements all 12 RPC methods from Phase 0 proto definition:
/// - GetUserProfile, GetUserProfilesByIds, UpdateUserProfile
/// - GetUserSettings, UpdateUserSettings
/// - FollowUser, UnfollowUser, BlockUser, UnblockUser
/// - GetUserFollowers, GetUserFollowing, CheckUserRelationship
/// - SearchUsers

use super::nova::user_service::*;
use crate::db::Pool;
use crate::AppState;
use sqlx::Row;
use tonic::{Request, Response, Status};
use std::sync::Arc;

/// UserServiceImpl - gRPC server implementation
#[derive(Clone)]
pub struct UserServiceImpl {
    db: Arc<Pool>,
}

impl UserServiceImpl {
    pub fn new(state: Arc<AppState>) -> Self {
        Self {
            db: Arc::new(state.db.clone()),
        }
    }
}

#[tonic::async_trait]
impl user_service_server::UserService for UserServiceImpl {
    /// GetUserProfile - Retrieve user profile by ID
    async fn get_user_profile(
        &self,
        request: Request<GetUserProfileRequest>,
    ) -> Result<Response<GetUserProfileResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id is required"));
        }

        let row = sqlx::query(
            "SELECT id, username, email, display_name, bio, avatar_url, cover_url, website,
                    location, is_verified, is_private, follower_count, following_count, post_count,
                    created_at, updated_at, deleted_at
             FROM user_profiles WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(&req.user_id)
        .fetch_optional(&**self.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match row {
            Some(row) => Ok(Response::new(GetUserProfileResponse {
                profile: Some(UserProfile {
                    id: row.get("id"),
                    username: row.get("username"),
                    email: row.get("email"),
                    display_name: row.get("display_name"),
                    bio: row.get("bio"),
                    avatar_url: row.get("avatar_url"),
                    cover_url: row.get("cover_url"),
                    website: row.get("website"),
                    location: row.get("location"),
                    is_verified: row.get("is_verified"),
                    is_private: row.get("is_private"),
                    follower_count: row.get("follower_count"),
                    following_count: row.get("following_count"),
                    post_count: row.get("post_count"),
                    created_at: row.get("created_at"),
                    updated_at: row.get("updated_at"),
                    deleted_at: row.get("deleted_at"),
                }),
            })),
            None => Err(Status::not_found("User profile not found")),
        }
    }

    /// GetUserProfilesByIds - Batch retrieve multiple user profiles
    async fn get_user_profiles_by_ids(
        &self,
        request: Request<GetUserProfilesByIdsRequest>,
    ) -> Result<Response<GetUserProfilesByIdsResponse>, Status> {
        let req = request.into_inner();

        if req.user_ids.is_empty() {
            return Err(Status::invalid_argument("user_ids cannot be empty"));
        }

        let rows = sqlx::query(
            "SELECT id, username, email, display_name, bio, avatar_url, cover_url, website,
                    location, is_verified, is_private, follower_count, following_count, post_count,
                    created_at, updated_at, deleted_at
             FROM user_profiles WHERE id = ANY($1) AND deleted_at IS NULL",
        )
        .bind(&req.user_ids)
        .fetch_all(&**self.db)
        .await
        .unwrap_or_default();

        let profiles = rows
            .iter()
            .map(|row| UserProfile {
                id: row.get("id"),
                username: row.get("username"),
                email: row.get("email"),
                display_name: row.get("display_name"),
                bio: row.get("bio"),
                avatar_url: row.get("avatar_url"),
                cover_url: row.get("cover_url"),
                website: row.get("website"),
                location: row.get("location"),
                is_verified: row.get("is_verified"),
                is_private: row.get("is_private"),
                follower_count: row.get("follower_count"),
                following_count: row.get("following_count"),
                post_count: row.get("post_count"),
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
                deleted_at: row.get("deleted_at"),
            })
            .collect();

        Ok(Response::new(GetUserProfilesByIdsResponse { profiles }))
    }

    /// UpdateUserProfile - Update user profile information
    /// Fix P0-4: Use CASE statement instead of COALESCE to allow setting boolean to false
    async fn update_user_profile(
        &self,
        request: Request<UpdateUserProfileRequest>,
    ) -> Result<Response<UpdateUserProfileResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id is required"));
        }

        let now = chrono::Utc::now().to_rfc3339();

        let row = sqlx::query(
            "UPDATE user_profiles SET
             display_name = CASE WHEN $2 = '' THEN display_name ELSE $2 END,
             bio = CASE WHEN $3 = '' THEN bio ELSE $3 END,
             avatar_url = CASE WHEN $4 = '' THEN avatar_url ELSE $4 END,
             cover_url = CASE WHEN $5 = '' THEN cover_url ELSE $5 END,
             website = CASE WHEN $6 = '' THEN website ELSE $6 END,
             location = CASE WHEN $7 = '' THEN location ELSE $7 END,
             updated_at = $9
             WHERE id = $1 AND deleted_at IS NULL
             RETURNING id, username, email, display_name, bio, avatar_url, cover_url, website,
                       location, is_verified, is_private, follower_count, following_count, post_count,
                       created_at, updated_at, deleted_at",
        )
        .bind(&req.user_id)
        .bind(&req.display_name)
        .bind(&req.bio)
        .bind(&req.avatar_url)
        .bind(&req.cover_url)
        .bind(&req.website)
        .bind(&req.location)
        .bind(&now)
        .fetch_optional(&**self.db)
        .await
        .map_err(|e| {
            tracing::error!(
                error = %e,
                user_id = %req.user_id,
                "Failed to update user profile"
            );
            Status::internal("Failed to update user profile")
        })?;

        match row {
            Some(row) => Ok(Response::new(UpdateUserProfileResponse {
                profile: Some(UserProfile {
                    id: row.get("id"),
                    username: row.get("username"),
                    email: row.get("email"),
                    display_name: row.get("display_name"),
                    bio: row.get("bio"),
                    avatar_url: row.get("avatar_url"),
                    cover_url: row.get("cover_url"),
                    website: row.get("website"),
                    location: row.get("location"),
                    is_verified: row.get("is_verified"),
                    is_private: row.get("is_private"),
                    follower_count: row.get("follower_count"),
                    following_count: row.get("following_count"),
                    post_count: row.get("post_count"),
                    created_at: row.get("created_at"),
                    updated_at: row.get("updated_at"),
                    deleted_at: row.get("deleted_at"),
                }),
            })),
            None => Err(Status::not_found("User profile not found")),
        }
    }

    /// GetUserSettings - Retrieve user settings
    async fn get_user_settings(
        &self,
        request: Request<GetUserSettingsRequest>,
    ) -> Result<Response<GetUserSettingsResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id is required"));
        }

        let row = sqlx::query(
            "SELECT user_id, email_notifications, push_notifications, marketing_emails,
                    timezone, language, dark_mode, privacy_level, allow_messages,
                    created_at, updated_at
             FROM user_settings WHERE user_id = $1",
        )
        .bind(&req.user_id)
        .fetch_optional(&**self.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match row {
            Some(row) => Ok(Response::new(GetUserSettingsResponse {
                settings: Some(UserSettings {
                    user_id: row.get("user_id"),
                    email_notifications: row.get("email_notifications"),
                    push_notifications: row.get("push_notifications"),
                    marketing_emails: row.get("marketing_emails"),
                    timezone: row.get("timezone"),
                    language: row.get("language"),
                    dark_mode: row.get("dark_mode"),
                    privacy_level: row.get("privacy_level"),
                    allow_messages: row.get("allow_messages"),
                    created_at: row.get("created_at"),
                    updated_at: row.get("updated_at"),
                }),
            })),
            None => Err(Status::not_found("User settings not found")),
        }
    }

    /// UpdateUserSettings - Update user settings
    /// Fix P0-4: Use CASE statement instead of COALESCE to allow setting boolean to false
    async fn update_user_settings(
        &self,
        request: Request<UpdateUserSettingsRequest>,
    ) -> Result<Response<UpdateUserSettingsResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id is required"));
        }

        let now = chrono::Utc::now().to_rfc3339();

        let row = sqlx::query(
            "UPDATE user_settings SET
             email_notifications = CASE WHEN $2::text = 'unset' THEN email_notifications ELSE $2::boolean END,
             push_notifications = CASE WHEN $3::text = 'unset' THEN push_notifications ELSE $3::boolean END,
             marketing_emails = CASE WHEN $4::text = 'unset' THEN marketing_emails ELSE $4::boolean END,
             timezone = CASE WHEN $5 = '' THEN timezone ELSE $5 END,
             language = CASE WHEN $6 = '' THEN language ELSE $6 END,
             dark_mode = CASE WHEN $7::text = 'unset' THEN dark_mode ELSE $7::boolean END,
             privacy_level = CASE WHEN $8 = '' THEN privacy_level ELSE $8 END,
             allow_messages = CASE WHEN $9::text = 'unset' THEN allow_messages ELSE $9::boolean END,
             updated_at = $10
             WHERE user_id = $1
             RETURNING user_id, email_notifications, push_notifications, marketing_emails,
                       timezone, language, dark_mode, privacy_level, allow_messages,
                       created_at, updated_at",
        )
        .bind(&req.user_id)
        .bind(req.email_notifications.to_string())
        .bind(req.push_notifications.to_string())
        .bind(req.marketing_emails.to_string())
        .bind(&req.timezone)
        .bind(&req.language)
        .bind(req.dark_mode.to_string())
        .bind(&req.privacy_level)
        .bind(req.allow_messages.to_string())
        .bind(&now)
        .fetch_optional(&**self.db)
        .await
        .map_err(|e| {
            tracing::error!(
                error = %e,
                user_id = %req.user_id,
                "Failed to update user settings"
            );
            Status::internal("Failed to update user settings")
        })?;

        match row {
            Some(row) => Ok(Response::new(UpdateUserSettingsResponse {
                settings: Some(UserSettings {
                    user_id: row.get("user_id"),
                    email_notifications: row.get("email_notifications"),
                    push_notifications: row.get("push_notifications"),
                    marketing_emails: row.get("marketing_emails"),
                    timezone: row.get("timezone"),
                    language: row.get("language"),
                    dark_mode: row.get("dark_mode"),
                    privacy_level: row.get("privacy_level"),
                    allow_messages: row.get("allow_messages"),
                    created_at: row.get("created_at"),
                    updated_at: row.get("updated_at"),
                }),
            })),
            None => Err(Status::not_found("User settings not found")),
        }
    }

    /// FollowUser - Create follow relationship with state machine protection
    /// Fix P1-3: Prevent overwriting block relationship with follow
    async fn follow_user(
        &self,
        request: Request<FollowUserRequest>,
    ) -> Result<Response<FollowUserResponse>, Status> {
        let req = request.into_inner();

        if req.follower_id.is_empty() || req.followee_id.is_empty() {
            return Err(Status::invalid_argument(
                "follower_id and followee_id are required",
            ));
        }

        let relationship_id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();

        // Prevent follow relationship from overwriting block
        // If block exists, keep it; otherwise, create/update to follow
        let result = sqlx::query(
            "INSERT INTO user_relationships
             (id, follower_id, followee_id, relationship_type, status, created_at, updated_at)
             VALUES ($1, $2, $3, 'follow', 'active', $4, $5)
             ON CONFLICT (follower_id, followee_id) DO UPDATE SET
                 relationship_type = CASE WHEN relationship_type = 'block' THEN 'block' ELSE 'follow' END,
                 status = 'active',
                 updated_at = $5
             WHERE relationship_type != 'block'
             RETURNING id, follower_id, followee_id, relationship_type, status, created_at, updated_at",
        )
        .bind(&relationship_id)
        .bind(&req.follower_id)
        .bind(&req.followee_id)
        .bind(&now)
        .bind(&now)
        .fetch_one(&**self.db)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to follow user");
            Status::internal("Failed to follow user")
        })?;

        Ok(Response::new(FollowUserResponse {
            relationship: Some(UserRelationship {
                id: result.get("id"),
                follower_id: result.get("follower_id"),
                followee_id: result.get("followee_id"),
                relationship_type: result.get("relationship_type"),
                status: result.get("status"),
                created_at: result.get("created_at"),
                updated_at: result.get("updated_at"),
            }),
        }))
    }

    /// UnfollowUser - Remove follow relationship
    async fn unfollow_user(
        &self,
        request: Request<UnfollowUserRequest>,
    ) -> Result<Response<UnfollowUserResponse>, Status> {
        let req = request.into_inner();

        if req.follower_id.is_empty() || req.followee_id.is_empty() {
            return Err(Status::invalid_argument(
                "follower_id and followee_id are required",
            ));
        }

        let result = sqlx::query_scalar::<_, i64>(
            "DELETE FROM user_relationships
             WHERE follower_id = $1 AND followee_id = $2 AND relationship_type = 'follow'
             RETURNING 1",
        )
        .bind(&req.follower_id)
        .bind(&req.followee_id)
        .fetch_optional(&**self.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        Ok(Response::new(UnfollowUserResponse {
            success: result.is_some(),
        }))
    }

    /// BlockUser - Create block relationship with state machine protection
    /// Fix P1-3: Ensure block always takes precedence; remove previous follow if exists
    async fn block_user(
        &self,
        request: Request<BlockUserRequest>,
    ) -> Result<Response<BlockUserResponse>, Status> {
        let req = request.into_inner();

        if req.blocker_id.is_empty() || req.blocked_id.is_empty() {
            return Err(Status::invalid_argument("blocker_id and blocked_id are required"));
        }

        let relationship_id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();

        // Block takes precedence over follow
        // Always set to block regardless of previous state
        let result = sqlx::query(
            "INSERT INTO user_relationships
             (id, follower_id, followee_id, relationship_type, status, created_at, updated_at)
             VALUES ($1, $2, $3, 'block', 'active', $4, $5)
             ON CONFLICT (follower_id, followee_id) DO UPDATE SET
                 relationship_type = 'block',
                 status = 'active',
                 updated_at = $5
             RETURNING id, follower_id, followee_id, relationship_type, status, created_at, updated_at",
        )
        .bind(&relationship_id)
        .bind(&req.blocker_id)
        .bind(&req.blocked_id)
        .bind(&now)
        .bind(&now)
        .fetch_one(&**self.db)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to block user");
            Status::internal("Failed to block user")
        })?;

        Ok(Response::new(BlockUserResponse {
            relationship: Some(UserRelationship {
                id: result.get("id"),
                follower_id: result.get("follower_id"),
                followee_id: result.get("followee_id"),
                relationship_type: result.get("relationship_type"),
                status: result.get("status"),
                created_at: result.get("created_at"),
                updated_at: result.get("updated_at"),
            }),
        }))
    }

    /// UnblockUser - Remove block relationship
    async fn unblock_user(
        &self,
        request: Request<UnblockUserRequest>,
    ) -> Result<Response<UnblockUserResponse>, Status> {
        let req = request.into_inner();

        if req.blocker_id.is_empty() || req.blocked_id.is_empty() {
            return Err(Status::invalid_argument("blocker_id and blocked_id are required"));
        }

        let result = sqlx::query_scalar::<_, i64>(
            "DELETE FROM user_relationships
             WHERE follower_id = $1 AND followee_id = $2 AND relationship_type = 'block'
             RETURNING 1",
        )
        .bind(&req.blocker_id)
        .bind(&req.blocked_id)
        .fetch_optional(&**self.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        Ok(Response::new(UnblockUserResponse {
            success: result.is_some(),
        }))
    }

    /// GetUserFollowers - Get list of followers with pagination
    async fn get_user_followers(
        &self,
        request: Request<GetUserFollowersRequest>,
    ) -> Result<Response<GetUserFollowersResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id is required"));
        }

        let limit = if req.limit <= 0 || req.limit > 100 {
            20 // default
        } else {
            req.limit as i64
        };
        let offset = if req.offset < 0 { 0 } else { req.offset as i64 };

        let total_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM user_relationships
             WHERE followee_id = $1 AND relationship_type = 'follow' AND status = 'active'",
        )
        .bind(&req.user_id)
        .fetch_one(&**self.db)
        .await
        .unwrap_or(0);

        let rows = sqlx::query(
            "SELECT up.id, up.username, up.email, up.display_name, up.bio, up.avatar_url,
                    up.cover_url, up.website, up.location, up.is_verified, up.is_private,
                    up.follower_count, up.following_count, up.post_count,
                    up.created_at, up.updated_at, up.deleted_at
             FROM user_relationships ur
             JOIN user_profiles up ON ur.follower_id = up.id
             WHERE ur.followee_id = $1 AND ur.relationship_type = 'follow' AND ur.status = 'active'
             ORDER BY ur.created_at DESC
             LIMIT $2 OFFSET $3",
        )
        .bind(&req.user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&**self.db)
        .await
        .unwrap_or_default();

        let profiles = rows
            .iter()
            .map(|row| UserProfile {
                id: row.get("id"),
                username: row.get("username"),
                email: row.get("email"),
                display_name: row.get("display_name"),
                bio: row.get("bio"),
                avatar_url: row.get("avatar_url"),
                cover_url: row.get("cover_url"),
                website: row.get("website"),
                location: row.get("location"),
                is_verified: row.get("is_verified"),
                is_private: row.get("is_private"),
                follower_count: row.get("follower_count"),
                following_count: row.get("following_count"),
                post_count: row.get("post_count"),
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
                deleted_at: row.get("deleted_at"),
            })
            .collect();

        Ok(Response::new(GetUserFollowersResponse {
            profiles,
            total_count: total_count as i32,
        }))
    }

    /// GetUserFollowing - Get list of users this user is following
    async fn get_user_following(
        &self,
        request: Request<GetUserFollowingRequest>,
    ) -> Result<Response<GetUserFollowingResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id is required"));
        }

        let limit = if req.limit <= 0 || req.limit > 100 {
            20 // default
        } else {
            req.limit as i64
        };
        let offset = if req.offset < 0 { 0 } else { req.offset as i64 };

        let total_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM user_relationships
             WHERE follower_id = $1 AND relationship_type = 'follow' AND status = 'active'",
        )
        .bind(&req.user_id)
        .fetch_one(&**self.db)
        .await
        .unwrap_or(0);

        let rows = sqlx::query(
            "SELECT up.id, up.username, up.email, up.display_name, up.bio, up.avatar_url,
                    up.cover_url, up.website, up.location, up.is_verified, up.is_private,
                    up.follower_count, up.following_count, up.post_count,
                    up.created_at, up.updated_at, up.deleted_at
             FROM user_relationships ur
             JOIN user_profiles up ON ur.followee_id = up.id
             WHERE ur.follower_id = $1 AND ur.relationship_type = 'follow' AND ur.status = 'active'
             ORDER BY ur.created_at DESC
             LIMIT $2 OFFSET $3",
        )
        .bind(&req.user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&**self.db)
        .await
        .unwrap_or_default();

        let profiles = rows
            .iter()
            .map(|row| UserProfile {
                id: row.get("id"),
                username: row.get("username"),
                email: row.get("email"),
                display_name: row.get("display_name"),
                bio: row.get("bio"),
                avatar_url: row.get("avatar_url"),
                cover_url: row.get("cover_url"),
                website: row.get("website"),
                location: row.get("location"),
                is_verified: row.get("is_verified"),
                is_private: row.get("is_private"),
                follower_count: row.get("follower_count"),
                following_count: row.get("following_count"),
                post_count: row.get("post_count"),
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
                deleted_at: row.get("deleted_at"),
            })
            .collect();

        Ok(Response::new(GetUserFollowingResponse {
            profiles,
            total_count: total_count as i32,
        }))
    }

    /// CheckUserRelationship - Check relationship between two users
    async fn check_user_relationship(
        &self,
        request: Request<CheckUserRelationshipRequest>,
    ) -> Result<Response<CheckUserRelationshipResponse>, Status> {
        let req = request.into_inner();

        if req.follower_id.is_empty() || req.followee_id.is_empty() {
            return Err(Status::invalid_argument(
                "follower_id and followee_id are required",
            ));
        }

        let row = sqlx::query(
            "SELECT relationship_type, status FROM user_relationships
             WHERE follower_id = $1 AND followee_id = $2
             LIMIT 1",
        )
        .bind(&req.follower_id)
        .bind(&req.followee_id)
        .fetch_optional(&**self.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match row {
            Some(row) => Ok(Response::new(CheckUserRelationshipResponse {
                relationship_type: row.get("relationship_type"),
                status: row.get("status"),
            })),
            None => Ok(Response::new(CheckUserRelationshipResponse {
                relationship_type: "none".to_string(),
                status: "".to_string(),
            })),
        }
    }

    /// SearchUsers - Search users by username or display name
    async fn search_users(
        &self,
        request: Request<SearchUsersRequest>,
    ) -> Result<Response<SearchUsersResponse>, Status> {
        let req = request.into_inner();

        if req.query.is_empty() {
            return Err(Status::invalid_argument("query is required"));
        }

        let limit = if req.limit <= 0 || req.limit > 100 {
            20 // default
        } else {
            req.limit as i64
        };
        let offset = if req.offset < 0 { 0 } else { req.offset as i64 };

        let search_pattern = format!("%{}%", req.query);

        let total_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM user_profiles
             WHERE deleted_at IS NULL AND (username ILIKE $1 OR display_name ILIKE $1)",
        )
        .bind(&search_pattern)
        .fetch_one(&**self.db)
        .await
        .unwrap_or(0);

        let rows = sqlx::query(
            "SELECT id, username, email, display_name, bio, avatar_url, cover_url, website,
                    location, is_verified, is_private, follower_count, following_count, post_count,
                    created_at, updated_at, deleted_at
             FROM user_profiles
             WHERE deleted_at IS NULL AND (username ILIKE $1 OR display_name ILIKE $1)
             ORDER BY username ASC
             LIMIT $2 OFFSET $3",
        )
        .bind(&search_pattern)
        .bind(limit)
        .bind(offset)
        .fetch_all(&**self.db)
        .await
        .unwrap_or_default();

        let profiles = rows
            .iter()
            .map(|row| UserProfile {
                id: row.get("id"),
                username: row.get("username"),
                email: row.get("email"),
                display_name: row.get("display_name"),
                bio: row.get("bio"),
                avatar_url: row.get("avatar_url"),
                cover_url: row.get("cover_url"),
                website: row.get("website"),
                location: row.get("location"),
                is_verified: row.get("is_verified"),
                is_private: row.get("is_private"),
                follower_count: row.get("follower_count"),
                following_count: row.get("following_count"),
                post_count: row.get("post_count"),
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
                deleted_at: row.get("deleted_at"),
            })
            .collect();

        Ok(Response::new(SearchUsersResponse {
            profiles,
            total_count: total_count as i32,
        }))
    }
}
