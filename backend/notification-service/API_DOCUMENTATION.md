# Notification Service API Documentation

## Overview
The Notification Service provides a comprehensive REST API for managing push notifications across multiple platforms (FCM for Android/Web, APNs for iOS).

## Base URL
```
http://localhost:8000/api/v1
```

## Health Check
```
GET /health
```
Returns `OK` if service is running.

---

## Notification Endpoints

### Create Notification
Creates and stores a new notification.

**Endpoint:** `POST /notifications`

**Request Body:**
```json
{
  "recipient_id": "uuid",
  "sender_id": "uuid (optional)",
  "notification_type": "like|comment|follow|mention|system|message|video|stream",
  "title": "Notification Title",
  "body": "Notification body/message",
  "image_url": "https://... (optional)",
  "object_id": "uuid (optional)",
  "object_type": "post|comment|conversation (optional)",
  "metadata": { "key": "value" } (optional),
  "priority": "low|normal|high (default: normal)"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "recipient_id": "uuid",
    "notification_type": "like",
    "title": "Notification Title",
    "body": "...",
    "priority": "normal",
    "status": "queued",
    "is_read": false,
    "created_at": "2025-01-01T00:00:00Z"
  }
}
```

**Status Codes:**
- `200 OK` - Notification created successfully
- `500 Internal Server Error` - Failed to create notification

---

### Get Notification
Retrieves a notification by ID.

**Endpoint:** `GET /notifications/{id}`

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "recipient_id": "uuid",
    ...
  }
}
```

**Status Codes:**
- `200 OK` - Notification found
- `404 Not Found` - Notification not found
- `500 Internal Server Error` - Server error

---

### Mark as Read
Marks a notification as read.

**Endpoint:** `PUT /notifications/{id}/read`

**Response:**
```json
{
  "success": true,
  "data": {
    "success": true
  }
}
```

**Status Codes:**
- `200 OK` - Successfully marked as read
- `500 Internal Server Error` - Server error

---

### Send Notification
Sends a notification to all user devices via push channels.

**Endpoint:** `POST /notifications/{id}/send`

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "device_token_id": "uuid",
      "success": true,
      "message_id": "fcm-message-id",
      "error": null
    }
  ]
}
```

**Status Codes:**
- `200 OK` - Sent successfully (see results for per-device status)
- `404 Not Found` - Notification not found
- `500 Internal Server Error` - Server error

---

## Device Management Endpoints

### Register Device
Registers a new device token for push notifications.

**Endpoint:** `POST /devices/register`

**Request Body:**
```json
{
  "user_id": "uuid",
  "token": "device-token-from-fcm-or-apns",
  "channel": "fcm|apns|websocket",
  "device_type": "ios|android|web"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "device_id": "uuid",
    "success": true
  }
}
```

**Status Codes:**
- `200 OK` - Device registered successfully
- `500 Internal Server Error` - Failed to register device

---

### Unregister Device
Deactivates a device token.

**Endpoint:** `POST /devices/unregister`

**Request Body:**
```json
{
  "user_id": "uuid",
  "token": "device-token"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "success": true
  }
}
```

**Status Codes:**
- `200 OK` - Device unregistered successfully
- `500 Internal Server Error` - Failed to unregister device

---

### Get User Devices
Lists all active devices for a user.

**Endpoint:** `GET /devices/user/{user_id}`

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "token": "device-token",
      "channel": "fcm",
      "device_type": "android",
      "is_active": true,
      "created_at": "2025-01-01T00:00:00Z"
    }
  ]
}
```

**Status Codes:**
- `200 OK` - Devices retrieved successfully
- `500 Internal Server Error` - Server error

---

## Preference Endpoints

### Get Preferences
Retrieves notification preferences for a user.

**Endpoint:** `GET /preferences/{user_id}`

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "user_id": "uuid",
    "enabled": true,
    "like_enabled": true,
    "comment_enabled": true,
    "follow_enabled": true,
    "mention_enabled": true,
    "message_enabled": true,
    "stream_enabled": true,
    "quiet_hours_start": "22:00 (optional)",
    "quiet_hours_end": "08:00 (optional)",
    "prefer_fcm": true,
    "prefer_apns": true,
    "prefer_email": false
  }
}
```

**Status Codes:**
- `200 OK` - Preferences retrieved (or default created if not found)
- `500 Internal Server Error` - Server error

---

### Update Preferences
Updates notification preferences for a user.

**Endpoint:** `PUT /preferences/{user_id}`

**Request Body:**
```json
{
  "enabled": true (optional),
  "like_enabled": true (optional),
  "comment_enabled": true (optional),
  "follow_enabled": true (optional),
  "mention_enabled": true (optional),
  "message_enabled": true (optional),
  "stream_enabled": true (optional),
  "quiet_hours_start": "22:00" (optional),
  "quiet_hours_end": "08:00" (optional),
  "prefer_fcm": true (optional),
  "prefer_apns": true (optional),
  "prefer_email": false (optional)
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    ...
  }
}
```

**Status Codes:**
- `200 OK` - Preferences updated successfully
- `500 Internal Server Error` - Server error

---

## Error Response Format

All error responses follow this format:

```json
{
  "success": false,
  "data": null,
  "error": "Error description"
}
```

---

## Notification Types

- `like` - User liked a post or comment
- `comment` - User commented on a post
- `follow` - User started following
- `mention` - User was mentioned in a post or comment
- `system` - System notification
- `message` - Direct message
- `video` - Video-related notification
- `stream` - Live stream notification

---

## Priority Levels

- `low` - Batched delivery, can be delayed
- `normal` - Standard delivery (default)
- `high` - Immediate delivery

---

## Notification Status

- `queued` - Waiting to be sent
- `sending` - Currently being sent
- `delivered` - Successfully delivered to device
- `failed` - Failed to deliver
- `read` - User has read the notification
- `dismissed` - User dismissed the notification

---

## Database Expiration

Notifications are automatically deleted after 30 days.

---

## Examples

### Create and Send a Notification

```bash
# 1. Create notification
curl -X POST http://localhost:8000/api/v1/notifications \
  -H "Content-Type: application/json" \
  -d '{
    "recipient_id": "550e8400-e29b-41d4-a716-446655440000",
    "sender_id": "550e8400-e29b-41d4-a716-446655440001",
    "notification_type": "like",
    "title": "New Like",
    "body": "John liked your post",
    "priority": "normal"
  }'

# 2. Send the notification
curl -X POST http://localhost:8000/api/v1/notifications/{notification_id}/send

# 3. Mark as read
curl -X PUT http://localhost:8000/api/v1/notifications/{notification_id}/read
```

### Register Device and Get Notifications

```bash
# 1. Register device
curl -X POST http://localhost:8000/api/v1/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "token": "fcm_device_token_here",
    "channel": "fcm",
    "device_type": "android"
  }'

# 2. Get user devices
curl -X GET http://localhost:8000/api/v1/devices/user/550e8400-e29b-41d4-a716-446655440000

# 3. Get preferences
curl -X GET http://localhost:8000/api/v1/preferences/550e8400-e29b-41d4-a716-446655440000

# 4. Update preferences
curl -X PUT http://localhost:8000/api/v1/preferences/550e8400-e29b-41d4-a716-446655440000 \
  -H "Content-Type: application/json" \
  -d '{
    "like_enabled": true,
    "comment_enabled": false,
    "quiet_hours_start": "22:00"
  }'
```
