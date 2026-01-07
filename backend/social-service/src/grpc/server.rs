use crate::repository::{BookmarkRepository, CommentRepository, LikeRepository, ShareRepository};
use crate::services::CounterService;
use tonic::{Request, Response, Status};
use uuid::Uuid;

// Generated proto code
pub mod social {
    tonic::include_proto!("nova.social_service.v2");
}

use social::social_service_server::SocialService;
use social::*;

/// Implementation of SocialService gRPC service
#[derive(Clone)]
pub struct SocialServiceImpl {
    like_repo: LikeRepository,
    comment_repo: CommentRepository,
    share_repo: ShareRepository,
    bookmark_repo: BookmarkRepository,
    counter_service: CounterService,
}

impl SocialServiceImpl {
    pub fn new(
        like_repo: LikeRepository,
        comment_repo: CommentRepository,
        share_repo: ShareRepository,
        bookmark_repo: BookmarkRepository,
        counter_service: CounterService,
    ) -> Self {
        Self {
            like_repo,
            comment_repo,
            share_repo,
            bookmark_repo,
            counter_service,
        }
    }
}

#[tonic::async_trait]
impl SocialService for SocialServiceImpl {
    // ========== Like Operations ==========

    async fn create_like(
        &self,
        request: Request<CreateLikeRequest>,
    ) -> Result<Response<CreateLikeResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Create like in database
        let (_like, _was_created) = self.like_repo
            .create_like(user_id, post_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to create like: {}", e)))?;

        // Read accurate count from PostgreSQL (source of truth)
        // Use rate-limited refresh to prevent thundering herd on hot posts
        let like_count = self.counter_service
            .refresh_like_count_rate_limited(post_id)
            .await
            .unwrap_or(0);

        Ok(Response::new(CreateLikeResponse {
            success: true,
            like_count,
            message: "Like created successfully".to_string(),
        }))
    }

    async fn delete_like(
        &self,
        request: Request<DeleteLikeRequest>,
    ) -> Result<Response<DeleteLikeResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Delete like from database
        let _was_deleted = self.like_repo
            .delete_like(user_id, post_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to delete like: {}", e)))?;

        // Read accurate count from PostgreSQL (source of truth)
        // Use rate-limited refresh to prevent thundering herd on hot posts
        let like_count = self.counter_service
            .refresh_like_count_rate_limited(post_id)
            .await
            .unwrap_or(0);

        Ok(Response::new(DeleteLikeResponse {
            success: true,
            like_count,
            message: "Like deleted successfully".to_string(),
        }))
    }

    async fn get_like_count(
        &self,
        request: Request<GetLikeCountRequest>,
    ) -> Result<Response<GetLikeCountResponse>, Status> {
        let req = request.into_inner();
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Try Redis first, fallback to PostgreSQL
        let count = match self.counter_service.get_like_count(post_id).await {
            Ok(count) => count,
            Err(_) => self.like_repo.get_like_count(post_id).await.unwrap_or(0),
        };

        Ok(Response::new(GetLikeCountResponse { count }))
    }

    async fn check_user_liked(
        &self,
        request: Request<CheckUserLikedRequest>,
    ) -> Result<Response<CheckUserLikedResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        let liked = self
            .like_repo
            .check_user_liked(user_id, post_id)
            .await
            .unwrap_or(false);

        Ok(Response::new(CheckUserLikedResponse { liked }))
    }

    async fn batch_check_user_liked(
        &self,
        _request: Request<BatchCheckUserLikedRequest>,
    ) -> Result<Response<BatchCheckUserLikedResponse>, Status> {
        // TODO: Implement batch check
        Err(Status::unimplemented("Batch check not yet implemented"))
    }

    async fn get_post_likes(
        &self,
        request: Request<GetPostLikesRequest>,
    ) -> Result<Response<GetPostLikesResponse>, Status> {
        let req = request.into_inner();
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;
        let limit = if req.limit > 0 && req.limit <= 100 {
            req.limit
        } else {
            50
        };
        let offset = req.offset.max(0);

        let likes = self
            .like_repo
            .get_post_likes(post_id, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get likes: {}", e)))?;

        let total_count = self
            .like_repo
            .get_like_count(post_id)
            .await
            .unwrap_or(0) as i32;

        let proto_likes: Vec<Like> = likes
            .into_iter()
            .map(|like| Like {
                id: like.id.to_string(),
                user_id: like.user_id.to_string(),
                post_id: like.post_id.to_string(),
                created_at: like.created_at.to_rfc3339(),
            })
            .collect();

        let has_more = (offset + limit) < total_count;

        Ok(Response::new(GetPostLikesResponse {
            likes: proto_likes,
            total_count,
            has_more,
        }))
    }

    // ========== Comment Operations ==========

    async fn create_comment(
        &self,
        request: Request<CreateCommentRequest>,
    ) -> Result<Response<CreateCommentResponse>, Status> {
        let req = request.into_inner();
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let parent_comment_id = if req.parent_comment_id.is_empty() {
            None
        } else {
            Some(
                Uuid::parse_str(&req.parent_comment_id)
                    .map_err(|_| Status::invalid_argument("Invalid parent_comment_id"))?,
            )
        };

        // Extract author_account_type from request, default to "primary" (Issue #259)
        let author_account_type = if req.author_account_type.is_empty() {
            None
        } else {
            Some(req.author_account_type.as_str())
        };

        let comment = self
            .comment_repo
            .create_comment(post_id, user_id, req.content, parent_comment_id, author_account_type)
            .await
            .map_err(|e| Status::internal(format!("Failed to create comment: {}", e)))?;

        // Increment counter in Redis
        let _ = self.counter_service.increment_comment_count(post_id).await;

        let proto_comment = Comment {
            id: comment.id.to_string(),
            post_id: comment.post_id.to_string(),
            user_id: comment.user_id.to_string(),
            content: comment.content,
            parent_comment_id: comment.parent_comment_id.map(|id| id.to_string()).unwrap_or_default(),
            created_at: comment.created_at.to_rfc3339(),
            updated_at: comment.updated_at.to_rfc3339(),
            author_account_type: comment.author_account_type.unwrap_or_else(|| "primary".to_string()),
        };

        Ok(Response::new(CreateCommentResponse {
            success: true,
            comment: Some(proto_comment),
            message: "Comment created successfully".to_string(),
        }))
    }

    async fn delete_comment(
        &self,
        request: Request<DeleteCommentRequest>,
    ) -> Result<Response<DeleteCommentResponse>, Status> {
        let req = request.into_inner();
        let comment_id = Uuid::parse_str(&req.comment_id)
            .map_err(|_| Status::invalid_argument("Invalid comment_id"))?;
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        // Get comment first to get post_id for counter decrement
        let comment = self.comment_repo.get_comment(comment_id).await
            .map_err(|e| Status::internal(format!("Failed to get comment: {}", e)))?
            .ok_or_else(|| Status::not_found("Comment not found"))?;

        let deleted = self
            .comment_repo
            .delete_comment(comment_id, user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to delete comment: {}", e)))?;

        if deleted {
            // Decrement counter in Redis
            let _ = self.counter_service.decrement_comment_count(comment.post_id).await;
        }

        Ok(Response::new(DeleteCommentResponse {
            success: deleted,
            message: if deleted {
                "Comment deleted successfully".to_string()
            } else {
                "Comment not found or unauthorized".to_string()
            },
        }))
    }

    async fn update_comment(
        &self,
        request: Request<UpdateCommentRequest>,
    ) -> Result<Response<UpdateCommentResponse>, Status> {
        let req = request.into_inner();
        let comment_id = Uuid::parse_str(&req.comment_id)
            .map_err(|_| Status::invalid_argument("Invalid comment_id"))?;
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        let comment = self
            .comment_repo
            .update_comment(comment_id, user_id, req.content)
            .await
            .map_err(|e| Status::internal(format!("Failed to update comment: {}", e)))?
            .ok_or_else(|| Status::not_found("Comment not found or unauthorized"))?;

        let proto_comment = Comment {
            id: comment.id.to_string(),
            post_id: comment.post_id.to_string(),
            user_id: comment.user_id.to_string(),
            content: comment.content,
            parent_comment_id: comment.parent_comment_id.map(|id| id.to_string()).unwrap_or_default(),
            created_at: comment.created_at.to_rfc3339(),
            updated_at: comment.updated_at.to_rfc3339(),
            author_account_type: comment.author_account_type.unwrap_or_else(|| "primary".to_string()),
        };

        Ok(Response::new(UpdateCommentResponse {
            success: true,
            comment: Some(proto_comment),
            message: "Comment updated successfully".to_string(),
        }))
    }

    async fn get_comments(
        &self,
        request: Request<GetCommentsRequest>,
    ) -> Result<Response<GetCommentsResponse>, Status> {
        let req = request.into_inner();
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;
        let limit = if req.limit > 0 && req.limit <= 100 {
            req.limit
        } else {
            50
        };
        let offset = req.offset.max(0);
        let sort_by = if req.sort_by.is_empty() {
            "created_at"
        } else {
            &req.sort_by
        };
        let order = if req.order.is_empty() {
            "desc"
        } else {
            &req.order
        };

        let comments = self
            .comment_repo
            .get_comments(post_id, limit, offset, sort_by, order)
            .await
            .map_err(|e| Status::internal(format!("Failed to get comments: {}", e)))?;

        let total_count = self
            .comment_repo
            .get_comment_count(post_id)
            .await
            .unwrap_or(0) as i32;

        let proto_comments: Vec<Comment> = comments
            .into_iter()
            .map(|comment| Comment {
                id: comment.id.to_string(),
                post_id: comment.post_id.to_string(),
                user_id: comment.user_id.to_string(),
                content: comment.content,
                parent_comment_id: comment.parent_comment_id.map(|id| id.to_string()).unwrap_or_default(),
                created_at: comment.created_at.to_rfc3339(),
                updated_at: comment.updated_at.to_rfc3339(),
                author_account_type: comment.author_account_type.unwrap_or_else(|| "primary".to_string()),
            })
            .collect();

        let has_more = (offset + limit) < total_count;

        Ok(Response::new(GetCommentsResponse {
            comments: proto_comments,
            total_count,
            has_more,
        }))
    }

    async fn get_comment(
        &self,
        request: Request<GetCommentRequest>,
    ) -> Result<Response<GetCommentResponse>, Status> {
        let req = request.into_inner();
        let comment_id = Uuid::parse_str(&req.comment_id)
            .map_err(|_| Status::invalid_argument("Invalid comment_id"))?;

        let comment = self
            .comment_repo
            .get_comment(comment_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get comment: {}", e)))?
            .ok_or_else(|| Status::not_found("Comment not found"))?;

        let proto_comment = Comment {
            id: comment.id.to_string(),
            post_id: comment.post_id.to_string(),
            user_id: comment.user_id.to_string(),
            content: comment.content,
            parent_comment_id: comment.parent_comment_id.map(|id| id.to_string()).unwrap_or_default(),
            created_at: comment.created_at.to_rfc3339(),
            updated_at: comment.updated_at.to_rfc3339(),
            author_account_type: comment.author_account_type.unwrap_or_else(|| "primary".to_string()),
        };

        Ok(Response::new(GetCommentResponse {
            comment: Some(proto_comment),
        }))
    }

    async fn get_comment_count(
        &self,
        request: Request<GetCommentCountRequest>,
    ) -> Result<Response<GetCommentCountResponse>, Status> {
        let req = request.into_inner();
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Try Redis first, fallback to PostgreSQL
        let count = match self.counter_service.get_comment_count(post_id).await {
            Ok(count) => count,
            Err(_) => self.comment_repo.get_comment_count(post_id).await.unwrap_or(0),
        };

        Ok(Response::new(GetCommentCountResponse { count }))
    }

    // ========== Share Operations ==========

    async fn create_share(
        &self,
        request: Request<CreateShareRequest>,
    ) -> Result<Response<CreateShareResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        self.share_repo
            .create_share(user_id, post_id, req.share_type)
            .await
            .map_err(|e| Status::internal(format!("Failed to create share: {}", e)))?;

        // Increment counter in Redis
        let share_count = self
            .counter_service
            .increment_share_count(post_id)
            .await
            .unwrap_or(0);

        Ok(Response::new(CreateShareResponse {
            success: true,
            share_count,
            message: "Share created successfully".to_string(),
        }))
    }

    async fn get_share_count(
        &self,
        request: Request<GetShareCountRequest>,
    ) -> Result<Response<GetShareCountResponse>, Status> {
        let req = request.into_inner();
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        // Try Redis first, fallback to PostgreSQL
        let count = match self.counter_service.get_share_count(post_id).await {
            Ok(count) => count,
            Err(_) => self.share_repo.get_share_count(post_id).await.unwrap_or(0),
        };

        Ok(Response::new(GetShareCountResponse { count }))
    }

    async fn check_user_shared(
        &self,
        request: Request<CheckUserSharedRequest>,
    ) -> Result<Response<CheckUserSharedResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        let shared = self
            .share_repo
            .check_user_shared(user_id, post_id)
            .await
            .unwrap_or(false);

        Ok(Response::new(CheckUserSharedResponse { shared }))
    }

    // ========== Batch Operations ==========

    async fn batch_get_post_stats(
        &self,
        request: Request<BatchGetPostStatsRequest>,
    ) -> Result<Response<BatchGetPostStatsResponse>, Status> {
        let req = request.into_inner();

        if req.post_ids.len() > 100 {
            return Err(Status::invalid_argument(
                "Maximum 100 post IDs allowed in batch",
            ));
        }

        let post_ids: Result<Vec<Uuid>, _> = req
            .post_ids
            .iter()
            .map(|id| Uuid::parse_str(id))
            .collect();

        let post_ids = post_ids.map_err(|_| Status::invalid_argument("Invalid post_id in batch"))?;

        let stats_map = self
            .counter_service
            .batch_get_post_stats(&post_ids)
            .await
            .map_err(|e| Status::internal(format!("Failed to get batch stats: {}", e)))?;

        let mut stats = std::collections::HashMap::new();
        for (post_id, (like_count, comment_count, share_count)) in stats_map {
            stats.insert(
                post_id.to_string(),
                PostStats {
                    like_count,
                    comment_count,
                    share_count,
                },
            );
        }

        Ok(Response::new(BatchGetPostStatsResponse { stats }))
    }

    // ========== Bookmark Operations ==========

    async fn create_bookmark(
        &self,
        request: Request<CreateBookmarkRequest>,
    ) -> Result<Response<CreateBookmarkResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        let bookmark = self
            .bookmark_repo
            .create_bookmark(user_id, post_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to create bookmark: {}", e)))?;

        let proto_bookmark = Bookmark {
            id: bookmark.id.to_string(),
            user_id: bookmark.user_id.to_string(),
            post_id: bookmark.post_id.to_string(),
            collection_id: bookmark.collection_id.map(|id| id.to_string()).unwrap_or_default(),
            bookmarked_at: Some(prost_types::Timestamp {
                seconds: bookmark.bookmarked_at.timestamp(),
                nanos: bookmark.bookmarked_at.timestamp_subsec_nanos() as i32,
            }),
        };

        Ok(Response::new(CreateBookmarkResponse {
            success: true,
            bookmark: Some(proto_bookmark),
        }))
    }

    async fn delete_bookmark(
        &self,
        request: Request<DeleteBookmarkRequest>,
    ) -> Result<Response<DeleteBookmarkResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        self.bookmark_repo
            .delete_bookmark(user_id, post_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to delete bookmark: {}", e)))?;

        Ok(Response::new(DeleteBookmarkResponse { success: true }))
    }

    async fn get_bookmarks(
        &self,
        request: Request<GetBookmarksRequest>,
    ) -> Result<Response<GetBookmarksResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let limit = if req.limit > 0 && req.limit <= 100 {
            req.limit
        } else {
            50
        };
        let offset = req.offset.max(0);

        let post_ids = self
            .bookmark_repo
            .get_bookmarked_post_ids(user_id, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get bookmarks: {}", e)))?;

        let total_count = self
            .bookmark_repo
            .get_user_bookmark_count(user_id)
            .await
            .unwrap_or(0) as i32;

        let post_id_strings: Vec<String> = post_ids.into_iter().map(|id| id.to_string()).collect();

        Ok(Response::new(GetBookmarksResponse {
            post_ids: post_id_strings,
            total_count,
        }))
    }

    async fn check_user_bookmarked(
        &self,
        request: Request<CheckUserBookmarkedRequest>,
    ) -> Result<Response<CheckUserBookmarkedResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;
        let post_id = Uuid::parse_str(&req.post_id)
            .map_err(|_| Status::invalid_argument("Invalid post_id"))?;

        let bookmarked = self
            .bookmark_repo
            .check_user_bookmarked(user_id, post_id)
            .await
            .unwrap_or(false);

        Ok(Response::new(CheckUserBookmarkedResponse { bookmarked }))
    }

    async fn batch_check_bookmarked(
        &self,
        request: Request<BatchCheckBookmarkedRequest>,
    ) -> Result<Response<BatchCheckBookmarkedResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        if req.post_ids.len() > 100 {
            return Err(Status::invalid_argument(
                "Maximum 100 post IDs allowed in batch",
            ));
        }

        let post_ids: Result<Vec<Uuid>, _> = req
            .post_ids
            .iter()
            .map(|id| Uuid::parse_str(id))
            .collect();

        let post_ids = post_ids.map_err(|_| Status::invalid_argument("Invalid post_id in batch"))?;

        let bookmarked_ids = self
            .bookmark_repo
            .batch_check_bookmarked(user_id, &post_ids)
            .await
            .map_err(|e| Status::internal(format!("Failed to batch check bookmarks: {}", e)))?;

        let bookmarked_post_ids: Vec<String> =
            bookmarked_ids.into_iter().map(|id| id.to_string()).collect();

        Ok(Response::new(BatchCheckBookmarkedResponse {
            bookmarked_post_ids,
        }))
    }
}
