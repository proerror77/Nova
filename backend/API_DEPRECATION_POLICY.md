# Nova API Deprecation Policy: REST → GraphQL Migration

**Effective Date**: 2025-11-10
**Migration Period**: 12 weeks (3 months)
**Target**: Complete REST API deprecation by 2026-02-10

---

## 📋 Overview

Nova is transitioning from a **three-layer API architecture** (REST + gRPC + GraphQL) to a **unified GraphQL-first architecture** to reduce complexity and improve developer experience.

### Why GraphQL?

| Aspect | REST | GraphQL |
|--------|------|---------|
| **Data Fetching** | Multiple endpoints, over/under-fetching | Single endpoint, precise queries |
| **Frontend SDK** | Multiple clients (REST + gRPC) | Single client library |
| **Real-time Updates** | Polling required | Native subscriptions (WebSocket) |
| **Type Safety** | Manual schema definition | Auto-generated from schema |
| **Documentation** | Separate OpenAPI/Swagger | Self-documenting via introspection |
| **Maintenance** | 3x code duplication | Single source of truth |

---

## 🗓️ Migration Timeline

### Phase 1: Announcement & Compatibility (Week 1-2)
- ✅ GraphQL subscriptions fully implemented
- ✅ Relay pagination deployed
- ✅ SDL schema endpoint available at `/graphql/schema`
- 📢 Send deprecation warnings in REST API responses
  - Header: `Deprecation: true`
  - Header: `Sunset: Wed, 10 Feb 2026 00:00:00 GMT`
  - Body warning in API responses

**REST API Status**: `DEPRECATED (Use /graphql instead)`

### Phase 2: Feature Parity (Week 3-8)
- Add remaining GraphQL mutations for messaging/notifications
- Implement GraphQL directives for auth and caching
- Create migration guide for clients
- Deploy gRPC-Web proxy (optional, for mobile)

**Client Actions Required**:
```javascript
// Old way (REST) - DEPRECATED
fetch('/api/v1/posts', { method: 'POST', body: ... })

// New way (GraphQL) - RECOMMENDED
graphQLClient.mutation(CreatePost, { content: "..." })
```

### Phase 3: Active Deprecation (Week 9-12)
- Monitor REST API usage via logs
- Publish migration timeline
- Provide client code generation examples
- Support team training on GraphQL

**REST API Status**: `DEPRECATED (Will be removed 2026-02-10)`

### Phase 4: Removal (Week 13+)
- Delete REST API endpoints
- Retain GraphQL as single API layer
- Archive REST documentation

**Final Status**: `REMOVED - Use GraphQL only`

---

## 🔧 Deprecation Warnings

### For REST API Responses

All REST endpoints will return deprecation headers:

```http
HTTP/1.1 200 OK
Deprecation: true
Sunset: Wed, 10 Feb 2026 00:00:00 GMT
Link: </graphql>; rel="successor-version"

{
  "data": { ... },
  "warning": {
    "message": "REST API is deprecated. Migrate to GraphQL: https://docs.nova.app/graphql-migration",
    "sunset_date": "2026-02-10",
    "migration_guide": "https://docs.nova.app/rest-to-graphql"
  }
}
```

### Log-level Warnings

```rust
// src/middleware/deprecation.rs
warn!(
    api = "REST",
    endpoint = "/api/v1/posts",
    client_user_agent = req.user_agent(),
    message = "REST endpoint deprecated, migrate to GraphQL /graphql",
);
```

---

## 📊 Endpoint Migration Map

### User Management

| REST Endpoint | GraphQL Equivalent | Status |
|---------------|-------------------|--------|
| `GET /api/v1/users/{id}` | `query { user(id: "X") { ... } }` | ✅ Ready |
| `POST /api/v1/users` | `mutation { createUser(...) { ... } }` | ✅ Ready |
| `PUT /api/v1/users/{id}` | `mutation { updateUser(...) { ... } }` | ⚠️ Plan |
| `DELETE /api/v1/users/{id}` | `mutation { deleteUser(...) }` | ⚠️ Plan |

### Content Management

| REST Endpoint | GraphQL Equivalent | Status |
|---------------|-------------------|--------|
| `GET /api/v1/posts` | `query { posts(first: 10) { edges { node } } }` | ✅ Ready |
| `GET /api/v1/posts/{id}` | `query { post(id: "X") { ... } }` | ✅ Ready |
| `POST /api/v1/posts` | `mutation { createPost(...) { ... } }` | ✅ Ready |
| `DELETE /api/v1/posts/{id}` | `mutation { deletePost(id: "X") }` | ✅ Ready |

### Messaging (NEW)

| REST Endpoint | GraphQL Equivalent | Status |
|---------------|-------------------|--------|
| N/A (gRPC only) | `mutation { sendMessage(...) { ... } }` | 🔴 Blocked |
| N/A (gRPC only) | `subscription { messageReceived { ... } }` | ✅ Ready |

### Notifications (NEW)

| REST Endpoint | GraphQL Equivalent | Status |
|---------------|-------------------|--------|
| N/A (gRPC only) | `mutation { markAsRead(...) { ... } }` | 🔴 Blocked |
| N/A (gRPC only) | `subscription { notificationReceived { ... } }` | ✅ Ready |

---

## 🚀 Migration Guide for Clients

### Before (REST + Multiple Clients)

```typescript
// REST client for posts
const post = await fetch('/api/v1/posts/123')
  .then(r => r.json())

// gRPC client for messages (web browsers can't call this!)
const messages = await messageServiceClient.getMessages({ conversationId })

// GraphQL client for queries (but no subscriptions)
const feed = await graphqlClient.query(GetFeedQuery)
```

**Problems**:
- 3 different client libraries to maintain
- Browser can't call gRPC directly
- No real-time updates for messages/notifications
- Redundant code in frontend and backend

### After (GraphQL Only)

```typescript
// Single GraphQL client for everything
const client = new ApolloClient({
  uri: 'https://api.nova.app/graphql',
})

// Queries
const post = await client.query(
  gql`query { post(id: "123") { id content } }`
)

// Mutations
await client.mutate(
  gql`mutation { createPost(content: "...") { id } }`
)

// Subscriptions (real-time!)
client.subscribe(
  gql`subscription { messageReceived { id content } }`
).subscribe(({ data }) => {
  console.log('New message:', data.messageReceived)
})
```

**Benefits**:
- Single client library (`apollo-client`)
- Fully typed with GraphQL code generation
- Real-time subscriptions built-in
- Self-documenting API

---

## 🛡️ Backward Compatibility

### Keep REST for 12 Weeks

To avoid breaking existing clients, REST endpoints remain functional with deprecation warnings:

```rust
// src/middleware/deprecation.rs
pub async fn add_deprecation_headers(
    req: HttpRequest,
    mut res: ServiceResponse,
) -> Result<ServiceResponse> {
    res.headers_mut().insert(
        DEPRECATION,
        HeaderValue::from_static("true"),
    );
    res.headers_mut().insert(
        "Sunset",
        HeaderValue::from_static("Wed, 10 Feb 2026 00:00:00 GMT"),
    );
    Ok(res)
}
```

### One-Click Migration Script

```bash
# Automatically migrate REST client code to GraphQL
npm install @nova/rest-to-graphql-migrator
npx rest-to-graphql-migrate --input=src/ --api-endpoint=https://api.nova.app/graphql
```

---

## 📈 Monitoring & Metrics

### Track REST API Usage

```rust
// src/middleware/deprecation_metrics.rs
metrics::counter!(
    "rest_api.deprecated_endpoint",
    "endpoint" => "/api/v1/posts",
    "client" => user_agent,
).increment(1);

// Track migration progress
metrics::gauge!(
    "api.migration.rest_usage_percentage",
    remaining_rest_calls as f64 / total_calls as f64 * 100.0
);
```

### Expected Timeline

```
Week 1-2:   REST usage: ~100% → GraphQL: ~10%
Week 3-6:   REST usage: ~90%  → GraphQL: ~50%
Week 7-10:  REST usage: ~60%  → GraphQL: ~85%
Week 11-12: REST usage: ~20%  → GraphQL: ~98%
```

---

## 📚 Documentation Strategy

### Migration Guide Content

1. **GraphQL Basics**
   - Why GraphQL (vs REST)
   - GraphQL Query Language Primer
   - How to use Apollo Client

2. **API Reference**
   - Auto-generated from `/graphql/schema`
   - Available at `https://docs.nova.app/graphql`
   - Searchable schema documentation

3. **Code Examples**
   - Before/After: REST to GraphQL
   - Real-time subscription examples
   - Pagination patterns

4. **Troubleshooting**
   - Common migration issues
   - Performance optimization tips
   - Debugging with GraphQL DevTools

---

## ⚠️ Known Limitations During Migration

### What's NOT Available Yet

1. **Messaging Mutations** - Still gRPC only
   - Solution: Use GraphQL subscriptions for real-time (read-only)
   - Workaround: Call gRPC from backend services

2. **Batch Operations** - Not in GraphQL yet
   - Use multiple mutations with IDs for now
   - Plan: Implement DataLoader batching

3. **File Uploads** - Not immediately supported
   - Workaround: Upload to S3 directly, link in GraphQL

---

## 🔐 Security During Migration

### Rate Limiting Both APIs

```rust
// REST API rate limit: 100 req/sec (deprecation discount)
// GraphQL rate limit: 100 req/sec (encourage migration)

// Expensive queries are rate-limited more aggressively
if depth > 5 || fields_count > 20 {
    rate_limit_config.requests_per_second = 10;
}
```

### Authentication Consistency

Both REST and GraphQL use same JWT validation:

```rust
// src/middleware/auth.rs
pub fn validate_jwt(token: &str) -> Result<Claims> {
    // Single validation logic for both APIs
    jsonwebtoken::decode(token, secret)
}
```

---

## 🎯 Success Metrics

Migration is complete when:

- ✅ 95%+ clients using GraphQL
- ✅ REST API usage < 5%
- ✅ Zero production incidents from migration
- ✅ Developer documentation fully updated
- ✅ All team members trained on GraphQL
- ✅ Monitoring shows 0 errors post-removal

---

## 📞 Support & Escalation

### For Clients Struggling with Migration

1. **Documentation**: https://docs.nova.app/graphql-migration
2. **Examples**: https://github.com/nova-app/graphql-examples
3. **Community Chat**: #graphql-migration (Slack)
4. **Support Email**: api-support@nova.app
5. **API Office Hours**: Every Tuesday 2 PM UTC (Zoom link in docs)

---

## ✅ Checklist Before Removal

- [ ] REST usage < 1%
- [ ] All public clients migrated
- [ ] Migration guide published and complete
- [ ] Team trained on GraphQL
- [ ] Monitoring shows no REST traffic spikes
- [ ] Backup of old REST schema archived
- [ ] Post-removal incident plan documented

---

**Status**: 🔴 Deprecation Phase 1 (Announcement)
**Next Review**: 2025-11-17
**Owner**: API Platform Team

