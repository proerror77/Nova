//! Content and feed schema

use async_graphql::{Context, Object, Result as GraphQLResult, SimpleObject};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::clients::ServiceClients;

#[derive(SimpleObject, Clone, Debug, Serialize, Deserialize)]
pub struct Post {
    pub id: String,
    pub creator_id: String,
    pub content: String,
    pub created_at: String,
    pub updated_at: String,
}

impl From<crate::clients::proto::content::Post> for Post {
    fn from(post: crate::clients::proto::content::Post) -> Self {
        let created_at = DateTime::<Utc>::from_timestamp(post.created_at, 0)
            .map(|dt| dt.to_rfc3339())
            .unwrap_or_else(|| post.created_at.to_string());

        let updated_at = DateTime::<Utc>::from_timestamp(post.updated_at, 0)
            .map(|dt| dt.to_rfc3339())
            .unwrap_or_else(|| post.updated_at.to_string());

        Post {
            id: post.id,
            creator_id: post.creator_id,
            content: post.content,
            created_at,
            updated_at,
        }
    }
}

#[derive(Default)]
pub struct ContentQuery;

#[Object]
impl ContentQuery {
    async fn post(&self, ctx: &Context<'_>, id: String) -> GraphQLResult<Option<Post>> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients
            .content_client()
            .await
            .map_err(|e| format!("Failed to connect to content service: {}", e))?;

        let request = tonic::Request::new(crate::clients::proto::content::GetPostRequest {
            post_id: id,
        });

        match client.get_post(request).await {
            Ok(response) => {
                let resp = response.into_inner();
                if resp.found {
                    Ok(Some(resp.post.unwrap_or_default().into()))
                } else {
                    Ok(None)
                }
            }
            Err(e) => {
                if e.code() == tonic::Code::NotFound {
                    Ok(None)
                } else {
                    Err(format!("Failed to get post: {}", e).into())
                }
            }
        }
    }
}

#[derive(Default)]
pub struct ContentMutation;

#[Object]
impl ContentMutation {
    async fn create_post(
        &self,
        ctx: &Context<'_>,
        content: String,
    ) -> GraphQLResult<Post> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients
            .content_client()
            .await
            .map_err(|e| format!("Failed to connect to content service: {}", e))?;

        // Get creator_id from context (would normally come from JWT token)
        let creator_id = ctx
            .data::<String>()
            .ok()
            .cloned()
            .unwrap_or_default();

        let request = tonic::Request::new(crate::clients::proto::content::CreatePostRequest {
            creator_id,
            content,
        });

        let response = client
            .create_post(request)
            .await
            .map_err(|e| format!("Failed to create post: {}", e))?
            .into_inner();

        Ok(response.post.unwrap_or_default().into())
    }

    async fn delete_post(&self, ctx: &Context<'_>, id: String) -> GraphQLResult<bool> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients
            .content_client()
            .await
            .map_err(|e| format!("Failed to connect to content service: {}", e))?;

        // Get deleted_by_id from context (would normally come from JWT token)
        let deleted_by_id = ctx
            .data::<String>()
            .ok()
            .cloned()
            .unwrap_or_default();

        let request = tonic::Request::new(crate::clients::proto::content::DeletePostRequest {
            post_id: id,
            deleted_by_id,
        });

        client
            .delete_post(request)
            .await
            .map_err(|e| format!("Failed to delete post: {}", e))?;

        Ok(true)
    }
}
