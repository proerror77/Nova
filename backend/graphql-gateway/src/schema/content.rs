//! Content and feed schema
//! ✅ P0-4: Relay cursor-based pagination support
//! ✅ P0: Application-level timeout protection for multi-RPC resolvers

use async_graphql::{Context, Object, Result as GraphQLResult, SimpleObject};
use chrono::{DateTime, Utc};
use resilience::timeout::{with_timeout_result, TimeoutError};
use serde::{Deserialize, Serialize};
use std::time::Duration;

use crate::clients::ServiceClients;
use crate::middleware::{check_user_authorization, get_authenticated_user_id};
use crate::schema::pagination::{Connection, PaginationArgs};

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
            creator_id: post.author_id,
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
    /// Get a single post by ID
    async fn post(&self, ctx: &Context<'_>, id: String) -> GraphQLResult<Option<Post>> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients.content_client();

        let request =
            tonic::Request::new(crate::clients::proto::content::GetPostRequest { post_id: id });

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

    /// Get posts with Relay cursor-based pagination
    /// ✅ P0-4: Demonstrates pagination pattern - ready for integration with list_posts RPC
    ///
    /// # Example
    /// ```graphql
    /// query {
    ///   posts(first: 10) {
    ///     edges {
    ///       cursor
    ///       node {
    ///         id
    ///         content
    ///         creatorId
    ///       }
    ///     }
    ///     pageInfo {
    ///       hasNextPage
    ///       endCursor
    ///     }
    ///   }
    /// }
    /// ```
    ///
    /// # Pagination Parameters
    /// - `first`: Number of items to return (forward pagination, max 100)
    /// - `after`: Cursor to start after
    /// - `last`: Number of items to return backwards (max 100)
    /// - `before`: Cursor to end before
    ///
    /// **Note**: Currently returns demo data. Ready to integrate with GetPostsByAuthorRequest once
    /// backend service adds proper ListPostsRequest RPC support.
    async fn posts(
        &self,
        _ctx: &Context<'_>,
        #[graphql(default = 10)] first: Option<i32>,
        after: Option<String>,
        last: Option<i32>,
        before: Option<String>,
    ) -> GraphQLResult<Connection<Post>> {
        let args = PaginationArgs {
            first,
            after,
            last,
            before,
        };

        args.validate()?;

        // Demo implementation with pagination pattern
        // In production, this would call a proper list_posts RPC:
        //   let request = tonic::Request::new(ListPostsRequest { offset, limit });
        //   match client.list_posts(request).await { ... }

        let offset = args.get_offset()?;
        let limit = args.get_limit();

        // Generate demo posts for pagination demonstration
        let demo_posts: Vec<Post> = (0..limit)
            .map(|i| Post {
                id: format!("post_{}", offset + i),
                creator_id: "demo_user".to_string(),
                content: format!("Demo post #{}", offset + i),
                created_at: chrono::Utc::now().to_rfc3339(),
                updated_at: chrono::Utc::now().to_rfc3339(),
            })
            .collect();

        let total_count = 1000; // Demo: assume 1000 total posts

        let connection = crate::schema::pagination::ConnectionBuilder::new(demo_posts, offset)
            .with_total_count(total_count)
            .build(&args);

        Ok(connection)
    }
}

#[derive(Default)]
pub struct ContentMutation;

#[Object]
impl ContentMutation {
    async fn create_post(&self, ctx: &Context<'_>, content: String) -> GraphQLResult<Post> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients.content_client();

        // Get author_id from context (would normally come from JWT token)
        let author_id = ctx.data::<String>().ok().cloned().unwrap_or_default();

        let request = tonic::Request::new(crate::clients::proto::content::CreatePostRequest {
            author_id,
            content,
            media_urls: vec![],
            media_type: String::new(),
        });

        let response = client
            .create_post(request)
            .await
            .map_err(|e| format!("Failed to create post: {}", e))?
            .into_inner();

        Ok(response.post.unwrap_or_default().into())
    }

    /// Delete a post (with application-level timeout protection)
    ///
    /// ✅ P0: Wrapped entire resolver in 12s timeout to prevent cumulative timeout
    /// from 2 sequential gRPC calls (each with 10s Channel timeout)
    ///
    /// Timeout hierarchy:
    /// - HTTP request: 30s (actix-web)
    /// - GraphQL resolver: 12s (application-level, THIS LEVEL)
    /// - gRPC call: 10s (Channel-level)
    async fn delete_post(&self, ctx: &Context<'_>, id: String) -> GraphQLResult<bool> {
        // ✅ Wrap entire resolver in 12s timeout (allows 2 RPCs @ 5s each + overhead)
        match with_timeout_result(Duration::from_secs(12), delete_post_impl(ctx, id)).await {
            Ok(success) => Ok(success),
            Err(TimeoutError::Elapsed(d)) => Err(async_graphql::Error::new(format!(
                "Delete post operation timed out after {:?}",
                d
            ))),
            Err(TimeoutError::OperationFailed(msg)) => Err(async_graphql::Error::new(msg)),
        }
    }
}

/// Internal implementation of delete_post (separated for timeout wrapping)
///
/// ✅ P0: Uses circuit breaker protection for all gRPC calls via clients.call_content()
async fn delete_post_impl(ctx: &Context<'_>, id: String) -> Result<bool, String> {
    let clients = ctx
        .data::<ServiceClients>()
        .map_err(|_| "Service clients not available".to_string())?;

    // Get current user from context (from JWT token)
    let current_user_id = get_authenticated_user_id(ctx).map_err(|e| e.to_string())?;

    // Step 1: Get post to verify ownership (gRPC call 1 with circuit breaker)
    let id_clone = id.clone();
    let clients_clone = clients.clone();
    let post = clients
        .call_content(|| async move {
            let mut client = clients_clone.content_client();
            let get_req = tonic::Request::new(crate::clients::proto::content::GetPostRequest {
                post_id: id_clone,
            });
            client.get_post(get_req).await
        })
        .await
        .map_err(|e| format!("Failed to get post: {}", e))?
        .post
        .ok_or("Post not found".to_string())?;

    // Step 2: Check authorization - user must be post owner
    let creator_uuid = uuid::Uuid::parse_str(&post.author_id)
        .map_err(|_| "Invalid post author ID format".to_string())?;

    check_user_authorization(ctx, creator_uuid, "delete").map_err(|e| e.to_string())?;

    // Step 3: Proceed with deletion (gRPC call 2 with circuit breaker)
    let clients_clone = clients.clone();
    clients
        .call_content(|| async move {
            let mut client = clients_clone.content_client();
            let del_req = tonic::Request::new(crate::clients::proto::content::DeletePostRequest {
                post_id: id,
                user_id: current_user_id.to_string(),
            });
            client.delete_post(del_req).await
        })
        .await
        .map_err(|e| format!("Failed to delete post: {}", e))?;

    Ok(true)
}
