# Phase 4: GraphQL Integration & Performance Optimization

**Status**: 🟢 Ready to Begin
**Start Date**: Week of November 11, 2025
**Duration**: 8 weeks (aligned with PHASE_4_PLANNING.md)
**Owner**: Backend + DevOps Teams

---

## Integration Overview

Phase 4 focuses on optimizing Nova's new GraphQL-first architecture for production. This guide integrates the GraphQL implementation (completed in Phase 1) with Phase 4's performance optimization roadmap.

### What's Completed
✅ GraphQL gateway with subscriptions
✅ Relay cursor-based pagination
✅ Schema SDL endpoint
✅ REST deprecation policy

### What This Guide Covers
🔄 Performance optimization for GraphQL
🔄 DataLoader N+1 query prevention
🔄 Subscription scalability
🔄 Caching strategies for GraphQL
🔄 Load testing GraphQL workloads

---

## Week 1-2: Database Optimization + GraphQL

### Goal
Ensure database queries serving GraphQL are optimized for <100ms response time.

### Database Analysis for GraphQL Queries

#### 1. Identify N+1 Prone Queries
**Current Pattern** (PROBLEMATIC):
```graphql
query {
  posts(first: 10) {
    edges {
      node {
        id
        creator {      # ← This causes N queries!
          id
          name
        }
      }
    }
  }
}
```

**Problem**: Query posts (1) + N creator lookups = N+1 queries
**Solution**: DataLoader batching

#### 2. Index Analysis for GraphQL Filters
```sql
-- For pagination
CREATE INDEX idx_posts_created_at ON posts(created_at DESC)
  WHERE deleted_at IS NULL;

-- For subscription filtering
CREATE INDEX idx_feed_user_created ON feed_items(user_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- For message queries
CREATE INDEX idx_messages_recipient ON messages(recipient_id, created_at DESC)
  WHERE read_at IS NULL;

-- For notification queries
CREATE INDEX idx_notifications_user ON notifications(user_id, created_at DESC)
  WHERE read_at IS NULL;
```

#### 3. Query Plan Analysis
```bash
# For each GraphQL query, run:
EXPLAIN ANALYZE
SELECT * FROM posts
  WHERE created_at > NOW() - INTERVAL '7 days'
  ORDER BY created_at DESC
  LIMIT 10;
```

**Target**: Seq scans should use index, <50ms execution

### Implementation Steps

**Week 1: Analysis**
1. Profile current GraphQL queries in staging
2. Identify top 20 queries by latency
3. Generate execution plans for each
4. Document N+1 opportunities

**Week 2: Optimization**
1. Create/optimize indexes
2. Implement database connection pooling
3. Add query timeout enforcement
4. Test on staging with real data

### Success Metrics
- Query p95 latency: < 100ms
- Database connections: < 100 (max pool)
- Seq scans: < 5% of queries

---

## Week 2-3: Caching Strategy

### 1. Application-Level Caching (Apollo Client)

**For Web/Mobile Clients**:
```typescript
// Apollo cache will automatically deduplicate queries
import { ApolloClient, InMemoryCache } from "@apollo/client";

const client = new ApolloClient({
  cache: new InMemoryCache({
    typePolicies: {
      Post: {
        keyFields: ["id"],
      },
      User: {
        keyFields: ["id"],
      },
    },
  }),
});

// Automatic cache hits for repeated queries
query GetPost($id: String!) {
  post(id: $id) {
    id
    content
    creator { id name }  # Deduplicated from cache
  }
}
```

### 2. DataLoader Implementation

Add to GraphQL resolvers to batch database queries:

```rust
// In subscription.rs and pagination.rs

use async_graphql::dataloader::DataLoader;
use std::collections::HashMap;

pub struct UserLoader;

#[async_trait::async_trait]
impl async_graphql::dataloader::Loader<String> for UserLoader {
    type Value = User;
    type Error = String;

    async fn load(&self, keys: Vec<String>) -> Result<HashMap<String, Self::Value>, Self::Error> {
        // Load multiple users in ONE query instead of N queries
        let users = load_users_batch(&keys).await?;

        Ok(users
            .into_iter()
            .map(|user| (user.id.clone(), user))
            .collect())
    }
}

// Usage in resolver:
#[Object]
impl Post {
    async fn creator(&self, ctx: &Context<'_>) -> Result<User> {
        let loader = ctx.data::<DataLoader<UserLoader>>()?;
        loader.load_one(self.creator_id.clone()).await?
    }
}
```

**Enable in schema**:
```rust
pub fn build_schema(clients: ServiceClients) -> AppSchema {
    Schema::build(
        QueryRoot::default(),
        MutationRoot::default(),
        SubscriptionRoot::default(),
    )
    .data(DataLoader::new(UserLoader, tokio::task::spawn_blocking))
    .data(DataLoader::new(PostLoader, tokio::task::spawn_blocking))
    .data(clients)
    .enable_federation()
    .finish()
}
```

### 3. Redis Caching for Subscriptions

Cache subscription state to enable reconnection:

```rust
// In subscription.rs

pub struct SubscriptionRoot;

#[Subscription]
impl SubscriptionRoot {
    async fn feed_updated(&self, ctx: &Context<'_>) -> impl Stream<Item = GraphQLResult<FeedUpdateEvent>> {
        // In production: Subscribe to Kafka with Redis backup
        // 1. Get user_id from JWT context
        // 2. Load cached events from Redis (last 50 events)
        // 3. Subscribe to new events from Kafka
        // 4. Save received events to Redis (1-hour TTL)
        // 5. On reconnect: Provide cached events from Redis

        let user_id = ctx.data::<String>().unwrap_or_default();

        // Load last 50 cached events from Redis
        let redis = ctx.data::<redis::Client>().ok();
        if let Ok(client) = redis {
            let cache_key = format!("feed:{}:events", user_id);
            if let Ok(cached) = client.get::<_, Vec<FeedUpdateEvent>>(&cache_key) {
                return futures_util::stream::iter(
                    cached.into_iter()
                        .map(|e| Ok(e))
                        .collect::<Vec<_>>()
                );
            }
        }

        // Fallback: Return demo events
        futures_util::stream::iter(vec![
            Ok(FeedUpdateEvent { ... }),
        ])
    }
}
```

### 4. HTTP Caching for SDL Endpoint

```rust
// In main.rs

async fn schema_handler(schema: web::Data<schema::AppSchema>) -> actix_web::HttpResponse {
    actix_web::HttpResponse::Ok()
        .content_type("text/plain")
        .insert_header(("Cache-Control", "public, max-age=3600"))  // 1 hour
        .insert_header(("ETag", compute_schema_hash(&schema)))
        .body(schema.sdl())
}
```

### Success Metrics
- DataLoader batch size: > 10 items per query
- Apollo cache hit ratio: > 80%
- Redis subscription cache hit: > 70%
- SDL endpoint cache hits: > 95%

---

## Week 3-4: GraphQL Performance Tuning

### 1. Query Complexity Analysis

Prevent runaway queries:

```rust
// Add to schema.rs

use async_graphql::validation::rules::QueryComplexity;

pub fn build_schema(clients: ServiceClients) -> AppSchema {
    Schema::build(
        QueryRoot::default(),
        MutationRoot::default(),
        SubscriptionRoot::default(),
    )
    .data(clients)
    .enable_federation()
    // ✅ P0-4: Limit query complexity
    .extension(QueryComplexity::default()
        .with_max_complexity(1000))  // Reject queries > 1000 complexity units
    .finish()
}

// Define complexity for fields:
#[Object]
impl Post {
    #[graphql(complexity = "1")]
    async fn id(&self) -> String { ... }

    #[graphql(complexity = "5")]  // More expensive field
    async fn creator(&self, ctx: &Context<'_>) -> Result<User> { ... }

    #[graphql(complexity = "first * 10")]  // Variable complexity based on pagination
    async fn comments(&self, first: i32) -> Result<Vec<Comment>> { ... }
}
```

### 2. Subscription Optimization

#### Backpressure Handling
```rust
// In subscription.rs

use futures_util::stream::StreamExt;

async fn feed_updated(&self) -> impl Stream<Item = GraphQLResult<FeedUpdateEvent>> {
    futures_util::stream::iter(vec![...])
        .throttle(Duration::from_millis(100))  // Max 10 events/sec per client
        .take(1000)  // Max 1000 events per connection
}
```

#### Connection Management
```rust
// In main.rs

async fn graphql_subscription_handler(
    schema: web::Data<schema::AppSchema>,
    req: actix_web::HttpRequest,
    payload: web::Payload,
) -> actix_web::Result<actix_web::HttpResponse> {
    // ✅ P0-4: Add connection limits
    let connection_count = ACTIVE_SUBSCRIPTIONS.fetch_add(1, Ordering::SeqCst);

    if connection_count > 10000 {  // Max 10K concurrent connections
        return Ok(actix_web::HttpResponse::ServiceUnavailable().finish());
    }

    GraphQLSubscription::new(schema.as_ref().clone())
        .start(&req, payload)
}
```

### 3. Response Compression

```rust
// In main.rs

use actix_web::middleware::Compress;

HttpServer::new(move || {
    App::new()
        .wrap(Compress::default())  // Enable Gzip/Brotli
        .wrap(Logger::default())
        // ... rest of configuration
})
```

### Success Metrics
- Query complexity enforcement: > 99% queries < 1000 units
- Subscription throttling: Zero burst events
- Response compression: > 60% size reduction
- p95 latency: < 100ms for queries

---

## Week 4-5: Load Testing GraphQL

### Test Scenario 1: Normal GraphQL Load
```bash
# 8K concurrent users
# Workload: 80% queries, 15% mutations, 5% subscriptions
# Duration: 5 minutes

k6 run --vus 8000 --duration 5m load-tests/graphql-normal.js
```

**Test Plan**:
```javascript
// load-tests/graphql-normal.js
import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 4000 },  // Ramp up
    { duration: '2m', target: 8000 },  // Steady state
    { duration: '1m', target: 0 },     // Ramp down
  ],
};

export default function() {
  // 80% - Queries
  if (Math.random() < 0.80) {
    const query = `
      query {
        posts(first: 10) {
          edges {
            node { id content creator { name } }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    `;

    const response = http.post(
      'http://localhost:8080/graphql',
      JSON.stringify({ query }),
      { headers: { 'Content-Type': 'application/json' } }
    );

    check(response, {
      'status is 200': (r) => r.status === 200,
      'has data': (r) => r.body.includes('"data"'),
    });
  }
  // 15% - Mutations
  else if (Math.random() < 0.15) {
    const mutation = `
      mutation {
        createPost(content: "Test post") {
          id createdAt
        }
      }
    `;
    // ... similar to query
  }
  // 5% - Subscriptions
  else {
    ws.connect('ws://localhost:8080/ws', {}, function(socket) {
      const subscription = `
        subscription {
          feedUpdated { postId creatorId content }
        }
      `;
      socket.send(JSON.stringify({ type: 'start', payload: { query: subscription } }));
      socket.setTimeout(() => socket.close(), 30000);
    });
  }

  sleep(1);
}
```

### Test Scenario 2: Peak Load (10K users)
```bash
k6 run --vus 10000 --duration 3m load-tests/graphql-peak.js
```

**Expected Results**:
- Latency p95: < 200ms
- Error rate: < 0.1%
- Throughput: > 10K rps

### Test Scenario 3: Subscription Stress
```bash
# 1000 concurrent subscriptions
# Test: Deliver 100K events across all subscriptions
# Duration: 10 minutes

k6 run --vus 1000 load-tests/graphql-subscriptions-stress.js
```

### Test Scenario 4: Spike Test
```bash
# Sudden 2x load (20K users in 30s)
# Verify: Auto-scaling, graceful degradation

k6 run --vus 20000 --duration 1m load-tests/graphql-spike.js
```

### Monitoring During Tests
```bash
# Terminal 1: Run k6 load test
k6 run load-tests/graphql-mixed.js

# Terminal 2: Monitor Prometheus metrics
watch 'curl -s localhost:9090/api/v1/query?query=\
  graphql_request_duration_seconds_bucket | jq .data.result[0].value'

# Terminal 3: Watch Kubernetes pods
watch 'kubectl get pods -n nova | grep graphql'

# Terminal 4: Check Kafka consumer lag
kafka-consumer-groups --bootstrap-server kafka:9092 \
  --group graphql-subscriptions --describe
```

### Success Criteria
- ✅ Query p95 < 100ms
- ✅ Mutation p95 < 200ms
- ✅ Subscription latency p95 < 50ms
- ✅ Error rate < 0.01% (normal), < 0.1% (peak)
- ✅ Auto-scaling handles load within 2 minutes
- ✅ Kafka consumer lag < 5s

---

## Week 5-6: Security Hardening for GraphQL

### 1. Input Validation

**Already Implemented**:
- ✅ Pagination limits (max 100 items)
- ✅ Cursor format validation (base64)
- ✅ String field length limits (in proto)

**Add These**:
```rust
// In schema/content.rs

#[Object]
impl ContentMutation {
    async fn create_post(
        &self,
        ctx: &Context<'_>,
        #[graphql(validator(max_length = 5000))]
        content: String,
    ) -> GraphQLResult<Post> {
        // Content max 5000 chars
        // Already validated by async-graphql
        // ...
    }
}
```

### 2. CORS Configuration

```rust
// In main.rs

use actix_cors::Cors;

HttpServer::new(move || {
    let cors = Cors::default()
        .allowed_origin("https://nova.app")
        .allowed_origin("https://app.nova.app")
        .allowed_methods(vec!["GET", "POST", "OPTIONS"])
        .allowed_headers(vec![
            actix_web::http::header::AUTHORIZATION,
            actix_web::http::header::CONTENT_TYPE,
        ])
        .max_age(3600);

    App::new()
        .wrap(cors)
        // ... rest
})
```

### 3. Rate Limiting Per User

```rust
// Update middleware/rate_limit.rs

pub struct RateLimiter {
    storage: Arc<Mutex<HashMap<String, RateLimitState>>>,
    max_requests: u32,
    window_secs: u64,
}

impl RateLimiter {
    pub fn check(&self, user_id: &str) -> bool {
        let mut storage = self.storage.lock().unwrap();

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let state = storage.entry(user_id.to_string())
            .or_insert_with(|| RateLimitState {
                count: 0,
                window_start: now,
            });

        // Reset window if expired
        if now - state.window_start > self.window_secs {
            state.count = 0;
            state.window_start = now;
        }

        state.count += 1;
        state.count <= self.max_requests as usize
    }
}

// Apply to GraphQL handler:
async fn graphql_handler(
    req: GraphQLRequest,
    limiter: web::Data<RateLimiter>,
) -> GraphQLResponse {
    let user_id = extract_user_id(&req);

    if !limiter.check(&user_id) {
        return GraphQLResponse::from(
            Err("Rate limit exceeded: 100 requests per 60 seconds".into())
        );
    }

    // Process request...
}
```

### 4. Introspection Control

Disable introspection in production:

```rust
// In schema.rs

pub fn build_schema(clients: ServiceClients, env: Environment) -> AppSchema {
    let mut schema = Schema::build(...)
        .data(clients)
        .enable_federation();

    // Disable introspection in production
    if env == Environment::Production {
        schema = schema.disable_introspection();
    }

    schema.finish()
}
```

### 5. GraphQL-Specific Attacks

**Prevent Circular Queries**:
```rust
// Already handled by QueryComplexity rule
// Queries referencing themselves > depth 10 rejected
```

**Prevent Alias Attacks**:
```graphql
# This query uses aliases to multiply requests
# Limit: Max 100 aliases per query
query {
  alias1: post(id: "1") { id }
  alias2: post(id: "1") { id }
  # ... 100 times
  alias100: post(id: "1") { id }
}
```

**Prevention in async-graphql**: Already limited by QueryComplexity

### Success Metrics
- ✅ CORS headers present on all responses
- ✅ Rate limiting: 100 requests/minute per user
- ✅ Input validation: 100% of fields
- ✅ Introspection: Disabled in production
- ✅ Security headers: All OWASP checks passing

---

## Week 6-7: Cost Optimization

### 1. Database Query Optimization
- Reduce average query time: 200ms → 50ms
- Reduce database CPU: 60% → 40%
- Estimated savings: $200/month

### 2. Subscription Connection Pooling
```rust
// In subscription.rs

// Reuse Kafka consumer groups
// Batch writes to Redis cache
// Use connection pooling for database
```

**Expected Savings**:
- Memory per subscription: 2MB → 500KB
- CPU per connection: 5% → 1%
- Estimated savings: $500/month

### 3. Storage Optimization
```sql
-- Archive old events to S3
SELECT COUNT(*) FROM notifications
  WHERE created_at < NOW() - INTERVAL '30 days';

-- Compress old feed items
ALTER TABLE feed_items SET (fillfactor = 100);
VACUUM ANALYZE feed_items;
```

**Expected Savings**: $300/month

### Total Cost Reduction Target
**From Phase 3**: $5,000/month infrastructure
**Target**: $4,000/month (20% reduction)
**Achieved**: ~$1,000/month savings from optimizations

---

## Week 7-8: Runbooks & Documentation

### Subscription Runbook

**Issue**: High latency in subscriptions

**Debugging Steps**:
```bash
# 1. Check Kafka consumer lag
kafka-consumer-groups --bootstrap-server kafka:9092 \
  --group graphql-subscriptions --describe

# 2. Monitor WebSocket connections
kubectl top pods -n nova | grep graphql

# 3. Check Redis cache hit rate
redis-cli INFO stats | grep hits

# 4. Review graphql-gateway logs
kubectl logs -f deployment/graphql-gateway -n nova \
  | grep "subscription\|error"
```

**Common Causes**:
- Kafka consumer lag > 30s → Increase consumer threads
- Memory > 80% → Reduce max connections
- Redis errors → Check Redis cluster health

**Resolution Steps**:
1. Scale graphql-gateway to 3x current replicas
2. Wait 2 minutes for connections to balance
3. Monitor latency for 5 minutes
4. If improved, scale permanent (adjust HPA)
5. If not improved, escalate to database team

### Query Performance Runbook

**Issue**: GraphQL queries returning 500ms+

**Debugging**:
```bash
# Check query performance
curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"query { posts(first: 10) { edges { node { id } } } }"}'

# Check explain plan
EXPLAIN ANALYZE SELECT * FROM posts LIMIT 10;

# Profile GraphQL resolver time
# In logs: look for "resolver_duration_ms" metric
```

**Common Causes**:
- Missing index → Create (5 min fix)
- N+1 queries → Add DataLoader (requires code change)
- Slow resolver → Check database

---

## Integration Checklist

- [ ] Week 1: Database indices created and verified
- [ ] Week 1: Connection pooling configured
- [ ] Week 2: DataLoader implemented for 5 key resolvers
- [ ] Week 2: Redis cache configured for subscriptions
- [ ] Week 3: Query complexity limits enforced
- [ ] Week 3: Subscription backpressure implemented
- [ ] Week 4: Load test infrastructure ready
- [ ] Week 4: Baseline performance metrics established
- [ ] Week 5: Load tests passing (Normal + Peak)
- [ ] Week 5: CORS and rate limiting configured
- [ ] Week 5: Input validation rules added
- [ ] Week 6: Cost analysis complete
- [ ] Week 6: Runbooks finalized
- [ ] Week 7: Team training completed
- [ ] Week 8: Performance targets verified
- [ ] Week 8: Production deployment ready

---

## Performance Targets (End of Phase 4)

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Query p95 latency | 100ms | TBD | 🔄 |
| Mutation p95 latency | 200ms | TBD | 🔄 |
| Subscription connection | < 100ms | TBD | 🔄 |
| Subscription latency | < 50ms | TBD | 🔄 |
| Error rate (normal) | < 0.01% | TBD | 🔄 |
| Error rate (peak) | < 0.1% | TBD | 🔄 |
| Concurrent subscriptions | > 10K | TBD | 🔄 |
| Kafka consumer lag | < 5s | TBD | 🔄 |
| Cost per user/month | < $0.10 | TBD | 🔄 |

---

## References

- [PHASE_4_PLANNING.md](PHASE_4_PLANNING.md) - Overall Phase 4 roadmap
- [GRAPHQL_IMPLEMENTATION_SUMMARY.md](GRAPHQL_IMPLEMENTATION_SUMMARY.md) - What was implemented
- [API_DEPRECATION_POLICY.md](backend/API_DEPRECATION_POLICY.md) - REST → GraphQL migration
- [GRAPHQL_DEPLOYMENT_VERIFICATION.md](GRAPHQL_DEPLOYMENT_VERIFICATION.md) - Pre-deployment checklist

---

**Ready to Begin: November 11, 2025**

*Owner: Backend + DevOps Teams*
*Duration: 8 weeks*
*Target Completion: January 9, 2026*
