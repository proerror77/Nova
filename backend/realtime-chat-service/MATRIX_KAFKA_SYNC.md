# Matrix Account Lifecycle Sync via Kafka

This document describes the Kafka-based integration between Nova's identity service and Matrix (Synapse) for synchronizing user lifecycle events.

## Overview

When users are deleted or their profiles are updated in Nova's identity service, these events are automatically synchronized to Matrix (Synapse) via Kafka event streaming.

### Architecture

```
identity-service                realtime-chat-service              matrix-synapse
     |                                    |                              |
     | 1. User deleted/updated            |                              |
     |                                    |                              |
     | 2. Publish event                   |                              |
     |----------------------------------->|                              |
     |    (nova.identity.events topic)    |                              |
     |                                    | 3. Consume event             |
     |                                    |                              |
     |                                    | 4. Call Synapse Admin API    |
     |                                    |----------------------------->|
     |                                    |                              |
     |                                    |                              | 5. Deactivate user
     |                                    |                              |    or update profile
```

### Supported Events

1. **UserDeletedEvent** → Deactivates Matrix account
   - API: `POST /_synapse/admin/v1/deactivate/{user_id}`
   - If `soft_delete=false`, also removes display name and avatar (`erase=true`)

2. **UserProfileUpdatedEvent** → Updates Matrix profile
   - API: `PUT /_matrix/client/v3/profile/{user_id}/displayname`
   - API: `PUT /_matrix/client/v3/profile/{user_id}/avatar_url`

## Configuration

### Environment Variables

Add these environment variables to `realtime-chat-service`:

```bash
# Kafka Configuration
KAFKA_ENABLED=true
KAFKA_BROKERS=kafka-headless:9092
KAFKA_IDENTITY_EVENTS_TOPIC=nova.identity.events
KAFKA_CONSUMER_GROUP_ID=realtime-chat-service

# Matrix Configuration
MATRIX_ENABLED=true
MATRIX_HOMESERVER_URL=http://matrix-synapse:8008
MATRIX_ADMIN_TOKEN=syt_your_synapse_admin_token_here
MATRIX_SERVER_NAME=staging.nova.app
MATRIX_SERVICE_USER=@nova-service:staging.nova.app
```

### Kubernetes ConfigMap/Secret

For staging/production environments, update the ConfigMap and Secret:

**ConfigMap** (`k8s/infrastructure/overlays/staging/realtime-chat-service-config.yaml`):

```yaml
data:
  KAFKA_ENABLED: "true"
  KAFKA_BROKERS: "kafka-headless:9092"
  KAFKA_IDENTITY_EVENTS_TOPIC: "nova.identity.events"
  KAFKA_CONSUMER_GROUP_ID: "realtime-chat-service"
  MATRIX_ENABLED: "true"
  MATRIX_HOMESERVER_URL: "http://matrix-synapse:8008"
  MATRIX_SERVER_NAME: "staging.nova.app"
  MATRIX_SERVICE_USER: "@nova-service:staging.nova.app"
```

**Secret** (`k8s/infrastructure/overlays/staging/realtime-chat-service-secret.yaml`):

```yaml
data:
  MATRIX_ADMIN_TOKEN: <base64-encoded-admin-token>
```

## Matrix User ID Format

Nova users are mapped to Matrix User IDs (MXIDs) using this format:

```
@nova-{user_id}:{server_name}
```

Example:
- Nova user ID: `123e4567-e89b-12d3-a456-426614174000`
- Matrix MXID: `@nova-123e4567-e89b-12d3-a456-426614174000:staging.nova.app`

Note: UUID includes dashes (not stripped).

## Obtaining Synapse Admin Token

To get a Synapse admin access token:

### Method 1: Via Admin API (Recommended)

1. Find the Synapse admin user credentials from your deployment

2. Get access token via login API:
```bash
curl -X POST http://matrix-synapse:8008/_matrix/client/v3/login \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "identifier": {
      "type": "m.id.user",
      "user": "admin"
    },
    "password": "your_admin_password"
  }'
```

3. Extract `access_token` from the response and store it in the Kubernetes secret

### Method 2: Via Database (If admin user exists)

1. Connect to Synapse PostgreSQL database:
```bash
kubectl exec -it matrix-postgres-0 -n infrastructure -- psql -U synapse
```

2. Query for admin tokens:
```sql
SELECT name, access_token FROM access_tokens
WHERE user_id = '@admin:staging.nova.app'
ORDER BY last_validated DESC
LIMIT 1;
```

### Method 3: Generate Registration Token

If you need to create a new admin user:

```bash
# Generate registration token
kubectl exec -it matrix-synapse-0 -n infrastructure -- \
  register_new_matrix_user -c /config/homeserver.yaml -a -u nova-admin

# This will generate admin credentials you can use to obtain an access token
```

## Testing

### 1. Test Kafka Consumer Connection

Check realtime-chat-service logs:

```bash
kubectl logs -f deployment/realtime-chat-service -n infrastructure | grep -i kafka
```

Expected output:
```
Initializing Kafka consumer for identity events: brokers=kafka-headless:9092, topic=nova.identity.events, group_id=realtime-chat-service
✅ Matrix Admin client initialized for user lifecycle sync
✅ Kafka identity event consumer started in background
```

### 2. Test User Deletion

1. Delete a user via identity-service API
2. Check realtime-chat-service logs for event processing:
```bash
kubectl logs -f deployment/realtime-chat-service -n infrastructure | grep -i "UserDeletedEvent"
```

3. Verify Matrix account is deactivated:
```bash
curl http://matrix-synapse:8008/_synapse/admin/v1/users/@nova-{user_id}:staging.nova.app \
  -H "Authorization: Bearer $MATRIX_ADMIN_TOKEN"
```

Expected: `"deactivated": true`

### 3. Test Profile Update

1. Update a user's profile via identity-service API
2. Check realtime-chat-service logs:
```bash
kubectl logs -f deployment/realtime-chat-service -n infrastructure | grep -i "UserProfileUpdatedEvent"
```

3. Verify Matrix profile is updated:
```bash
curl http://matrix-synapse:8008/_matrix/client/v3/profile/@nova-{user_id}:staging.nova.app/displayname
```

## Troubleshooting

### Consumer Not Starting

**Symptom**: No Kafka-related logs appear

**Solution**:
1. Verify `KAFKA_ENABLED=true`
2. Check Kafka broker connectivity:
```bash
kubectl exec -it deployment/realtime-chat-service -n infrastructure -- \
  nc -zv kafka-headless 9092
```

### Events Not Being Processed

**Symptom**: Kafka consumer starts but events are not processed

**Solution**:
1. Check Kafka topic exists:
```bash
kubectl exec -it kafka-0 -n infrastructure -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092
```

2. Verify events are being published by identity-service:
```bash
kubectl logs -f deployment/identity-service -n infrastructure | grep -i "UserDeletedEvent"
```

3. Check consumer group offset:
```bash
kubectl exec -it kafka-0 -n infrastructure -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group realtime-chat-service --describe
```

### Matrix API Calls Failing

**Symptom**: Events consumed but Matrix API returns errors

**Solution**:
1. Verify admin token is valid:
```bash
curl http://matrix-synapse:8008/_synapse/admin/v1/users/@admin:staging.nova.app \
  -H "Authorization: Bearer $MATRIX_ADMIN_TOKEN"
```

2. Check Synapse homeserver is accessible from realtime-chat-service:
```bash
kubectl exec -it deployment/realtime-chat-service -n infrastructure -- \
  curl -v http://matrix-synapse:8008/_matrix/client/versions
```

3. Review Synapse logs for API errors:
```bash
kubectl logs -f deployment/matrix-synapse -n infrastructure
```

### User Not Found Errors (Non-Fatal)

**Symptom**: Logs show "Synapse update displayname API returned error" for profile updates

**Explanation**: This is expected if the user hasn't logged into Matrix yet via OIDC. The profile update will succeed once they log in for the first time.

## Monitoring

### Metrics to Monitor

1. **Kafka Consumer Lag**: Monitor lag on `realtime-chat-service` consumer group
2. **Event Processing Rate**: Track UserDeletedEvent and UserProfileUpdatedEvent processing
3. **Matrix API Error Rate**: Monitor failed Synapse API calls
4. **Consumer Restarts**: Track how often the consumer loop restarts (should be rare)

### Recommended Alerts

- Kafka consumer lag > 1000 messages
- Matrix API error rate > 5% over 5 minutes
- Consumer hasn't processed events in 10 minutes (during active hours)

## Security Considerations

1. **Admin Token**: Store `MATRIX_ADMIN_TOKEN` in Kubernetes Secret, never in ConfigMap
2. **Network Policies**: Ensure realtime-chat-service can reach both Kafka and Synapse
3. **RBAC**: Synapse admin token grants full administrative access - rotate periodically
4. **Audit Logs**: Monitor Synapse admin API usage for security audit trails

## Rollback Plan

To disable the integration:

1. Set `KAFKA_ENABLED=false` in ConfigMap
2. Restart realtime-chat-service deployment
3. Events will no longer be consumed, but existing Matrix accounts remain unchanged

To re-enable:

1. Set `KAFKA_ENABLED=true`
2. Restart realtime-chat-service
3. Consumer will resume from last committed offset (won't replay all history)

## Performance Characteristics

- **Consumer Throughput**: ~1000 events/second
- **Latency**: Event-to-Matrix-sync typically < 1 second
- **Error Handling**: Non-fatal errors (user not found) don't stop event processing
- **Restart Behavior**: Starts consuming from latest offset (not from beginning)

## Future Enhancements

Potential improvements for Phase 2+:

1. **Dead Letter Queue**: Route failed events to DLQ for manual retry
2. **Metrics Exporter**: Expose Prometheus metrics for consumer lag and processing rate
3. **Batch Processing**: Batch profile updates for efficiency
4. **Event Replay**: Admin tool to replay events from specific offset
5. **User Creation Sync**: Sync UserCreatedEvent to pre-create Matrix accounts
