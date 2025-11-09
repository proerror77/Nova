---
name: rust-async-patterns
description: Master Rust async/await patterns with Tokio runtime for building high-performance, non-blocking microservices. Use when implementing async handlers, managing concurrent tasks, or optimizing I/O-bound operations.
---

# Rust Async Patterns

Comprehensive guide to async programming in Rust using Tokio for building production-grade microservices.

## When to Use This Skill

- Implementing async HTTP/gRPC handlers
- Managing concurrent database operations
- Building non-blocking I/O pipelines
- Optimizing service throughput and latency
- Handling thousands of concurrent connections
- Implementing real-time features (WebSocket, streaming)

## Core Concepts

### 1. Tokio Runtime

The Tokio runtime is the foundation of async Rust applications.

**Multi-threaded Runtime:**
```rust
#[tokio::main]
async fn main() {
    // Tokio automatically creates a multi-threaded runtime
    println!("Workers: {}", num_cpus::get());
}
```

**Custom Configuration:**
```rust
use tokio::runtime::Runtime;

fn main() {
    let runtime = Runtime::new().unwrap();

    runtime.block_on(async {
        // Async code here
    });
}

// Or with custom worker threads
let runtime = tokio::runtime::Builder::new_multi_thread()
    .worker_threads(4)
    .thread_name("my-service")
    .enable_all()
    .build()
    .unwrap();
```

### 2. Async/Await Fundamentals

**Basic Async Function:**
```rust
async fn fetch_user(user_id: i64) -> Result<User, Error> {
    let user = sqlx::query_as!(
        User,
        "SELECT * FROM users WHERE id = $1",
        user_id
    )
    .fetch_one(&pool)
    .await?;

    Ok(user)
}
```

**Concurrent Execution:**
```rust
use tokio::join;

async fn get_user_data(user_id: i64) -> Result<UserData, Error> {
    // Execute in parallel
    let (user, posts, followers) = tokio::join!(
        fetch_user(user_id),
        fetch_user_posts(user_id),
        fetch_followers(user_id)
    );

    Ok(UserData {
        user: user?,
        posts: posts?,
        followers: followers?,
    })
}
```

### 3. Error Handling Patterns

**Using anyhow for Application Errors:**
```rust
use anyhow::{Context, Result};

async fn process_order(order_id: i64) -> Result<Order> {
    let order = fetch_order(order_id)
        .await
        .context("Failed to fetch order")?;

    validate_order(&order)
        .context("Order validation failed")?;

    save_order(&order)
        .await
        .context("Failed to save order")?;

    Ok(order)
}
```

**Using thiserror for Domain Errors:**
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ServiceError {
    #[error("User not found: {0}")]
    UserNotFound(i64),

    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Unauthorized access")]
    Unauthorized,
}

async fn get_user(id: i64) -> Result<User, ServiceError> {
    sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", id)
        .fetch_optional(&pool)
        .await?
        .ok_or(ServiceError::UserNotFound(id))
}
```

## Advanced Patterns

### Pattern 1: Connection Pooling

**SQLx Pool Configuration:**
```rust
use sqlx::postgres::PgPoolOptions;
use std::time::Duration;

async fn create_pool(database_url: &str) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(50)                    // Maximum connections
        .min_connections(5)                     // Minimum idle connections
        .connect_timeout(Duration::from_secs(5)) // Connection timeout
        .idle_timeout(Duration::from_secs(300))  // Idle connection timeout
        .acquire_timeout(Duration::from_secs(10)) // Acquire timeout
        .max_lifetime(Duration::from_secs(1800)) // Max connection lifetime
        .connect(database_url)
        .await
}
```

**Redis Pool with deadpool:**
```rust
use deadpool_redis::{Config, Runtime};

fn create_redis_pool(redis_url: &str) -> Result<deadpool_redis::Pool> {
    let cfg = Config::from_url(redis_url);
    cfg.create_pool(Some(Runtime::Tokio1))
}

async fn get_cached_user(
    pool: &deadpool_redis::Pool,
    user_id: i64,
) -> Result<Option<User>> {
    let mut conn = pool.get().await?;
    let key = format!("user:{}", user_id);

    let cached: Option<String> = redis::cmd("GET")
        .arg(&key)
        .query_async(&mut conn)
        .await?;

    Ok(cached.and_then(|s| serde_json::from_str(&s).ok()))
}
```

### Pattern 2: Graceful Shutdown

```rust
use tokio::signal;
use tokio::sync::broadcast;

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("Failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    tracing::info!("Shutdown signal received, starting graceful shutdown");
}

#[tokio::main]
async fn main() -> Result<()> {
    let (shutdown_tx, _) = broadcast::channel(1);

    // Start server
    let server = tokio::spawn(async move {
        // Server logic
    });

    // Wait for shutdown signal
    shutdown_signal().await;

    // Notify all tasks to shutdown
    let _ = shutdown_tx.send(());

    // Wait for server to finish
    server.await??;

    tracing::info!("Graceful shutdown complete");
    Ok(())
}
```

### Pattern 3: Task Spawning and Management

**Spawning Background Tasks:**
```rust
use tokio::task::JoinHandle;

async fn process_events(mut rx: tokio::sync::mpsc::Receiver<Event>) {
    while let Some(event) = rx.recv().await {
        tokio::spawn(async move {
            if let Err(e) = handle_event(event).await {
                tracing::error!("Failed to handle event: {}", e);
            }
        });
    }
}
```

**Task with Timeout:**
```rust
use tokio::time::{timeout, Duration};

async fn fetch_with_timeout(url: &str) -> Result<String> {
    let future = reqwest::get(url);

    match timeout(Duration::from_secs(5), future).await {
        Ok(Ok(response)) => Ok(response.text().await?),
        Ok(Err(e)) => Err(e.into()),
        Err(_) => Err(anyhow::anyhow!("Request timed out")),
    }
}
```

### Pattern 4: Channels for Communication

**MPSC Channel (Multiple Producer, Single Consumer):**
```rust
use tokio::sync::mpsc;

#[derive(Debug)]
struct WorkItem {
    id: u64,
    data: String,
}

async fn worker_pool() -> Result<()> {
    let (tx, mut rx) = mpsc::channel::<WorkItem>(100);

    // Spawn workers
    for i in 0..4 {
        let mut rx_clone = rx.clone();
        tokio::spawn(async move {
            while let Some(item) = rx_clone.recv().await {
                tracing::info!("Worker {} processing item {}", i, item.id);
                // Process item
            }
        });
    }

    // Producer
    for id in 0..1000 {
        tx.send(WorkItem {
            id,
            data: format!("data-{}", id),
        })
        .await?;
    }

    Ok(())
}
```

**Broadcast Channel:**
```rust
use tokio::sync::broadcast;

async fn broadcast_events() {
    let (tx, _rx) = broadcast::channel(16);

    // Subscriber 1
    let mut rx1 = tx.subscribe();
    tokio::spawn(async move {
        while let Ok(msg) = rx1.recv().await {
            println!("Subscriber 1 received: {}", msg);
        }
    });

    // Subscriber 2
    let mut rx2 = tx.subscribe();
    tokio::spawn(async move {
        while let Ok(msg) = rx2.recv().await {
            println!("Subscriber 2 received: {}", msg);
        }
    });

    // Broadcast messages
    tx.send("Hello".to_string()).unwrap();
}
```

### Pattern 5: Semaphore for Rate Limiting

```rust
use tokio::sync::Semaphore;
use std::sync::Arc;

async fn rate_limited_requests(urls: Vec<String>) -> Result<Vec<String>> {
    let semaphore = Arc::new(Semaphore::new(5)); // Max 5 concurrent requests
    let mut handles = vec![];

    for url in urls {
        let permit = semaphore.clone().acquire_owned().await?;

        let handle = tokio::spawn(async move {
            let result = reqwest::get(&url).await?.text().await;
            drop(permit); // Release permit
            result
        });

        handles.push(handle);
    }

    // Wait for all requests
    let mut results = vec![];
    for handle in handles {
        results.push(handle.await??);
    }

    Ok(results)
}
```

### Pattern 6: Select for Racing Futures

```rust
use tokio::time::{sleep, Duration};

async fn fetch_with_fallback(primary_url: &str, fallback_url: &str) -> Result<String> {
    tokio::select! {
        result = reqwest::get(primary_url) => {
            Ok(result?.text().await?)
        }
        _ = sleep(Duration::from_secs(2)) => {
            // Primary timed out, try fallback
            Ok(reqwest::get(fallback_url).await?.text().await?)
        }
    }
}
```

## Production Patterns

### Pattern 7: Circuit Breaker

```rust
use std::sync::Arc;
use tokio::sync::RwLock;
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
enum CircuitState {
    Closed,
    Open { opened_at: Instant },
    HalfOpen,
}

struct CircuitBreaker {
    state: Arc<RwLock<CircuitState>>,
    failure_threshold: u32,
    reset_timeout: Duration,
    failures: Arc<RwLock<u32>>,
}

impl CircuitBreaker {
    pub fn new(failure_threshold: u32, reset_timeout: Duration) -> Self {
        Self {
            state: Arc::new(RwLock::new(CircuitState::Closed)),
            failure_threshold,
            reset_timeout,
            failures: Arc::new(RwLock::new(0)),
        }
    }

    pub async fn call<F, Fut, T>(&self, f: F) -> Result<T, anyhow::Error>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<T, anyhow::Error>>,
    {
        // Check circuit state
        let state = self.state.read().await.clone();

        match state {
            CircuitState::Open { opened_at } => {
                if opened_at.elapsed() > self.reset_timeout {
                    // Try half-open
                    *self.state.write().await = CircuitState::HalfOpen;
                } else {
                    return Err(anyhow::anyhow!("Circuit breaker is open"));
                }
            }
            _ => {}
        }

        // Execute function
        match f().await {
            Ok(result) => {
                // Reset on success
                *self.failures.write().await = 0;
                *self.state.write().await = CircuitState::Closed;
                Ok(result)
            }
            Err(e) => {
                // Increment failures
                let mut failures = self.failures.write().await;
                *failures += 1;

                if *failures >= self.failure_threshold {
                    *self.state.write().await = CircuitState::Open {
                        opened_at: Instant::now(),
                    };
                }

                Err(e)
            }
        }
    }
}
```

### Pattern 8: Retry with Exponential Backoff

```rust
use tokio::time::{sleep, Duration};

async fn retry_with_backoff<F, Fut, T>(
    mut f: F,
    max_retries: u32,
    base_delay: Duration,
) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
{
    let mut attempt = 0;

    loop {
        match f().await {
            Ok(result) => return Ok(result),
            Err(e) if attempt >= max_retries => return Err(e),
            Err(e) => {
                let delay = base_delay * 2u32.pow(attempt);
                tracing::warn!(
                    "Attempt {} failed: {}. Retrying in {:?}",
                    attempt + 1,
                    e,
                    delay
                );
                sleep(delay).await;
                attempt += 1;
            }
        }
    }
}

// Usage
let result = retry_with_backoff(
    || async { fetch_user(123).await },
    3,
    Duration::from_millis(100),
)
.await?;
```

## Best Practices

1. **Always use `.await?` for error propagation** - Don't unwrap in production code
2. **Configure connection pools properly** - Match your workload characteristics
3. **Implement graceful shutdown** - Handle SIGTERM for zero-downtime deployments
4. **Use timeouts for all external calls** - Prevent hanging operations
5. **Spawn blocking tasks correctly** - Use `tokio::task::spawn_blocking` for CPU-intensive work
6. **Monitor async runtime** - Use tokio-console for debugging
7. **Batch database operations** - Reduce round trips with batch queries
8. **Use structured logging** - tracing crate with correlation IDs
9. **Implement circuit breakers** - Protect against cascading failures
10. **Test async code properly** - Use `#[tokio::test]` and mock async traits

## Common Pitfalls

### ❌ Blocking the Runtime

```rust
// BAD: Blocks async runtime
async fn bad_example() {
    std::thread::sleep(Duration::from_secs(1)); // Blocks!
}

// GOOD: Non-blocking sleep
async fn good_example() {
    tokio::time::sleep(Duration::from_secs(1)).await;
}
```

### ❌ Holding Locks Across Await Points

```rust
// BAD: Holds lock across await
async fn bad_mutex() {
    let data = mutex.lock().await;
    some_async_operation().await; // Lock still held!
}

// GOOD: Release lock before await
async fn good_mutex() {
    let value = {
        let data = mutex.lock().await;
        data.clone()
    }; // Lock released
    some_async_operation().await;
}
```

### ❌ Unbounded Task Spawning

```rust
// BAD: Can spawn unlimited tasks
for item in huge_list {
    tokio::spawn(process(item));
}

// GOOD: Use semaphore for backpressure
let sem = Arc::new(Semaphore::new(100));
for item in huge_list {
    let permit = sem.clone().acquire_owned().await?;
    tokio::spawn(async move {
        process(item).await;
        drop(permit);
    });
}
```

## Resources

- [Tokio Documentation](https://tokio.rs)
- [Async Book](https://rust-lang.github.io/async-book/)
- [tokio-console](https://github.com/tokio-rs/console) - Runtime debugger
- [cargo-flamegraph](https://github.com/flamegraph-rs/flamegraph) - Profiling
