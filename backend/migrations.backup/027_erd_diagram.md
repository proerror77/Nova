# Post-Video Association ERD

## Entity Relationship Diagram

```mermaid
erDiagram
    users ||--o{ posts : creates
    users ||--o{ videos : uploads
    users ||--o{ likes : gives
    users ||--o{ comments : writes

    posts ||--o{ post_images : contains
    posts ||--o{ post_videos : contains
    posts ||--o{ likes : receives
    posts ||--o{ comments : receives
    posts ||--|| post_metadata : has
    posts ||--|| social_metadata : has

    videos ||--o{ post_videos : "linked to"
    videos ||--|| video_engagement : has

    users {
        uuid id PK
        varchar username UK
        varchar email UK
        varchar password_hash
        boolean email_verified
        timestamptz created_at
    }

    posts {
        uuid id PK
        uuid user_id FK
        text caption
        varchar image_key
        varchar status
        varchar content_type "NEW: image|video|mixed"
        timestamptz created_at
        timestamptz soft_delete
    }

    post_images {
        uuid id PK
        uuid post_id FK
        varchar s3_key
        varchar size_variant "thumbnail|medium|original"
        varchar status
        int width
        int height
    }

    post_videos {
        uuid id PK "NEW TABLE"
        uuid post_id FK
        uuid video_id FK
        int position "NEW: ordering"
        timestamptz created_at
    }

    videos {
        uuid id PK
        uuid creator_id FK
        varchar title
        int duration_seconds
        varchar cdn_url
        varchar thumbnail_url
        varchar status
        timestamptz created_at
    }

    likes {
        uuid id PK
        uuid user_id FK
        uuid post_id FK
        timestamptz created_at
    }

    comments {
        uuid id PK
        uuid post_id FK
        uuid user_id FK
        text content
        uuid parent_comment_id FK
        timestamptz created_at
    }

    post_metadata {
        uuid post_id PK,FK
        int like_count
        int comment_count
        int view_count
    }

    social_metadata {
        uuid post_id PK,FK
        int follower_count
        int like_count
        int comment_count
        int share_count
        int view_count
    }

    video_engagement {
        uuid video_id PK,FK
        bigint view_count
        bigint like_count
        bigint share_count
        bigint comment_count
        float completion_rate
    }
```

## Key Changes Highlighted

### 🆕 New Entities

1. **`post_videos`** (Junction Table)
   - Links posts to videos with positioning
   - Enables multiple videos per post
   - Supports future carousel/playlist features

2. **`posts.content_type`** (New Column)
   - Distinguishes post types: `'image'`, `'video'`, `'mixed'`
   - Auto-updated by triggers based on attachments

### 🔗 Relationship Details

| From | To | Cardinality | On Delete |
|------|-----|-------------|-----------|
| `posts` | `post_videos` | 1:N | CASCADE |
| `videos` | `post_videos` | 1:N | CASCADE |
| `post_videos` | `videos` | N:1 | CASCADE |
| `post_videos` | `posts` | N:1 | CASCADE |

### 🎯 Design Patterns

**Pattern 1: Polymorphic Attachments (Simplified)**
```
posts (container)
  ├── post_images[] (image attachments)
  └── post_videos[] (video attachments)
```

**Pattern 2: Position-Based Ordering**
```sql
-- Videos rendered in order: 0, 1, 2, ...
SELECT * FROM post_videos
WHERE post_id = $1
ORDER BY position ASC;
```

**Pattern 3: Engagement Stays at Post Level**
```
User likes/comments → post (not individual videos)
Video engagement → tracked separately in video_engagement
```

---

## Data Flow Examples

### Creating a Video Post

```mermaid
sequenceDiagram
    participant User
    participant API
    participant posts
    participant post_videos
    participant videos

    User->>API: POST /api/posts {caption, video_id}
    API->>posts: INSERT (content_type='video')
    posts-->>API: post_id
    API->>post_videos: INSERT (post_id, video_id, position=0)
    post_videos->>posts: Trigger updates content_type
    posts-->>API: Updated post
    API-->>User: 201 Created
```

### Retrieving Feed with Mixed Content

```mermaid
sequenceDiagram
    participant Client
    participant API
    participant get_post_with_media()
    participant DB

    Client->>API: GET /api/feed
    API->>get_post_with_media(): Call for each post
    get_post_with_media()->>DB: JOIN posts+post_images+post_videos+videos
    DB-->>get_post_with_media(): Aggregated JSONB
    get_post_with_media()-->>API: {images: [], videos: []}
    API-->>Client: Feed with mixed content
```

---

## Index Strategy

### Composite Indexes for Common Queries

```sql
-- Query: "Show me all video posts from user X"
CREATE INDEX idx_posts_user_content_type
ON posts(user_id, content_type, created_at DESC)
WHERE soft_delete IS NULL;

-- Query: "Get all videos in a post, ordered"
CREATE INDEX idx_post_videos_post_position
ON post_videos(post_id, position);

-- Query: "Find posts containing a specific video"
CREATE INDEX idx_post_videos_video_id
ON post_videos(video_id);
```

### Query Performance

| Query | Index Used | Rows Scanned |
|-------|-----------|--------------|
| User's video posts | `idx_posts_user_content_type` | O(user's posts) |
| Videos in a post | `idx_post_videos_post_position` | O(videos per post) |
| Posts with video X | `idx_post_videos_video_id` | O(posts with video) |

---

## Comparison: Before vs After

### Before Migration 027

```
┌─────────┐         ┌──────────┐
│  posts  │         │  videos  │
│ (images │         │ (isolated│
│  only)  │         │  content)│
└─────────┘         └──────────┘
     │                    │
     ├─ post_images       ├─ video_engagement
     ├─ likes             │
     └─ comments          (no social features)
```

**Issues**:
- Cannot post videos through main feed
- Videos lack social engagement (likes/comments)
- Inconsistent content model

### After Migration 027

```
┌──────────────────────────────────┐
│             posts                │
│  (unified content container)     │
│  content_type: image|video|mixed │
└──────────────────────────────────┘
     │
     ├─ post_images (images)
     ├─ post_videos (videos) ← NEW
     ├─ likes (unified)
     └─ comments (unified)

┌──────────┐
│  videos  │ (video metadata)
└──────────┘
     │
     └─ video_engagement (analytics)
```

**Benefits**:
- ✅ Videos integrated into main feed
- ✅ Consistent engagement model
- ✅ Supports mixed content (images + videos)
- ✅ Backward compatible with existing posts
