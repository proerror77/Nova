# Nova iOS - API Specification

## Base URL
```
https://api.nova.app
```

## Authentication
All authenticated endpoints require:
```
Authorization: Bearer {access_token}
```

## Endpoints (15 Total)

### Auth Endpoints (4)

#### 1. POST `/auth/signin`
**Email/password sign in**

Request:
```json
{
  "email": "user@example.com",
  "password": "securePassword123"
}
```

Response (200):
```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "eyJhbGc...",
  "user": {
    "id": "user_123",
    "username": "johndoe",
    "display_name": "John Doe",
    "avatar_url": "https://cdn.nova.app/avatars/user_123.jpg",
    "bio": "Hello world",
    "followers_count": 42,
    "following_count": 100,
    "posts_count": 15
  }
}
```

#### 2. POST `/auth/signup`
**Create new account**

Request:
```json
{
  "username": "johndoe",
  "email": "user@example.com",
  "password": "securePassword123"
}
```

Response (201): Same as sign in

#### 3. POST `/auth/apple`
**Sign in with Apple**

Request:
```json
{
  "identity_token": "eyJraWQ...",
  "user": "000123.abc456...",
  "email": "user@privaterelay.appleid.com",
  "full_name": "John Doe"
}
```

Response (200): Same as sign in

#### 4. POST `/auth/refresh`
**Refresh access token**

Request:
```json
{
  "refresh_token": "eyJhbGc..."
}
```

Response (200):
```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "eyJhbGc..."
}
```

---

### Feed Endpoints (2)

#### 5. GET `/feed`
**Get personalized feed**

Query params:
- `page` (int, default: 0)
- `limit` (int, default: 20, max: 50)

Response (200):
```json
{
  "posts": [
    {
      "id": "post_123",
      "author": { /* User object */ },
      "image_url": "https://cdn.nova.app/posts/post_123.jpg",
      "caption": "Beautiful sunset 🌅",
      "like_count": 42,
      "comment_count": 5,
      "is_liked": false,
      "created_at": "2025-10-18T10:30:00Z"
    }
  ],
  "has_more": true
}
```

#### 6. GET `/posts/:id`
**Get single post details**

Response (200):
```json
{
  "id": "post_123",
  "author": { /* User object */ },
  "image_url": "https://cdn.nova.app/posts/post_123.jpg",
  "caption": "Beautiful sunset 🌅",
  "like_count": 42,
  "comment_count": 5,
  "is_liked": false,
  "created_at": "2025-10-18T10:30:00Z"
}
```

---

### Post Interaction Endpoints (4)

#### 7. POST `/posts`
**Create new post** (requires idempotency-key)

Request (multipart/form-data):
```
image: [binary]
caption: "My photo"
```

Response (201):
```json
{
  "id": "post_123",
  "image_url": "https://cdn.nova.app/posts/post_123.jpg",
  "created_at": "2025-10-18T10:30:00Z"
}
```

#### 8. POST `/posts/:id/like`
**Like a post** (requires idempotency-key)

Response (200):
```json
{}
```

#### 9. DELETE `/posts/:id/like`
**Unlike a post**

Response (200):
```json
{}
```

#### 10. DELETE `/posts/:id`
**Delete own post**

Response (204): No content

---

### Comment Endpoints (2)

#### 11. GET `/posts/:id/comments`
**Get comments for a post**

Query params:
- `page` (int, default: 0)
- `limit` (int, default: 20)

Response (200):
```json
{
  "comments": [
    {
      "id": "comment_123",
      "post_id": "post_123",
      "author": { /* User object */ },
      "text": "Great shot!",
      "created_at": "2025-10-18T10:35:00Z"
    }
  ],
  "has_more": false
}
```

#### 12. POST `/posts/:id/comments`
**Create comment** (requires idempotency-key)

Request:
```json
{
  "text": "Great shot!"
}
```

Response (201):
```json
{
  "id": "comment_123",
  "created_at": "2025-10-18T10:35:00Z"
}
```

---

### Search Endpoints (1)

#### 13. GET `/search/users`
**Search for users**

Query params:
- `q` (string, required)
- `page` (int, default: 0)
- `limit` (int, default: 20)

Response (200):
```json
{
  "users": [
    { /* User object */ }
  ],
  "has_more": false
}
```

---

### Profile Endpoints (2)

#### 14. PATCH `/users/:id`
**Update profile** (multipart/form-data)

Request:
```
display_name: "John Doe Jr."
bio: "Updated bio"
avatar: [binary]
```

Response (200):
```json
{
  /* Updated User object */
}
```

#### 15. DELETE `/users/:id`
**Delete account**

Response (204): No content

---

## Upload Flow

### Presigned Upload (S3)

#### POST `/upload/presign`
Request:
```json
{
  "filename": "photo.jpg",
  "content_type": "image/jpeg"
}
```

Response (200):
```json
{
  "upload_url": "https://s3.amazonaws.com/nova-uploads/...",
  "file_key": "uploads/abc123/photo.jpg",
  "expires_at": "2025-10-18T11:30:00Z"
}
```

Then upload directly to S3:
```
PUT {upload_url}
Content-Type: image/jpeg
[binary data]
```

---

## Error Responses

### 400 Bad Request
```json
{
  "error": "validation_error",
  "message": "Invalid email format",
  "fields": {
    "email": "Must be a valid email address"
  }
}
```

### 401 Unauthorized
```json
{
  "error": "unauthorized",
  "message": "Invalid or expired token"
}
```

### 404 Not Found
```json
{
  "error": "not_found",
  "message": "Post not found"
}
```

### 429 Too Many Requests
```json
{
  "error": "rate_limit_exceeded",
  "message": "Too many requests, retry after 60 seconds",
  "retry_after": 60
}
```

### 500 Internal Server Error
```json
{
  "error": "internal_error",
  "message": "An unexpected error occurred",
  "request_id": "req_abc123"
}
```

---

## Rate Limits
- **Feed endpoints:** 100 requests/minute
- **Post creation:** 10 requests/hour
- **Like/unlike:** 300 requests/minute
- **Search:** 60 requests/minute

## Idempotency
Mutating operations (POST/PATCH/DELETE) support idempotency via:
```
Idempotency-Key: {uuid}
```

Repeat requests with same key within 24h return cached response.

## Pagination
Standard pagination pattern:
```
?page=0&limit=20
```

Response includes `has_more` field to indicate if more pages exist.

## Date Format
All timestamps use ISO 8601 format:
```
2025-10-18T10:30:00Z
```
