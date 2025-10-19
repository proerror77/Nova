# Implementation Plan: 图片贴文发布与存储系统

**Feature Branch**: `001-post-publish-system`
**Status**: PLANNING
**Prepared**: 2025-10-18

## Phase 0: Technical Context & Research

### Technology Stack

- **Backend**: Rust + Actix-web (async web framework)
- **Database**: PostgreSQL with async driver (sqlx)
- **Storage**: AWS S3 + CloudFront CDN
- **Image Processing**: ImageMagick or Rust image crate (tokio background task)
- **Authentication**: JWT from 001-user-auth
- **IPC/Events**: Redis for job queue (image processing tasks)

### Key Architecture Decisions

1. **Pre-signed URL Pattern**: Client requests upload URL → backend generates AWS pre-signed URL (5 min validity) → client uploads directly to S3 → client notifies backend of completion → backend creates Post record
2. **Async Image Processing**: Post created in PROCESSING state → async worker processes image → state transitions to PUBLISHED after thumbnail generation
3. **Denormalized Image URLs**: Store original_url, medium_url, thumbnail_url in Post table for quick retrieval
4. **CDN Integration**: All image URLs point to CloudFront (not S3 directly) for caching and performance

### Critical Dependencies

- **User Authentication** (001-user-auth): User must be authenticated to call upload endpoints
- **Database Schema**: Post table with fields: id, user_id, image_url, medium_url, thumbnail_url, caption, status, created_at, updated_at
- **AWS S3 Configuration**: Bucket configured, CORS enabled for client uploads, CloudFront distribution configured
- **Background Job System**: Redis + async worker for image processing

### Integration Points

- **Downstream**: Feed Query System (002), Like/Comment System (003) - they query Post table
- **Upstream**: User authentication, database setup
- **External**: AWS S3 API, CloudFront

## Phase 1: Data Model & API Design

### Data Model

**Post Entity**:
```
id (UUID, Primary Key)
user_id (UUID, Foreign Key → User)
image_url (String, CDN URL to original image)
medium_url (String, CDN URL to 600px version)
thumbnail_url (String, CDN URL to 300px version)
caption (String, max 300 chars, nullable)
status (Enum: PROCESSING, PUBLISHED, FAILED)
created_at (DateTime)
updated_at (DateTime)
error_reason (String, nullable, for FAILED status)

Indexes:
- (user_id, created_at) - for Feed queries
- created_at - for timeline queries
- status - for background job filtering
```

**Image Processing Job** (Redis queue):
```
job_id (UUID)
post_id (UUID)
file_key (String, S3 key path)
status (PENDING, PROCESSING, COMPLETED, FAILED)
retry_count (Int)
created_at (DateTime)
```

### API Contracts

**1. Request Upload URL**
```
POST /api/v1/posts/upload-url
Header: Authorization: Bearer {token}
Request: {
  content_type?: "image/jpeg" | "image/png" (optional, for validation)
}
Response (200): {
  upload_url: "https://bucket.s3.aws.com/...",
  file_key: "posts/2025/10/18/{user_id}/{uuid}",
  expires_at: ISO8601
}
Errors:
  - 401: Unauthorized
  - 429: Rate limit exceeded
```

**2. Create Post**
```
POST /api/v1/posts
Header: Authorization: Bearer {token}
Request: {
  file_key: "posts/2025/10/18/{user_id}/{uuid}",
  caption?: "string, max 300 chars"
}
Response (201): {
  id: UUID,
  user_id: UUID,
  image_url: "https://cdn.example.com/...",
  medium_url: "https://cdn.example.com/...",
  thumbnail_url: "https://cdn.example.com/...",
  caption: "string",
  status: "PROCESSING",
  created_at: ISO8601
}
Errors:
  - 400: Invalid file_key or caption too long
  - 401: Unauthorized
  - 404: File not found in S3
```

**3. Get Post Details**
```
GET /api/v1/posts/{post_id}
Header: Authorization: Bearer {token}
Response (200): {
  id: UUID,
  user_id: UUID,
  image_url: "https://cdn.example.com/...",
  medium_url: "https://cdn.example.com/...",
  thumbnail_url: "https://cdn.example.com/...",
  caption: "string",
  status: "PUBLISHED",
  like_count: 0,
  comment_count: 0,
  created_at: ISO8601,
  user: {
    id: UUID,
    username: "string",
    avatar_url: "string"
  }
}
Errors:
  - 404: Post not found
  - 401: Unauthorized
```

## Phase 2: Implementation Strategy

### Stage 1: Foundation (Week 1)

1. **Database Setup**
   - Create Post table with indexes
   - Create migration files
   - Set up sqlx for query validation at compile time

2. **S3 Integration**
   - Integrate AWS SDK (rusoto or aws-sdk-rust)
   - Implement pre-signed URL generation
   - Configure bucket policies and CORS
   - Test direct upload from local client

3. **API Endpoints (stubs)**
   - Implement `POST /api/v1/posts/upload-url` (return pre-signed URL)
   - Implement `POST /api/v1/posts` (create Post record)
   - Implement `GET /api/v1/posts/{id}` (fetch Post)
   - Add JWT middleware for authentication

### Stage 2: Image Processing (Week 2)

1. **Background Job System**
   - Set up Redis connection pool
   - Create image processing job schema
   - Implement async worker (using tokio::spawn)

2. **Image Processing Logic**
   - Implement download image from S3
   - Generate thumbnail (300px)
   - Generate medium version (600px)
   - Upload processed images back to S3
   - Update Post record with CDN URLs

3. **Error Handling**
   - Retry logic with exponential backoff (max 3 attempts)
   - Mark Post as FAILED if processing fails
   - Cleanup orphaned S3 objects on failure

### Stage 3: Client Integration & Testing (Week 3)

1. **Validation & Constraints**
   - Implement image format validation (JPEG/PNG only)
   - Implement file size validation (max 10MB)
   - Implement caption length validation (max 300 chars)

2. **iOS Client Support**
   - URLSession background transfer for large uploads
   - Handle background transfer completion
   - Retry on network failure

3. **Testing & Performance**
   - Unit tests for S3 integration
   - Integration tests for complete upload flow
   - Performance testing (concurrent uploads)
   - CDN cache validation

## Constitution Check

### Code Quality Gates

- [ ] No implementation details in specification (business requirements only) ✅
- [ ] All functional requirements have clear acceptance criteria ✅
- [ ] Success criteria are measurable and technology-agnostic ✅
- [ ] Dependencies clearly identified ✅
- [ ] Edge cases addressed ✅

### Architecture Review

- [ ] Stateless API design (each request contains full context) ✅
- [ ] Database transactions for data consistency ✅
- [ ] Async processing doesn't block user operations ✅
- [ ] Error handling includes user-friendly messages ✅

### Security Review

- [ ] Pre-signed URLs have expiration ✅
- [ ] JWT authentication required for all endpoints ✅
- [ ] File validation prevents malicious uploads ✅
- [ ] SQL injection prevention (parameterized queries) ✅

## Artifact Output

**Generated Files**:
- `/specs/001-post-publish-system/plan.md` (this file)
- `/src/models/post.rs` - Post struct and database operations
- `/src/handlers/posts.rs` - API endpoint handlers
- `/src/services/s3.rs` - S3 integration
- `/src/services/image_processor.rs` - Image processing worker
- `/src/db/migrations/001_create_posts.sql` - Database migration

**Next Phase**: Implementation execution via `/speckit.tasks`
