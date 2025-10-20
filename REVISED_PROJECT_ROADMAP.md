# Nova Project - Revised Phase Roadmap 🎯

**Date**: October 17, 2024
**Status**: Replanning based on comprehensive Instagram PRD
**Original Estimate**: 89.5 hours
**Completed**: 34.5 hours (38.6%) - Phase 0 + Phase 1
**Revised Total Estimate**: 156 hours (comprehensive Instagram app)

---

## 📊 Executive Summary

### Phase Completion Status

| Phase | Name | Status | Duration | Tests | Endpoints |
|-------|------|--------|----------|-------|-----------|
| **0** | Infrastructure & Docker | ✅ COMPLETE | 13.5h | - | - |
| **1** | User Authentication | ✅ COMPLETE | 21h | 51 | 6 auth + 3 health |
| **2** | Content Publishing | 📋 PLANNED | 12h | 25 | 4 endpoints |
| **3** | Social Graph & Feed | 📋 PLANNED | 14h | 30 | 5 endpoints |
| **4** | Post Interactions | 📋 PLANNED | 10h | 20 | 4 endpoints |
| **5** | User Profiles & Discovery | 📋 PLANNED | 11h | 22 | 5 endpoints |
| **6** | Notifications | 📋 PLANNED | 8h | 15 | 3 endpoints |
| **7** | Advanced Auth & Apple Sign-in | 📋 PLANNED | 9h | 18 | 3 endpoints |
| **8** | Compliance & GDPR | 📋 PLANNED | 6h | 12 | 2 endpoints |
| **9** | Integration & E2E Testing | 📋 PLANNED | 15h | 50 | - |
| **10** | Performance & Optimization | 📋 PLANNED | 12h | - | - |
| **11** | iOS Frontend Integration | 📋 PLANNED | 20h | - | - |
| **12** | Production Hardening | 📋 PLANNED | 5h | - | - |

**Total**: ~156 hours (comprehensive production-ready Instagram app)

---

## 🏗️ Architecture Foundation (Phases 0-1) ✅

### Completed Infrastructure

**Database Layer**
- PostgreSQL 14 with 30+ indexes
- Migration system (sqlx migrations)
- Connection pooling (sqlx PgPool)
- Schema design with 6 tables (users, sessions, profiles, etc.)

**Cache & Storage**
- Redis 7 for session management
- Token storage (verification tokens, refresh tokens, blacklist)
- Rate limiting counters
- Ready for: image metadata cache, feed pagination

**Authentication Foundation**
- User registration with validation
- Email verification workflow
- JWT (RS256) token generation (access + refresh)
- Account lockout & failed login tracking
- Rate limiting middleware
- Token revocation system

**API Framework**
- Actix-web 4 REST API
- Comprehensive error handling
- CORS configuration
- Request logging & tracing
- Health check endpoints (ready, live, liveness)

**CI/CD Pipeline**
- GitHub Actions workflow
- Docker multi-stage builds
- Automated testing on push
- PostgreSQL & Redis test containers

**Dependencies Already Available**
- ✅ `sqlx` - Database queries (parameterized, SQL injection safe)
- ✅ `uuid` - User IDs and entity identifiers
- ✅ `chrono` - Timestamps and date operations
- ✅ `jsonwebtoken` - JWT generation and validation
- ✅ `argon2` - Password hashing
- ✅ `redis` - Caching and session management
- ✅ `tokio` - Async runtime
- ✅ `actix-web` - HTTP framework

---

## 📋 Phase 2: Content Publishing (12 hours)

### Overview
Enable users to upload, process, and store images to S3 with automatic transcoding to multiple sizes (thumbnail, medium, original).

### PRD Alignment
- Fulfills: "Image post publishing (S3, transcoding, thumbnails)"
- Dependent on: Phase 1 (user authentication)
- Required for: Phase 3 (feed), Phase 4 (interactions)

### Technical Requirements

**AWS S3 Integration**
- S3 bucket setup for image storage
- IAM policies for backend access
- Multipart upload for large files
- Object lifecycle policies (cleanup old uploads)

**Image Processing Pipeline**
- Image upload to temporary S3 location
- Trigger Lambda function for transcoding
- Generate 3 sizes:
  - `thumbnail_*.jpg` (150x150, optimized)
  - `medium_*.jpg` (600x600, web optimized)
  - `original_*.jpg` (max 4000x4000)
- S3 object metadata with size info

**Database Schema Expansion**
```sql
posts table:
  - id (UUID, primary key)
  - user_id (FK to users)
  - caption (text, optional)
  - image_key (S3 object key)
  - image_sizes (JSON: {thumbnail_url, medium_url, original_url})
  - created_at, updated_at, soft_delete

post_images table (for processing status):
  - id (UUID)
  - post_id (FK)
  - s3_key (object key)
  - status (pending, processing, completed, failed)
  - size_variant (original, medium, thumbnail)
```

### Endpoints (4 total)

**POST /api/v1/posts/upload**
- Presigned URL generation for direct S3 upload
- Returns: presigned_url, post_id, upload_token
- Validation: file type, file size (max 50MB)
- Response: 200 OK with upload credentials

**POST /api/v1/posts/complete-upload**
- Finalize upload after S3 confirms completion
- Verify uploaded file integrity
- Trigger transcoding job
- Response: 201 Created with post metadata

**GET /api/v1/posts/:id**
- Retrieve single post with all image URLs
- Response: Post object with image_sizes
- Rate limited: yes

**DELETE /api/v1/posts/:id**
- Soft delete post
- Remove S3 objects
- Response: 204 No Content

### Dependencies Required
- `aws-sdk-s3` - AWS S3 SDK
- `image-rs` or `imagemagick` - Image processing
- `sha2` - File integrity verification
- `mime` - MIME type detection

### Database Operations (6 new CRUD functions)
```rust
pub async fn create_post() -> Result<Post>
pub async fn find_post_by_id() -> Result<Option<Post>>
pub async fn find_posts_by_user() -> Result<Vec<Post>>
pub async fn update_post_status() -> Result<()>
pub async fn soft_delete_post() -> Result<()>
pub async fn get_post_image_urls() -> Result<ImageUrls>
```

### Testing Strategy (25 unit tests)
- Input validation (file size, type, format)
- S3 upload simulation
- Transcoding status tracking
- Error handling (S3 failures, timeout)
- Presigned URL generation
- POST CRUD operations
- Soft delete verification

### Time Breakdown
- S3 integration & presigned URLs: 2h
- Upload endpoint & validation: 2h
- Image processing pipeline setup: 3h
- Database schema & CRUD ops: 2h
- Error handling & edge cases: 2h
- Unit tests (25 tests): 1h

---

## 📋 Phase 3: Social Graph & Feed (14 hours)

### Overview
Implement user following relationships, feed algorithm, and pagination for displaying posts from followed users.

### PRD Alignment
- Fulfills: "Feed display (followed users' posts)"
- Dependent on: Phase 1 (auth), Phase 2 (posts)
- Required for: Phase 4 (interactions)

### Technical Requirements

**Database Schema Expansion**
```sql
follows table:
  - id (UUID)
  - follower_id (FK to users)
  - following_id (FK to users)
  - created_at
  - UNIQUE(follower_id, following_id)
  - Indexes: (follower_id), (following_id)

feed_cache table (materialized view optimization):
  - id (UUID)
  - user_id (FK)
  - post_id (FK)
  - post_timestamp (for pagination)
  - cached_at

post_metadata table (analytics):
  - post_id (FK)
  - view_count (integer)
  - like_count (integer)
  - comment_count (integer)
  - created_at, updated_at
```

**Redis Caching Strategy**
- `feed:{user_id}:{page}` - Paginated feed cache (TTL: 5 mins)
- `following:{user_id}` - User's following list (TTL: 1 hour)
- `followers:{user_id}` - User's followers list (TTL: 1 hour)
- `post_metadata:{post_id}` - Post stats cache (TTL: 30 mins)

**Feed Algorithm**
```
FOR user_id:
  1. Get following list from Redis (or DB if cache miss)
  2. Query posts from last 24 hours for all following users
  3. Order by: (timestamp DESC, engagement_score)
  4. Paginate: 20 posts per page
  5. Cache result in Redis
  6. Return with pagination metadata
```

### Endpoints (5 total)

**POST /api/v1/users/:id/follow**
- Follow another user
- Validation: can't follow self, already following check
- Response: 201 Created
- Invalidate: Redis following lists + feed cache

**POST /api/v1/users/:id/unfollow**
- Unfollow user
- Response: 204 No Content
- Invalidate: Redis caches

**GET /api/v1/feed**
- Get personalized feed for authenticated user
- Query params: page (default 1), limit (default 20, max 50)
- Response: 200 OK with posts array + pagination metadata
- Caching: Redis with 5-minute TTL

**GET /api/v1/users/:id/following**
- Get list of users this person follows
- Pagination: page, limit
- Response: 200 OK with user array

**GET /api/v1/users/:id/followers**
- Get list of followers
- Pagination: page, limit
- Response: 200 OK with user array

### Dependencies
- `redis` - For feed caching and list management (already included)
- No new external dependencies

### Database Operations (8 new CRUD functions)
```rust
pub async fn follow_user() -> Result<()>
pub async fn unfollow_user() -> Result<()>
pub async fn is_following() -> Result<bool>
pub async fn get_follower_count() -> Result<i64>
pub async fn get_following_count() -> Result<i64>
pub async fn get_user_feed() -> Result<Vec<Post>>
pub async fn get_following_list() -> Result<Vec<User>>
pub async fn get_followers_list() -> Result<Vec<User>>
```

### Testing Strategy (30 unit tests)
- Following/unfollowing logic
- Self-follow prevention
- Duplicate follow prevention
- Feed pagination
- Feed ordering (most recent first)
- Cache invalidation
- Redis cache hits/misses
- Following/followers counts
- Edge cases (removed users, soft-deleted posts)

### Time Breakdown
- Schema design & migrations: 2h
- Follow/unfollow endpoints: 2h
- Feed algorithm implementation: 3h
- Pagination system: 2h
- Redis caching strategy: 2h
- CRUD database operations: 1.5h
- Unit tests (30 tests): 1.5h

---

## 📋 Phase 4: Post Interactions (10 hours)

### Overview
Implement likes and comments on posts with real-time counters.

### PRD Alignment
- Fulfills: "Post interactions (likes, comments)"
- Dependent on: Phase 1 (auth), Phase 2 (posts), Phase 3 (feed)
- Required for: Phase 5 (profiles), Phase 6 (notifications)

### Technical Requirements

**Database Schema Expansion**
```sql
likes table:
  - id (UUID)
  - post_id (FK)
  - user_id (FK)
  - created_at
  - UNIQUE(post_id, user_id)
  - Indexes: (post_id), (user_id)

comments table:
  - id (UUID)
  - post_id (FK)
  - user_id (FK)
  - content (text, 1-500 chars)
  - created_at, updated_at, soft_delete
  - Indexes: (post_id), (user_id)

comment_likes table:
  - id (UUID)
  - comment_id (FK)
  - user_id (FK)
  - created_at
  - UNIQUE(comment_id, user_id)
```

**Redis Counters**
- `likes:{post_id}` - Atomic like counter (TTL: none, persist)
- `comments:{post_id}` - Comment count (TTL: none, persist)
- `user_likes:{user_id}` - User's liked posts (set, for feed filtering)

### Endpoints (4 total)

**POST /api/v1/posts/:id/like**
- Like a post
- Idempotent: like again = no change
- Response: 200 OK with like count
- Update: post_metadata.like_count

**DELETE /api/v1/posts/:id/like**
- Unlike a post
- Response: 204 No Content
- Update counters

**POST /api/v1/posts/:id/comments**
- Add comment to post
- Validation: content 1-500 chars, not empty
- Response: 201 Created with comment object

**GET /api/v1/posts/:id/comments**
- Get comments for post
- Pagination: page, limit (default 20)
- Ordering: newest first
- Response: 200 OK with comments array

### Database Operations (6 new CRUD functions)
```rust
pub async fn create_like() -> Result<()>
pub async fn remove_like() -> Result<()>
pub async fn has_user_liked() -> Result<bool>
pub async fn create_comment() -> Result<Comment>
pub async fn find_post_comments() -> Result<Vec<Comment>>
pub async fn soft_delete_comment() -> Result<()>
```

### Testing Strategy (20 unit tests)
- Like/unlike toggling
- Duplicate like prevention
- Like count accuracy
- Comment creation validation
- Comment content sanitization
- Comment pagination
- Delete verification
- Counter accuracy
- Edge cases

### Time Breakdown
- Database schema & migrations: 1.5h
- Like system (endpoints + CRUD): 2.5h
- Comment system (endpoints + CRUD): 2.5h
- Counter management (Redis + DB): 1.5h
- Unit tests (20 tests): 1.5h
- Error handling & edge cases: 0.5h

---

## 📋 Phase 5: User Profiles & Discovery (11 hours)

### Overview
User profile pages, profile editing, search functionality for users.

### PRD Alignment
- Fulfills: "User profiles (edit, view)" + "User search"
- Dependent on: Phase 1 (auth), Phase 3 (follow count data)
- Integrates with: Phase 4 (interaction counts)

### Technical Requirements

**Database Schema Expansion**
```sql
user_profiles table:
  - user_id (FK to users, PK)
  - bio (text, max 500 chars)
  - profile_image_url (S3 URL, optional)
  - website_url (URL, optional)
  - location (text, optional)
  - birth_date (date, optional)
  - is_private (boolean, default false)
  - verified (boolean, for later V2)
  - created_at, updated_at

user_search_index table:
  - user_id (FK)
  - search_vector (for FTS)
  - username_lowercase
  - display_name_lowercase
  - updated_at
```

**Search Implementation**
- PostgreSQL Full Text Search (FTS)
- Query: `SELECT * FROM users WHERE to_tsvector(username || ' ' || display_name) @@ plainto_tsquery(...)`
- Pagination: offset/limit

### Endpoints (5 total)

**GET /api/v1/users/:id**
- Get public profile
- Response: user object with profile data + stats
  - follower_count, following_count, post_count
  - has_user_followed (boolean, for logged-in users)

**PUT /api/v1/users/:id**
- Update own profile
- Validation: bio length, URL format
- Response: 200 OK with updated profile
- Requires: authentication + user_id match

**POST /api/v1/users/:id/avatar**
- Upload profile avatar
- Similar to post image upload (S3 presigned URL)
- Response: 200 OK with avatar URL

**GET /api/v1/search/users**
- Search users by username/display name
- Query param: q (required, min 2 chars)
- Pagination: page, limit (default 20)
- Response: 200 OK with user array

**GET /api/v1/users/:id/posts**
- Get all posts by user
- Pagination: page, limit
- Respect: private profile rules (Phase 8)
- Response: 200 OK with posts array

### Database Operations (7 new CRUD functions)
```rust
pub async fn create_profile() -> Result<Profile>
pub async fn find_profile_by_user() -> Result<Option<Profile>>
pub async fn update_profile() -> Result<Profile>
pub async fn search_users() -> Result<Vec<User>>
pub async fn get_user_posts() -> Result<Vec<Post>>
pub async fn get_user_stats() -> Result<UserStats>
pub async fn update_avatar_url() -> Result<()>
```

### Testing Strategy (22 unit tests)
- Profile CRUD operations
- Username search functionality
- Display name search
- Search result ordering (relevance)
- Pagination in search results
- Profile visibility rules
- Avatar upload validation
- Bio length validation
- URL format validation

### Time Breakdown
- Database schema: 1h
- Profile endpoints (get/update): 2h
- Avatar upload (S3 integration): 2h
- User search implementation: 2h
- Search index optimization: 1.5h
- CRUD operations: 1h
- Unit tests (22 tests): 1.5h

---

## 📋 Phase 6: Notifications (8 hours)

### Overview
Notification system supporting both push notifications (iOS) and in-app notifications.

### PRD Alignment
- Fulfills: "Notifications (push & in-app)"
- Dependent on: All previous phases
- Integrates with: Phase 4 (interactions)

### Technical Requirements

**Database Schema**
```sql
notifications table:
  - id (UUID)
  - user_id (FK)
  - type (like, comment, follow, etc.)
  - actor_id (FK to user who triggered)
  - resource_id (post_id or comment_id)
  - is_read (boolean)
  - created_at

notification_preferences table:
  - user_id (FK, PK)
  - likes_enabled (boolean, default true)
  - comments_enabled (boolean)
  - follows_enabled (boolean)
  - updated_at
```

**Push Notification Service**
- Apple Push Notification service (APNs) integration
- Device token storage and management
- Batch notification sending
- Delivery tracking

### Endpoints (3 total)

**GET /api/v1/notifications**
- Get user's notifications
- Query params: unread_only (boolean), limit, page
- Response: 200 OK with notifications array

**PUT /api/v1/notifications/:id/read**
- Mark notification as read
- Response: 200 OK

**GET /api/v1/notifications/preferences**
- Get notification settings
- Response: 200 OK with preferences

**PUT /api/v1/notifications/preferences**
- Update notification settings
- Response: 200 OK

### Internal Services
- `NotificationService::create()` - Create and dispatch notifications
- `NotificationService::send_push()` - Send to APNs
- Background job to deliver pending notifications

### Dependencies
- `apple-push` or equivalent - APNs SDK
- Job queue system: Redis or built-in channel

### Testing Strategy (15 unit tests)
- Notification creation on events
- Push notification sending
- Notification read status
- Preference updates
- Batch operations
- Error handling

### Time Breakdown
- Database schema: 1h
- Notification endpoints: 2h
- APNs integration: 2.5h
- Background job setup: 1.5h
- Unit tests (15 tests): 1h

---

## 📋 Phase 7: Advanced Authentication (9 hours)

### Overview
Password reset flow, Apple Sign-in integration, and additional security features.

### PRD Alignment
- Fulfills: "Email & Apple Sign In" for login
- Dependent on: Phase 1 (base auth)
- Enhances: Phase 1 infrastructure

### Technical Requirements

**Password Reset Flow**
```
1. POST /auth/forgot-password {email}
   → Generate reset token (15-min expiry)
   → Send email with link
   → Response: 200 OK

2. GET /auth/reset-password/{token}
   → Verify token valid
   → Frontend shows form

3. POST /auth/reset-password {token, new_password}
   → Validate token
   → Update password
   → Invalidate all existing tokens
   → Response: 200 OK
```

**Apple Sign-in**
```
1. iOS app uses sign_in_with_apple
2. Frontend sends apple identity token to backend
3. Backend verifies token with Apple's servers
4. Create user or link existing user
5. Generate JWT tokens
```

### Endpoints (3 total)

**POST /api/v1/auth/forgot-password**
- Request: {email}
- Response: 200 OK (generic message for security)

**POST /api/v1/auth/reset-password**
- Request: {token, password}
- Response: 200 OK

**POST /api/v1/auth/apple-signin**
- Request: {apple_identity_token, nonce}
- Response: 200 OK with JWT tokens

### Dependencies
- `jsonwebtoken` (already have)
- Apple identity validation library

### Database Changes
```sql
ALTER users ADD apple_id (string, nullable, unique)
ALTER users ADD password_reset_attempts (for rate limiting)

CREATE password_reset_tokens table:
  - token (hex string)
  - user_id (FK)
  - created_at
  - expires_at
  - used (boolean)
```

### Testing Strategy (18 unit tests)
- Forgot password flow
- Reset token validation
- Password update security
- Apple token verification
- Account linking
- Token invalidation

### Time Breakdown
- Password reset endpoints: 2.5h
- Apple Sign-in integration: 3h
- Token management: 1.5h
- Security hardening: 1h
- Unit tests (18 tests): 1h

---

## 📋 Phase 8: Compliance & GDPR (6 hours)

### Overview
Account deletion, privacy policy, and GDPR compliance features.

### PRD Alignment
- Fulfills: "Compliance (account deletion, privacy policy)"
- Dependent on: All previous phases
- Affects: All data operations

### Technical Requirements

**Account Deletion Process**
```
1. User requests deletion
2. Send confirmation email (24-hour window)
3. Verify email link
4. Cascade soft-delete:
   - User → soft_delete timestamp
   - Posts → soft_delete
   - Comments → soft_delete
   - Likes → logical delete
   - Follows → cascade delete
   - Profile → anonymize
5. Retain: minimal data for legal compliance (90 days)
```

**Data Export (GDPR)**
```
1. User requests data export
2. Collect:
   - User profile
   - All posts & metadata
   - All comments
   - Following/followers lists
   - Activity history
3. Package as JSON + CSV files
4. Email download link (7-day expiry)
```

### Endpoints (2 total)

**POST /api/v1/account/delete**
- Request: {password} (confirmation)
- Response: 200 OK (send confirmation email)

**POST /api/v1/account/export**
- Request: {} (authenticated)
- Response: 200 OK (initiate export job)

### Internal Services
- `GDPRService::delete_account()` - Cascade deletion
- `GDPRService::export_user_data()` - Data export job

### Testing Strategy (12 unit tests)
- Cascade deletion verification
- Data retention checks
- Email confirmation flow
- Export data format
- Privacy rule enforcement

### Time Breakdown
- Account deletion flow: 2h
- Data export system: 1.5h
- GDPR audit & compliance: 1.5h
- Unit tests (12 tests): 1h

---

## 📋 Phase 9: Integration & E2E Testing (15 hours)

### Overview
Comprehensive integration tests and end-to-end testing across all features.

### Testing Strategy

**Integration Tests (40 tests)**
- Multi-endpoint workflows (register → verify → login → post → feed)
- Database transaction consistency
- Redis cache invalidation sequences
- S3 integration scenarios
- Error recovery paths
- Concurrent request handling

**End-to-End Tests (10 tests)**
- Complete user journeys (iOS front-end to backend)
- Feed loading with pagination
- Image upload and display
- Notification delivery
- Search functionality

### Components

**Test Infrastructure**
- Docker Compose for full stack (PostgreSQL + Redis + S3 mock)
- Test fixtures and factories
- Database state cleanup between tests
- Request/response logging

### Time Breakdown
- Integration test framework setup: 3h
- Multi-endpoint integration tests (40 tests): 8h
- E2E test scenarios (10 tests): 2h
- Test data generation: 1.5h
- Documentation: 0.5h

---

## 📋 Phase 10: Performance & Optimization (12 hours)

### Overview
Load testing, database optimization, caching strategy refinement, and CDN configuration.

### Components

**Database Optimization**
- Query analysis and index optimization
- N+1 query elimination
- Connection pool tuning
- Slow query logging

**Caching Strategy Refinement**
- Feed cache warming
- Post metadata pre-caching
- Cache invalidation patterns
- TTL optimization based on usage

**CDN Configuration**
- CloudFront setup for image delivery
- Cache headers configuration
- Invalidation strategies

**Load Testing**
- 1000 concurrent users scenario
- Feed pagination performance
- Image upload throughput
- Search query performance

### Time Breakdown
- Database optimization: 3h
- Query analysis & tuning: 2h
- Cache strategy refinement: 2.5h
- CDN setup & configuration: 2h
- Load testing & results analysis: 2.5h

---

## 📋 Phase 11: iOS Frontend Integration (20 hours)

### Overview
Build iOS SwiftUI frontend integrated with REST backend.

**Key Components**
- Authentication UI (register, login, password reset)
- Image capture & upload
- Feed display with infinite scroll
- Post creation
- Interactions (like, comment)
- User profiles
- Search interface
- Notifications
- Settings & preferences

**Technical Requirements**
- Network layer (URLSession/Combine)
- Local storage (UserDefaults, CoreData for cache)
- Image caching
- Background task handling for uploads
- Keychain for token storage
- Push notification handling

---

## 📋 Phase 12: Production Hardening (5 hours)

### Overview
Security audit, performance tuning, monitoring setup, and deployment preparation.

**Components**
- Security audit (OWASP, SQL injection, XSS, CSRF)
- Rate limiting tuning
- Monitoring & alerting setup
- Logging aggregation
- Error tracking (Sentry)
- Performance monitoring

---

## 🗂️ Dependency Graph

```
Phase 0: Infrastructure ✅
   ↓
Phase 1: Authentication ✅
   ↓
Phase 2: Content Publishing ←┐
   ↓                           │
Phase 3: Social Graph & Feed  │
   ├→ Phase 4: Interactions   │
   ├→ Phase 5: Profiles    ←──┘
   │
   ├→ Phase 6: Notifications
   ├→ Phase 7: Advanced Auth
   └→ Phase 8: Compliance

Phase 9: Integration & E2E Testing (all phases complete)
Phase 10: Performance & Optimization (all phases complete)
Phase 11: iOS Frontend (all phases complete)
Phase 12: Production Hardening (all phases complete)
```

---

## 📊 Time Budget Summary

| Phase | Duration | Status |
|-------|----------|--------|
| 0-1: Foundation | 34.5h | ✅ COMPLETE |
| 2-8: Core Features | 70h | 📋 PLANNED |
| 9-12: Testing & Hardening | 52h | 📋 PLANNED |
| **Total** | **156.5h** | - |

**Completion Timeline (assuming 20h/week dev time)**:
- Weeks 1-2: Phase 2 (Content Publishing)
- Weeks 2-3: Phase 3 (Social Graph & Feed)
- Weeks 3-4: Phase 4-5 (Interactions & Profiles)
- Weeks 4-5: Phase 6-7 (Notifications & Advanced Auth)
- Week 5: Phase 8 (Compliance)
- Weeks 5-6: Phase 9 (Integration Testing)
- Weeks 6-7: Phase 10 (Performance)
- Weeks 7-10: Phase 11 (iOS Frontend)
- Week 10: Phase 12 (Production Hardening)

**Estimated Completion**: 10 weeks (assuming consistent 20h/week development)

---

## 🎯 Key Architectural Decisions

**Maintained from Phase 0-1**:
1. ✅ Rust + Actix-web backend
2. ✅ PostgreSQL relational database
3. ✅ Redis caching layer
4. ✅ JWT authentication (RS256)
5. ✅ Async/await throughout

**New Decisions**:
1. AWS S3 for image storage + CloudFront CDN
2. Image transcoding via AWS Lambda or local processing
3. Redis-based feed cache with TTL strategy
4. Full-text search via PostgreSQL FTS
5. Background job queue (Redis or Tokio channels)
6. APNs for push notifications

---

## ✅ Success Criteria per Phase

**Phase 2**: All images uploaded to S3, 3 sizes generated, retrievable via URLs
**Phase 3**: Feed shows posts from followed users, pagination works, cache improves performance
**Phase 4**: Like/unlike toggles, comment creation, counts accurate
**Phase 5**: Search returns relevant users, profiles display stats
**Phase 6**: Notifications created on events, push delivery works
**Phase 7**: Password reset flow works end-to-end, Apple Sign-in functional
**Phase 8**: Account deletion cascades properly, data export works
**Phase 9**: 50+ integration tests passing, E2E workflows verified
**Phase 10**: Load test: 1000 users, feed loads <200ms, search <100ms
**Phase 11**: iOS app connects to backend, core user flows work
**Phase 12**: Zero critical security issues, all performance targets met

---

## 🚀 Deployment Strategy

**Per-Phase Deployments**
- Each phase deployed independently
- Feature flags for gradual rollout
- Database migrations backwards-compatible
- Monitoring alerts active before each deployment

**Staging Environment**
- Mirrors production exactly
- Full test suite runs pre-deployment
- Performance benchmarks established

**Production**
- Zero-downtime deployments
- Automatic rollback on health check failures
- Database backups before migrations

---

**Generated**: October 17, 2024
**Status**: Ready for Phase 2 execution
**Next Action**: Begin Phase 2 (Content Publishing) - 12 hours

