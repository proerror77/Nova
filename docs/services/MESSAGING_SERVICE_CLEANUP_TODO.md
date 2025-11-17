# messaging-service Cleanup TODO

**Phase**: E - Service Refactoring
**Date**: 2025-11-12
**Status**: ⏳ Pending Cleanup

## Background

After Phase E refactoring:
1. ✅ realtime-chat-service - WebSocket + E2EE logic extracted
2. ✅ notification-service - Push notification logic (already superior)
3. ❌ messaging-service - TO BE DELETED (no remaining purpose)

## Files to DELETE

### 1. Push Notification Services (Obsolete)

These files are **obsolete** because notification-service has superior implementations:

```bash
backend/messaging-service/src/services/
├── fcm.rs                   # DELETE: Old FCM using fcm = "0.9" crate
├── push.rs                  # DELETE: Simple ApnsPush wrapper (nova-apns-shared)
├── notification_service.rs  # DELETE: Old notification service
└── notification_queue.rs    # DELETE: PostgreSQL-based queue (replaced by priority_queue.rs)
```

**Reason**: notification-service has:
- Modern shared libraries (nova-fcm-shared, nova-apns-shared)
- Advanced features (batch sending, priority queue, rate limiting)
- Better error handling and retry logic
- Kafka integration for event-driven architecture

### 2. WebSocket & E2EE Services (Moved)

These files have been **moved to realtime-chat-service**:

```bash
backend/messaging-service/src/services/
├── message_service.rs       # DELETE: Moved to realtime-chat-service
├── conversation_service.rs  # DELETE: Moved to realtime-chat-service
├── call_service.rs          # DELETE: Moved to realtime-chat-service (WebRTC signaling)
├── location_service.rs      # DELETE: Moved to realtime-chat-service (location sharing)
├── offline_queue.rs         # DELETE: Moved to realtime-chat-service (offline message queue)
├── e2ee.rs                  # DELETE: Moved to realtime-chat-service (E2EE message handling)
├── encryption.rs            # DELETE: Moved to realtime-chat-service (encryption primitives)
└── key_exchange.rs          # DELETE: Moved to realtime-chat-service (X25519 key exchange)
```

**Reason**: All real-time messaging and E2EE functionality is now in realtime-chat-service.

### 3. Auth Client (Shared)

```bash
backend/messaging-service/src/services/
└── auth_client.rs           # DELETE: Use grpc-clients/auth_client instead
```

**Reason**: Moved to shared library `grpc-clients` for reuse across services.

### 4. Dependencies to REMOVE

From `backend/messaging-service/Cargo.toml`:

```toml
# DELETE: Old push notification crates
fcm = "0.9"              # Replaced by nova-fcm-shared
apns2 = "0.1"            # Replaced by nova-apns-shared (was mixed with nova-apns-shared)

# DELETE: WebSocket dependencies (moved to realtime-chat-service)
tokio-tungstenite = "0.28"
actix-web-actors = "4.3"

# DELETE: E2EE dependencies (moved to realtime-chat-service)
x25519-dalek = "2.0"
hkdf = { workspace = true }

# DELETE: If messaging-service is deleted entirely
# All dependencies become obsolete
```

### 5. Entire Service Deletion (Final Step)

After confirming all functionality is migrated:

```bash
# DELETE ENTIRE SERVICE
rm -rf backend/messaging-service/

# UPDATE workspace Cargo.toml
# Remove "messaging-service" from workspace members

# UPDATE deployment configs
# Remove messaging-service from:
# - k8s manifests
# - docker-compose files
# - CI/CD pipelines
```

## Verification Checklist

Before deleting messaging-service, verify:

- [ ] ✅ realtime-chat-service handles all WebSocket connections
- [ ] ✅ realtime-chat-service handles all E2EE message encryption/decryption
- [ ] ✅ notification-service handles all push notifications (FCM + APNs)
- [ ] ✅ All gRPC clients use grpc-clients library (not local auth_client)
- [ ] ✅ No services reference messaging-service in their dependencies
- [ ] ✅ Database migrations are preserved (if any messaging-specific tables exist)
- [ ] ✅ Integration tests updated to use realtime-chat-service + notification-service

## Current Status

### ✅ Completed
- [x] realtime-chat-service extracted and operational
- [x] notification-service has superior push notification logic
- [x] Analysis completed: No migration needed for push notifications

### ⏳ Pending
- [ ] Remove push notification files from messaging-service
- [ ] Remove WebSocket/E2EE files from messaging-service
- [ ] Update service dependencies
- [ ] Delete messaging-service entirely
- [ ] Update deployment configurations

## Migration Path

### Step 1: Soft Deprecation (Current)
```yaml
# Mark messaging-service as deprecated in k8s
annotations:
  deprecated: "true"
  replacement: "realtime-chat-service, notification-service"
```

### Step 2: Traffic Migration
```yaml
# Redirect all traffic to new services
apiVersion: v1
kind: Service
metadata:
  name: messaging-service
spec:
  # Route WebSocket to realtime-chat-service
  # Route push notifications to notification-service
```

### Step 3: Service Deletion
```bash
# After 1-2 release cycles of traffic monitoring
kubectl delete deployment messaging-service
kubectl delete service messaging-service
rm -rf backend/messaging-service/
```

## Dependencies Analysis

### Services that USE messaging-service (need updates)
```bash
# Search for messaging-service references
$ rg "messaging-service" backend/ --type toml
# No results = safe to delete

$ rg "messaging_service" backend/ --type rust
# Update any import statements to use:
# - realtime-chat-service for WebSocket/E2EE
# - notification-service for push notifications
```

### Services that PROVIDE functionality to messaging-service
```bash
# These services are unaffected by deletion:
- user-service (gRPC client used by messaging-service)
- auth-service (gRPC client used by messaging-service)
```

## Rollback Plan

If issues are discovered after deletion:

1. **Restore from Git**:
   ```bash
   git checkout <commit-before-deletion> -- backend/messaging-service/
   ```

2. **Re-deploy**:
   ```bash
   kubectl apply -f k8s/messaging-service/
   ```

3. **Traffic Split**:
   ```yaml
   # Route partial traffic back to messaging-service
   # While debugging issues in realtime-chat-service/notification-service
   ```

## Timeline

- **2025-11-12**: Analysis complete - No migration needed
- **2025-11-20** (Target): Soft deprecation deployed
- **2025-12-01** (Target): Traffic fully migrated
- **2025-12-15** (Target): messaging-service deleted

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Missing functionality | High | Comprehensive feature comparison completed ✅ |
| Data loss | High | Database tables preserved, only code deleted |
| Service downtime | Medium | Blue-green deployment, traffic split |
| Rollback complexity | Low | Git history + k8s manifests preserved |

## Conclusion

**messaging-service can be safely deleted** after:
1. ✅ Confirming realtime-chat-service handles WebSocket/E2EE
2. ✅ Confirming notification-service handles push notifications
3. ⏳ Monitoring traffic patterns for 1-2 release cycles
4. ⏳ Updating all service references

**No functionality is lost** - all features are preserved in specialized services with better architecture.

---

**Status**: ⏳ Ready for cleanup after traffic validation
**Owner**: Backend Team
**Next Review**: 2025-11-20
