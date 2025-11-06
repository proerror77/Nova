# Notification Service Quick Start

## 🚀 Setup

### 1. Database Setup

```bash
# Run migrations
psql $DATABASE_URL -f backend/notification-service/migrations/001_initial_schema.sql
```

### 2. Environment Variables

```bash
export DATABASE_URL="postgres://user:password@localhost/nova"
export PORT=8000
export KAFKA_BROKER="localhost:9092"
```

### 3. Build and Run

```bash
# Development
cargo run -p notification-service

# Production
cargo build -p notification-service --release
./target/release/notification-service
```

## 📡 Endpoints

### HTTP (Port 8000)

- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics
- `GET /` - Service info

### gRPC (Port 9000)

All RPCs from `notification_service.proto`:

- `CreateNotification`
- `GetNotification`
- `GetNotifications` (with pagination)
- `MarkNotificationAsRead`
- `MarkAllNotificationsAsRead`
- `DeleteNotification`
- `RegisterPushToken`
- `UnregisterPushToken`
- `GetUnreadCount`
- `GetNotificationStats`
- `GetNotificationPreferences`

## 🔧 Testing

```bash
# Run tests
cargo test -p notification-service

# Run with logs
RUST_LOG=debug cargo test -p notification-service -- --nocapture
```

## 📊 Kafka Topics

The service consumes from:

- `MessageCreated`
- `FollowAdded`
- `CommentCreated`
- `PostLiked`
- `ReplyLiked`

## 📦 Features

✅ Real-time notification delivery via Kafka
✅ Batch processing (100 notifications / 5 seconds)
✅ Deduplication (1-minute window)
✅ Push notifications (FCM/APNs)
✅ Pagination and filtering
✅ Soft delete
✅ Statistics and metrics

## 🔍 Database Tables

- `notifications` - Core notifications
- `push_tokens` - Device tokens
- `push_delivery_logs` - Delivery tracking
- `notification_preferences` - User preferences
- `notification_dedup` - Deduplication cache

## 📈 Performance

- Batch throughput: > 1000 notifications/second
- Kafka latency: < 10 seconds
- Push success rate: > 99%

## 🐛 Troubleshooting

### Cannot connect to database

```bash
# Check connection
psql $DATABASE_URL -c "SELECT 1"

# Run migrations
psql $DATABASE_URL < backend/notification-service/migrations/001_initial_schema.sql
```

### Kafka consumer not working

```bash
# Check Kafka is running
kafka-topics.sh --list --bootstrap-server localhost:9092

# Create topics if needed
kafka-topics.sh --create --topic MessageCreated --bootstrap-server localhost:9092
```

### gRPC server not accessible

```bash
# Check port
netstat -an | grep 9000

# Test with grpcurl
grpcurl -plaintext localhost:9000 list
```

## 📝 Notes

- gRPC server runs on HTTP_PORT + 1000
- Kafka consumer starts automatically
- Push notifications require FCM/APNs credentials
- All timestamps are UTC
