---
name: database-optimization
description: Master PostgreSQL optimization techniques including indexing strategies, query optimization, and connection pooling for Rust applications. Use when troubleshooting slow queries, designing schemas, or optimizing database performance.
---

# Database Optimization Patterns

Essential PostgreSQL optimization techniques for high-performance Rust applications.

## When to Use This Skill

- Troubleshooting slow queries
- Designing efficient schemas
- Optimizing query performance
- Configuring connection pools
- Preventing N+1 queries
- Implementing caching strategies

## Core Optimization Patterns

### Pattern 1: Efficient Indexing

```sql
-- Single column index
CREATE INDEX idx_users_email ON users(email);

-- Composite index (order matters!)
CREATE INDEX idx_posts_user_created
ON posts(user_id, created_at DESC);

-- Partial index for common queries
CREATE INDEX idx_posts_published
ON posts(created_at DESC)
WHERE status = 'published';

-- Covering index (INCLUDE clause)
CREATE INDEX idx_users_email_covering
ON users(email) INCLUDE (name, created_at);

-- Full-text search index
CREATE INDEX idx_posts_search
ON posts USING GIN(to_tsvector('english', title || ' ' || content));
```

**Query Usage:**
```rust
// Uses idx_posts_user_created
let posts = sqlx::query_as!(
    Post,
    "SELECT * FROM posts
     WHERE user_id = $1
     ORDER BY created_at DESC
     LIMIT 20",
    user_id
)
.fetch_all(&pool)
.await?;
```

### Pattern 2: Query Optimization

**Avoid N+1 Queries:**
```rust
// ❌ BAD: N+1 query
let posts = sqlx::query_as!(Post, "SELECT * FROM posts")
    .fetch_all(&pool)
    .await?;

for post in &posts {
    let user = sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", post.user_id)
        .fetch_one(&pool)
        .await?;
    // Use user...
}

// ✅ GOOD: Single query with JOIN
let posts_with_users = sqlx::query_as!(
    PostWithUser,
    r#"
    SELECT
        p.*,
        u.id as "user_id!",
        u.name as "user_name!"
    FROM posts p
    INNER JOIN users u ON p.user_id = u.id
    "#
)
.fetch_all(&pool)
.await?;

// ✅ ALSO GOOD: Batch query
let user_ids: Vec<i64> = posts.iter().map(|p| p.user_id).collect();
let users = sqlx::query_as!(
    User,
    "SELECT * FROM users WHERE id = ANY($1)",
    &user_ids
)
.fetch_all(&pool)
.await?;
```

**Use EXPLAIN ANALYZE:**
```sql
EXPLAIN ANALYZE
SELECT * FROM posts
WHERE user_id = 123
ORDER BY created_at DESC
LIMIT 20;

/*
Output:
Limit  (cost=0.42..16.73 rows=20 width=500) (actual time=0.025..0.050 rows=20 loops=1)
  ->  Index Scan using idx_posts_user_created on posts
      (cost=0.42..489.67 rows=600 width=500)
      (actual time=0.024..0.045 rows=20 loops=1)
      Index Cond: (user_id = 123)
Planning Time: 0.123 ms
Execution Time: 0.067 ms
*/
```

### Pattern 3: Connection Pool Configuration

```rust
use sqlx::postgres::PgPoolOptions;
use std::time::Duration;

async fn create_optimized_pool(database_url: &str) -> Result<PgPool> {
    let pool = PgPoolOptions::new()
        // Pool sizing formula: connections = (core_count * 2) + effective_spindle_count
        .max_connections(50)       // Based on load testing
        .min_connections(5)        // Keep connections warm

        // Timeouts
        .connect_timeout(Duration::from_secs(5))
        .acquire_timeout(Duration::from_secs(10))
        .idle_timeout(Duration::from_secs(300))  // 5 minutes
        .max_lifetime(Duration::from_secs(1800)) // 30 minutes

        // Connection health
        .test_before_acquire(true)

        .connect(database_url)
        .await?;

    Ok(pool)
}
```

### Pattern 4: Batch Operations

```rust
// ❌ BAD: Individual inserts
for user in users {
    sqlx::query!("INSERT INTO users (email, name) VALUES ($1, $2)", user.email, user.name)
        .execute(&pool)
        .await?;
}

// ✅ GOOD: Batch insert
let mut query_builder = QueryBuilder::new("INSERT INTO users (email, name) ");

query_builder.push_values(users, |mut b, user| {
    b.push_bind(user.email)
     .push_bind(user.name);
});

query_builder.build().execute(&pool).await?;

// ✅ ALSO GOOD: Use UNNEST for large batches
sqlx::query!(
    r#"
    INSERT INTO users (email, name)
    SELECT * FROM UNNEST($1::text[], $2::text[])
    "#,
    &emails,
    &names
)
.execute(&pool)
.await?;
```

### Pattern 5: Caching Strategy

```rust
use redis::AsyncCommands;

pub async fn get_user_cached(
    user_id: i64,
    pool: &PgPool,
    redis: &mut redis::aio::Connection,
) -> Result<User> {
    let cache_key = format!("user:{}", user_id);

    // Try cache first
    if let Ok(Some(cached)) = redis.get::<_, Option<String>>(&cache_key).await {
        if let Ok(user) = serde_json::from_str(&cached) {
            return Ok(user);
        }
    }

    // Cache miss: fetch from database
    let user = sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", user_id)
        .fetch_one(pool)
        .await?;

    // Update cache (fire-and-forget)
    let cached = serde_json::to_string(&user)?;
    let _: () = redis.set_ex(&cache_key, cached, 300).await?; // 5 min TTL

    Ok(user)
}
```

### Pattern 6: Transaction Management

```rust
// Simple transaction
pub async fn transfer_funds(
    from_user: i64,
    to_user: i64,
    amount: i64,
    pool: &PgPool,
) -> Result<()> {
    let mut tx = pool.begin().await?;

    // Debit
    sqlx::query!(
        "UPDATE accounts SET balance = balance - $1 WHERE user_id = $2",
        amount,
        from_user
    )
    .execute(&mut tx)
    .await?;

    // Credit
    sqlx::query!(
        "UPDATE accounts SET balance = balance + $1 WHERE user_id = $2",
        amount,
        to_user
    )
    .execute(&mut tx)
    .await?;

    tx.commit().await?;
    Ok(())
}

// With rollback on error
pub async fn create_post_with_tags(
    post: NewPost,
    tags: Vec<String>,
    pool: &PgPool,
) -> Result<Post> {
    let mut tx = pool.begin().await?;

    let post = sqlx::query_as!(
        Post,
        "INSERT INTO posts (title, content, user_id) VALUES ($1, $2, $3) RETURNING *",
        post.title,
        post.content,
        post.user_id
    )
    .fetch_one(&mut tx)
    .await?;

    for tag in tags {
        sqlx::query!(
            "INSERT INTO post_tags (post_id, tag) VALUES ($1, $2)",
            post.id,
            tag
        )
        .execute(&mut tx)
        .await?;
    }

    tx.commit().await?;
    Ok(post)
}
```

## Performance Monitoring

**Identify Slow Queries:**
```sql
-- Enable query logging
ALTER DATABASE mydb SET log_min_duration_statement = 100; -- Log queries > 100ms

-- Find slow queries
SELECT
    query,
    calls,
    total_time,
    mean_time,
    max_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 20;

-- Index usage statistics
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE idx_scan = 0  -- Unused indexes
ORDER BY tablename;
```

## Best Practices

1. **Index frequently queried columns** (WHERE, JOIN, ORDER BY)
2. **Use composite indexes** for multi-column queries
3. **Avoid SELECT *** - specify needed columns
4. **Use connection pooling** - never create connections per request
5. **Implement caching** for read-heavy workloads
6. **Batch operations** when possible
7. **Monitor slow queries** with pg_stat_statements
8. **Use transactions** for multi-step operations
9. **Analyze query plans** with EXPLAIN ANALYZE
10. **Vacuum regularly** - enable auto-vacuum

## Connection Pool Sizing

```
Optimal connections = (core_count * 2) + effective_spindle_count

For a 4-core server with SSD:
connections = (4 * 2) + 1 = 9

Add buffer for spikes: 15-20 connections
```

## Common Pitfalls

### ❌ Too Many Connections
```rust
// BAD: Creating pool per request
async fn handler() -> Result<Response> {
    let pool = PgPool::connect(&url).await?; // Creates new pool!
    // ...
}

// GOOD: Share pool across app
struct AppState {
    pool: PgPool,
}
```

### ❌ Missing Indexes
```sql
-- This will be slow without index on user_id
SELECT * FROM posts WHERE user_id = 123;

-- Add index
CREATE INDEX idx_posts_user_id ON posts(user_id);
```

## Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Use The Index, Luke!](https://use-the-index-luke.com/)
- [SQLx Documentation](https://docs.rs/sqlx)
