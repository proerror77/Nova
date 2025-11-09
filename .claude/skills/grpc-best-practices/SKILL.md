---
name: grpc-best-practices
description: Master gRPC service design with Tonic and Protocol Buffers for production-grade Rust microservices. Use when designing .proto schemas, implementing gRPC services, or optimizing service communication.
---

# gRPC Best Practices

Essential patterns for building robust gRPC services with Tonic in Rust.

## When to Use This Skill

- Designing Protocol Buffer schemas
- Implementing gRPC service handlers
- Creating service clients with retry logic
- Optimizing service-to-service communication
- Implementing streaming patterns
- Adding authentication and observability

## Core Patterns

### Pattern 1: Proto Schema Design

**Well-Designed Service:**
```protobuf
syntax = "proto3";

package user.v1;

service UserService {
  // Use descriptive RPC names
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
  rpc ListUsers(ListUsersRequest) returns (ListUsersResponse);
  rpc CreateUser(CreateUserRequest) returns (CreateUserResponse);

  // Server streaming for large datasets
  rpc StreamUsers(StreamUsersRequest) returns (stream User);

  // Bidirectional streaming for real-time
  rpc Chat(stream ChatMessage) returns (stream ChatMessage);
}

message GetUserRequest {
  int64 user_id = 1;
}

message GetUserResponse {
  User user = 1;
}

message User {
  int64 id = 1;
  string email = 2;
  string name = 3;
  google.protobuf.Timestamp created_at = 4;
}
```

### Pattern 2: Tonic Server Implementation

```rust
use tonic::{Request, Response, Status};
use user::user_service_server::{UserService, UserServiceServer};

pub struct UserServiceImpl {
    pool: PgPool,
}

#[tonic::async_trait]
impl UserService for UserServiceImpl {
    async fn get_user(
        &self,
        request: Request<GetUserRequest>,
    ) -> Result<Response<GetUserResponse>, Status> {
        let user_id = request.into_inner().user_id;

        let user = sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", user_id)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| Status::internal(format!("Database error: {}", e)))?
            .ok_or_else(|| Status::not_found("User not found"))?;

        Ok(Response::new(GetUserResponse { user: Some(user) }))
    }
}

// Server setup
#[tokio::main]
async fn main() -> Result<()> {
    let addr = "0.0.0.0:50051".parse()?;
    let service = UserServiceImpl { pool };

    Server::builder()
        .add_service(UserServiceServer::new(service))
        .serve(addr)
        .await?;

    Ok(())
}
```

### Pattern 3: Authentication Interceptor

```rust
use tonic::service::Interceptor;
use tonic::{Request, Status};

#[derive(Clone)]
pub struct AuthInterceptor {
    jwt_secret: String,
}

impl Interceptor for AuthInterceptor {
    fn call(&mut self, mut req: Request<()>) -> Result<Request<()>, Status> {
        let token = req
            .metadata()
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.strip_prefix("Bearer "))
            .ok_or_else(|| Status::unauthenticated("Missing authorization token"))?;

        let claims = verify_jwt(token, &self.jwt_secret)
            .map_err(|_| Status::unauthenticated("Invalid token"))?;

        // Inject user ID into request extensions
        req.extensions_mut().insert(claims.user_id);

        Ok(req)
    }
}

// Usage
Server::builder()
    .add_service(
        UserServiceServer::with_interceptor(service, AuthInterceptor { jwt_secret })
    )
    .serve(addr)
    .await?;
```

### Pattern 4: Client with Retry Logic

```rust
use tonic::transport::{Channel, Endpoint};
use tower::ServiceBuilder;
use tower::retry::RetryLayer;
use std::time::Duration;

pub async fn create_user_client() -> Result<UserServiceClient<Channel>> {
    let endpoint = Endpoint::from_static("http://user-service:50051")
        .timeout(Duration::from_secs(5))
        .connect_timeout(Duration::from_secs(2))
        .tcp_keepalive(Some(Duration::from_secs(30)));

    let channel = endpoint.connect().await?;

    let client = UserServiceClient::new(channel);

    Ok(client)
}

// With retry
use tower::retry::Policy;

pub struct RetryPolicy;

impl<E> Policy<Request<()>, Response<()>, E> for RetryPolicy {
    type Future = futures::future::Ready<Self>;

    fn retry(&self, _: &Request<()>, result: Result<&Response<()>, &E>) -> Option<Self::Future> {
        match result {
            Ok(_) => None,
            Err(_) => Some(futures::future::ready(RetryPolicy)),
        }
    }

    fn clone_request(&self, req: &Request<()>) -> Option<Request<()>> {
        Some(Request::new(()))
    }
}
```

### Pattern 5: Server Streaming

```rust
use tokio_stream::wrappers::ReceiverStream;

#[tonic::async_trait]
impl UserService for UserServiceImpl {
    type StreamUsersStream = ReceiverStream<Result<User, Status>>;

    async fn stream_users(
        &self,
        request: Request<StreamUsersRequest>,
    ) -> Result<Response<Self::StreamUsersStream>, Status> {
        let (tx, rx) = tokio::sync::mpsc::channel(100);

        let pool = self.pool.clone();

        tokio::spawn(async move {
            let mut stream = sqlx::query_as!(User, "SELECT * FROM users")
                .fetch(&pool);

            while let Some(result) = stream.next().await {
                match result {
                    Ok(user) => {
                        if tx.send(Ok(user)).await.is_err() {
                            break; // Client disconnected
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Err(Status::internal(e.to_string()))).await;
                        break;
                    }
                }
            }
        });

        Ok(Response::new(ReceiverStream::new(rx)))
    }
}
```

## Best Practices

1. **Use versioned packages** - `package user.v1`
2. **Include timestamps** - Use `google.protobuf.Timestamp`
3. **Design for evolution** - Add fields with new numbers
4. **Use streaming for large data** - Server/client streaming
5. **Implement health checks** - `tonic::health` for K8s probes
6. **Add request tracing** - OpenTelemetry integration
7. **Set timeouts** - Client and server-side timeouts
8. **Implement retries** - Exponential backoff with jitter
9. **Use interceptors** - Auth, logging, metrics
10. **Handle errors properly** - Map to appropriate Status codes

## Common Status Codes

| Code | Use Case |
|------|----------|
| `OK` | Success |
| `INVALID_ARGUMENT` | Client error, bad request data |
| `NOT_FOUND` | Resource doesn't exist |
| `ALREADY_EXISTS` | Duplicate resource |
| `PERMISSION_DENIED` | Unauthorized |
| `UNAUTHENTICATED` | Missing/invalid credentials |
| `INTERNAL` | Server error |
| `UNAVAILABLE` | Service temporarily unavailable |
| `DEADLINE_EXCEEDED` | Request timeout |

## Resources

- [Tonic Documentation](https://docs.rs/tonic)
- [gRPC Best Practices](https://grpc.io/docs/guides/performance/)
- [Protocol Buffers Guide](https://developers.google.com/protocol-buffers/docs/proto3)
