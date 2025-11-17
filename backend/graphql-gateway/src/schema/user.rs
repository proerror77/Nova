//! User schema built on identity-service + graph-service

use async_graphql::{Context, Object, Result as GraphQLResult, SimpleObject};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::clients::ServiceClients;
use crate::middleware::get_authenticated_user_id;

#[derive(SimpleObject, Clone, Debug, Serialize, Deserialize)]
pub struct UserProfile {
    pub id: String,
    pub username: String,
    pub email: Option<String>,
    pub created_at: String,
    pub follower_count: i32,
    pub following_count: i32,
}

impl UserProfile {
    fn from_identity_and_counts(
        user: crate::clients::proto::auth::User,
        follower_count: i32,
        following_count: i32,
    ) -> Self {
        let created_at = DateTime::<Utc>::from_timestamp(user.created_at, 0)
            .map(|dt| dt.to_rfc3339())
            .unwrap_or_else(|| user.created_at.to_string());

        UserProfile {
            id: user.id,
            username: user.username,
            email: Some(user.email),
            created_at,
            follower_count,
            following_count,
        }
    }
}

#[derive(Default)]
pub struct UserQuery;

#[Object]
impl UserQuery {
    /// Get user profile by ID (identity-service + graph-service)
    async fn user(&self, ctx: &Context<'_>, id: String) -> GraphQLResult<Option<UserProfile>> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        // Fetch identity data
        let mut auth_client = clients.auth_client();
        let identity_req = tonic::Request::new(crate::clients::proto::auth::GetUserRequest {
            user_id: id.clone(),
        });

        let identity_resp = auth_client
            .get_user(identity_req)
            .await
            .map_err(|e| format!("Failed to get user from identity-service: {}", e))?
            .into_inner();

        // If identity-service returns an error or empty user, treat as not found
        let user = if let Some(u) = identity_resp.user {
            u
        } else {
            return Ok(None);
        };

        // Fetch follower / following counts from graph-service (best-effort)
        let follower_count = clients
            .call_graph(|| {
                let mut client = clients.graph_client();
                let req = tonic::Request::new(crate::clients::proto::graph::GetFollowersRequest {
                    user_id: id.clone(),
                    limit: 0,
                    offset: 0,
                });
                async move { client.get_followers(req).await }
            })
            .await
            .map(|resp| resp.total_count)
            .unwrap_or(0);

        let following_count = clients
            .call_graph(|| {
                let mut client = clients.graph_client();
                let req = tonic::Request::new(crate::clients::proto::graph::GetFollowingRequest {
                    user_id: id.clone(),
                    limit: 0,
                    offset: 0,
                });
                async move { client.get_following(req).await }
            })
            .await
            .map(|resp| resp.total_count)
            .unwrap_or(0);

        Ok(Some(UserProfile::from_identity_and_counts(
            user,
            follower_count,
            following_count,
        )))
    }
}

#[derive(Default)]
pub struct UserMutation;

#[Object]
impl UserMutation {
    /// Follow another user (uses graph-service)
    async fn follow_user(&self, ctx: &Context<'_>, followee_id: String) -> GraphQLResult<bool> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let follower_id = get_authenticated_user_id(ctx)
            .map_err(|e| format!("Authentication required: {}", e))?
            .to_string();

        let clients_clone = clients.clone();
        clients
            .call_graph(|| async move {
                let mut client = clients_clone.graph_client();
                let req = tonic::Request::new(crate::clients::proto::graph::CreateFollowRequest {
                    follower_id,
                    followee_id,
                });
                client.create_follow(req).await
            })
            .await
            .map_err(|e| format!("Failed to follow user: {}", e))?;

        Ok(true)
    }

    /// Unfollow a user (uses graph-service)
    async fn unfollow_user(&self, ctx: &Context<'_>, followee_id: String) -> GraphQLResult<bool> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let follower_id = get_authenticated_user_id(ctx)
            .map_err(|e| format!("Authentication required: {}", e))?
            .to_string();

        let clients_clone = clients.clone();
        clients
            .call_graph(|| async move {
                let mut client = clients_clone.graph_client();
                let req = tonic::Request::new(crate::clients::proto::graph::DeleteFollowRequest {
                    follower_id,
                    followee_id,
                });
                client.delete_follow(req).await
            })
            .await
            .map_err(|e| format!("Failed to unfollow user: {}", e))?;

        Ok(true)
    }
}
