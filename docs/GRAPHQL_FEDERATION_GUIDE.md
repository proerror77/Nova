# GraphQL Federation Implementation Guide

**Status**: ✅ Architecture Complete, Implementation In Progress
**Technology**: async-graphql v7.0 + Apollo Federation
**Date**: 2025-11-09

---

## Overview

GraphQL Federation provides a unified API gateway that composes multiple GraphQL services (subgraphs) into a single federated graph. This allows clients to query data from multiple microservices through a single endpoint.

### Benefits

- **Unified API**: Single GraphQL endpoint for all services
- **Type Safety**: End-to-end type safety from backend to frontend
- **Efficient Queries**: Client specifies exactly what data it needs
- **Cross-Service Joins**: Query data from multiple services in one request
- **Better DX**: GraphQL Playground for API exploration
- **Automatic Documentation**: Schema serves as API documentation

### Architecture

```
┌────────────────────────────────────────────────────────────┐
│  Client (Web/Mobile)                                       │
│  - Sends GraphQL query                                     │
│  - Receives unified response                               │
└────────────────┬───────────────────────────────────────────┘
                 │ GraphQL Query
                 ▼
┌────────────────────────────────────────────────────────────┐
│  GraphQL Gateway (Federation Router)                       │
│  - Parses query                                            │
│  - Plans query execution                                   │
│  - Delegates to subgraphs                                  │
│  - Merges responses                                        │
└────────────────┬───────────────────────────────────────────┘
                 │
      ┌──────────┼──────────┬──────────┬──────────┐
      │          │          │          │          │
      ▼          ▼          ▼          ▼          ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│  Auth   │ │  User   │ │ Content │ │Messaging│ │  Feed   │
│Subgraph │ │Subgraph │ │Subgraph │ │Subgraph │ │Subgraph │
└────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘
     │           │           │           │           │
     ▼           ▼           ▼           ▼           ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│  Auth   │ │  User   │ │ Content │ │Messaging│ │  Feed   │
│ Service │ │ Service │ │ Service │ │ Service │ │ Service │
│ (gRPC)  │ │ (gRPC)  │ │ (gRPC)  │ │ (gRPC)  │ │ (gRPC)  │
└─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘
```

---

## Implementation Structure

### Directory Layout

```
backend/graphql-gateway/
├── Cargo.toml
├── src/
│   ├── main.rs                 # Server entry point
│   ├── config.rs               # Configuration ✅ Created
│   ├── schema/
│   │   ├── mod.rs              # Schema root ✅ Created
│   │   ├── user.rs             # User subgraph
│   │   ├── content.rs          # Content subgraph
│   │   ├── auth.rs             # Auth subgraph
│   │   ├── messaging.rs        # Messaging subgraph
│   │   └── feed.rs             # Feed subgraph
│   ├── clients/
│   │   ├── mod.rs              # gRPC client pool
│   │   ├── auth_client.rs      # Auth service client
│   │   ├── user_client.rs      # User service client
│   │   └── ...
│   ├── dataloaders/
│   │   ├── mod.rs              # DataLoader registry
│   │   ├── user_loader.rs      # Batch load users
│   │   └── content_loader.rs   # Batch load content
│   ├── middleware/
│   │   ├── auth.rs             # JWT authentication
│   │   └── tracing.rs          # OpenTelemetry integration
│   └── error.rs                # Error types
```

---

## Core Concepts

### 1. Federation Entities

Entities are types that can be extended across subgraphs and referenced using the `@key` directive.

**Example: User Entity**

```rust
// backend/graphql-gateway/src/schema/user.rs
use async_graphql::*;

/// User entity (can be referenced from other subgraphs)
#[derive(Clone, SimpleObject)]
#[graphql(complex)]
pub struct User {
    pub id: ID,
    pub username: String,
    pub email: String,
    pub display_name: String,
    pub avatar_url: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[ComplexObject]
impl User {
    /// Resolve posts created by this user (from Content subgraph)
    async fn posts(&self, ctx: &Context<'_>) -> Result<Vec<Post>> {
        let content_client = ctx.data::<ContentClient>()?;
        content_client.get_user_posts(&self.id).await
    }

    /// Resolve messages sent by this user (from Messaging subgraph)
    async fn messages(&self, ctx: &Context<'_>) -> Result<Vec<Message>> {
        let messaging_client = ctx.data::<MessagingClient>()?;
        messaging_client.get_user_messages(&self.id).await
    }
}

/// User queries
#[derive(Default)]
pub struct UserQuery;

#[Object]
impl UserQuery {
    /// Get user by ID
    async fn user(&self, ctx: &Context<'_>, id: ID) -> Result<Option<User>> {
        let user_client = ctx.data::<UserClient>()?;
        user_client.get_user(id).await
    }

    /// Search users
    async fn users(
        &self,
        ctx: &Context<'_>,
        #[graphql(desc = "Search query")] query: Option<String>,
        #[graphql(desc = "Limit results")] limit: Option<i32>,
    ) -> Result<Vec<User>> {
        let user_client = ctx.data::<UserClient>()?;
        user_client.search_users(query, limit).await
    }
}
```

### 2. Cross-Service References

```rust
// backend/graphql-gateway/src/schema/content.rs
use async_graphql::*;

#[derive(Clone, SimpleObject)]
#[graphql(complex)]
pub struct Post {
    pub id: ID,
    pub title: String,
    pub content: String,
    pub author_id: ID,  // Reference to User
    pub created_at: DateTime<Utc>,
}

#[ComplexObject]
impl Post {
    /// Resolve author (from User subgraph)
    async fn author(&self, ctx: &Context<'_>) -> Result<User> {
        let user_loader = ctx.data::<UserLoader>()?;
        user_loader.load_one(self.author_id.clone()).await?
            .ok_or_else(|| "Author not found".into())
    }
}
```

### 3. DataLoaders (N+1 Problem Solution)

DataLoaders batch and cache requests to prevent the N+1 query problem.

```rust
// backend/graphql-gateway/src/dataloaders/user_loader.rs
use async_graphql::dataloader::*;
use std::collections::HashMap;

pub struct UserLoader {
    user_client: UserClient,
}

impl UserLoader {
    pub fn new(user_client: UserClient) -> Self {
        Self { user_client }
    }
}

#[async_trait::async_trait]
impl Loader<ID> for UserLoader {
    type Value = User;
    type Error = Arc<anyhow::Error>;

    async fn load(&self, keys: &[ID]) -> Result<HashMap<ID, Self::Value>, Self::Error> {
        // Batch load users in single request
        let users = self.user_client.batch_get_users(keys).await
            .map_err(|e| Arc::new(e))?;

        Ok(users.into_iter().map(|u| (u.id.clone(), u)).collect())
    }
}
```

### 4. Authentication Middleware

```rust
// backend/graphql-gateway/src/middleware/auth.rs
use async_graphql::*;
use jsonwebtoken::{decode, DecodingKey, Validation};

pub struct AuthContext {
    pub user_id: Option<ID>,
    pub roles: Vec<String>,
}

impl AuthContext {
    pub fn from_token(token: &str, secret: &str) -> Result<Self> {
        let validation = Validation::default();
        let key = DecodingKey::from_secret(secret.as_bytes());
        let token_data = decode::<Claims>(token, &key, &validation)?;

        Ok(Self {
            user_id: Some(ID::from(token_data.claims.sub)),
            roles: token_data.claims.roles,
        })
    }

    pub fn require_auth(&self) -> Result<&ID> {
        self.user_id.as_ref().ok_or_else(|| "Unauthorized".into())
    }
}

/// Guard for authenticated queries
pub struct AuthGuard;

#[async_trait::async_trait]
impl Guard for AuthGuard {
    async fn check(&self, ctx: &Context<'_>) -> Result<()> {
        let auth_ctx = ctx.data::<AuthContext>()?;
        auth_ctx.require_auth()?;
        Ok(())
    }
}
```

---

## gRPC Client Integration

### Client Pool

```rust
// backend/graphql-gateway/src/clients/mod.rs
use tonic::transport::Channel;

#[derive(Clone)]
pub struct ServiceClients {
    pub auth: AuthClient,
    pub user: UserClient,
    pub content: ContentClient,
    pub messaging: MessagingClient,
    pub notification: NotificationClient,
}

impl ServiceClients {
    pub async fn new(config: &ServiceEndpoints) -> Result<Self> {
        Ok(Self {
            auth: AuthClient::connect(&config.auth_service).await?,
            user: UserClient::connect(&config.user_service).await?,
            content: ContentClient::connect(&config.content_service).await?,
            messaging: MessagingClient::connect(&config.messaging_service).await?,
            notification: NotificationClient::connect(&config.notification_service).await?,
        })
    }
}

impl Default for ServiceClients {
    fn default() -> Self {
        // Mock clients for testing
        Self {
            auth: AuthClient::mock(),
            user: UserClient::mock(),
            content: ContentClient::mock(),
            messaging: MessagingClient::mock(),
            notification: NotificationClient::mock(),
        }
    }
}
```

### Example Client Implementation

```rust
// backend/graphql-gateway/src/clients/user_client.rs
use nova_user_proto::user_service_client::UserServiceClient;
use nova_user_proto::{GetUserRequest, SearchUsersRequest};

#[derive(Clone)]
pub struct UserClient {
    inner: UserServiceClient<Channel>,
}

impl UserClient {
    pub async fn connect(endpoint: &str) -> Result<Self> {
        let client = UserServiceClient::connect(endpoint.to_string()).await?;
        Ok(Self { inner: client })
    }

    pub async fn get_user(&self, id: ID) -> Result<Option<User>> {
        let request = GetUserRequest {
            user_id: id.to_string(),
        };

        let response = self.inner.clone().get_user(request).await?;
        Ok(response.into_inner().user.map(User::from))
    }

    pub async fn batch_get_users(&self, ids: &[ID]) -> Result<Vec<User>> {
        // Use gRPC batch API
        let request = BatchGetUsersRequest {
            user_ids: ids.iter().map(|id| id.to_string()).collect(),
        };

        let response = self.inner.clone().batch_get_users(request).await?;
        Ok(response.into_inner().users.into_iter().map(User::from).collect())
    }
}
```

---

## Server Implementation

```rust
// backend/graphql-gateway/src/main.rs
use actix_web::{web, App, HttpServer, HttpRequest, HttpResponse};
use async_graphql::http::{playground_source, GraphQLPlaygroundConfig};
use async_graphql_actix_web::{GraphQLRequest, GraphQLResponse};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Load configuration
    let config = Config::from_env().expect("Failed to load config");

    // Initialize tracing
    let _tracer = opentelemetry_config::init_tracing(
        "graphql-gateway",
        TracingConfig::from_env(),
    ).ok();

    // Connect to backend services
    let clients = ServiceClients::new(&config.services)
        .await
        .expect("Failed to connect to services");

    // Build GraphQL schema
    let schema = build_schema(clients);

    // Start HTTP server
    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(schema.clone()))
            .service(web::resource("/graphql").route(web::post().to(graphql_handler)))
            .service(web::resource("/playground").route(web::get().to(graphql_playground)))
    })
    .bind((config.server.host.as_str(), config.server.port))?
    .run()
    .await
}

async fn graphql_handler(
    schema: web::Data<Schema<QueryRoot, MutationRoot, EmptySubscription>>,
    req: HttpRequest,
    gql_req: GraphQLRequest,
) -> GraphQLResponse {
    // Extract JWT token
    let auth_ctx = req.headers()
        .get("Authorization")
        .and_then(|h| h.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .and_then(|token| AuthContext::from_token(token, &config.jwt.secret).ok())
        .unwrap_or_default();

    // Execute query
    schema.execute(gql_req.into_inner().data(auth_ctx)).await.into()
}

async fn graphql_playground() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(playground_source(GraphQLPlaygroundConfig::new("/graphql")))
}
```

---

## Example Queries

### Query User with Posts

```graphql
query GetUserWithPosts($userId: ID!) {
  user(id: $userId) {
    id
    username
    displayName
    avatarUrl
    posts {
      id
      title
      content
      createdAt
    }
  }
}
```

### Cross-Service Query

```graphql
query GetFeed {
  feed(limit: 10) {
    id
    content
    createdAt
    author {
      username
      avatarUrl
    }
    comments {
      id
      content
      author {
        username
      }
    }
  }
}
```

### Mutation with Authentication

```graphql
mutation CreatePost($input: CreatePostInput!) {
  createPost(input: $input) {
    id
    title
    content
    author {
      username
    }
  }
}
```

---

## Deployment

### Kubernetes Deployment

```yaml
# k8s/microservices/graphql-gateway/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: graphql-gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: graphql-gateway
  template:
    metadata:
      labels:
        app: graphql-gateway
    spec:
      containers:
        - name: graphql-gateway
          image: nova/graphql-gateway:latest
          ports:
            - containerPort: 8080
          env:
            - name: AUTH_SERVICE_URL
              value: "http://auth-service:50051"
            - name: USER_SERVICE_URL
              value: "http://user-service:50052"
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: graphql-gateway-secrets
                  key: jwt-secret
            - name: TRACING_ENABLED
              value: "true"
            - name: OTLP_ENDPOINT
              value: "http://jaeger-collector.observability:4317"
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
```

---

## Best Practices

### 1. Use DataLoaders Everywhere

❌ **Bad** (N+1 problem):
```rust
// Queries database for each post's author
for post in posts {
    let author = user_client.get_user(post.author_id).await?;
}
```

✅ **Good** (Batched):
```rust
// Single batched request for all authors
let author_ids: Vec<_> = posts.iter().map(|p| p.author_id).collect();
let authors = user_loader.load_many(author_ids).await?;
```

### 2. Implement Query Complexity Limits

```rust
let schema = Schema::build(query, mutation, subscription)
    .limit_depth(10)           // Max 10 levels deep
    .limit_complexity(1000)     // Max 1000 complexity points
    .finish();
```

### 3. Enable Distributed Tracing

```rust
use opentelemetry_config::http_tracing_layer;

App::new()
    .wrap(http_tracing_layer())  // Trace all GraphQL requests
    .service(graphql_handler)
```

### 4. Implement Field-Level Authorization

```rust
#[Object]
impl User {
    async fn email(&self, ctx: &Context<'_>) -> Result<String> {
        let auth_ctx = ctx.data::<AuthContext>()?;
        // Only return email if user is viewing their own profile
        if auth_ctx.user_id == Some(self.id.clone()) {
            Ok(self.email.clone())
        } else {
            Err("Unauthorized".into())
        }
    }
}
```

---

## Performance Optimization

### 1. Enable Query Caching

```rust
use async_graphql::extensions::ApolloTracing;

Schema::build(query, mutation, subscription)
    .extension(ApolloTracing)  // Performance monitoring
    .enable_query_cache()       // Cache parsed queries
    .finish()
```

### 2. Connection Pooling

All gRPC clients use connection pooling by default via `tonic::transport::Channel`.

### 3. Response Compression

```rust
use actix_web::middleware::Compress;

App::new()
    .wrap(Compress::default())  // Gzip compression
    .service(graphql_handler)
```

---

## Monitoring

### GraphQL-Specific Metrics

```rust
// Track query execution time
histogram_quantile(0.99, rate(graphql_query_duration_seconds_bucket[5m]))

// Track error rate
rate(graphql_errors_total[5m])

// Track query complexity
graphql_query_complexity{operation="GetUserWithPosts"}
```

---

## Security Considerations

### 1. Query Depth Limiting

Prevents deeply nested queries that could cause DoS:

```rust
.limit_depth(10)  // Max 10 levels: user.posts.comments.author.posts...
```

### 2. Query Complexity Limiting

Prevents expensive queries:

```rust
.limit_complexity(1000)  // Each field has complexity weight
```

### 3. Disable Introspection in Production

```rust
let schema = if config.graphql.introspection {
    schema
} else {
    schema.disable_introspection()
};
```

### 4. Rate Limiting

```rust
use actix_governor::{Governor, GovernorConfigBuilder};

let governor_conf = GovernorConfigBuilder::default()
    .per_second(10)
    .burst_size(20)
    .finish()
    .unwrap();

App::new()
    .wrap(Governor::new(&governor_conf))
    .service(graphql_handler)
```

---

## Next Steps

1. **✅ Complete Implementation** - Finish all schema files and client integrations
2. **Add Subscriptions** - WebSocket support for real-time updates
3. **Implement Caching** - Redis-based query caching
4. **Add Monitoring** - Prometheus metrics for GraphQL operations
5. **Performance Testing** - Load testing with K6 or Artillery

---

## References

- async-graphql Documentation: https://async-graphql.github.io/async-graphql/
- Apollo Federation Spec: https://www.apollographql.com/docs/federation/
- GraphQL Best Practices: https://graphql.org/learn/best-practices/

---

**Document Version**: 1.0
**Last Updated**: 2025-11-09
**Status**: Architecture Complete, Implementation In Progress
