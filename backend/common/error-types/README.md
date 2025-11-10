# Nova Error Types Library

Unified error handling library for all Nova backend microservices.

## Features

- ✅ **Type Safety**: Strongly typed errors prevent runtime surprises
- ✅ **GDPR Compliant**: No PII in error messages or logs
- ✅ **gRPC Ready**: Clean mapping to gRPC status codes
- ✅ **HTTP Ready**: Standard HTTP error responses
- ✅ **Observability**: Structured logging with tracing
- ✅ **Retryable**: Built-in retry logic for transient errors

## Installation

Add to your `Cargo.toml`:

```toml
[dependencies]
error-types = { path = "../common/error-types" }

# With sqlx support
error-types = { path = "../common/error-types", features = ["sqlx"] }
```

## Usage

### Basic Service Errors

```rust
use error_types::{ServiceError, ServiceResult};

fn get_user(id: Uuid) -> ServiceResult<User> {
    let user = db.find_user(id)
        .await
        .map_err(|_| ServiceError::NotFound {
            resource: "user",
            id: id.to_string(),
        })?;

    Ok(user)
}
```

### Using Error Context

```rust
use error_types::ErrorContext;

fn load_config() -> ServiceResult<Config> {
    std::fs::read_to_string("config.toml")
        .context("Failed to read config file")?
        .parse()
        .context("Failed to parse config")?
}
```

### Validation Errors

```rust
use error_types::{ValidationError, ValidationErrorBuilder};
use error_types::validation::rules;

fn validate_user_input(input: &UserInput) -> Result<(), ValidationError> {
    let mut error = ValidationError::new("User validation failed");

    // Validate email
    if let Err(e) = rules::validate_email(&input.email) {
        error = error.add_field_error("email", "invalid_format", "Invalid email format");
    }

    // Validate age
    if let Err(e) = rules::validate_range("age", input.age, Some(18), Some(120)) {
        error = error.add_field_error("age", "out_of_range", "Age must be between 18 and 120");
    }

    if error.has_errors() {
        return Err(error);
    }

    Ok(())
}
```

### Database Errors

```rust
use error_types::{DatabaseError, ServiceError};

async fn handle_database_operation() -> ServiceResult<()> {
    match db.execute(query).await {
        Err(e) => {
            let db_error = DatabaseError::from(e);

            // Check if retryable
            if db_error.is_retryable() {
                if let Some(delay) = db_error.retry_delay() {
                    tokio::time::sleep(delay).await;
                    // Retry operation
                }
            }

            Err(ServiceError::Database { source: db_error })
        }
        Ok(result) => Ok(result)
    }
}
```

### Authentication Errors

```rust
use error_types::{AuthError, PermissionCheck};

fn check_permissions(user: &User, required: Vec<&str>) -> Result<(), AuthError> {
    PermissionCheck::new()
        .require_all(required)
        .with_actual(user.permissions.iter().map(|s| s.as_str()))
        .check()
}

fn handle_auth_error(error: AuthError) {
    // Log without PII
    error.log();

    // Get safe client message
    let client_msg = error.client_message();

    // Check if retryable
    if let Some(retry_after) = error.retry_after() {
        // Handle rate limiting
    }
}
```

### gRPC Integration

```rust
use error_types::{ServiceError, grpc};
use tonic::{Request, Response, Status};

#[tonic::async_trait]
impl UserService for UserServiceImpl {
    async fn get_user(
        &self,
        request: Request<GetUserRequest>,
    ) -> Result<Response<User>, Status> {
        let user_id = Uuid::parse_str(&request.into_inner().id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        self.get_user_internal(user_id)
            .await
            .map(Response::new)
            .map_err(|e| e.to_status())  // Automatic conversion
    }
}
```

### HTTP API Integration

```rust
use error_types::{ServiceError, http::HttpErrorResponse};
use actix_web::{web, HttpResponse};

async fn get_user_handler(
    path: web::Path<String>,
) -> Result<HttpResponse, HttpResponse> {
    let user_id = Uuid::parse_str(&path.into_inner())
        .map_err(|_| {
            HttpResponse::BadRequest().json(
                HttpErrorResponse::new(400, "INVALID_ID", "Invalid user ID")
            )
        })?;

    let user = get_user(user_id)
        .await
        .map_err(|e| {
            let error_response: HttpErrorResponse = e.into();
            HttpResponse::build(
                actix_web::http::StatusCode::from_u16(error_response.status).unwrap()
            ).json(error_response)
        })?;

    Ok(HttpResponse::Ok().json(user))
}
```

## Error Types Reference

### ServiceError

Main error type for service operations:

- `NotFound` - Resource not found
- `InvalidInput` - Invalid input data
- `Unauthenticated` - Authentication required
- `PermissionDenied` - Insufficient permissions
- `Database` - Database operation failed
- `Validation` - Validation failed
- `ExternalService` - External service error
- `RateLimitExceeded` - Rate limit hit
- `Internal` - Internal server error
- `Conflict` - Resource conflict
- `Timeout` - Operation timeout
- `CircuitBreakerOpen` - Service unavailable

### DatabaseError

Database-specific errors:

- `PoolExhausted` - Connection pool full
- `ConnectionTimeout` - Connection timeout
- `QueryTimeout` - Query timeout
- `Deadlock` - Deadlock detected
- `ForeignKeyViolation` - FK constraint violated
- `UniqueViolation` - Unique constraint violated
- `CheckViolation` - Check constraint violated
- `NotNullViolation` - Not null constraint violated

### AuthError

Authentication/authorization errors:

- `MissingCredentials` - No credentials provided
- `InvalidCredentials` - Wrong credentials
- `TokenExpired` - JWT/session expired
- `InvalidTokenFormat` - Malformed token
- `AccountLocked` - Account temporarily locked
- `TwoFactorRequired` - 2FA needed
- `InsufficientPermissions` - Missing permissions

## Best Practices

1. **Always use context** for I/O operations:
   ```rust
   file.read_to_string()
       .context("Failed to read user data file")?;
   ```

2. **Never expose PII** in error messages:
   ```rust
   // ❌ BAD
   ServiceError::NotFound {
       resource: "user",
       id: user_email,  // PII!
   }

   // ✅ GOOD
   ServiceError::NotFound {
       resource: "user",
       id: user_id.to_string(),  // UUID is safe
   }
   ```

3. **Log errors appropriately**:
   ```rust
   match process_request().await {
       Err(e) => {
           e.log();  // Automatic level selection
           e.to_status()  // Clean client response
       }
       Ok(result) => Ok(result)
   }
   ```

4. **Handle retryable errors**:
   ```rust
   if let ServiceError::Database { source } = &error {
       if source.is_retryable() {
           // Implement retry logic
       }
   }
   ```

## Migration Guide

### From String Errors

Before:
```rust
fn get_user(id: Uuid) -> Result<User, String> {
    db.find_user(id)
        .map_err(|e| format!("Failed to find user: {}", e))
}
```

After:
```rust
use error_types::{ServiceError, ServiceResult};

fn get_user(id: Uuid) -> ServiceResult<User> {
    db.find_user(id)
        .map_err(|_| ServiceError::NotFound {
            resource: "user",
            id: id.to_string(),
        })
}
```

### From anyhow

Before:
```rust
use anyhow::{Context, Result};

fn load_config() -> Result<Config> {
    let content = std::fs::read_to_string("config.toml")
        .context("Failed to read config")?;
    Ok(toml::from_str(&content)?)
}
```

After:
```rust
use error_types::{ServiceResult, ErrorContext};

fn load_config() -> ServiceResult<Config> {
    let content = std::fs::read_to_string("config.toml")
        .context("Failed to read config")?;
    toml::from_str(&content)
        .context("Failed to parse config")
}
```

## Testing

```rust
#[cfg(test)]
mod tests {
    use error_types::{ServiceError, ValidationError};

    #[test]
    fn test_error_conversion() {
        let error = ServiceError::NotFound {
            resource: "user",
            id: "123".to_string(),
        };

        let status = error.to_status();
        assert_eq!(status.code(), tonic::Code::NotFound);
    }

    #[test]
    fn test_no_pii_in_errors() {
        let error = ServiceError::NotFound {
            resource: "user",
            id: "user@example.com".to_string(),
        };

        // The display message should not contain PII
        let message = error.to_string();
        assert!(!message.contains("user@example.com"));
    }
}
```

## Performance Considerations

- Error creation is cheap (no heap allocations for most variants)
- Context adds minimal overhead (single string allocation)
- Retry delays are computed lazily
- Field violations are stored efficiently in HashMap

## Future Enhancements

- [ ] Telemetry integration (OpenTelemetry)
- [ ] Error recovery strategies
- [ ] Circuit breaker patterns
- [ ] Distributed tracing context
- [ ] Error budget tracking