# Phase 2: Content Publishing - Kickoff Plan

**Duration**: 12 hours
**Status**: Ready to start
**Estimated Completion**: ~3 days (at 4h/day development pace)

---

## 🎯 Phase Objective

Enable users to upload images to AWS S3 with automatic transcoding to multiple sizes (thumbnail, medium, original). Posts are created with captions and multiple image URLs for different display contexts.

---

## 🏗️ Technical Architecture

### New Components

```
Frontend (iOS)
    ↓ (1. POST /posts/upload)
Backend API
    ├─ Presigned URL generation
    ├─ S3 client
    └─ PostgreSQL

S3
    ├─ Upload bucket
    └─ Transcoding trigger

Lambda (or local service)
    ├─ Image resizing (3 sizes)
    ├─ Format conversion
    └─ Metadata generation

Redis
    ├─ Processing status cache
    └─ Upload token validation
```

### Data Flow

```
1. iOS requests presigned URL
   POST /api/v1/posts/upload
   Response: {upload_url, post_id, upload_token}

2. iOS uploads file directly to S3
   PUT {presigned_url}

3. S3 triggers Lambda function
   Lambda creates thumbnails + medium + original

4. Backend completes upload
   POST /api/v1/posts/complete-upload
   Request: {post_id, upload_token, file_hash}
   Response: {post_id, image_urls, caption_url}

5. Frontend can retrieve post
   GET /api/v1/posts/{id}
```

---

## 📋 Implementation Checklist

### Week 1: Database & AWS Setup (3 hours)

- [ ] **1.1 Database Migrations** (0.5h)
  - Create `posts` table with schema
  - Create `post_images` table for processing status
  - Add indexes on (user_id), (created_at)
  - Test migrations run without errors

- [ ] **1.2 AWS S3 Configuration** (1h)
  - Create S3 bucket for image storage
  - Configure bucket lifecycle policies (cleanup incomplete uploads after 7 days)
  - Set up IAM policy for backend service
  - Configure CORS for direct browser uploads
  - Test: Backend can write/read objects

- [ ] **1.3 Environment Variables** (0.5h)
  - Add to `.env`: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  - Add to `.env`: S3_BUCKET_NAME, S3_REGION, CLOUDFRONT_URL
  - Add to `config/default.toml`: image upload limits
  - Document required env vars in README

- [ ] **1.4 Dependencies** (1h)
  - Add `aws-sdk-s3` to Cargo.toml
  - Add `tokio` (already have)
  - Add `sha2` for file integrity
  - Add `mime` for MIME type detection
  - Run `cargo build` - verify no errors

### Week 1: Core Upload Endpoints (3.5 hours)

- [ ] **2.1 Presigned URL Endpoint** (1.5h)
  - Implement `POST /api/v1/posts/upload`
  - Validation: authenticated user, file_name, file_size, content_type
  - Generate presigned URL (15-minute expiry)
  - Create post with status = "pending"
  - Generate upload token (store in Redis, 1-hour expiry)
  - Response: presigned_url, post_id, upload_token
  - Error handling: file too large, invalid content type

- [ ] **2.2 Complete Upload Endpoint** (1.5h)
  - Implement `POST /api/v1/posts/complete-upload`
  - Validation: post_id, upload_token, file_hash
  - Verify token not expired
  - Verify file exists in S3
  - Verify file integrity (hash check)
  - Trigger transcoding job
  - Update post status to "processing"
  - Response: post metadata + image URLs
  - Error handling: hash mismatch, file not found, token invalid

- [ ] **2.3 Get Post Endpoint** (0.5h)
  - Implement `GET /api/v1/posts/:id`
  - Validation: post exists, user has access
  - Response: post object with all 3 image URLs
  - Return 404 if post soft-deleted

### Week 2: Image Processing (2.5 hours)

- [ ] **3.1 Image Transcoding Setup** (1.5h)
  - Option A: AWS Lambda (recommended)
    - Set up Lambda function triggered by S3:ObjectCreated event
    - Function: resize to 3 sizes, upload processed images
    - Test: upload image, verify thumbnails created

  - Option B: Local processing (simpler for dev)
    - Use `image` crate for local resizing
    - Process on background thread/job queue
    - Store resized versions to S3

- [ ] **3.2 Image Size Specifications** (0.5h)
  - Thumbnail: 150x150px, JPEG, 30kb max
  - Medium: 600x600px, JPEG, 100kb max
  - Original: max 4000x4000, JPEG, 2mb max
  - Implement aspect ratio preservation
  - Test: upload various aspect ratios

- [ ] **3.3 Update Processing Status** (0.5h)
  - Create service function to mark processing complete
  - Store final image URLs in database
  - Update post status to "published"
  - Invalidate Redis cache

### Week 2: Database Operations & CRUD (2 hours)

- [ ] **4.1 Post Repository** (1.5h)
  - `create_post()` - Create with status="pending"
  - `find_post_by_id()` - Get single post
  - `find_posts_by_user()` - Paginated posts by user
  - `update_post_status()` - Update processing status
  - `soft_delete_post()` - Mark as deleted
  - `get_post_image_urls()` - Get all 3 URLs

- [ ] **4.2 Post Image Tracking** (0.5h)
  - Track each image variant (thumbnail, medium, original)
  - Store S3 object keys
  - Store file sizes
  - Enable re-processing if failed

### Week 2: Testing (2.5 hours)

- [ ] **5.1 Unit Tests - Input Validation** (0.5h)
  - File size limits (too small, too large)
  - Content type validation (JPEG, PNG, etc)
  - Filename validation (no path traversal)
  - User authentication check
  - 4 unit tests

- [ ] **5.2 Unit Tests - S3 Operations** (1h)
  - Presigned URL generation
  - Upload token creation/expiry
  - File hash verification
  - S3 mock: object created, found, deleted
  - 6 unit tests

- [ ] **5.3 Unit Tests - Post CRUD** (0.5h)
  - Create post validation
  - Status transitions (pending → processing → published)
  - Soft delete verification
  - Image URL retrieval
  - 5 unit tests

- [ ] **5.4 Unit Tests - Error Cases** (0.5h)
  - Invalid upload token
  - Hash mismatch
  - File not found in S3
  - Concurrent upload handling
  - Database transaction rollback
  - 4 unit tests

- [ ] **5.5 Integration Tests** (0-1h optional)
  - End-to-end upload flow (create → upload → complete)
  - Multiple concurrent uploads
  - Error recovery

### Documentation (0.5 hour)

- [ ] **6.1 API Documentation**
  - Document all 3 endpoints with request/response examples
  - Include error responses
  - Add curl examples

- [ ] **6.2 Architecture Documentation**
  - Document S3 structure
  - Document image processing pipeline
  - Document Redis cache keys

---

## 🗂️ File Structure After Phase 2

```
backend/user-service/src/
├── handlers/
│   ├── auth.rs (existing)
│   ├── posts.rs (NEW - 3 endpoints)
│   └── health.rs (existing)
├── db/
│   ├── user_repo.rs (existing)
│   └── post_repo.rs (NEW - 6 CRUD functions)
├── services/
│   ├── email_verification.rs (existing)
│   ├── token_revocation.rs (existing)
│   ├── image_processing.rs (NEW)
│   └── s3_service.rs (NEW)
├── models/
│   ├── mod.rs (add Post, PostImage models)
└── main.rs (add /posts routes)

migrations/
└── 002_posts_schema.sql (NEW)
```

---

## 🧪 Unit Test Count

**Target**: 25 unit tests
- Input validation: 4 tests
- S3 operations: 6 tests
- Post CRUD: 5 tests
- Error handling: 4 tests
- Image processing: 3 tests
- Integration flows: 3 tests

---

## ⚠️ Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| S3 bucket misconfiguration | Use IAM policy simulator before deploy |
| File upload timeout | Set reasonable limits (50MB), add retry logic |
| Concurrent upload collisions | Use unique post IDs (UUIDs) |
| Image transcoding failures | Implement retry queue + manual reprocessing |
| Database schema mismatch | Run migrations in dev/test first |

---

## 🎯 Success Criteria

- ✅ All 3 endpoints implemented and tested
- ✅ 25 unit tests passing (100% pass rate)
- ✅ Zero compilation errors
- ✅ Zero warnings
- ✅ Code formatted with rustfmt
- ✅ Images successfully uploaded to S3
- ✅ 3 image sizes generated and retrievable
- ✅ API documentation complete

---

## 📝 Next: Phase 3 Preview

Once Phase 2 completes:
1. **Social Graph** - Implement follow relationships
2. **Feed Algorithm** - Query posts from followed users
3. **Pagination** - Return paginated feed results
4. **Redis Caching** - Cache feed for performance

---

**Start Date**: Today
**Target Completion**: 3 days
**Success Checkpoint**: First image uploaded and retrieved via API

