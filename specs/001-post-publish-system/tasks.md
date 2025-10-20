# Tasks: 图片贴文发布与存储系统

**Feature Branch**: `001-post-publish-system`
**Generated**: 2025-10-18
**Status**: Ready for Implementation

## Implementation Strategy

**MVP Scope**: User Story 1 (Post Upload) + User Story 2 (Image Processing)
- Enables core user-generated content workflow
- Creates foundation for Feed system
- Estimated: 2-3 weeks for MVP

**Phase 2 Extensions**: User Stories 3-6 (Resilience, Optimization, Validation)
- Background upload support
- Validation and limits
- Error handling improvements

## Phase 1: Setup & Infrastructure

- [ ] T001 Set up PostgreSQL migrations directory and create Post table schema in `src/db/migrations/001_create_posts.sql`
- [ ] T002 Create Post model struct with all fields (id, user_id, image_url, caption, status) in `src/models/post.rs`
- [ ] T003 Configure AWS S3 SDK integration in `Cargo.toml` and `src/services/s3.rs`
- [ ] T004 Set up image processing crate (image or imagemagick) in `Cargo.toml`
- [ ] T005 Create Redis connection pool for background jobs in `src/services/redis.rs`
- [ ] T006 Set up error handling types in `src/errors/mod.rs` for S3, image, and validation errors

## Phase 2: Foundational Services (Blocking Prerequisites)

- [ ] T007 Implement S3 pre-signed URL generation in `src/services/s3.rs` (5-minute expiration)
- [ ] T008 [P] Create image validation service in `src/services/image_validator.rs` (format: JPEG/PNG, max 10MB)
- [ ] T008B [P] Create caption validation in `src/services/caption_validator.rs` (max 300 chars, Unicode/Emoji support)
- [ ] T009 Implement AWS S3 client initialization and error handling in `src/services/s3.rs`
- [ ] T010 Create database transaction helper for atomic Post creation in `src/db/transactions.rs`
- [ ] T011 Set up background job schema and Redis queue integration in `src/services/job_queue.rs`

## Phase 3: User Story 1 - 用户发布图片贴文 (P1)

**Goal**: Users can upload image, add caption, and publish post visible in their profile

**Independent Test Criteria**:
- User can request upload URL (pre-signed S3 URL returned)
- User can upload image to S3 using returned URL
- User can create Post record with caption
- Post appears immediately in user's profile with PROCESSING status
- Post status transitions to PUBLISHED after image processing

### Implementation Tasks

- [ ] T012 [US1] Create POST `/api/v1/posts/upload-url` endpoint in `src/handlers/posts.rs`
  - Validates user authentication
  - Generates pre-signed S3 URL with 5-minute expiration
  - Returns upload_url, file_key, expires_at
- [ ] T013 [US1] Implement `RequestUploadUrlRequest` and `UploadUrlResponse` DTOs in `src/models/post.rs`
- [ ] T014 [US1] Create POST `/api/v1/posts` endpoint in `src/handlers/posts.rs`
  - Accepts file_key and optional caption
  - Creates Post record with PROCESSING status
  - Returns created Post with all URLs
- [ ] T015 [US1] Implement Post creation logic in `src/services/post_service.rs`
  - Validates file exists in S3
  - Creates Post record atomically
  - Sets initial status to PROCESSING
- [ ] T016 [US1] Create GET `/api/v1/posts/{id}` endpoint in `src/handlers/posts.rs`
  - Returns full Post details including user info
  - Includes like_count, comment_count (initially 0)
- [ ] T017 [US1] Add JWT middleware to all post endpoints in `src/middleware/auth.rs`
- [ ] T018 [US1] Create integration test for post creation flow in `tests/integration/post_creation_tests.rs`

## Phase 4: User Story 2 - 图片自动转码与缩略图生成 (P1)

**Goal**: System automatically generates thumbnail (300px) and medium (600px) versions after upload

**Independent Test Criteria**:
- Background job downloads image from S3
- Thumbnail (300px) is generated
- Medium version (600px) is generated
- Both uploaded to S3 with correct URLs
- Post status updated to PUBLISHED
- Post status visible in GET request

### Implementation Tasks

- [ ] T019 [US2] Create image processing worker in `src/workers/image_processor.rs`
  - Downloads image from S3 using file_key
  - Generates thumbnail (300px)
  - Generates medium (600px)
- [ ] T020 [US2] Implement thumbnail generation logic in `src/services/image_processor.rs`
  - Uses image crate for resizing
  - Handles JPEG/PNG output
  - Returns processed bytes
- [ ] T021 [US2] Create S3 upload for processed images in `src/services/s3.rs`
  - Uploads thumbnail to S3
  - Uploads medium to S3
  - Returns CDN URLs for both
- [ ] T022 [US2] Implement async job dispatch in `src/services/post_service.rs`
  - On Post creation, dispatch image processing job to Redis
  - Include file_key and post_id in job
- [ ] T023 [US2] Create async job consumer in `src/main.rs`
  - Spawns background task to consume Redis queue
  - Processes image jobs sequentially (or with concurrency limit)
- [ ] T024 [US2] Implement Post status update in `src/services/post_service.rs`
  - Updates post_image_url, post_medium_url, post_thumbnail_url
  - Sets status to PUBLISHED
  - Handles error case → FAILED status
- [ ] T025 [US2] Add CDN URL generation in `src/services/s3.rs`
  - Maps S3 keys to CloudFront URLs
  - Configurable CloudFront domain
- [ ] T026 [US2] Create integration test for image processing in `tests/integration/image_processing_tests.rs`

## Phase 5: User Story 3 - 支持后台上传与断网重试 (P1)

**Goal**: iOS client can background upload, and system retries on network failures

**Independent Test Criteria**:
- Background upload continues after app switch
- Network interruption triggers automatic retry
- Retry count limited to 3 attempts
- Exponential backoff between retries

### Implementation Tasks

- [ ] T027 [US3] Implement retry logic in `src/workers/image_processor.rs`
  - On error: increment retry_count
  - Check if retry_count < 3
  - Re-queue with exponential backoff (1s, 2s, 4s)
- [ ] T028 [US3] Create error tracking in database for failed jobs in `src/db/migrations/002_add_job_tracking.sql`
  - job_id, post_id, retry_count, last_error, next_retry_at
- [ ] T029 [US3] Implement backoff calculation in `src/services/job_queue.rs`
  - Exponential: 2^retry_count seconds
  - Max 4 seconds (3 retries: 1s, 2s, 4s)
- [ ] T030 [US3] Create admin endpoint to view failed jobs in `src/handlers/admin.rs`
  - GET `/api/v1/admin/failed-jobs`
  - Shows jobs with retry_count > 2
- [ ] T031 [US3] Document URLSession background transfer in iOS client guide (out of scope for backend, but API must support resumable uploads)

## Phase 6: User Story 4 - 预签名 URL 直传到 S3 (P2)

**Goal**: Pre-signed URLs enable direct client-to-S3 upload without backend relay

**Independent Test Criteria**:
- Pre-signed URL includes valid S3 signature
- URL expires after 5 minutes
- Client can upload using returned URL
- File appears in S3 bucket
- Expired URL rejected by S3

### Implementation Tasks

- [ ] T032 [US4] Validate S3 pre-signed URL generation in `src/services/s3.rs`
  - Uses AWS SDK to generate proper signature
  - Includes correct S3 bucket and key
  - Expiration set to exactly 300 seconds (5 minutes)
- [ ] T033 [US4] Add S3 CORS configuration documentation in `docs/s3-setup.md`
  - Required CORS headers for direct upload
  - Allowed methods: PUT
- [ ] T034 [US4] Create test to verify pre-signed URL functionality in `tests/integration/s3_upload_tests.rs`

## Phase 7: User Story 5 - 验证图片格式与大小限制 (P2)

**Goal**: Reject non-JPEG/PNG and files > 10MB with clear error messages

**Independent Test Criteria**:
- BMP file rejected with "unsupported format" message
- 15MB file rejected with "file too large" message
- 5MB JPEG accepted
- 10MB PNG accepted
- 10.1MB file rejected

### Implementation Tasks

- [ ] T035 [US5] Implement format validation in `src/services/image_validator.rs`
  - Magic byte checking (not extension)
  - Support JPEG and PNG only
  - Reject others with clear message
- [ ] T036 [US5] Implement size validation in `src/services/image_validator.rs`
  - Check file size from S3 metadata
  - Max 10MB (10485760 bytes)
  - Return clear error if exceeded
- [ ] T037 [US5] Create validation endpoint test in `tests/integration/validation_tests.rs`
  - Test invalid format rejection
  - Test size limit enforcement

## Phase 8: User Story 6 - 描述文字验证与存储 (P2)

**Goal**: Caption limited to 300 chars, support Unicode and Emoji

**Independent Test Criteria**:
- 200-char caption saves correctly
- 350-char caption rejected with error message
- Emoji caption saves and displays correctly
- Chinese characters save correctly

### Implementation Tasks

- [ ] T038 [US6] Implement caption validation in `src/services/caption_validator.rs`
  - Trim whitespace
  - Count characters (not bytes)
  - Max 300 chars
  - Accept Unicode and Emoji
- [ ] T039 [US6] Add caption length check to POST `/api/v1/posts` in `src/handlers/posts.rs`
  - Validate before creating Post
  - Return 400 with "caption too long" message
- [ ] T040 [US6] Create caption validation test in `tests/integration/caption_tests.rs`

## Phase 9: Polish & Cross-Cutting Concerns

- [ ] T041 Implement error response standardization in `src/handlers/mod.rs`
  - All errors return consistent format: { error: string, code: string }
  - Include user-friendly messages
- [ ] T042 Add logging to all post endpoints in `src/handlers/posts.rs`
  - Log upload URL requests, post creation, image processing
  - Include user_id and post_id for tracing
- [ ] T043 Create comprehensive integration test suite in `tests/integration/post_system_tests.rs`
  - Test complete flow: upload URL → upload → create post → process image
  - Test error scenarios
- [ ] T044 Add performance monitoring in `src/services/post_service.rs`
  - Track time to create post record (should be < 100ms)
  - Track image processing time (should be < 2 min)
- [ ] T045 Document API endpoints in `docs/api/posts.md`
  - POST /posts/upload-url
  - POST /posts
  - GET /posts/{id}
  - Include curl examples
- [ ] T046 Create migration rollback procedure in `src/db/migrations/`
  - Ensure 001_create_posts.sql is reversible

## Dependency Graph

```
Phase 1: Setup
  ↓
Phase 2: Foundational Services (blocking all user stories)
  ↓
Phase 3: US1 (Post Publishing)
  └─ Depends on: Phase 2
  ├─ Parallelizable: T012-T017 (endpoint code)
  └─ Test gate: T018 (integration test)
  ↓
Phase 4: US2 (Image Processing)
  └─ Depends on: US1 (post creation)
  ├─ Parallelizable: T019-T023 (worker code)
  └─ Test gate: T026 (integration test)
  ↓
Phase 5: US3 (Retry Logic)
  └─ Depends on: US2 (background jobs exist)
  ├─ Parallelizable: T027-T030
  └─ Test gate: Manual testing recommended
  ↓
Phase 6-8: US4-6 (Optimization, Validation)
  └─ Depends on: US2 (basic flow working)
  └─ Can proceed in parallel: Independent features
```

## Parallel Execution Opportunities

**Within Phase 2 (Foundational)**:
- T008 (image validation) can run parallel with T008B (caption validation)
- T009 (S3 client) can run parallel with T010 (transactions)

**Within Phase 3 (US1)**:
- T012, T013, T014, T015, T016 can start in parallel (DTO and handler implementations)
- T017 (JWT middleware) can run parallel with other endpoint code
- T018 (tests) depends on T012-T017 completion

**Within Phase 4 (US2)**:
- T019 (worker) and T020 (image processing) can start in parallel
- T023 (job consumer) can start after T019 started

**Phases 6-8 (US4-6)**:
- All tasks across US4, US5, US6 can run in parallel (no dependencies between stories)

## MVP Recommendation

**Minimum Viable Product**: Complete Phase 1-4 (Setup + US1 + US2)
- Users can upload images
- Posts appear immediately
- Images are processed in background
- Post shows in profile

**Estimated effort**: 150-200 engineering hours
**Timeline**: 3-4 weeks with 1-2 engineers

**Defer to Phase 2 (v1.1)**:
- Phase 5 (retry logic) - requires iOS client URLSession integration
- Phase 6 (pre-signed URL optimization) - performance improvement, not essential
- Phase 7-8 (validation) - can add incrementally

## Testing Notes

Each user story includes independent test criteria that can be validated without other stories being complete.

**Test Execution Strategy**:
1. Manual testing for each phase (use curl or Postman)
2. Integration tests included in tasks
3. Load testing recommended for Phase 2 (image processing throughput)
4. E2E testing deferred to frontend integration

## Success Criteria Validation

After all tasks complete:
- ✅ SC-001: Users complete workflow in < 30s (measured manually)
- ✅ SC-002: Thumbnails load in < 1s (measured via CDN)
- ✅ SC-003: Upload success rate 99% (tracked via job success metrics)
- ✅ SC-004: Posts appear immediately (status = PROCESSING visible)
- ✅ SC-005: Images in Feed within 5s of publication (verified via timestamp tracking)
