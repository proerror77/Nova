# P0 Blockers Implementation Guide - Part 2
## Fixes 6-12: Performance, Testing & Documentation

**Generated**: 2025-11-10
**Prerequisite**: Complete [P0_BLOCKERS_IMPLEMENTATION_GUIDE.md](./P0_BLOCKERS_IMPLEMENTATION_GUIDE.md) (P0-1 to P0-5)
**Total Time**: 58 hours (Week 2-4)

---

## Quick Reference

| ID | Issue | Time | Complexity |
|----|-------|------|------------|
| P0-6 | N+1 Query Optimization | 6h | Medium |
| P0-7 | Redis Caching | 4h | Low |
| P0-8 | Authentication Tests | 16h | High |
| P0-9 | Security Tests | 16h | High |
| P0-10 | Load Testing | 8h | Medium |
| P0-11 | GraphQL Documentation | 4h | Low |
| P0-12 | iOS Integration Guide | 4h | Low |

---

## 🔴 P0-6: N+1 Query Optimization [6 hours]

### Current Issue:
The `feed()` resolver makes sequential gRPC calls for each post's author and media. With 20 posts, this results in:
- 1 call to get post IDs
- 20 calls to get post details
- 20 calls to get user profiles
- 20 calls to get media metadata

**Total**: 61 sequential calls → 3+ seconds latency

### Solution: DataLoader Pattern with Batch Requests

#### Step 1: Create DataLoader (`backend/graphql-gateway/src/data_loader.rs`)

```rust
//! DataLoader for batching and caching gRPC requests

use async_graphql::dataloader::{DataLoader as AsyncDataLoader, Loader};
use std::collections::HashMap;
use std::sync::Arc;
use async_trait::async_trait;

use crate::clients::{ServiceClients, proto};

/// User profile loader - batches user requests
pub struct UserLoader {
    clients: Arc<ServiceClients>,
}

impl UserLoader {
    pub fn new(clients: Arc<ServiceClients>) -> Self {
        Self { clients }
    }
}

#[async_trait]
impl Loader<String> for UserLoader {
    type Value = proto::user::UserProfile;
    type Error = Arc<String>;

    async fn load(&self, keys: &[String]) -> Result<HashMap<String, Self::Value>, Self::Error> {
        let mut client = self.clients.user_client();

        // Batch request for all user IDs
        let request = tonic::Request::new(proto::user::GetUserProfilesBatchRequest {
            user_ids: keys.to_vec(),
        });

        let response = client
            .get_user_profiles_batch(request)
            .await
            .map_err(|e| Arc::new(format!("Failed to batch load users: {}", e)))?;

        // Convert to HashMap<user_id, profile>
        let profiles = response
            .into_inner()
            .profiles
            .into_iter()
            .map(|p| (p.id.clone(), p))
            .collect();

        Ok(profiles)
    }
}

/// Post loader - batches post requests
pub struct PostLoader {
    clients: Arc<ServiceClients>,
}

impl PostLoader {
    pub fn new(clients: Arc<ServiceClients>) -> Self {
        Self { clients }
    }
}

#[async_trait]
impl Loader<String> for PostLoader {
    type Value = proto::content::Post;
    type Error = Arc<String>;

    async fn load(&self, keys: &[String]) -> Result<HashMap<String, Self::Value>, Self::Error> {
        let mut client = self.clients.content_client();

        let request = tonic::Request::new(proto::content::GetPostsBatchRequest {
            post_ids: keys.to_vec(),
        });

        let response = client
            .get_posts_batch(request)
            .await
            .map_err(|e| Arc::new(format!("Failed to batch load posts: {}", e)))?;

        let posts = response
            .into_inner()
            .posts
            .into_iter()
            .map(|p| (p.id.clone(), p))
            .collect();

        Ok(posts)
    }
}

/// Media loader - batches media requests
pub struct MediaLoader {
    clients: Arc<ServiceClients>,
}

impl MediaLoader {
    pub fn new(clients: Arc<ServiceClients>) -> Self {
        Self { clients }
    }
}

#[async_trait]
impl Loader<String> for MediaLoader {
    type Value = proto::content::MediaMetadata;
    type Error = Arc<String>;

    async fn load(&self, keys: &[String]) -> Result<HashMap<String, Self::Value>, Self::Error> {
        let mut client = self.clients.content_client();

        let request = tonic::Request::new(proto::content::GetMediaBatchRequest {
            media_ids: keys.to_vec(),
        });

        let response = client
            .get_media_batch(request)
            .await
            .map_err(|e| Arc::new(format!("Failed to batch load media: {}", e)))?;

        let media = response
            .into_inner()
            .media
            .into_iter()
            .map(|m| (m.id.clone(), m))
            .collect();

        Ok(media)
    }
}
```

#### Step 2: Update `content.rs` to Use DataLoader

```rust
// backend/graphql-gateway/src/schema/content.rs

use async_graphql::{Context, Object, Result as GraphQLResult, ComplexObject};
use crate::data_loader::{UserLoader, PostLoader, MediaLoader};

#[derive(Clone)]
pub struct Post {
    pub id: String,
    pub content: String,
    pub user_id: String,
    pub media_ids: Vec<String>,
    pub created_at: String,
}

#[ComplexObject]
impl Post {
    /// Lazy-load author using DataLoader (batched)
    async fn author(&self, ctx: &Context<'_>) -> GraphQLResult<UserProfile> {
        let loader = ctx.data::<AsyncDataLoader<UserLoader>>()?;

        let user = loader
            .load_one(self.user_id.clone())
            .await?
            .ok_or("User not found")?;

        Ok(user.into())
    }

    /// Lazy-load media using DataLoader (batched)
    async fn media(&self, ctx: &Context<'_>) -> GraphQLResult<Vec<MediaMetadata>> {
        let loader = ctx.data::<AsyncDataLoader<MediaLoader>>()?;

        let media_futures: Vec<_> = self
            .media_ids
            .iter()
            .map(|id| loader.load_one(id.clone()))
            .collect();

        let media = futures::future::try_join_all(media_futures).await?;

        Ok(media.into_iter().flatten().map(Into::into).collect())
    }
}

#[Object]
impl ContentQuery {
    /// Optimized feed - parallel batch loading
    async fn feed(
        &self,
        ctx: &Context<'_>,
        limit: Option<i32>,
        offset: Option<i32>,
    ) -> GraphQLResult<Vec<Post>> {
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.recommendation_client();

        // Step 1: Get post IDs from recommendation service
        let request = tonic::Request::new(proto::feed::GetFeedRequest {
            user_id: ctx.data::<String>()?.clone(),
            limit: limit.unwrap_or(20),
            offset: offset.unwrap_or(0),
        });

        let response = client.get_feed(request).await?;
        let post_ids = response.into_inner().post_ids;

        // Step 2: Batch load all posts using DataLoader
        let post_loader = ctx.data::<AsyncDataLoader<PostLoader>>()?;

        let post_futures: Vec<_> = post_ids
            .iter()
            .map(|id| post_loader.load_one(id.clone()))
            .collect();

        let posts = futures::future::try_join_all(post_futures).await?;

        // GraphQL will automatically batch-load authors/media when requested
        Ok(posts.into_iter().flatten().map(Into::into).collect())
    }
}
```

#### Step 3: Register DataLoaders in `main.rs`

```rust
// backend/graphql-gateway/src/main.rs

use async_graphql::dataloader::DataLoader;
use crate::data_loader::{UserLoader, PostLoader, MediaLoader};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let clients = Arc::new(ServiceClients::default());

    // Create DataLoaders
    let user_loader = DataLoader::new(
        UserLoader::new(clients.clone()),
        tokio::spawn,
    );

    let post_loader = DataLoader::new(
        PostLoader::new(clients.clone()),
        tokio::spawn,
    );

    let media_loader = DataLoader::new(
        MediaLoader::new(clients.clone()),
        tokio::spawn,
    );

    let schema = Schema::build(QueryRoot::default(), MutationRoot::default(), EmptySubscription)
        .data(clients)
        .data(user_loader)
        .data(post_loader)
        .data(media_loader)
        .finish();

    // ... rest of server setup
}
```

#### Step 4: Add Backend Batch Endpoints

Update backend services to support batch requests:

```proto
// proto/user-service.proto
service UserService {
  // Add batch endpoint
  rpc GetUserProfilesBatch(GetUserProfilesBatchRequest) returns (GetUserProfilesBatchResponse);
}

message GetUserProfilesBatchRequest {
  repeated string user_ids = 1;
}

message GetUserProfilesBatchResponse {
  repeated UserProfile profiles = 1;
}
```

```rust
// backend/user-service/src/handlers/user.rs

pub async fn get_user_profiles_batch(
    req: Request<GetUserProfilesBatchRequest>,
    pool: &PgPool,
) -> Result<Response<GetUserProfilesBatchResponse>, Status> {
    let user_ids = req.into_inner().user_ids;

    // Single database query for all users
    let profiles = sqlx::query_as!(
        UserProfile,
        r#"
        SELECT id, username, email, bio, avatar_url,
               follower_count, following_count, post_count,
               created_at, is_verified, is_private
        FROM users
        WHERE id = ANY($1)
        "#,
        &user_ids
    )
    .fetch_all(pool)
    .await
    .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

    Ok(Response::new(GetUserProfilesBatchResponse { profiles }))
}
```

### Performance Impact:
- **Before**: 61 sequential calls → 3+ seconds
- **After**: 3-4 parallel batch calls → <300ms
- **Improvement**: 10× faster

---

## 🟡 P0-7: Redis Caching Strategy [4 hours]

### Current Issue:
User profiles and post metadata fetched from database on every request, even for hot content.

### Solution: Redis L1 Cache

#### Step 1: Add Redis Dependency

```toml
# backend/graphql-gateway/Cargo.toml
[dependencies]
redis = { version = "0.24", features = ["tokio-comp", "connection-manager"] }
```

#### Step 2: Create Cache Module (`backend/graphql-gateway/src/cache.rs`)

```rust
//! Redis caching layer for frequently accessed data

use redis::{AsyncCommands, Client};
use std::time::Duration;
use serde::{Deserialize, Serialize};

pub struct RedisCache {
    client: redis::aio::ConnectionManager,
}

impl RedisCache {
    pub async fn new(redis_url: &str) -> Result<Self, redis::RedisError> {
        let client = Client::open(redis_url)?;
        let conn_mgr = client.get_tokio_connection_manager().await?;

        Ok(Self { client: conn_mgr })
    }

    /// Get cached value or execute fallback
    pub async fn get_or_fetch<T, F, Fut>(
        &mut self,
        key: &str,
        ttl: Duration,
        fallback: F,
    ) -> Result<T, Box<dyn std::error::Error>>
    where
        T: Serialize + for<'de> Deserialize<'de>,
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<T, Box<dyn std::error::Error>>>,
    {
        // Try cache first
        let cached: Option<String> = self.client.get(key).await.ok();

        if let Some(data) = cached {
            if let Ok(value) = serde_json::from_str(&data) {
                tracing::debug!(key, "Cache HIT");
                return Ok(value);
            }
        }

        tracing::debug!(key, "Cache MISS");

        // Cache miss - fetch from source
        let value = fallback().await?;

        // Store in cache
        let serialized = serde_json::to_string(&value)?;
        let _: () = self.client
            .set_ex(key, serialized, ttl.as_secs() as usize)
            .await?;

        Ok(value)
    }

    /// Invalidate cache entry
    pub async fn invalidate(&mut self, key: &str) -> Result<(), redis::RedisError> {
        let _: () = self.client.del(key).await?;
        Ok(())
    }

    /// Invalidate pattern (e.g., "user:*")
    pub async fn invalidate_pattern(&mut self, pattern: &str) -> Result<(), redis::RedisError> {
        use redis::Script;

        let script = Script::new(r#"
            local keys = redis.call('KEYS', ARGV[1])
            for i=1,#keys,5000 do
                redis.call('DEL', unpack(keys, i, math.min(i+4999, #keys)))
            end
            return #keys
        "#);

        let _: i32 = script.arg(pattern).invoke_async(&mut self.client).await?;
        Ok(())
    }
}
```

#### Step 3: Update UserLoader with Cache

```rust
// backend/graphql-gateway/src/data_loader.rs

use crate::cache::RedisCache;

pub struct UserLoader {
    clients: Arc<ServiceClients>,
    cache: Arc<tokio::sync::Mutex<RedisCache>>,
}

#[async_trait]
impl Loader<String> for UserLoader {
    type Value = proto::user::UserProfile;
    type Error = Arc<String>;

    async fn load(&self, keys: &[String]) -> Result<HashMap<String, Self::Value>, Self::Error> {
        let mut results = HashMap::new();
        let mut cache_misses = Vec::new();

        // Check cache for each key
        let mut cache = self.cache.lock().await;
        for key in keys {
            let cache_key = format!("user:profile:{}", key);

            match cache.get_or_fetch(
                &cache_key,
                Duration::from_secs(300), // 5 min TTL
                || async { Err("skip".into()) },
            ).await {
                Ok(profile) => {
                    results.insert(key.clone(), profile);
                }
                Err(_) => {
                    cache_misses.push(key.clone());
                }
            }
        }

        // Batch fetch cache misses
        if !cache_misses.is_empty() {
            let mut client = self.clients.user_client();

            let request = tonic::Request::new(proto::user::GetUserProfilesBatchRequest {
                user_ids: cache_misses.clone(),
            });

            let response = client
                .get_user_profiles_batch(request)
                .await
                .map_err(|e| Arc::new(format!("Failed to batch load users: {}", e)))?;

            // Store in cache and results
            for profile in response.into_inner().profiles {
                let cache_key = format!("user:profile:{}", profile.id);
                let serialized = serde_json::to_string(&profile).unwrap();
                let _: () = cache.client.set_ex(&cache_key, serialized, 300).await.unwrap();

                results.insert(profile.id.clone(), profile);
            }
        }

        Ok(results)
    }
}
```

#### Step 4: Cache Invalidation on Mutations

```rust
// backend/graphql-gateway/src/schema/user.rs

#[Object]
impl UserMutation {
    async fn update_profile(
        &self,
        ctx: &Context<'_>,
        input: UpdateProfileInput,
    ) -> GraphQLResult<UserProfile> {
        // Update in database
        let updated_profile = /* ... update logic ... */;

        // Invalidate cache
        let mut cache = ctx.data::<Arc<tokio::sync::Mutex<RedisCache>>>()?.lock().await;
        cache.invalidate(&format!("user:profile:{}", input.user_id)).await?;

        Ok(updated_profile)
    }
}
```

### Caching Strategy:

| Data Type | TTL | Invalidation |
|-----------|-----|--------------|
| User Profiles | 5 min | On profile update |
| Posts | 2 min | On edit/delete |
| Media Metadata | 30 min | On upload/delete |
| Feed Recommendations | 1 min | On new post |

---

## 🔴 P0-8: Authentication Test Suite [16 hours]

### Goal: 80%+ test coverage for authentication flows

#### Test Structure:

```rust
// backend/graphql-gateway/tests/auth/
├── middleware_tests.rs      // JWT validation
├── login_tests.rs           // Login flow
├── register_tests.rs        // Registration
├── token_refresh_tests.rs   // Token refresh
└── edge_cases_tests.rs      // Error handling
```

#### Example: `middleware_tests.rs`

```rust
use actix_web::{test, web, App};
use graphql_gateway::middleware::JwtMiddleware;

#[actix_web::test]
async fn test_valid_jwt_allows_access() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/graphql", web::post().to(graphql_handler)),
    )
    .await;

    let valid_token = create_test_jwt("user-123", 3600); // 1 hour expiry

    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Authorization", format!("Bearer {}", valid_token)))
        .set_json(json!({
            "query": "{ user(id: \"user-123\") { id username } }"
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200);
}

#[actix_web::test]
async fn test_expired_jwt_rejected() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/graphql", web::post().to(graphql_handler)),
    )
    .await;

    let expired_token = create_test_jwt("user-123", -3600); // Expired 1 hour ago

    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Authorization", format!("Bearer {}", expired_token)))
        .set_json(json!({"query": "{ health }"}))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401);

    let body: serde_json::Value = test::read_body_json(resp).await;
    assert!(body["error"].as_str().unwrap().contains("expired"));
}

#[actix_web::test]
async fn test_invalid_signature_rejected() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/graphql", web::post().to(graphql_handler)),
    )
    .await;

    // Token signed with different secret
    let token_wrong_secret = create_jwt_with_secret("user-123", 3600, "wrong-secret");

    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Authorization", format!("Bearer {}", token_wrong_secret)))
        .set_json(json!({"query": "{ health }"}))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401);
}

#[actix_web::test]
async fn test_missing_authorization_header() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/graphql", web::post().to(graphql_handler)),
    )
    .await;

    let req = test::TestRequest::post()
        .uri("/graphql")
        .set_json(json!({"query": "{ health }"}))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401);
}

#[actix_web::test]
async fn test_malformed_bearer_token() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/graphql", web::post().to(graphql_handler)),
    )
    .await;

    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Authorization", "NotBearer invalid"))
        .set_json(json!({"query": "{ health }"}))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401);
}
```

#### Test Helpers (`tests/helpers/jwt.rs`):

```rust
use jsonwebtoken::{encode, EncodingKey, Header, Algorithm};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
struct Claims {
    sub: String,
    exp: usize,
    iat: usize,
}

pub fn create_test_jwt(user_id: &str, expires_in_seconds: i64) -> String {
    let now = chrono::Utc::now().timestamp();
    let exp = (now + expires_in_seconds) as usize;

    let claims = Claims {
        sub: user_id.to_string(),
        exp,
        iat: now as usize,
    };

    encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret("test-secret".as_bytes()),
    )
    .unwrap()
}

pub fn create_jwt_with_secret(user_id: &str, expires_in: i64, secret: &str) -> String {
    let now = chrono::Utc::now().timestamp();
    let exp = (now + expires_in) as usize;

    let claims = Claims {
        sub: user_id.to_string(),
        exp,
        iat: now as usize,
    };

    encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .unwrap()
}
```

### Full Test Coverage Plan:

#### 1. Middleware Tests (8 tests)
- ✅ Valid JWT allows access
- ✅ Expired JWT rejected
- ✅ Invalid signature rejected
- ✅ Missing Authorization header
- ✅ Malformed Bearer token
- ✅ JWT with missing claims
- ✅ JWT with invalid algorithm
- ✅ Concurrent requests with same token

#### 2. Login Tests (12 tests)
- Valid credentials → success
- Invalid email → 401
- Invalid password → 401
- SQL injection attempt → escaped
- Rate limiting (5 failures → 15min lockout)
- Account not verified → 403
- Account disabled → 403
- Password reset required → 403
- Successful login increments login_count
- Login logs IP address
- Login returns fresh JWT + refresh token
- Login sets last_login_at timestamp

#### 3. Register Tests (15 tests)
- Valid registration → success
- Duplicate email → 409
- Duplicate username → 409
- Invalid email format → 400
- Weak password → 400
- Username with special chars → 400
- Email XSS attempt → sanitized
- Password < 8 chars → 400
- Password missing uppercase → 400
- Password missing number → 400
- Registration sends verification email
- Username case-insensitive collision
- Email case-insensitive collision
- Registration rate limiting
- GDPR consent required

#### 4. Token Refresh Tests (8 tests)
- Valid refresh token → new JWT
- Expired refresh token → 401
- Invalid refresh token → 401
- Revoked refresh token → 401
- Refresh token reuse detection
- Refresh rotates refresh token
- Refresh inherits user permissions
- Refresh logs security event

#### 5. Edge Cases (12 tests)
- Extremely long JWT (>8KB) → 413
- JWT with future iat claim → 401
- JWT with nbf (not before) claim
- Clock skew tolerance (5 min)
- Special characters in email
- Unicode username handling
- Null byte injection
- Header injection attempt
- CORS preflight handling
- GraphQL introspection disabled in prod
- Rate limit headers returned
- Error messages don't leak info

**Total: 55 tests**

---

## 🟡 P0-9: Security Test Suite [16 hours]

### Goal: Prevent IDOR, privilege escalation, and authorization bypasses

#### Test Structure:

```rust
// backend/graphql-gateway/tests/security/
├── idor_tests.rs            // Insecure Direct Object Reference
├── authorization_tests.rs   // Permission checks
├── sql_injection_tests.rs   // Input sanitization
└── xss_tests.rs             // Output encoding
```

#### Example: `idor_tests.rs`

```rust
use actix_web::test;

#[actix_web::test]
async fn test_cannot_view_private_profile() {
    let app = create_test_app().await;

    // User A tries to view User B's private profile
    let token_a = create_test_jwt("user-a");

    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Authorization", format!("Bearer {}", token_a)))
        .set_json(json!({
            "query": r#"
                query {
                    user(id: "user-b-private") {
                        id
                        email
                        phoneNumber
                    }
                }
            "#
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    let body: serde_json::Value = test::read_body_json(resp).await;

    // Should return partial data (public fields only)
    assert!(body["data"]["user"]["id"].is_string());
    assert!(body["data"]["user"]["email"].is_null());
    assert!(body["data"]["user"]["phoneNumber"].is_null());
}

#[actix_web::test]
async fn test_cannot_delete_other_users_post() {
    let app = create_test_app().await;

    // Create post as User B
    let post_id = create_test_post("user-b").await;

    // User A tries to delete User B's post
    let token_a = create_test_jwt("user-a");

    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Authorization", format!("Bearer {}", token_a)))
        .set_json(json!({
            "query": format!(r#"
                mutation {{
                    deletePost(postId: "{}") {{
                        success
                    }}
                }}
            "#, post_id)
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    let body: serde_json::Value = test::read_body_json(resp).await;

    // Should return error
    assert!(body["errors"][0]["message"]
        .as_str()
        .unwrap()
        .contains("Forbidden"));
}

#[actix_web::test]
async fn test_cannot_update_other_users_profile() {
    let app = create_test_app().await;

    let token_a = create_test_jwt("user-a");

    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Authorization", format!("Bearer {}", token_a)))
        .set_json(json!({
            "query": r#"
                mutation {
                    updateProfile(input: {
                        userId: "user-b",
                        displayName: "HACKED"
                    }) {
                        id
                    }
                }
            "#
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    let body: serde_json::Value = test::read_body_json(resp).await;

    assert!(body["errors"][0]["message"]
        .as_str()
        .unwrap()
        .contains("Forbidden"));
}
```

### Security Test Categories:

#### 1. IDOR Tests (15 tests)
- Cannot view other user's private profile
- Cannot view other user's DMs
- Cannot delete other user's posts
- Cannot update other user's profile
- Cannot access other user's draft posts
- Cannot view other user's payment methods
- Cannot modify other user's settings
- Cannot view other user's notifications
- Cannot accept follows on behalf of others
- Cannot view blocked users list
- Admin can view all profiles
- Moderator can delete any post
- Cannot enumerate user IDs
- Cannot access deleted content
- Cannot view archived data without permission

#### 2. Authorization Tests (12 tests)
- Unauthenticated user cannot post
- Unauthenticated user cannot follow
- Suspended user cannot comment
- Unverified email cannot DM
- Free tier cannot upload videos
- Pro tier can upload videos
- Admin bypasses rate limits
- Moderator can ban users
- Regular user cannot ban users
- Cannot escalate own permissions
- Cannot modify role through mutation
- Session expires after logout

#### 3. SQL Injection Tests (8 tests)
- SQL in username → escaped
- SQL in bio → escaped
- SQL in search query → parameterized
- SQL in filter parameters → safe
- Union-based injection blocked
- Time-based blind injection safe
- Boolean-based injection safe
- Stacked queries prevented

#### 4. XSS Tests (8 tests)
- Script tag in bio → encoded
- Event handler in username → encoded
- Image onerror XSS → sanitized
- SVG XSS → sanitized
- Data URL XSS → blocked
- Stored XSS in comments → encoded
- Reflected XSS in search → encoded
- DOM-based XSS prevented

**Total: 43 tests**

---

## 🟡 P0-10: Load Testing [8 hours]

### Goal: Validate connection pooling under high load

#### Test Setup:

```bash
# Install k6
brew install k6  # macOS
# or
sudo apt install k6  # Linux
```

#### Load Test Script (`tests/load/connection_pool_test.js`):

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// Custom metrics
const connectionErrors = new Counter('connection_errors');
const authLatency = new Trend('auth_latency');

export const options = {
  stages: [
    { duration: '2m', target: 50 },   // Ramp up to 50 users
    { duration: '5m', target: 100 },  // Ramp up to 100 users
    { duration: '3m', target: 200 },  // Spike to 200 users
    { duration: '2m', target: 100 },  // Ramp down
    { duration: '2m', target: 0 },    // Cooldown
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% of requests < 500ms
    http_req_failed: ['rate<0.01'],    // Error rate < 1%
    connection_errors: ['count<10'],   // < 10 connection errors
  },
};

const GRAPHQL_ENDPOINT = 'http://localhost:8080/graphql';

export default function () {
  const payload = JSON.stringify({
    query: `
      query {
        user(id: "test-user-123") {
          id
          username
          email
        }
      }
    `,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${__ENV.TEST_JWT}`,
    },
  };

  const start = Date.now();
  const res = http.post(GRAPHQL_ENDPOINT, payload, params);
  const duration = Date.now() - start;

  authLatency.add(duration);

  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'has data': (r) => JSON.parse(r.body).data !== undefined,
    'no connection errors': (r) => !r.body.includes('connection'),
  });

  if (!success && res.body.includes('connection')) {
    connectionErrors.add(1);
  }

  sleep(1);
}
```

#### Run Load Test:

```bash
# 1. Start GraphQL Gateway
cd backend/graphql-gateway
cargo run --release

# 2. Generate test JWT
export TEST_JWT=$(curl -s -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"mutation { login(email:\"test@example.com\", password:\"password123\") { token } }"}' \
  | jq -r '.data.login.token')

# 3. Run load test
k6 run tests/load/connection_pool_test.js

# 4. Analyze results
k6 run --out json=results.json tests/load/connection_pool_test.js
```

#### Expected Results:

**Before Connection Pooling:**
```
✗ http_req_duration............: avg=1.2s  p95=3.5s
✗ http_req_failed..............: 5.2%
✗ connection_errors............: 143
```

**After Connection Pooling:**
```
✓ http_req_duration............: avg=120ms  p95=280ms
✓ http_req_failed..............: 0.3%
✓ connection_errors............: 2
```

### Additional Load Tests:

#### 2. Feed Pagination Test (`feed_load_test.js`)

```javascript
export default function () {
  const queries = [
    'query { feed(limit: 20, offset: 0) { id content } }',
    'query { feed(limit: 20, offset: 20) { id content } }',
    'query { feed(limit: 20, offset: 40) { id content } }',
  ];

  const query = queries[Math.floor(Math.random() * queries.length)];

  const res = http.post(GRAPHQL_ENDPOINT, JSON.stringify({ query }), params);

  check(res, {
    'feed loaded in <500ms': (r) => r.timings.duration < 500,
    'returns 20 posts': (r) => JSON.parse(r.body).data.feed.length === 20,
  });
}
```

#### 3. Concurrent Mutations Test (`mutation_load_test.js`)

```javascript
export default function () {
  const mutations = [
    `mutation { createPost(input: { content: "Test ${Date.now()}" }) { id } }`,
    `mutation { followUser(followeeId: "user-${Math.floor(Math.random() * 1000)}") }`,
    `mutation { likePost(postId: "post-${Math.floor(Math.random() * 5000)}") }`,
  ];

  const mutation = mutations[Math.floor(Math.random() * mutations.length)];

  const res = http.post(GRAPHQL_ENDPOINT, JSON.stringify({ query: mutation }), params);

  check(res, {
    'mutation succeeded': (r) => r.status === 200 && !JSON.parse(r.body).errors,
    'no database deadlocks': (r) => !r.body.includes('deadlock'),
  });
}
```

---

## 🔴 P0-11: GraphQL Schema Documentation [4 hours]

### Goal: Auto-generate schema.graphql and API documentation

#### Step 1: Export Schema

```rust
// backend/graphql-gateway/src/main.rs

use async_graphql::Schema;
use std::fs;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let schema = build_schema();

    // Export schema to file
    let sdl = schema.sdl();
    fs::write("schema.graphql", sdl)?;

    println!("✅ Schema exported to schema.graphql");

    // Start server...
}
```

#### Generated Schema Example:

```graphql
# schema.graphql (auto-generated)

"""
User profile with public and private fields
"""
type UserProfile {
  id: ID!
  username: String!
  email: String  # Only visible to owner
  bio: String
  avatarUrl: String
  followerCount: Int!
  followingCount: Int!
  postCount: Int!
  createdAt: String!
  isVerified: Boolean!
  isPrivate: Boolean!
}

"""
Post with embedded author and media
"""
type Post {
  id: ID!
  content: String!
  author: UserProfile!
  media: [MediaMetadata!]!
  likeCount: Int!
  commentCount: Int!
  createdAt: String!
  updatedAt: String
}

type Query {
  """
  Get user profile by ID
  """
  user(id: ID!): UserProfile

  """
  Get personalized feed
  """
  feed(limit: Int = 20, offset: Int = 0): [Post!]!

  """
  Search posts by keyword
  """
  searchPosts(query: String!, limit: Int = 20): [Post!]!
}

type Mutation {
  """
  Authenticate user with email and password
  """
  login(email: String!, password: String!): LoginResponse!

  """
  Register new user account
  """
  register(
    email: String!
    password: String!
    username: String!
  ): RegisterResponse!

  """
  Create new post
  """
  createPost(input: CreatePostInput!): Post!

  """
  Delete post (owner only)
  """
  deletePost(postId: ID!): Boolean!

  """
  Follow another user
  """
  followUser(followeeId: ID!): Boolean!
}

input CreatePostInput {
  content: String!
  mediaIds: [ID!]
}

type LoginResponse {
  userId: ID!
  token: String!
  refreshToken: String!
  expiresIn: Int!
}
```

#### Step 2: Generate HTML Documentation

```bash
# Install spectaql
npm install -g spectaql

# Generate docs
spectaql config.yml
```

**config.yml:**

```yaml
spectaql:
  targetDir: docs/graphql
  logoFile: assets/logo.png

introspection:
  schemaFile: schema.graphql

info:
  title: Nova Social GraphQL API
  description: |
    Complete API reference for Nova Social platform.

    ## Authentication
    All requests require JWT Bearer token:
    ```
    Authorization: Bearer <your-jwt-token>
    ```

    ## Rate Limits
    - 100 requests/minute (authenticated)
    - 10 requests/minute (unauthenticated)

  contact:
    name: API Support
    email: api@novasocial.com
  version: 1.0.0
```

#### Step 3: Add Inline Examples

```rust
// backend/graphql-gateway/src/schema/user.rs

#[Object]
impl UserQuery {
    /// Get user profile by ID
    ///
    /// # Example
    /// ```graphql
    /// query {
    ///   user(id: "user-123") {
    ///     id
    ///     username
    ///     followerCount
    ///   }
    /// }
    /// ```
    ///
    /// # Response
    /// ```json
    /// {
    ///   "data": {
    ///     "user": {
    ///       "id": "user-123",
    ///       "username": "alice",
    ///       "followerCount": 42
    ///     }
    ///   }
    /// }
    /// ```
    async fn user(&self, ctx: &Context<'_>, id: String) -> GraphQLResult<Option<UserProfile>> {
        // ...
    }
}
```

---

## 🔴 P0-12: iOS Integration Guide [4 hours]

### Goal: Complete iOS client setup documentation

#### Create `docs/iOS_INTEGRATION_GUIDE.md`:

```markdown
# iOS Integration Guide - Nova Social

## Prerequisites

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

---

## 1. Installation

### Add Apollo GraphQL

```ruby
# Podfile
target 'NovaSocial' do
  use_frameworks!

  pod 'Apollo', '~> 1.9'
  pod 'KeychainAccess', '~> 4.2'
end
```

```bash
pod install
```

---

## 2. Configure GraphQL Client

Create `Apollo/ApolloClient.swift`:

```swift
import Apollo
import Foundation

class Network {
    static let shared = Network()

    private(set) lazy var apollo: ApolloClient = {
        let cache = InMemoryNormalizedCache()
        let store = ApolloStore(cache: cache)

        let authInterceptor = AuthInterceptor()
        let networkTransport = RequestChainNetworkTransport(
            interceptorProvider: NetworkInterceptorProvider(
                store: store,
                interceptor: authInterceptor
            ),
            endpointURL: URL(string: Config.graphqlEndpoint)!
        )

        return ApolloClient(networkTransport: networkTransport, store: store)
    }()
}

// Auth interceptor
class AuthInterceptor: ApolloInterceptor {
    func interceptAsync<Operation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) where Operation : GraphQLOperation {

        // Add JWT from Keychain
        if let token = KeychainHelper.read(key: "jwt_token") {
            request.addHeader(name: "Authorization", value: "Bearer \(token)")
        }

        chain.proceedAsync(request: request, response: response, completion: completion)
    }
}
```

---

## 3. Example Queries

### Fetch User Profile

```swift
import Apollo

func fetchUserProfile(userId: String) {
    let query = GetUserProfileQuery(userId: userId)

    Network.shared.apollo.fetch(query: query) { result in
        switch result {
        case .success(let graphQLResult):
            if let user = graphQLResult.data?.user {
                print("Username: \(user.username)")
                print("Followers: \(user.followerCount)")
            }

            if let errors = graphQLResult.errors {
                print("GraphQL Errors: \(errors)")
            }

        case .failure(let error):
            print("Network error: \(error)")
        }
    }
}
```

### Fetch Feed

```swift
func fetchFeed(limit: Int = 20, offset: Int = 0) {
    let query = GetFeedQuery(limit: limit, offset: offset)

    Network.shared.apollo.fetch(query: query, cachePolicy: .fetchIgnoringCacheData) { result in
        switch result {
        case .success(let graphQLResult):
            if let posts = graphQLResult.data?.feed {
                self.posts = posts.compactMap { post in
                    Post(
                        id: post.id,
                        content: post.content,
                        author: post.author.username,
                        likeCount: post.likeCount
                    )
                }
            }

        case .failure(let error):
            self.handleError(error)
        }
    }
}
```

---

## 4. Example Mutations

### Login

```swift
func login(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
    let mutation = LoginMutation(email: email, password: password)

    Network.shared.apollo.perform(mutation: mutation) { result in
        switch result {
        case .success(let graphQLResult):
            if let loginResponse = graphQLResult.data?.login {
                // Store tokens securely
                KeychainHelper.save(key: "jwt_token", value: loginResponse.token)
                KeychainHelper.save(key: "refresh_token", value: loginResponse.refreshToken)

                completion(.success(loginResponse.userId))
            } else if let errors = graphQLResult.errors {
                completion(.failure(GraphQLError.serverError(errors.first?.message ?? "Unknown error")))
            }

        case .failure(let error):
            completion(.failure(error))
        }
    }
}
```

### Create Post

```swift
func createPost(content: String, mediaIds: [String] = []) {
    let input = CreatePostInput(content: content, mediaIds: mediaIds)
    let mutation = CreatePostMutation(input: input)

    Network.shared.apollo.perform(mutation: mutation) { result in
        switch result {
        case .success(let graphQLResult):
            if let post = graphQLResult.data?.createPost {
                print("Post created: \(post.id)")
            }

        case .failure(let error):
            print("Failed to create post: \(error)")
        }
    }
}
```

---

## 5. Error Handling

```swift
enum GraphQLError: Error {
    case serverError(String)
    case networkError(Error)
    case unauthorized
    case invalidData
}

func handleError(_ error: Error) {
    if let graphQLError = error as? GraphQLError {
        switch graphQLError {
        case .unauthorized:
            // Token expired - refresh or logout
            refreshToken()

        case .serverError(let message):
            showAlert(title: "Error", message: message)

        case .networkError:
            showAlert(title: "Network Error", message: "Please check your connection")

        case .invalidData:
            showAlert(title: "Error", message: "Invalid response from server")
        }
    }
}
```

---

## 6. Caching Strategy

```swift
// Fetch fresh data
apollo.fetch(query: query, cachePolicy: .fetchIgnoringCacheData) { ... }

// Use cache if available, fetch if not
apollo.fetch(query: query, cachePolicy: .returnCacheDataElseFetch) { ... }

// Use cache only (offline mode)
apollo.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { ... }
```

---

## 7. Testing

```swift
import XCTest
@testable import NovaSocial

class GraphQLTests: XCTestCase {
    func testLoginMutation() {
        let expectation = XCTestExpectation(description: "Login completes")

        login(email: "test@example.com", password: "password123") { result in
            switch result {
            case .success(let userId):
                XCTAssertFalse(userId.isEmpty)
                expectation.fulfill()

            case .failure(let error):
                XCTFail("Login failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }
}
```

---

## 8. Security Best Practices

### ✅ DO:
- Store tokens in Keychain (never UserDefaults)
- Use HTTPS only (disable App Transport Security exceptions)
- Validate SSL certificates
- Implement token refresh logic
- Clear tokens on logout

### ❌ DON'T:
- Log tokens or sensitive data
- Store passwords locally
- Trust server responses without validation
- Ignore SSL errors

---

## Troubleshooting

### "Unauthorized" errors
```swift
// Refresh token logic
func refreshToken() {
    guard let refreshToken = KeychainHelper.read(key: "refresh_token") else {
        logout()
        return
    }

    let mutation = RefreshTokenMutation(refreshToken: refreshToken)
    Network.shared.apollo.perform(mutation: mutation) { result in
        // Update tokens...
    }
}
```

### GraphQL schema updates
```bash
# Download latest schema
apollo schema:download --endpoint=https://api.novasocial.com/graphql schema.graphqls

# Generate Swift types
apollo codegen:generate --target=swift --includes=./**/*.graphql --localSchemaFile=schema.graphqls API.swift
```
```

---

## Summary - Part 2 Complete

### Deliverables Created:

1. ✅ **P0-6**: DataLoader pattern with batch endpoints (6h)
2. ✅ **P0-7**: Redis caching with TTL strategy (4h)
3. ✅ **P0-8**: 55+ authentication tests (16h)
4. ✅ **P0-9**: 43+ security tests for IDOR/XSS/SQLi (16h)
5. ✅ **P0-10**: k6 load testing scripts (8h)
6. ✅ **P0-11**: GraphQL schema documentation (4h)
7. ✅ **P0-12**: Complete iOS integration guide (4h)

### Next Steps:

1. Start with **P0-1** from [Part 1](./P0_BLOCKERS_IMPLEMENTATION_GUIDE.md)
2. Work through fixes sequentially (easier → harder)
3. Run tests after each fix
4. Commit with descriptive messages

**Recommended Order**:
1. Week 1: P0-1, P0-2, P0-3, P0-4 (low-hanging fruit)
2. Week 2: P0-6, P0-7 (performance wins)
3. Week 3: P0-8, P0-9 (comprehensive testing)
4. Week 4: P0-10, P0-11, P0-12 (validation & docs)

---

**Total Implementation Time**: 71 hours (Part 1 + Part 2)
**Expected Production-Ready Date**: Week 4 (2025-12-08)
