# Migration 027: Post-Video Association

## Overview

Enables Posts to contain Videos alongside Images, unifying content creation into a single `posts` table structure.

## Problem Statement

**Before**: Posts and Videos were completely isolated systems
- `posts` table → only images via `post_images`
- `videos` table → standalone video content
- **Issue**: Cannot create posts containing videos

**After**: Posts are content "containers" that can hold images, videos, or both
- `posts.content_type` → `'image'`, `'video'`, or `'mixed'`
- `post_videos` junction table → links posts to videos with positioning
- **Benefit**: Unified content model, simplified feed architecture

---

## Database Changes

### 1. New Column: `posts.content_type`

```sql
ALTER TABLE posts
ADD COLUMN content_type VARCHAR(50) NOT NULL DEFAULT 'image'
CHECK (content_type IN ('image', 'video', 'mixed'));
```

**Values**:
- `'image'` - Legacy posts with only images (default)
- `'video'` - Posts containing only videos
- `'mixed'` - Posts with both images and videos

### 2. New Table: `post_videos`

```sql
CREATE TABLE post_videos (
    id UUID PRIMARY KEY,
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    position INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(post_id, video_id),
    UNIQUE(post_id, position)
);
```

**Key Features**:
- `position` - Display order for multiple videos (0-indexed)
- Unique constraints prevent duplicate videos and position conflicts
- Cascade delete when post or video is deleted

### 3. Automatic Triggers

Auto-updates `posts.content_type` based on attachments:

```sql
CREATE TRIGGER trg_validate_post_content_type_videos
AFTER INSERT OR DELETE ON post_videos
FOR EACH ROW EXECUTE FUNCTION validate_post_content_type();

CREATE TRIGGER trg_validate_post_content_type_images
AFTER INSERT OR DELETE ON post_images
FOR EACH ROW EXECUTE FUNCTION validate_post_content_type();
```

**Behavior**:
- Has images + videos → `content_type = 'mixed'`
- Has only videos → `content_type = 'video'`
- Has only images → `content_type = 'image'`

### 4. Helper Function: `get_post_with_media()`

Retrieves complete post data in a single query:

```sql
SELECT * FROM get_post_with_media('post-uuid');
```

**Returns**:
```jsonb
{
  "id": "uuid",
  "content_type": "video",
  "images": [...],        -- Array of image variants
  "videos": [             -- Array of videos with position
    {
      "id": "video-uuid",
      "cdn_url": "...",
      "thumbnail_url": "...",
      "duration_seconds": 30,
      "position": 0
    }
  ],
  "like_count": 42,
  "comment_count": 15,
  ...
}
```

---

## Migration Safety

### ✅ Backward Compatibility

- All existing posts default to `content_type = 'image'`
- Zero breaking changes to existing data
- `likes` and `comments` tables unchanged (continue using `post_id`)

### ✅ Idempotency

Run migration multiple times safely:

```bash
docker-compose exec postgres psql -U postgres -d nova_auth \
  -f backend/migrations/027_post_video_association.sql
```

All DDL statements use `IF NOT EXISTS` or `ON CONFLICT` clauses.

### ✅ Data Integrity

**Constraints**:
- `posts.content_type` must be one of: `'image'`, `'video'`, `'mixed'`
- `post_videos.position` must be non-negative
- No duplicate video in same post
- No duplicate position in same post

**Cascade Behavior**:
- Delete post → auto-deletes `post_videos` entries
- Delete video → auto-deletes `post_videos` entries

---

## Performance Optimizations

### Indexes Created

```sql
-- Filter posts by content type
CREATE INDEX idx_posts_content_type ON posts(content_type)
WHERE soft_delete IS NULL;

-- User's posts by type
CREATE INDEX idx_posts_user_content_type ON posts(user_id, content_type, created_at DESC)
WHERE soft_delete IS NULL;

-- Post-video lookups
CREATE INDEX idx_post_videos_post_id ON post_videos(post_id);
CREATE INDEX idx_post_videos_video_id ON post_videos(video_id);
CREATE INDEX idx_post_videos_post_position ON post_videos(post_id, position);
```

**Query Patterns Optimized**:
- Feed queries filtered by content type
- User profile filtered by video posts only
- Ordered video retrieval within a post

---

## Usage Examples

### Create Video-Only Post

```rust
// 1. Create post
let post_id = sqlx::query_scalar!(
    "INSERT INTO posts (user_id, caption, image_key, status, content_type)
     VALUES ($1, $2, $3, 'published', 'video')
     RETURNING id",
    user_id, caption, "placeholder.jpg"
).fetch_one(&pool).await?;

// 2. Link video
sqlx::query!(
    "INSERT INTO post_videos (post_id, video_id, position)
     VALUES ($1, $2, 0)",
    post_id, video_id
).execute(&pool).await?;
```

### Create Mixed Post (Images + Videos)

```rust
// Post automatically becomes 'mixed' via trigger
let post_id = create_post_with_images(...).await?;

sqlx::query!(
    "INSERT INTO post_videos (post_id, video_id, position)
     VALUES ($1, $2, 0)",
    post_id, video_id
).execute(&pool).await?;

// Trigger updates posts.content_type = 'mixed'
```

### Retrieve Post with All Media

```rust
#[derive(sqlx::FromRow)]
struct PostWithMedia {
    id: Uuid,
    content_type: String,
    images: serde_json::Value,  // JSONB array
    videos: serde_json::Value,  // JSONB array
    like_count: i32,
    comment_count: i32,
}

let post = sqlx::query_as!(
    PostWithMedia,
    "SELECT * FROM get_post_with_media($1)",
    post_id
).fetch_one(&pool).await?;
```

### Query Video Posts in Feed

```sql
SELECT p.id, p.caption, pv.videos
FROM posts p
LEFT JOIN LATERAL (
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', v.id,
            'cdn_url', v.cdn_url,
            'thumbnail_url', v.thumbnail_url
        ) ORDER BY pv.position
    ) as videos
    FROM post_videos pv
    JOIN videos v ON pv.video_id = v.id
    WHERE pv.post_id = p.id
) pv ON true
WHERE p.content_type IN ('video', 'mixed')
  AND p.status = 'published'
  AND p.soft_delete IS NULL
ORDER BY p.created_at DESC;
```

---

## Testing

Run comprehensive test suite:

```bash
docker-compose exec -T postgres psql -U postgres -d nova_auth \
  < backend/migrations/027_post_video_association_test.sql
```

**Test Coverage**:
- ✅ Backward compatibility (legacy image posts)
- ✅ Video-only posts
- ✅ Multiple videos with positioning
- ✅ `get_post_with_media()` function
- ✅ Position uniqueness constraints
- ✅ Post-video uniqueness constraints
- ✅ Cascade delete behavior
- ✅ Index existence verification

---

## Design Philosophy (Linus Torvalds Style)

### Good Taste Principles Applied

**1. Eliminate Special Cases**
- ❌ **Bad**: Separate `posts` and `videos` tables with complex joins
- ✅ **Good**: Posts are containers, attachments are polymorphic via junction tables

**2. Simplicity Over Complexity**
- ❌ **Bad**: Polymorphic `attachments` table with `content_type` + `content_id`
- ✅ **Good**: Direct foreign keys in `post_images` and `post_videos`

**3. Never Break Userspace**
- ✅ All existing posts remain `'image'` type
- ✅ Zero changes to `likes` and `comments` tables
- ✅ Backward-compatible API (posts still return image data)

**4. Pragmatism**
- Real problem: Users need to post videos
- Simple solution: Link existing `videos` table to `posts`
- No over-engineering: Triggers auto-maintain `content_type`

---

## Future Extensibility

### Supported Scenarios

**Multiple Videos in One Post**:
```sql
INSERT INTO post_videos (post_id, video_id, position) VALUES
    (post_id, video1_id, 0),
    (post_id, video2_id, 1),
    (post_id, video3_id, 2);
```

**Mixed Content (Carousel)**:
- Images at positions 0-2
- Video at position 3
- Content type auto-updates to `'mixed'`

### Potential Extensions

**Add audio posts** (future):
```sql
ALTER TABLE posts
DROP CONSTRAINT posts_content_type_check;

ALTER TABLE posts
ADD CONSTRAINT posts_content_type_check
CHECK (content_type IN ('image', 'video', 'mixed', 'audio'));

CREATE TABLE post_audio (
    id UUID PRIMARY KEY,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    audio_id UUID REFERENCES audio_files(id) ON DELETE CASCADE,
    position INT NOT NULL DEFAULT 0
);
```

---

## Rollback Plan

If migration causes issues:

```sql
BEGIN;

-- Drop new structures
DROP TABLE IF EXISTS post_videos CASCADE;
DROP FUNCTION IF EXISTS validate_post_content_type() CASCADE;
DROP FUNCTION IF EXISTS get_post_with_media(UUID) CASCADE;

-- Remove content_type column
ALTER TABLE posts DROP COLUMN IF EXISTS content_type;

-- Drop indexes
DROP INDEX IF EXISTS idx_posts_content_type;
DROP INDEX IF EXISTS idx_posts_user_content_type;

COMMIT;
```

**Note**: This will delete all post-video associations but preserves both `posts` and `videos` tables.

---

## Files Modified

```
backend/migrations/
├── 027_post_video_association.sql          ← Migration DDL
├── 027_post_video_association_test.sql     ← Test suite
└── 027_POST_VIDEO_ASSOCIATION_README.md    ← This file
```

---

## Metadata

- **Migration Number**: 027
- **Created**: 2025-01-24
- **Dependencies**: 003 (posts schema), 007 (videos schema)
- **Status**: ✅ Production-ready
- **Test Status**: ✅ All tests passing
- **Idempotency**: ✅ Verified
- **Backward Compatibility**: ✅ Zero breaking changes
