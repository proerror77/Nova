#!/bin/bash

# Script to find and help fix unwrap() calls in Rust code
# Based on Codex P0 security recommendation

echo "🔍 Scanning for unwrap() calls in I/O and network paths..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Find all Rust files
RUST_FILES=$(find . -name "*.rs" -type f | grep -v target | grep -v .git)

# Count total unwrap calls
TOTAL_UNWRAPS=$(grep -h "\.unwrap()" $RUST_FILES | wc -l)
echo -e "${YELLOW}Total unwrap() calls found: $TOTAL_UNWRAPS${NC}"

# Find unwrap calls in critical paths
echo -e "\n${RED}Critical unwrap() calls in I/O paths:${NC}"
grep -n "\.unwrap()" $RUST_FILES | grep -E "(db\.|pool\.|client\.|redis\.|kafka\.|grpc\.|http\.|file\.|fs::|tokio::|sqlx::|tonic::|actix)" | head -20

# Find unwrap calls after await
echo -e "\n${RED}Unwrap calls after async operations:${NC}"
grep -n "\.await.*\.unwrap()" $RUST_FILES | head -20

# Generate fix suggestions
echo -e "\n${GREEN}Suggested fixes:${NC}"
echo "1. Replace .unwrap() with .context()? for anyhow Results"
echo "2. Replace .unwrap() with .ok_or_else()? for Options"
echo "3. Use .expect() with descriptive message for initialization"
echo "4. Add proper error handling with thiserror"

# Create a sample fix file
cat > fix_unwrap_examples.md << 'EOF'
# Unwrap Fix Examples

## Database Operations
```rust
// ❌ BAD: Panics on connection failure
let pool = PgPool::connect(&url).await.unwrap();

// ✅ GOOD: Proper error handling
let pool = PgPool::connect(&url)
    .await
    .context("Failed to connect to database")?;
```

## gRPC Calls
```rust
// ❌ BAD: Panics on network error
let response = client.get_user(request).await.unwrap();

// ✅ GOOD: With timeout and error handling
let response = tokio::time::timeout(
    Duration::from_secs(10),
    client.get_user(request)
)
.await
.context("Request timed out")?
.context("Failed to get user")?;
```

## Redis Operations
```rust
// ❌ BAD: Panics on cache miss
let value: String = redis_conn.get(&key).await.unwrap();

// ✅ GOOD: Handle cache miss gracefully
let value: Option<String> = redis_conn.get(&key)
    .await
    .context("Redis operation failed")?;

if let Some(cached) = value {
    return Ok(cached);
}
// Fetch from database if not cached
```

## Kafka Producer
```rust
// ❌ BAD: Panics on publish failure
producer.send(record).await.unwrap();

// ✅ GOOD: Retry with backoff
use backoff::{ExponentialBackoff, future::retry};

retry(ExponentialBackoff::default(), || async {
    producer.send(record.clone())
        .await
        .map_err(backoff::Error::transient)
})
.await
.context("Failed to publish to Kafka after retries")?;
```

## File Operations
```rust
// ❌ BAD: Panics on file not found
let content = fs::read_to_string(path).await.unwrap();

// ✅ GOOD: Check file exists first
if !tokio::fs::try_exists(&path).await? {
    return Err(anyhow!("File not found: {}", path));
}
let content = fs::read_to_string(path)
    .await
    .context("Failed to read file")?;
```
EOF

echo -e "\n${GREEN}Created fix_unwrap_examples.md with replacement patterns${NC}"

# Count by service
echo -e "\n${YELLOW}Unwrap count by service:${NC}"
for service in user auth content feed messaging notification search media video streaming cdn events graphql; do
    COUNT=$(grep -h "\.unwrap()" backend/*${service}*/**/*.rs 2>/dev/null | wc -l)
    if [ $COUNT -gt 0 ]; then
        echo "- ${service}-service: $COUNT unwraps"
    fi
done

echo -e "\n${GREEN}Next steps:${NC}"
echo "1. Review fix_unwrap_examples.md for patterns"
echo "2. Run: cargo clippy -- -W clippy::unwrap_used"
echo "3. Add #![deny(clippy::unwrap_used)] to lib.rs"
echo "4. Use cargo-expand to review macro-generated code"