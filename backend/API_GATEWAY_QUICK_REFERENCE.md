# Nova API Gateway - Quick Reference

## 🚀 Quick Start

### Unified API Entry Point
```bash
# New unified base URL
http://localhost:3000

# All services accessible through single port
```

### Start Services
```bash
cd /path/to/nova
docker-compose up -d

# Verify gateway is running
curl http://localhost:3000/health
```

## 📋 Client Configuration Changes

### iOS (Swift)
```swift
// Before
static let baseURL = "http://localhost:8080"

// After
static let baseURL = "http://localhost:3000"
```

### Web (TypeScript/JavaScript)
```typescript
// Before
const API_BASE_URL = 'http://localhost:8080';

// After
const API_BASE_URL = 'http://localhost:3000';
```

## 🔀 Service Routing

| Endpoint Pattern | Service | Port |
|-----------------|---------|------|
| `/api/v1/auth/*` | user-service | 8080 |
| `/api/v1/users/*` | user-service | 8080 |
| `/api/v1/posts/*` | user-service | 8080 |
| `/api/v1/conversations/*` | messaging-service | 3000 |
| `/api/v1/messages/*` | messaging-service | 3000 |
| `/api/v1/search/*` | **search-service** | 8086 |

## ⚠️ Breaking Changes

### ❌ REMOVED
```bash
# User-service search endpoint (REMOVED)
GET /api/v1/search/users  # from user-service:8080
```

### ✅ USE INSTEAD
```bash
# Search-service endpoint (via gateway)
GET http://localhost:3000/api/v1/search/users?q=john
GET http://localhost:3000/api/v1/search/posts?q=hello
GET http://localhost:3000/api/v1/search/hashtags?q=tech
```

## 🧪 Testing

### Health Checks
```bash
# Gateway health
curl http://localhost:3000/health

# All services
docker-compose ps
```

### Search Endpoints
```bash
# Search users (via gateway)
curl "http://localhost:3000/api/v1/search/users?q=john"

# Search posts
curl "http://localhost:3000/api/v1/search/posts?q=hello"
```

### Authentication
```bash
# Login via gateway
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"user@example.com","password":"password"}'
```

## 📚 Documentation

```bash
# Unified OpenAPI spec
http://localhost:3000/api/v1/openapi.json

# Swagger UI
http://localhost:3000/swagger-ui/

# Service-specific specs
http://localhost:3000/api/v1/openapi/user-service.json
http://localhost:3000/api/v1/openapi/messaging-service.json
http://localhost:3000/api/v1/openapi/search-service.json
```

## 🐛 Debugging

### Enable Direct Service Access
Uncomment in `docker-compose.yml`:
```yaml
user-service:
  ports:
    - "8080:8080"  # Uncomment this line

messaging-service:
  ports:
    - "8085:3000"  # Uncomment this line

search-service:
  ports:
    - "8086:8086"  # Uncomment this line
```

Then: `docker-compose up -d`

### Check Logs
```bash
# Gateway logs
docker logs nova-api-gateway

# Service logs
docker logs nova-user-service
docker logs nova-messaging-service
docker logs nova-search-service
```

## 🎯 Migration Checklist

- [ ] Update client base URL to `http://localhost:3000`
- [ ] Remove service-specific URLs from configuration
- [ ] Update search endpoint calls to use gateway
- [ ] Test all API endpoints
- [ ] Test WebSocket connections
- [ ] Verify rate limiting behavior
- [ ] Update environment variables
- [ ] Update CI/CD pipelines (if applicable)

## 📞 Common Issues

### "Connection refused" on port 3000
```bash
# Check if gateway is running
docker ps | grep api-gateway
docker logs nova-api-gateway
```

### "404 Not Found"
```bash
# Verify service is running
docker-compose ps

# Check service logs
docker logs <service-name>
```

### Search not working
```bash
# Test search-service directly (if port exposed)
curl "http://localhost:8086/api/v1/search/users?q=test"

# Test via gateway
curl "http://localhost:3000/api/v1/search/users?q=test"
```

## 🚢 Production Deployment

For Kubernetes:
```bash
kubectl apply -f backend/k8s/ingress.yaml
```

Update domain in `ingress.yaml`:
```yaml
spec:
  rules:
    - host: api.yourdomain.com  # Change this
```

---

**For detailed documentation, see:** [API_GATEWAY_MIGRATION_GUIDE.md](./API_GATEWAY_MIGRATION_GUIDE.md)
