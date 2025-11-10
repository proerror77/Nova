# GraphQL-First Architecture: Quick Reference

**Last Updated**: 2025-11-10
**For**: Engineers, QA, DevOps
**Purpose**: Day-to-day reference during development and testing

---

## 🚀 Quick Start

### Build Locally
```bash
cd backend/graphql-gateway
cargo build
cargo run
```

### Test Locally
```bash
# Unit tests
cargo test

# GraphQL playground
open http://localhost:8080/playground

# Schema SDL
curl http://localhost:8080/graphql/schema | head -20
```

---

## 📋 What's New in Nova

### Three New Components

1. **WebSocket Subscriptions** (`/ws` or `/graphql`)
   - `feedUpdated` - Real-time posts
   - `messageReceived` - Direct messages
   - `notificationReceived` - Likes, follows, mentions

2. **Relay Pagination** (on `posts` query)
   - `posts(first: 10, after: "cursor")` - Forward pagination
   - `posts(last: 10, before: "cursor")` - Backward pagination
   - Max 100 items per page

3. **Schema SDL** (`/graphql/schema` or `/schema`)
   - Full GraphQL schema in SDL format
   - Use with code generators (Apollo, GraphQL Codegen)

---

## 🔍 Key File Locations

| File | Lines | Purpose |
|------|-------|---------|
| `backend/graphql-gateway/src/schema/subscription.rs` | 169 | Three subscription types |
| `backend/graphql-gateway/src/schema/pagination.rs` | 261 | Relay pagination + cursors |
| `backend/graphql-gateway/src/schema/content.rs` | 238 | Posts query with pagination |
| `backend/graphql-gateway/src/main.rs` | ~350 | Routes + WebSocket |
| `backend/graphql-gateway/Cargo.toml` | ~80 | Dependencies |

---

## 🔗 Endpoint Reference

### HTTP Endpoints

| Method | URL | Purpose |
|--------|-----|---------|
| POST | `/graphql` | Queries & mutations |
| GET | `/graphql/schema` | GraphQL SDL schema |
| GET | `/playground` | GraphQL IDE |
| GET | `/health` | Health check |

### WebSocket Endpoints

| Method | URL | Purpose |
|--------|-----|---------|
| GET (WS upgrade) | `/graphql` | Subscriptions (standard) |
| GET (WS upgrade) | `/ws` | Subscriptions (alternative) |

---

## 📝 GraphQL Query Examples

### Basic Query
```graphql
query {
  post(id: "post_1") {
    id
    content
    creatorId
    createdAt
  }
}
```

### Query with Pagination
```graphql
query {
  posts(first: 10, after: "offset:0") {
    edges {
      cursor
      node {
        id
        content
        creatorId
      }
    }
    pageInfo {
      hasNextPage
      endCursor
      totalCount
    }
  }
}
```

### Backward Pagination
```graphql
query {
  posts(last: 5, before: "offset:100") {
    edges {
      cursor
      node { id }
    }
    pageInfo {
      hasPreviousPage
      startCursor
    }
  }
}
```

### Create Mutation
```graphql
mutation {
  createPost(content: "Hello world") {
    id
    content
    createdAt
  }
}
```

### Delete Mutation
```graphql
mutation {
  deletePost(id: "post_1")
}
```

### Feed Subscription
```graphql
subscription {
  feedUpdated {
    postId
    creatorId
    content
    createdAt
    eventType
  }
}
```

### Message Subscription
```graphql
subscription {
  messageReceived {
    messageId
    conversationId
    senderId
    content
    createdAt
    encrypted
  }
}
```

### Notification Subscription
```graphql
subscription {
  notificationReceived {
    notificationId
    userId
    actorId
    action
    targetId
    createdAt
    read
  }
}
```

---

## 🧪 Testing with cURL

### Test GraphQL Query
```bash
curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"query":"query { posts(first: 10) { edges { node { id } } } }"}'
```

### Test Schema SDL
```bash
curl http://localhost:8080/graphql/schema | head -30
```

### Test WebSocket (with wscat)
```bash
# Install wscat
npm install -g wscat

# Connect to subscription endpoint
wscat -c ws://localhost:8080/ws

# Send subscription
{"type":"start","payload":{"query":"subscription { feedUpdated { postId } }"}}
```

---

## 🐛 Common Issues & Solutions

### Issue: "Query returned null"
**Cause**: Pagination arguments invalid
**Fix**:
- Check cursor format (should be base64)
- Verify `first` or `last` is specified
- Ensure `first` and `last` not both specified

### Issue: "Subscription connection failed"
**Cause**: JWT token missing or invalid
**Fix**:
- Add `Authorization: Bearer TOKEN` header
- Generate new token if expired
- Check WebSocket upgrade headers

### Issue: "Rate limit exceeded"
**Cause**: Too many requests in 60 seconds
**Fix**:
- Wait 1 minute before retrying
- Reduce request frequency
- Use batch queries where possible

### Issue: "Schema SDL returns empty"
**Cause**: Schema not properly built
**Fix**:
- Restart GraphQL gateway
- Check logs: `cargo run`
- Verify Cargo.toml has async-graphql

---

## 📊 Performance Quick Check

```bash
# Time a query
time curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"query { posts(first: 10) { edges { node { id } } } }"}'
# Should be < 100ms

# Check schema size
curl http://localhost:8080/graphql/schema | wc -c
# Should be ~50KB

# Monitor subscriptions
kubectl get pods -n nova | grep graphql
kubectl top pods -n nova | grep graphql
# Memory should be < 500MB per pod
```

---

## 🔐 Security Checklist

- [ ] JWT token required for all requests (enforced by middleware)
- [ ] Pagination max 100 items enforced
- [ ] Cursor tampering rejected gracefully
- [ ] No credentials in error messages
- [ ] CORS headers properly configured
- [ ] Rate limiting: 100 requests/minute per user
- [ ] Introspection disabled in production

---

## 🚢 Deployment Steps

### Local Testing
```bash
cargo build
cargo test
cargo run
# Test at http://localhost:8080/playground
```

### Staging Deployment
```bash
# Build Docker image
docker build -t graphql-gateway:latest .

# Push to registry
docker push YOUR_REGISTRY/graphql-gateway:latest

# Deploy to Kubernetes
kubectl apply -f k8s/graphql-gateway-deployment.yaml
kubectl get pods -n nova | grep graphql
```

### Production Deployment
```bash
# Canary deployment (10% traffic)
kubectl patch deployment graphql-gateway -n nova \
  --type='json' -p='[{"op": "replace", "path": "/spec/replicas", "value":1}]'

# Monitor for 5 minutes
kubectl logs -f deployment/graphql-gateway -n nova

# Full rollout (100% traffic)
kubectl patch deployment graphql-gateway -n nova \
  --type='json' -p='[{"op": "replace", "path": "/spec/replicas", "value":10}]'
```

### Rollback (if needed)
```bash
kubectl rollout undo deployment/graphql-gateway -n nova
kubectl rollout status deployment/graphql-gateway -n nova
```

---

## 📈 Key Metrics to Monitor

```
✓ graphql_request_duration_seconds    Target: < 200ms p95
✓ graphql_subscription_connections     Target: > 95% success
✓ graphql_subscription_latency         Target: < 50ms p95
✓ graphql_error_total                  Target: < 0.01%
✓ graphql_query_complexity             Target: avg < 100 units
✓ database_query_duration              Target: < 100ms p95
✓ kafka_consumer_lag                   Target: < 5s
```

---

## 🎯 Development Workflow

### 1. Implement New GraphQL Field
```rust
// Edit backend/graphql-gateway/src/schema/content.rs

#[Object]
impl Post {
    #[graphql(field)]
    async fn my_new_field(&self) -> Result<String> {
        Ok("value".to_string())
    }
}
```

### 2. Add Unit Test
```rust
#[cfg(test)]
mod tests {
    #[test]
    fn test_my_new_field() {
        // Test logic
    }
}
```

### 3. Build & Test
```bash
cargo test
cargo build
```

### 4. Query in Playground
```
http://localhost:8080/playground
```

### 5. Commit
```bash
git add .
git commit -m "feat: add my_new_field to Post"
```

---

## 📚 Documentation Map

| Document | Purpose | Audience |
|----------|---------|----------|
| [GRAPHQL_IMPLEMENTATION_SUMMARY.md](GRAPHQL_IMPLEMENTATION_SUMMARY.md) | Technical overview | Engineers |
| [API_DEPRECATION_POLICY.md](backend/API_DEPRECATION_POLICY.md) | REST → GraphQL migration | All teams |
| [GRAPHQL_DEPLOYMENT_VERIFICATION.md](GRAPHQL_DEPLOYMENT_VERIFICATION.md) | Pre-deployment checklist | DevOps |
| [PHASE_4_GRAPHQL_INTEGRATION.md](PHASE_4_GRAPHQL_INTEGRATION.md) | Performance optimization roadmap | Architects |
| [GRAPHQL_QUICK_REFERENCE.md](GRAPHQL_QUICK_REFERENCE.md) | This document! | Engineers |

---

## 🆘 Getting Help

### For Implementation Questions
- Check the schema: `curl http://localhost:8080/graphql/schema`
- Read code comments in `subscription.rs` and `pagination.rs`
- Look at test cases: `cargo test -- --nocapture`

### For Performance Issues
- Monitor metrics: `kubectl top pods`
- Check logs: `kubectl logs deployment/graphql-gateway`
- Profile queries: Look at `graphql_request_duration_seconds` metrics

### For Deployment Issues
- See [GRAPHQL_DEPLOYMENT_VERIFICATION.md](GRAPHQL_DEPLOYMENT_VERIFICATION.md)
- Check rollout status: `kubectl rollout status deployment/graphql-gateway`
- View deployment history: `kubectl rollout history deployment/graphql-gateway`

---

## 📅 Timeline Reminder

| Phase | Duration | Status |
|-------|----------|--------|
| Code Implementation | ✅ Complete | Nov 10 |
| Pre-Deployment Verification | Week 1 | Nov 11-15 |
| Staging Deployment | Week 2 | Nov 18-22 |
| Canary (10%) | Week 3 | Nov 25-29 |
| Full Production | Week 4+ | Dec 2+ |

---

## ✅ Pre-Deployment Checklist

Before deploying to any environment:

- [ ] `cargo test` passes locally
- [ ] `cargo build --release` succeeds
- [ ] Schema SDL endpoint works
- [ ] Subscriptions connect in playground
- [ ] Pagination cursors valid
- [ ] No compilation warnings
- [ ] Updated CHANGELOG.md
- [ ] Documented breaking changes (if any)

---

## 💡 Pro Tips

1. **Use GraphQL variables for security**
   ```graphql
   query GetPost($id: String!) {
     post(id: $id) { id content }
   }
   ```
   NOT:
   ```graphql
   query {
     post(id: "post_1") { id content }
   }
   ```

2. **Batch queries to reduce round trips**
   ```graphql
   {
     post1: post(id: "1") { id }
     post2: post(id: "2") { id }
     post3: post(id: "3") { id }
   }
   ```

3. **Use pagination for large datasets**
   - Never fetch `posts(first: 1000)` in production
   - Always use pagination to control result size

4. **Monitor subscription connections**
   - Set connection timeout: 30 minutes idle
   - Alert on connection failure > 5%

---

**Version**: 2.0 (Phase 4 Integration Ready)
**Last Verified**: 2025-11-10
**Status**: 🟢 Ready for Production

*Questions? Check [PHASE_4_GRAPHQL_INTEGRATION.md](PHASE_4_GRAPHQL_INTEGRATION.md) for detailed implementation guide.*
