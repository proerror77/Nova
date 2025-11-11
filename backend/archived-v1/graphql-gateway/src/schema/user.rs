//! User schema and resolvers

use async_graphql::{Context, Object, Result as GraphQLResult, SimpleObject};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::clients::ServiceClients;

#[derive(SimpleObject, Clone, Debug, Serialize, Deserialize)]
pub struct UserProfile {
    pub id: String,
    pub username: String,
    pub email: String,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub follower_count: i32,
    pub following_count: i32,
    pub post_count: i32,
    pub created_at: String,
    pub is_verified: bool,
    pub is_private: bool,
}

impl From<crate::clients::proto::user::UserProfile> for UserProfile {
    fn from(profile: crate::clients::proto::user::UserProfile) -> Self {
        let created_at = DateTime::<Utc>::from_timestamp(profile.created_at, 0)
            .map(|dt| dt.to_rfc3339())
            .unwrap_or_else(|| profile.created_at.to_string());

        UserProfile {
            id: profile.id,
            username: profile.username,
            email: profile.email,
            bio: if profile.bio.is_empty() {
                None
            } else {
                Some(profile.bio)
            },
            avatar_url: if profile.avatar_url.is_empty() {
                None
            } else {
                Some(profile.avatar_url)
            },
            follower_count: profile.follower_count,
            following_count: profile.following_count,
            post_count: profile.post_count,
            created_at,
            is_verified: profile.is_verified,
            is_private: profile.is_private,
        }
    }
}

#[derive(Default)]
pub struct UserQuery;

#[Object]
impl UserQuery {
    async fn user(
        &self,
        ctx: &Context<'_>,
        id: String,
    ) -> GraphQLResult<Option<UserProfile>> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients.user_client();

        let request = tonic::Request::new(crate::clients::proto::user::GetUserProfileRequest {
            user_id: id,
        });

        match client.get_user_profile(request).await {
            Ok(response) => {
                let resp = response.into_inner();
                Ok(Some(resp.profile.unwrap_or_default().into()))
            }
            Err(e) => {
                if e.code() == tonic::Code::NotFound {
                    Ok(None)
                } else {
                    Err(format!("Failed to get user: {}", e).into())
                }
            }
        }
    }
}

#[derive(Default)]
pub struct UserMutation;

#[Object]
impl UserMutation {
    async fn follow_user(
        &self,
        ctx: &Context<'_>,
        followee_id: String,
    ) -> GraphQLResult<bool> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients.user_client();

        // Get current user from context (would normally come from JWT token)
        let follower_id = ctx
            .data::<String>()
            .ok()
            .cloned()
            .unwrap_or_default();

        let request = tonic::Request::new(crate::clients::proto::user::FollowUserRequest {
            follower_id,
            followee_id,
        });

        client
            .follow_user(request)
            .await
            .map_err(|e| format!("Follow failed: {}", e))?;

        Ok(true)
    }
}
