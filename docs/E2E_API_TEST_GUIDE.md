# E2E API Testing Guide

## Overview

This guide explains how to perform end-to-end API testing for the Nova platform's REST API endpoints exposed by the GraphQL Gateway.

## Prerequisites

### Required Tools

```bash
# Install jq (JSON processor)
brew install jq

# Verify installation
jq --version
curl --version
```

### Required Credentials

You need two pieces of information:

1. **JWT Token**: Valid authentication token from staging environment
2. **User ID**: UUID of the authenticated user

## How to Obtain Credentials

### Method 1: Using Existing User (Recommended for Testing)

If you already have a test account in staging:

```bash
# 1. Login via GraphQL Gateway
export GW_BASE="http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com"

# 2. Login request (replace with actual credentials)
curl -s -X POST "$GW_BASE/api/v2/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "your-email@example.com",
    "password": "your-password"
  }' | jq '.'

# 3. Extract token and user_id from response
# Response format:
# {
#   "token": "eyJhbGc...",
#   "user": {
#     "id": "550e8400-e29b-41d4-a716-446655440000",
#     ...
#   }
# }
```

### Method 2: Using kubectl to Extract from Pod

If you have kubectl access to staging:

```bash
# Port-forward to identity-service
kubectl port-forward -n nova-staging svc/identity-service 50051:50051

# Use grpcurl to create test user (if needed)
# This requires grpcurl and proper proto files
```

### Method 3: Database Direct Query

**⚠️ Use with caution - for emergency debugging only**

```bash
# Connect to staging database
kubectl port-forward -n nova-staging svc/postgres 5432:5432

# Query for test users
psql -h localhost -U nova -d nova_staging -c \
  "SELECT id, email, created_at FROM users WHERE email LIKE '%test%' LIMIT 5;"
```

## Running the E2E Tests

### Basic Usage

```bash
# 1. Set environment variables
export TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
export USER_ID="550e8400-e29b-41d4-a716-446655440000"

# 2. Run the test script
./scripts/e2e-api-test.sh
```

### Custom Gateway URL

```bash
# Override default gateway URL
export GW_BASE="http://your-custom-gateway-url.com"
export TOKEN="your-token"
export USER_ID="your-user-id"

./scripts/e2e-api-test.sh
```

### Save Test Results

```bash
# Save to file
./scripts/e2e-api-test.sh 2>&1 | tee e2e-test-results.log

# Filter only failures
./scripts/e2e-api-test.sh 2>&1 | grep -E "(FAIL|✗)"
```

## Test Categories

The E2E test script covers the following categories:

### 1. Health Checks (No Auth)
- `/health` - Basic service health
- `/health/circuit-breakers` - Circuit breaker status

### 2. Authentication (Public Endpoints)
- `/api/v2/auth/register` - User registration (skipped to avoid side effects)
- `/api/v2/auth/login` - User login (skipped - using existing token)
- `/api/v2/auth/refresh` - Token refresh (skipped to avoid invalidation)
- `/api/v2/auth/logout` - User logout (skipped to preserve session)

### 3. User Profile
- `GET /api/v2/users/{id}` - Get user profile
- `PUT /api/v2/users/{id}` - Update profile
- `POST /api/v2/users/avatar` - Request avatar upload URL

### 4. Channels
- `GET /api/v2/channels` - List all channels
- `GET /api/v2/channels/{id}` - Get channel details
- `GET /api/v2/users/{id}/channels` - Get user's subscribed channels
- `POST /api/v2/channels/subscribe` - Subscribe to channels
- `DELETE /api/v2/channels/unsubscribe` - Unsubscribe from channels

### 5. Devices
- `GET /api/v2/devices` - List user devices
- `GET /api/v2/devices/current` - Get current device info
- `POST /api/v2/devices` - Register device (skipped)
- `DELETE /api/v2/devices/{id}` - Remove device (skipped)

### 6. Invitations
- `POST /api/v2/invitations/generate` - Generate invite code
- `GET /api/v2/invitations/validate/{code}` - Validate invite
- `GET /api/v2/invitations` - List user invitations
- `GET /api/v2/invitations/stats` - Get invitation stats

### 7. Friends & Social Graph
- `GET /api/v2/friends/list` - Get friends list
- `GET /api/v2/search/users` - Search users
- `GET /api/v2/friends/recommendations` - Friend recommendations
- `POST /api/v2/friends/add` - Add friend
- `DELETE /api/v2/friends/remove` - Remove friend

### 8. Group Chat
- `GET /api/v2/chat/conversations` - List conversations
- `POST /api/v2/chat/groups/create` - Create group
- `GET /api/v2/chat/conversations/{id}` - Get conversation
- `GET /api/v2/chat/messages` - Get messages
- `POST /api/v2/chat/messages/send` - Send message
- `PUT /api/v2/chat/groups/{id}` - Update group info

### 9. Media Upload
- `POST /api/v2/media/upload` - Request upload URL
- Actual S3 upload (skipped - requires real file)

### 10. Feed
- `GET /api/v2/feed` - Personalized feed
- `GET /api/v2/feed/user/{id}` - User's feed
- `GET /api/v2/feed/explore` - Explore feed
- `GET /api/v2/feed/trending` - Trending feed

### 11. Social Interactions
- `POST /api/v2/social/likes` - Create like
- `GET /api/v2/social/likes` - Get likes
- `GET /api/v2/social/likes/check` - Check if liked
- `DELETE /api/v2/social/likes` - Remove like
- `POST /api/v2/social/comments` - Create comment
- `GET /api/v2/social/comments` - Get comments
- `DELETE /api/v2/social/comments/{id}` - Delete comment
- `POST /api/v2/social/shares` - Create share
- `GET /api/v2/social/shares/count` - Get share count

### 12. Alice AI Assistant
- `GET /api/v2/alice/status` - Alice status (not implemented)
- `POST /api/v2/alice/chat` - Chat with Alice (not implemented)
- `POST /api/v2/alice/voice` - Voice mode (not implemented)

## Understanding Test Results

### Output Format

```
========================================
[0] Health Checks
========================================
  [TEST] Basic health check ... ✓ 200
ok

  [TEST] Circuit breaker health ... ✓ 200
{
  "status": "healthy",
  "circuit_breakers": [...]
}

========================================
Test Summary
========================================
Total:   45
Passed:  38
Failed:  2
Skipped: 5

Pass Rate: 95%

Detailed Results:
  ✓ Basic health check
  ✓ Circuit breaker health
  ○ POST /api/v2/auth/register - SKIP (Would create new user)
  ✗ Get user profile - FAIL (401)
```

### Status Indicators

- `✓` - Test passed
- `✗` - Test failed
- `○` - Test skipped

### Common Failure Reasons

1. **401 Unauthorized**
   - Invalid or expired JWT token
   - Token not set in environment
   - Solution: Refresh token or login again

2. **403 Forbidden**
   - User doesn't have permission
   - Resource belongs to another user
   - Solution: Use appropriate user credentials

3. **404 Not Found**
   - Resource doesn't exist
   - Endpoint not implemented
   - Solution: Check if resource exists or endpoint is available

4. **500 Internal Server Error**
   - Backend service issue
   - Database connection problem
   - Solution: Check backend service logs

## Troubleshooting

### Check Service Health

```bash
# Basic health check (no auth)
curl http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/health

# Circuit breaker status (no auth)
curl http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/health/circuit-breakers
```

### Verify Token

```bash
# Decode JWT token (header and payload only, signature verification happens server-side)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '.'

# Check token expiration
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '.exp | todate'
```

### Test Individual Endpoints

```bash
# Test with verbose output
curl -v -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/users/$USER_ID"

# Save response headers
curl -D headers.txt -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/users/$USER_ID"

cat headers.txt
```

### Check Backend Logs

```bash
# GraphQL Gateway logs
kubectl logs -n nova-staging -l app=graphql-gateway --tail=100 -f

# Identity Service logs
kubectl logs -n nova-staging -l app=identity-service --tail=100 -f

# Content Service logs
kubectl logs -n nova-staging -l app=content-service --tail=100 -f
```

## Best Practices

### 1. Use Test Users

Always use dedicated test users for E2E testing:
- Email: `e2e-test-{number}@example.com`
- Easy to identify in logs
- Can be cleaned up after testing

### 2. Clean Up Test Data

After testing, clean up created resources:
```bash
# Delete test groups
# Delete test comments
# Delete test invitations
```

### 3. Run Tests in CI/CD

```yaml
# .github/workflows/e2e-test.yml
name: E2E API Tests

on:
  push:
    branches: [main, staging]
  pull_request:

jobs:
  e2e-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install jq
        run: sudo apt-get install -y jq
      - name: Run E2E tests
        env:
          TOKEN: ${{ secrets.STAGING_TEST_TOKEN }}
          USER_ID: ${{ secrets.STAGING_TEST_USER_ID }}
        run: ./scripts/e2e-api-test.sh
```

### 4. Monitor Test Results

Track test results over time:
- Pass rate trends
- Failed endpoint patterns
- Response time degradation

## Security Notes

### ⚠️ Token Security

- **NEVER** commit tokens to git
- **NEVER** share tokens in public channels
- **ALWAYS** use environment variables
- **ROTATE** test tokens regularly

### ⚠️ Rate Limiting

The API has rate limiting enabled:
- 100 requests per second per IP
- Burst capacity: 10 requests

If you hit rate limits:
```bash
# Add delays between requests
sleep 0.1  # 100ms delay
```

## Next Steps

1. **Automate**: Add to CI/CD pipeline
2. **Extend**: Add performance testing (response time tracking)
3. **Monitor**: Set up alerts for test failures
4. **Document**: Keep test cases updated with API changes

## Support

For issues or questions:
- Check backend logs first
- Review API documentation
- Contact backend team via Slack: #backend-support
