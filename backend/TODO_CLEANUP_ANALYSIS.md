# Backend TODO Cleanup Analysis

Generated: 2025-10-30

## Summary

Total TODO items in backend: **104**

### Distribution by Service

| Service | Count | Category |
|---------|-------|----------|
| recommendation-service | 8 | gRPC stubs, JWT rotation |
| notification-service | 12 | APNs implementation, Kafka consumer |
| streaming-service | 9 | gRPC implementation, metrics export |
| video-service | 8 | Transcoding, progress tracking |
| user-service | 23 | Various utility and infrastructure |
| search-service | 5 | Redis optimization, consumers |
| messaging-service | 10 | Kafka consumer, metrics |
| Other (libs, etc) | 20+ | Configuration, utilities |

## TODO Categories

### 1. Implementation Stubs (High Priority)
- **Location**: recommendation-service, streaming-service, notification-service gRPC
- **Count**: ~35
- **Action**: Review each and either:
  - Remove if feature no longer needed
  - Convert to actual implementation
  - Move to Phase 2/Phase 3 planning

Examples:
```rust
// TODO: Implement actual gRPC call
// TODO: Implement actual feed generation logic
// TODO: Implement APNs API call
```

### 2. Feature Enhancements (Medium Priority)
- **Location**: user-service, streaming-service, recommendation-service
- **Count**: ~30
- **Examples**:
  - JWT key rotation service
  - Connection pooling for APNs
  - Batch processing optimization
- **Action**: Evaluate against current Phase 7A scope

### 3. Test/Infrastructure TODOs (Medium Priority)
- **Location**: Various services
- **Count**: ~20
- **Examples**:
  - "Setup test Redis"
  - "Test parallel sends"
- **Action**: Move to test task backlog

### 4. Outdated/Obsolete (Low Priority)
- **Location**: Multiple services
- **Count**: ~19 (estimated)
- **Examples**:
  - References to deprecated modules
  - Features replaced by auth-service deletion
- **Action**: Delete immediately

## Recommended Cleanup Approach

### Phase 1 (Immediate - 30 mins)
```
1. Delete obsolete TODOs related to deleted auth-service
2. Delete TODOs for features marked as "Phase 2" or "Phase 3"
3. Delete test setup TODOs that have alternatives
4. Commit as: "docs: remove obsolete TODO items"
```

### Phase 2 (Short Term - 2-3 hours)
```
1. Convert high-priority stubs to GitHub issues (in project issues tracker)
2. Create GitHub issue for each remaining TODO with context
3. Label by priority: P0, P1, P2, P3
4. Link to existing architecture documentation
```

### Phase 3 (Planning)
```
1. Prioritize GitHub issues for Phase 7B or Phase 8
2. Break large issues into smaller subtasks
3. Assign to team members
4. Create sprint planning from issues
```

## Critical TODOs to Address

### Blocking Issues
1. **gRPC servers not started** (recommendation-service, streaming-service)
   - Search: "TODO: Start gRPC server"
   - Impact: Services not serving gRPC endpoints
   - Fix: 1 hour

2. **APNs implementation incomplete** (notification-service)
   - Search: "TODO: Implement APNs"
   - Impact: iOS notifications may not work
   - Note: push.rs in messaging-service IS complete; this is notification-service wrapper
   - Fix: 2 hours

3. **Kafka consumers stubbed out**
   - Search: "TODO: Implement with rdkafka"
   - Impact: CDC pattern broken for certain event types
   - Fix: 3 hours per service

### Non-Blocking TODOs
1. Performance optimizations (connection pooling, batch processing)
2. Feature enhancements (key rotation, advanced metrics)
3. Test infrastructure setup

## Recommendations

1. **Quick Wins** (30 mins): Delete ~20 obsolete TODOs
2. **File GitHub Issues** (1-2 hours): Convert remaining 80+ into structured issues
3. **Planning** (1 hour): Categorize by phase and priority
4. **Backlog**: Move to project sprint planning

## Files with Most TODOs

```
16 grpc-related TODOs (recommendation-service, streaming-service)
16 server startup TODOs (main.rs files)
12 apns_client TODOs (notification-service)
10 kafka_consumer TODOs (multiple services)
```

---

**Status**: Analysis complete, ready for Phase 1 cleanup
**Owner**: Backend Architecture Team
**Estimated Total Cleanup Time**: 5-7 hours (all phases)
