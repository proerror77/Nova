//! Content (Posts, Comments) GraphQL Schema

use async_graphql::{Context, Object, Result, SimpleObject, Error};
use crate::schema::user::User;
use crate::clients::ServiceClients;

/// Post type matching iOS expectations
#[derive(SimpleObject, Clone)]
pub struct Post {
    pub id: String,
    #[graphql(name = "userId")]
    pub user_id: String,

    /// Post caption/content text
    /// Note: iOS uses "caption", backend proto uses "content"
    /// We support both names for compatibility
    pub caption: Option<String>,

    /// Image URL for post
    #[graphql(name = "imageUrl")]
    pub image_url: Option<String>,

    /// Thumbnail URL for post
    #[graphql(name = "thumbnailUrl")]
    pub thumbnail_url: Option<String>,

    #[graphql(name = "likeCount")]
    pub like_count: i32,

    #[graphql(name = "commentCount")]
    pub comment_count: i32,

    #[graphql(name = "viewCount")]
    pub view_count: i32,

    #[graphql(name = "createdAt")]
    pub created_at: i64,

    /// Author of the post (nested user object)
    pub author: Option<User>,

    /// Whether current user has liked this post
    #[graphql(name = "isLiked")]
    pub is_liked: Option<bool>,
}

/// Comment type
#[derive(SimpleObject, Clone)]
pub struct Comment {
    pub id: String,
    #[graphql(name = "postId")]
    pub post_id: String,
    #[graphql(name = "userId")]
    pub user_id: String,
    pub content: String,
    #[graphql(name = "createdAt")]
    pub created_at: i64,

    /// Author of the comment
    pub author: Option<User>,
}

/// Feed response with pagination
#[derive(SimpleObject)]
pub struct FeedResponse {
    pub posts: Vec<Post>,
    pub cursor: Option<String>,
    #[graphql(name = "hasMore")]
    pub has_more: bool,
}

/// Create post input
#[derive(async_graphql::InputObject)]
pub struct CreatePostInput {
    pub caption: Option<String>,
    #[graphql(name = "imageUrl")]
    pub image_url: String,
}

/// Content queries
#[derive(Default)]
pub struct ContentQuery;

#[Object]
impl ContentQuery {
    /// Get single post by ID
    async fn post(&self, ctx: &Context<'_>, id: String) -> Result<Post> {
        // TODO: Call content-service via gRPC
        // For now, return mock data
        Ok(Post {
            id: id.clone(),
            user_id: "mock-user-id".to_string(),
            caption: Some("Mock post caption".to_string()),
            image_url: Some("https://example.com/image.jpg".to_string()),
            thumbnail_url: Some("https://example.com/thumb.jpg".to_string()),
            like_count: 42,
            comment_count: 5,
            view_count: 120,
            created_at: chrono::Utc::now().timestamp(),
            author: None,
            is_liked: Some(false),
        })
    }

    /// Get personalized feed with pagination
    async fn feed(
        &self,
        ctx: &Context<'_>,
        limit: Option<i32>,
        cursor: Option<String>,
    ) -> Result<FeedResponse> {
        use crate::clients::proto::feed::GetFeedRequest;
        use crate::clients::proto::content::GetPostsByIdsRequest;
        use crate::clients::proto::user::GetUserProfilesByIdsRequest;

        let limit = limit.unwrap_or(20).min(100);

        // Get current user ID (simplified - should extract from JWT)
        let user_id = ctx.data_opt::<String>()
            .unwrap_or(&"anonymous".to_string())
            .clone();

        let clients = ctx.data::<ServiceClients>()
            .map_err(|_| Error::new("Service clients not available"))?;

        // 1. Get feed from recommendation service
        let mut feed_client = clients.feed_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to feed service: {}", e)))?;

        let feed_request = tonic::Request::new(GetFeedRequest {
            user_id: user_id.clone(),
            limit: limit as u32,
            cursor: cursor.unwrap_or_default(),
            algorithm: "ch".to_string(),  // Use ClickHouse algorithm
        });

        let feed_response = feed_client.get_feed(feed_request)
            .await
            .map_err(|e| Error::new(format!("Failed to get feed: {}", e)))?
            .into_inner();

        if feed_response.posts.is_empty() {
            return Ok(FeedResponse {
                posts: vec![],
                cursor: None,
                has_more: false,
            });
        }

        // 2. Get full post details from content service
        let post_ids: Vec<String> = feed_response.posts.iter().map(|p| p.id.clone()).collect();
        let mut content_client = clients.content_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to content service: {}", e)))?;

        let posts_request = tonic::Request::new(GetPostsByIdsRequest {
            post_ids: post_ids.clone(),
        });

        let posts_response = content_client.get_posts_by_ids(posts_request)
            .await
            .map_err(|e| Error::new(format!("Failed to get posts: {}", e)))?
            .into_inner();

        // 3. Get author profiles from user service
        let author_ids: Vec<String> = posts_response.posts.iter().map(|p| p.user_id.clone()).collect();
        let mut user_client = clients.user_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to user service: {}", e)))?;

        let profiles_request = tonic::Request::new(GetUserProfilesByIdsRequest {
            user_ids: author_ids,
        });

        let profiles_response = user_client.get_user_profiles_by_ids(profiles_request)
            .await
            .map_err(|e| Error::new(format!("Failed to get user profiles: {}", e)))?
            .into_inner();

        // 4. Combine data into GraphQL Post objects
        let mut posts = vec![];
        for content_post in posts_response.posts {
            let author = profiles_response.profiles.iter()
                .find(|p| p.id == content_post.user_id)
                .map(|p| p.clone().into());

            posts.push(Post {
                id: content_post.id,
                user_id: content_post.user_id,
                caption: if content_post.content.is_empty() { None } else { Some(content_post.content) },
                image_url: if content_post.image_url.is_empty() { None } else { Some(content_post.image_url) },
                thumbnail_url: if content_post.thumbnail_url.is_empty() { None } else { Some(content_post.thumbnail_url) },
                like_count: content_post.like_count as i32,
                comment_count: content_post.comment_count as i32,
                view_count: 0,  // Not in proto
                created_at: content_post.created_at,
                author,
                is_liked: None,  // TODO: Check if user liked this post
            });
        }

        Ok(FeedResponse {
            posts,
            cursor: if feed_response.next_cursor.is_empty() { None } else { Some(feed_response.next_cursor) },
            has_more: feed_response.has_more,
        })
    }
}

/// Content mutations
#[derive(Default)]
pub struct ContentMutation;

#[Object]
impl ContentMutation {
    /// Create a new post
    async fn create_post(
        &self,
        ctx: &Context<'_>,
        input: CreatePostInput,
    ) -> Result<Post> {
        // TODO: Call content-service via gRPC
        // For now, return mock data
        Ok(Post {
            id: "new-post-id".to_string(),
            user_id: "current-user-id".to_string(),
            caption: input.caption,
            image_url: Some(input.image_url),
            thumbnail_url: None,
            like_count: 0,
            comment_count: 0,
            view_count: 0,
            created_at: chrono::Utc::now().timestamp(),
            author: None,
            is_liked: Some(false),
        })
    }

    /// Delete a post
    async fn delete_post(
        &self,
        ctx: &Context<'_>,
        #[graphql(name = "postId")] post_id: String,
    ) -> Result<bool> {
        // TODO: Call content-service via gRPC
        Ok(true)
    }

    /// Like a post
    async fn like_post(
        &self,
        ctx: &Context<'_>,
        #[graphql(name = "postId")] post_id: String,
    ) -> Result<bool> {
        // TODO: Call content-service via gRPC
        Ok(true)
    }

    /// Unlike a post
    async fn unlike_post(
        &self,
        ctx: &Context<'_>,
        #[graphql(name = "postId")] post_id: String,
    ) -> Result<bool> {
        // TODO: Call content-service via gRPC
        Ok(true)
    }
}
