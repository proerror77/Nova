import React, { useState, useEffect } from 'react';
import { useAuth } from '../../context/AuthContext';
import PostCard from '../Post/PostCard';

interface Post {
  id: string;
  user_id: string;
  caption?: string;
  thumbnail_url?: string;
  medium_url?: string;
  original_url?: string;
  videos?: Array<{
    id: string;
    cdn_url?: string;
    thumbnail_url?: string;
    duration_seconds?: number;
    position: number;
  }>;
  content_type: string;
  like_count: number;
  comment_count: number;
  view_count: number;
  status: string;
  created_at: string;
}

interface FeedResponse {
  posts: string[]; // Array of post IDs
  cursor?: string;
  has_more: boolean;
  total_count: number;
}

/**
 * FeedView Component
 * Displays a personalized feed of posts
 * Features:
 * - Fetch posts from API
 * - Infinite scroll pagination
 * - Support for posts with images and videos
 * - Loading and error states
 */
const FeedView: React.FC = () => {
  const { accessToken } = useAuth();
  const [posts, setPosts] = useState<Post[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [cursor, setCursor] = useState<string | undefined>();
  const [error, setError] = useState<string | null>(null);
  const apiBase = 'http://localhost:8000/api/v1';

  const fetchFeed = async (paginationCursor?: string) => {
    if (!accessToken) {
      setError('Not authenticated');
      return;
    }

    setIsLoading(true);
    try {
      // Fetch feed (get post IDs)
      const feedParams = new URLSearchParams({
        algo: 'time', // Use timeline algorithm
        limit: '10',
      });
      if (paginationCursor) {
        feedParams.append('cursor', paginationCursor);
      }

      const feedRes = await fetch(`${apiBase}/feed?${feedParams}`, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      });

      if (!feedRes.ok) {
        throw new Error(`HTTP ${feedRes.status} from /feed`);
      }

      const feedData: FeedResponse = await feedRes.json();
      setHasMore(feedData.has_more);
      setCursor(feedData.cursor);

      // Fetch full post data for each post ID
      const postDetails = await Promise.all(
        feedData.posts.map((postId) =>
          fetch(`${apiBase}/posts/${postId}`, {
            headers: {
              Authorization: `Bearer ${accessToken}`,
            },
          })
            .then((res) => {
              if (!res.ok) {
                throw new Error(`Failed to fetch post ${postId}`);
              }
              return res.json();
            })
            .catch((err) => {
              console.error(`Error fetching post ${postId}:`, err);
              return null;
            })
        )
      );

      const validPosts = postDetails.filter((p) => p !== null);

      if (paginationCursor) {
        setPosts((prev) => [...prev, ...validPosts]);
      } else {
        setPosts(validPosts);
      }

      setError(null);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      console.error('Feed fetch error:', err);
    } finally {
      setIsLoading(false);
    }
  };

  // Initial fetch
  useEffect(() => {
    fetchFeed();
  }, [accessToken]);

  const handleLoadMore = () => {
    if (!isLoading && hasMore && cursor) {
      fetchFeed(cursor);
    }
  };

  const handleLike = async (postId: string) => {
    if (!accessToken) return;

    try {
      // Update local state optimistically
      setPosts((prevPosts) =>
        prevPosts.map((post) =>
          post.id === postId
            ? { ...post, like_count: post.like_count + 1 }
            : post
        )
      );

      // Import at usage to avoid circular dependency
      const { likePost } = await import('../../services/api/postService');
      await likePost(postId);
    } catch (err) {
      // Rollback on error
      setPosts((prevPosts) =>
        prevPosts.map((post) =>
          post.id === postId
            ? { ...post, like_count: Math.max(0, post.like_count - 1) }
            : post
        )
      );
      console.error('Like error:', err);
    }
  };

  const handleComment = async (postId: string) => {
    if (!accessToken) return;

    // For now, just show a prompt - full implementation would need a modal/dialog
    const content = window.prompt('Write a comment...');
    if (!content) return;

    try {
      // Update local state optimistically
      setPosts((prevPosts) =>
        prevPosts.map((post) =>
          post.id === postId
            ? { ...post, comment_count: post.comment_count + 1 }
            : post
        )
      );

      // Import at usage to avoid circular dependency
      const { createComment } = await import('../../services/api/postService');
      await createComment(postId, content);
    } catch (err) {
      // Rollback on error
      setPosts((prevPosts) =>
        prevPosts.map((post) =>
          post.id === postId
            ? { ...post, comment_count: Math.max(0, post.comment_count - 1) }
            : post
        )
      );
      console.error('Comment error:', err);
    }
  };

  if (!accessToken) {
    return (
      <div
        style={{
          padding: '24px',
          textAlign: 'center',
          background: '#f5f5f5',
          borderRadius: '8px',
        }}
      >
        <p>Please log in to view your feed</p>
      </div>
    );
  }

  return (
    <div style={{ maxWidth: '600px', margin: '0 auto' }}>
      <div style={{ marginBottom: '24px' }}>
        <h2 style={{ margin: 0, marginBottom: '8px' }}>Your Feed</h2>
        <p style={{ margin: 0, color: '#666', fontSize: '14px' }}>
          Scroll down to see more posts
        </p>
      </div>

      {error && (
        <div
          style={{
            padding: '12px 16px',
            background: '#f8d7da',
            color: '#721c24',
            borderRadius: '4px',
            marginBottom: '16px',
          }}
        >
          Error: {error}
        </div>
      )}

      {posts.length === 0 && !isLoading && !error && (
        <div
          style={{
            padding: '24px',
            textAlign: 'center',
            background: '#f5f5f5',
            borderRadius: '8px',
          }}
        >
          <p style={{ color: '#666' }}>No posts yet. Create one or follow someone!</p>
        </div>
      )}

      {/* Posts List */}
      <div>
        {posts.map((post) => (
          <PostCard
            key={post.id}
            id={post.id}
            userId={post.user_id}
            caption={post.caption}
            thumbnailUrl={post.thumbnail_url}
            mediumUrl={post.medium_url}
            originalUrl={post.original_url}
            videos={post.videos}
            contentType={post.content_type}
            likeCount={post.like_count}
            commentCount={post.comment_count}
            viewCount={post.view_count}
            status={post.status}
            createdAt={post.created_at}
            onLike={handleLike}
            onComment={handleComment}
          />
        ))}
      </div>

      {/* Loading and Load More */}
      <div style={{ marginTop: '24px', textAlign: 'center' }}>
        {isLoading && <p style={{ color: '#666' }}>Loading posts...</p>}

        {!isLoading && hasMore && posts.length > 0 && (
          <button
            onClick={handleLoadMore}
            style={{
              padding: '10px 20px',
              background: '#007bff',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              fontSize: '14px',
              fontWeight: 600,
            }}
            onMouseOver={(e) => (e.currentTarget.style.background = '#0056b3')}
            onMouseOut={(e) => (e.currentTarget.style.background = '#007bff')}
          >
            Load More Posts
          </button>
        )}

        {!hasMore && posts.length > 0 && (
          <p style={{ color: '#999', fontSize: '14px' }}>No more posts to load</p>
        )}
      </div>
    </div>
  );
};

export default FeedView;
