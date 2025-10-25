import React from 'react';
import VideoPlayer from '../VideoPlayer/VideoPlayer';

interface VideoMetadata {
  id: string;
  cdn_url?: string;
  thumbnail_url?: string;
  duration_seconds?: number;
  position: number;
}

interface PostCardProps {
  id: string;
  userId: string;
  caption?: string;
  thumbnailUrl?: string;
  mediumUrl?: string;
  originalUrl?: string;
  videos?: VideoMetadata[];
  contentType: string; // 'image', 'video', or 'mixed'
  likeCount: number;
  commentCount: number;
  viewCount: number;
  status: string;
  createdAt: string;
  onLike?: (postId: string) => void;
  onComment?: (postId: string) => void;
}

/**
 * PostCard Component
 * Displays a single post with:
 * - Images (thumbnails, medium, original)
 * - Videos with HLS player
 * - Engagement metrics (likes, comments, views)
 * - Post metadata (caption, timestamp, author)
 */
const PostCard: React.FC<PostCardProps> = ({
  id,
  userId,
  caption,
  thumbnailUrl,
  mediumUrl,
  originalUrl,
  videos,
  contentType,
  likeCount,
  commentCount,
  viewCount,
  status,
  createdAt,
  onLike,
  onComment,
}) => {
  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  };

  const handleLike = () => {
    onLike?.(id);
  };

  const handleComment = () => {
    onComment?.(id);
  };

  return (
    <div
      style={{
        border: '1px solid #e0e0e0',
        borderRadius: '8px',
        overflow: 'hidden',
        background: 'white',
        marginBottom: '16px',
        boxShadow: '0 2px 4px rgba(0,0,0,0.1)',
      }}
    >
      {/* Header */}
      <div style={{ padding: '12px 16px', borderBottom: '1px solid #f0f0f0' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <div style={{ fontSize: '14px', fontWeight: 600, color: '#333' }}>User {userId.slice(0, 8)}</div>
            <div style={{ fontSize: '12px', color: '#999', marginTop: '4px' }}>
              {formatDate(createdAt)}
            </div>
          </div>
          <div style={{ fontSize: '12px', color: '#999', background: '#f5f5f5', padding: '4px 8px', borderRadius: '4px' }}>
            {contentType.charAt(0).toUpperCase() + contentType.slice(1)}
          </div>
        </div>
      </div>

      {/* Content Area */}
      <div style={{ position: 'relative', background: '#fafafa' }}>
        {/* Images */}
        {(contentType === 'image' || contentType === 'mixed') && (mediumUrl || originalUrl) && (
          <div style={{ width: '100%', aspectRatio: '4/3', overflow: 'hidden', background: '#000' }}>
            <img
              src={mediumUrl || originalUrl || ''}
              alt="Post"
              style={{
                width: '100%',
                height: '100%',
                objectFit: 'cover',
              }}
            />
          </div>
        )}

        {/* Videos */}
        {(contentType === 'video' || contentType === 'mixed') && videos && videos.length > 0 && (
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: videos.length === 1 ? '1fr' : 'repeat(auto-fit, minmax(200px, 1fr))',
              gap: videos.length === 1 ? 0 : '8px',
              padding: videos.length === 1 ? 0 : '8px',
            }}
          >
            {videos.map((video, index) => (
              <div key={video.id || index}>
                <VideoPlayer
                  cdnUrl={video.cdn_url}
                  thumbnailUrl={video.thumbnail_url}
                  durationSeconds={video.duration_seconds}
                  position={video.position}
                />
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Caption */}
      {caption && (
        <div style={{ padding: '12px 16px', borderBottom: '1px solid #f0f0f0' }}>
          <p style={{ margin: 0, fontSize: '14px', color: '#333', lineHeight: '1.5' }}>
            {caption}
          </p>
        </div>
      )}

      {/* Stats */}
      <div style={{ padding: '12px 16px', fontSize: '13px', color: '#666', borderBottom: '1px solid #f0f0f0' }}>
        <div style={{ display: 'flex', gap: '16px' }}>
          <span>❤️ {likeCount} likes</span>
          <span>💬 {commentCount} comments</span>
          <span>👁️ {viewCount} views</span>
        </div>
      </div>

      {/* Actions */}
      <div style={{ padding: '12px 16px', display: 'flex', gap: '12px' }}>
        <button
          onClick={handleLike}
          style={{
            flex: 1,
            padding: '8px 12px',
            border: 'none',
            background: '#007bff',
            color: 'white',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '13px',
            fontWeight: 600,
            transition: 'background 0.2s',
          }}
          onMouseOver={(e) => (e.currentTarget.style.background = '#0056b3')}
          onMouseOut={(e) => (e.currentTarget.style.background = '#007bff')}
        >
          👍 Like
        </button>
        <button
          onClick={handleComment}
          style={{
            flex: 1,
            padding: '8px 12px',
            border: '1px solid #ddd',
            background: 'white',
            color: '#333',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '13px',
            fontWeight: 600,
            transition: 'all 0.2s',
          }}
          onMouseOver={(e) => {
            e.currentTarget.style.background = '#f5f5f5';
          }}
          onMouseOut={(e) => {
            e.currentTarget.style.background = 'white';
          }}
        >
          💬 Comment
        </button>
      </div>

      {/* Status Indicator */}
      {status !== 'published' && (
        <div
          style={{
            padding: '8px 16px',
            background: '#fff3cd',
            color: '#856404',
            fontSize: '12px',
            textAlign: 'center',
          }}
        >
          Status: {status}
        </div>
      )}
    </div>
  );
};

export default PostCard;
