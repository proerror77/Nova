//! User GraphQL Schema

use async_graphql::{Context, Object, Result, SimpleObject, Error};
use crate::clients::ServiceClients;

/// Convert proto UserProfile to GraphQL User
impl From<crate::clients::proto::user::UserProfile> for User {
    fn from(profile: crate::clients::proto::user::UserProfile) -> Self {
        User {
            id: profile.id,
            username: profile.username,
            email: Some(profile.email),
            display_name: if profile.display_name.is_empty() { None } else { Some(profile.display_name) },
            bio: if profile.bio.is_empty() { None } else { Some(profile.bio) },
            avatar_url: if profile.avatar_url.is_empty() { None } else { Some(profile.avatar_url) },
            cover_url: if profile.cover_url.is_empty() { None } else { Some(profile.cover_url) },
            website: if profile.website.is_empty() { None } else { Some(profile.website) },
            location: if profile.location.is_empty() { None } else { Some(profile.location) },
            is_verified: profile.is_verified,
            is_private: profile.is_private,
            follower_count: profile.follower_count,
            following_count: profile.following_count,
            post_count: profile.post_count,
            created_at: profile.created_at,
        }
    }
}

/// User profile type
#[derive(SimpleObject, Clone)]
pub struct User {
    pub id: String,
    pub username: String,
    pub email: Option<String>,
    #[graphql(name = "displayName")]
    pub display_name: Option<String>,
    pub bio: Option<String>,
    #[graphql(name = "avatarUrl")]
    pub avatar_url: Option<String>,
    #[graphql(name = "coverUrl")]
    pub cover_url: Option<String>,
    pub website: Option<String>,
    pub location: Option<String>,
    #[graphql(name = "isVerified")]
    pub is_verified: bool,
    #[graphql(name = "isPrivate")]
    pub is_private: bool,
    #[graphql(name = "followerCount")]
    pub follower_count: i32,
    #[graphql(name = "followingCount")]
    pub following_count: i32,
    #[graphql(name = "postCount")]
    pub post_count: i32,
    #[graphql(name = "createdAt")]
    pub created_at: i64,
}

/// User update input
#[derive(async_graphql::InputObject)]
pub struct UpdateProfileInput {
    #[graphql(name = "displayName")]
    pub display_name: Option<String>,
    pub bio: Option<String>,
    #[graphql(name = "avatarUrl")]
    pub avatar_url: Option<String>,
    #[graphql(name = "coverUrl")]
    pub cover_url: Option<String>,
    pub website: Option<String>,
    pub location: Option<String>,
}

/// User queries
#[derive(Default)]
pub struct UserQuery;

#[Object]
impl UserQuery {
    /// Get user by ID
    async fn user(&self, ctx: &Context<'_>, id: String) -> Result<User> {
        use crate::clients::proto::user::GetUserProfileRequest;

        let clients = ctx.data::<ServiceClients>()
            .map_err(|_| Error::new("Service clients not available"))?;

        let mut client = clients.user_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to user service: {}", e)))?;

        let request = tonic::Request::new(GetUserProfileRequest {
            user_id: id,
        });

        let response = client.get_user_profile(request)
            .await
            .map_err(|e| Error::new(format!("Failed to get user profile: {}", e)))?
            .into_inner();

        Ok(response.profile.ok_or_else(|| Error::new("User not found"))?.into())
    }

    /// Search users
    async fn search_users(
        &self,
        ctx: &Context<'_>,
        query: String,
        limit: Option<i32>,
    ) -> Result<Vec<User>> {
        use crate::clients::proto::user::SearchUsersRequest;

        let clients = ctx.data::<ServiceClients>()
            .map_err(|_| Error::new("Service clients not available"))?;

        let mut client = clients.user_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to user service: {}", e)))?;

        let request = tonic::Request::new(SearchUsersRequest {
            query,
            limit: limit.unwrap_or(20).min(100),
            offset: 0,
        });

        let response = client.search_users(request)
            .await
            .map_err(|e| Error::new(format!("Failed to search users: {}", e)))?
            .into_inner();

        Ok(response.profiles.into_iter().map(|p| p.into()).collect())
    }
}

/// User mutations
#[derive(Default)]
pub struct UserMutation;

#[Object]
impl UserMutation {
    /// Update user profile
    async fn update_profile(
        &self,
        ctx: &Context<'_>,
        input: UpdateProfileInput,
    ) -> Result<User> {
        use crate::clients::proto::user::UpdateUserProfileRequest;

        // Extract user ID from auth token (simplified - assumes user_id is in context)
        let user_id = ctx.data_opt::<String>()
            .ok_or_else(|| Error::new("User not authenticated"))?;

        let clients = ctx.data::<ServiceClients>()
            .map_err(|_| Error::new("Service clients not available"))?;

        let mut client = clients.user_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to user service: {}", e)))?;

        let request = tonic::Request::new(UpdateUserProfileRequest {
            user_id: user_id.clone(),
            display_name: input.display_name.unwrap_or_default(),
            bio: input.bio.unwrap_or_default(),
            avatar_url: input.avatar_url.unwrap_or_default(),
            cover_url: input.cover_url.unwrap_or_default(),
            website: input.website.unwrap_or_default(),
            location: input.location.unwrap_or_default(),
            is_private: false,  // Default, could be added to input
        });

        let response = client.update_user_profile(request)
            .await
            .map_err(|e| Error::new(format!("Failed to update profile: {}", e)))?
            .into_inner();

        Ok(response.profile.ok_or_else(|| Error::new("Failed to update profile"))?.into())
    }

    /// Follow a user
    async fn follow_user(
        &self,
        ctx: &Context<'_>,
        #[graphql(name = "userId")] user_id: String,
    ) -> Result<bool> {
        use crate::clients::proto::user::FollowUserRequest;

        // Extract current user ID from auth token
        let follower_id = ctx.data_opt::<String>()
            .ok_or_else(|| Error::new("User not authenticated"))?;

        let clients = ctx.data::<ServiceClients>()
            .map_err(|_| Error::new("Service clients not available"))?;

        let mut client = clients.user_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to user service: {}", e)))?;

        let request = tonic::Request::new(FollowUserRequest {
            follower_id: follower_id.clone(),
            followee_id: user_id,
        });

        client.follow_user(request)
            .await
            .map_err(|e| Error::new(format!("Failed to follow user: {}", e)))?;

        Ok(true)
    }

    /// Unfollow a user
    async fn unfollow_user(
        &self,
        ctx: &Context<'_>,
        #[graphql(name = "userId")] user_id: String,
    ) -> Result<bool> {
        use crate::clients::proto::user::UnfollowUserRequest;

        // Extract current user ID from auth token
        let follower_id = ctx.data_opt::<String>()
            .ok_or_else(|| Error::new("User not authenticated"))?;

        let clients = ctx.data::<ServiceClients>()
            .map_err(|_| Error::new("Service clients not available"))?;

        let mut client = clients.user_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to user service: {}", e)))?;

        let request = tonic::Request::new(UnfollowUserRequest {
            follower_id: follower_id.clone(),
            followee_id: user_id,
        });

        let response = client.unfollow_user(request)
            .await
            .map_err(|e| Error::new(format!("Failed to unfollow user: {}", e)))?
            .into_inner();

        Ok(response.success)
    }
}
