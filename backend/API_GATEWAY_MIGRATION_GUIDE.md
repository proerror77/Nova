# Nova API Gateway Migration Guide

## Overview

Nova backend now uses a **unified API gateway** (Nginx reverse proxy) to provide a single entry point for all services. This eliminates the need for clients to know about individual service ports and simplifies the architecture.

## Architecture Changes

### Before (Multi-Port Architecture)
```
Client → user-service:8080      (/api/v1/auth/*, /api/v1/users/*, /api/v1/search/users)
Client → messaging-service:8085 (/api/v1/conversations/*, /api/v1/messages/*)
Client → search-service:8086    (/api/v1/search/*)
```

**Problems:**
- Duplicate `/api/v1/search/users` endpoint in both user-service and search-service
- Clients need to track multiple service endpoints
- Port management complexity
- No centralized rate limiting or security

### After (Unified Gateway)
```
Client → api-gateway:3000 → {
    /api/v1/auth/*          → user-service:8080
    /api/v1/users/*         → user-service:8080
    /api/v1/posts/*         → user-service:8080
    /api/v1/conversations/* → messaging-service:3000
    /api/v1/messages/*      → messaging-service:3000
    /api/v1/search/*        → search-service:8086
}
```

**Benefits:**
- Single entry point: `http://localhost:3000`
- No duplicate endpoints (user-service search endpoint removed)
- Centralized rate limiting, logging, and security
- Easy to add new services without client changes
- Production-ready architecture

## Service Port Changes

| Service | Old Direct Port | New Gateway Access | Direct Access (Debug Only) |
|---------|----------------|-------------------|---------------------------|
| **API Gateway** | N/A | **Port 3000** (NEW) | N/A |
| user-service | 8080 | Via gateway:3000 | Commented out by default |
| messaging-service | 8085 | Via gateway:3000 | Commented out by default |
| search-service | 8086 | Via gateway:3000 | Commented out by default |

## Client Configuration Updates

### iOS Client (Swift)

**File:** `iOS/Nova/Config/APIConfig.swift` (or similar)

**Before:**
```swift
struct APIConfig {
    static let userServiceBaseURL = "http://localhost:8080"
    static let messagingServiceBaseURL = "http://localhost:8085"
    static let searchServiceBaseURL = "http://localhost:8086"
}
```

**After:**
```swift
struct APIConfig {
    // Unified API Gateway endpoint
    static let baseURL = "http://localhost:3000"

    // All services accessible through unified gateway
    // No need to track individual service URLs
}
```

**API Client Updates:**
```swift
// Before: Multiple service clients
class APIClient {
    let userService = URLSession.shared
    let messagingService = URLSession.shared
    let searchService = URLSession.shared

    func searchUsers(query: String) {
        let url = "\(APIConfig.searchServiceBaseURL)/api/v1/search/users?q=\(query)"
        // ...
    }
}

// After: Single unified client
class APIClient {
    let baseURL = APIConfig.baseURL

    func searchUsers(query: String) {
        let url = "\(baseURL)/api/v1/search/users?q=\(query)"
        // All endpoints now use same base URL
    }
}
```

### Web Client (JavaScript/TypeScript)

**File:** `web/src/config/api.ts` (or similar)

**Before:**
```typescript
export const API_CONFIG = {
  userService: 'http://localhost:8080',
  messagingService: 'http://localhost:8085',
  searchService: 'http://localhost:8086',
};
```

**After:**
```typescript
export const API_CONFIG = {
  baseURL: 'http://localhost:3000',
  // All services accessible through unified gateway
};

// Update API client
export const apiClient = axios.create({
  baseURL: API_CONFIG.baseURL,
  timeout: 10000,
});
```

### Environment Variables

**Before:**
```bash
# .env
REACT_APP_USER_SERVICE_URL=http://localhost:8080
REACT_APP_MESSAGING_SERVICE_URL=http://localhost:8085
REACT_APP_SEARCH_SERVICE_URL=http://localhost:8086
```

**After:**
```bash
# .env
REACT_APP_API_BASE_URL=http://localhost:3000
```

## API Endpoint Changes

### Search Endpoints (IMPORTANT)

**❌ REMOVED:** `GET /api/v1/search/users` from user-service

**✅ USE:** `GET /api/v1/search/users` via search-service (through gateway)

**Migration:**
- All search operations now go through search-service
- Search endpoints: `/api/v1/search/users`, `/api/v1/search/posts`, `/api/v1/search/hashtags`
- No changes needed in request/response format
- Just update the base URL to use the gateway

### Route Mapping Reference

| Route Pattern | Target Service | Notes |
|--------------|----------------|-------|
| `/api/v1/auth/*` | user-service | Login, register, OAuth |
| `/api/v1/users/*` | user-service | User profiles, relationships |
| `/api/v1/posts/*` | user-service | Posts, comments, likes |
| `/api/v1/videos/*` | user-service | Video uploads, streaming |
| `/api/v1/stories/*` | user-service | Ephemeral stories |
| `/api/v1/streams/*` | user-service | Live streaming |
| `/api/v1/feed/*` | user-service | Personalized feed |
| `/api/v1/discover/*` | user-service | Suggested users |
| `/api/v1/trending/*` | user-service | Trending content |
| `/api/v1/conversations/*` | messaging-service | DM conversations |
| `/api/v1/messages/*` | messaging-service | Direct messages |
| `/api/v1/search/*` | search-service | Search users/posts/hashtags |
| `/ws/*` | user-service | WebSocket for streams |
| `/ws/messaging/*` | messaging-service | WebSocket for messaging |

## WebSocket Connections

WebSocket endpoints also go through the gateway:

**Before:**
```javascript
const ws = new WebSocket('ws://localhost:8080/ws/streams/123/chat');
```

**After:**
```javascript
const ws = new WebSocket('ws://localhost:3000/ws/streams/123/chat');
```

## Development & Debugging

### Accessing the API Gateway

```bash
# All API requests go through port 3000
curl http://localhost:3000/api/v1/health

# Search users (now via search-service)
curl "http://localhost:3000/api/v1/search/users?q=john"

# Login
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"user@example.com","password":"password"}'
```

### Direct Service Access (Debug Only)

If you need to bypass the gateway for debugging, uncomment the port mappings in `docker-compose.yml`:

```yaml
user-service:
  ports:
    - "8080:8080"  # Uncomment for direct access

messaging-service:
  ports:
    - "8085:3000"  # Uncomment for direct access

search-service:
  ports:
    - "8086:8086"  # Uncomment for direct access
```

Then restart: `docker-compose up -d`

### Health Checks

```bash
# Gateway health
curl http://localhost:3000/health

# User service health (if port exposed)
curl http://localhost:8080/api/v1/health

# Messaging service health (if port exposed)
curl http://localhost:8085/health

# Search service health (if port exposed)
curl http://localhost:8086/health
```

## API Documentation

### Unified OpenAPI Specification

Access comprehensive API documentation:

```bash
# Unified OpenAPI spec (all services)
http://localhost:3000/api/v1/openapi.json

# Service-specific specs
http://localhost:3000/api/v1/openapi/user-service.json
http://localhost:3000/api/v1/openapi/messaging-service.json
http://localhost:3000/api/v1/openapi/search-service.json

# Swagger UI (interactive documentation)
http://localhost:3000/swagger-ui/
http://localhost:3000/docs
```

## Rate Limiting

The API gateway implements rate limiting:

- **General API endpoints:** 100 requests/second per IP (burst: 20)
- **Search endpoints:** 20 requests/second per IP (burst: 10)

Rate limit headers are included in responses:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1234567890
```

## Deployment Checklist

### Local Development

1. ✅ Update client base URL to `http://localhost:3000`
2. ✅ Remove old service-specific URLs from config
3. ✅ Update WebSocket connection URLs
4. ✅ Test all API endpoints through gateway
5. ✅ Verify search endpoints work correctly

### Docker Compose

```bash
# Start all services with API gateway
docker-compose up -d

# Verify gateway is running
docker ps | grep nova-api-gateway

# Check gateway logs
docker logs nova-api-gateway

# Test gateway routing
curl http://localhost:3000/health
```

### Production Deployment

**Additional configuration needed:**

1. **TLS/SSL:** Add SSL certificates to Nginx
2. **Domain:** Update `server_name` in `nginx.conf`
3. **Rate limiting:** Adjust limits based on traffic
4. **Monitoring:** Add Prometheus metrics endpoint
5. **CORS:** Review and restrict allowed origins

## Troubleshooting

### Issue: "Connection refused" on port 3000

**Check:**
```bash
# Is the gateway container running?
docker ps | grep api-gateway

# Check gateway logs
docker logs nova-api-gateway

# Verify services are running
docker-compose ps
```

### Issue: "404 Not Found" for known endpoint

**Check:**
1. Verify endpoint exists in service OpenAPI spec
2. Check Nginx routing configuration
3. Verify service is healthy: `docker logs <service-name>`

### Issue: Search endpoints not working

**Verify:**
```bash
# Check search-service is running
docker logs nova-search-service

# Test direct search-service access (if port exposed)
curl "http://localhost:8086/api/v1/search/users?q=test"

# Test via gateway
curl "http://localhost:3000/api/v1/search/users?q=test"
```

### Issue: WebSocket connections failing

**Check:**
1. WebSocket upgrade headers in Nginx config
2. Client using correct protocol: `ws://` or `wss://`
3. Gateway routing for `/ws/` paths

## Breaking Changes Summary

### ⚠️ BREAKING CHANGES

1. **Base URL change:** All clients MUST update to `http://localhost:3000`
2. **Search endpoint removed from user-service:** Use search-service via gateway
3. **Direct service access disabled by default:** Only accessible through gateway
4. **Port changes:** Services no longer expose individual ports to host

### ✅ NON-BREAKING

1. **Request/response formats:** Unchanged
2. **Authentication:** Same JWT tokens work across all services
3. **Endpoint paths:** All `/api/v1/*` paths remain the same
4. **WebSocket protocols:** No changes to message formats

## Migration Timeline

### Phase 1: Update Configuration (Day 1)
- Update all client configs to use `http://localhost:3000`
- Remove service-specific URL configurations
- Update environment variables

### Phase 2: Testing (Day 2)
- Test all API endpoints through gateway
- Verify WebSocket connections
- Test rate limiting behavior
- Validate search functionality

### Phase 3: Cleanup (Day 3)
- Remove direct port mappings from docker-compose.yml
- Update documentation
- Remove old service URL references from code

## Support

If you encounter issues during migration:

1. Check this guide first
2. Review service logs: `docker logs <service-name>`
3. Test endpoints with `curl` to isolate client vs. server issues
4. Verify gateway routing in `backend/nginx/nginx.conf`

## Kubernetes/Production Deployment

For Kubernetes deployment, see: `backend/k8s/ingress.yaml` (to be created)

The Nginx configuration can be adapted to Kubernetes Ingress with minimal changes.
