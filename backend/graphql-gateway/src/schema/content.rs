//! Content and feed schema
//! ✅ P0-4: Relay cursor-based pagination support

use async_graphql::{Context, Object, Result as GraphQLResult, SimpleObject};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

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
    /// Get a single post by ID
    async fn post(&self, ctx: &Context<'_>, id: String) -> GraphQLResult<Option<Post>> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients.content_client();

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
        ctx: &Context<'_>,
        #[graphql(default = 10)] first: Option<i32>,
        after: Option<String>,
        #[graphql(default = 10)] last: Option<i32>,
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
    async fn create_post(
        &self,
        ctx: &Context<'_>,
        content: String,
    ) -> GraphQLResult<Post> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients.content_client();

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

        let mut client = clients.content_client();

        // Get current user from context (from JWT token)
        let current_user_id = get_authenticated_user_id(ctx)
            .map_err(|e| async_graphql::Error::new(e))?;

        // Step 1: Get post to verify ownership
        let get_req = tonic::Request::new(crate::clients::proto::content::GetPostRequest {
            post_id: id.clone(),
        });

        let post_response = client
            .get_post(get_req)
            .await
            .map_err(|e| format!("Failed to get post: {}", e))?;

        let post = post_response
            .into_inner()
            .post
            .ok_or("Post not found")?;

        // Step 2: Check authorization - user must be post owner
        // Parse creator_id as UUID
        let creator_uuid = uuid::Uuid::parse_str(&post.creator_id)
            .map_err(|_| async_graphql::Error::new("Invalid post creator ID format"))?;

        check_user_authorization(ctx, creator_uuid, "delete")
            .map_err(|e| async_graphql::Error::new(e))?;

        // Step 3: Proceed with deletion
        let del_req = tonic::Request::new(crate::clients::proto::content::DeletePostRequest {
            post_id: id,
            deleted_by_id: current_user_id.to_string(),
        });

        client
            .delete_post(del_req)
            .await
            .map_err(|e| format!("Failed to delete post: {}", e))?;

        Ok(true)
    }
}
