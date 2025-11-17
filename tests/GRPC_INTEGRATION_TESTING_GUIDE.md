# gRPC Cross-Service Integration Testing Guide

This guide explains how to run integration tests for gRPC communication between microservices in the Nova platform.

## Overview

The integration tests validate:
- Service connectivity and availability
- Cross-service gRPC communication
- Request/response handling
- Error handling and timeouts
- Data consistency across services
- Concurrent service interactions

## Architecture

> ⚠️ **注意**：本文件原始版本針對 V1 `user-service` / `messaging-service`。目前兩個服務皆已淘汰，整個身份與即時訊息域分別由 **identity-service** 與 **realtime-chat-service** 負責。以下章節已更新為 V2 架構，若需查閱舊版流程請參考 `docs/legacy/` 目錄。
>
> | Legacy 名稱 | 目前對應服務 | 備註 |
> |-------------|--------------|------|
> | user-service | identity-service | Auth / Profile API 全數併入 identity-service |
> | messaging-service | realtime-chat-service | 即時訊息、歷史查詢、呼叫、typing indicator |
> | auth-service | identity-service | 舊命名僅保留於 proto 套件 `nova.identity_service.v2` |

### Services Under Test

1. **Identity Service** (gRPC: port 50051)
   - Auth、Token、使用者基本資料查詢
   - gRPC endpoint: `http://127.0.0.1:50051`

2. **Realtime Chat Service** (gRPC: port 50052)
   - Conversation、Message、Call signaling、Typing indicator
   - gRPC endpoint: `http://127.0.0.1:50052`

3. **Graph Service** (gRPC: port 9083)
   - Follow/Mute/Block 圖譜，供 gateway 與 feed-service 查詢

### Service Dependencies

```
┌─────────────────┐
│  Messaging      │
│  Service        │
└────────┬────────┘
         │ queries
         ▼
┌─────────────────┐      ┌────────────────┐
│  User           │◄────┤  Auth          │
│  Service        │      │  Service       │
└─────────────────┘      └────────────────┘
```

## Running Tests

### 1. Local Development Testing

#### Prerequisites

```bash
# Start all services locally
cargo run -p identity-service &
cargo run -p realtime-chat-service &
cargo run -p graph-service &

# Wait for services to be ready (check logs)
sleep 5
```

#### Run Integration Tests via Makefile

```bash
# Run all gRPC integration tests
make test-grpc-integration-local

# Or run the test script directly
make test-grpc-script
```

#### Run Integration Tests via Cargo

```bash
# Run with services running
SERVICES_RUNNING=true cargo test --test grpc_cross_service_integration_test -- --nocapture --ignored
```

### 2. Kubernetes Staging Testing

#### Prerequisites

```bash
# Ensure kubectl is configured
kubectl config current-context

# Verify services are deployed
kubectl get pods -n nova-user -l app=user-service
kubectl get pods -n nova-messaging -l app=messaging-service
kubectl get pods -n nova-auth -l app=auth-service
```

#### Run Integration Tests via Script

```bash
# Run tests against staging environment
make test-grpc-script-staging

# Or directly
./tests/grpc_integration_test.sh staging
```

### 3. Manual Testing with grpcurl

Install grpcurl (for manual gRPC testing):

```bash
# macOS
brew install grpcurl

# Ubuntu/Debian
apt-get install grpcurl
```

Test User Service:

```bash
# Get user profile
grpcurl -plaintext \
  -d '{"user_id": "user-123"}' \
  127.0.0.1:9081 \
  nova.user_service.UserService.GetUserProfile

# Search users
grpcurl -plaintext \
  -d '{"query": "alice", "limit": 10}' \
  127.0.0.1:9081 \
  nova.user_service.UserService.SearchUsers
```

Test Messaging Service:

```bash
# Get messages in conversation
grpcurl -plaintext \
  -d '{"conversation_id": "conv-123", "limit": 20}' \
  127.0.0.1:9085 \
  nova.messaging_service.MessagingService.GetMessages

# List user conversations
grpcurl -plaintext \
  -d '{"user_id": "user-123", "limit": 50}' \
  127.0.0.1:9085 \
  nova.messaging_service.MessagingService.ListConversations
```

## Test Files

### 1. `grpc_cross_service_integration_test.rs`

Main integration test suite with:
- Service connectivity validation
- Cross-service gRPC calls
- Concurrent request handling
- Error handling scenarios
- End-to-end workflows

**Run:**
```bash
cargo test --test grpc_cross_service_integration_test -- --nocapture --ignored
```

### 2. `grpc_integration_test.sh`

Bash script for comprehensive testing:
- Service discovery and connectivity
- gRPC endpoint validation
- Error handling
- Performance metrics

**Run:**
```bash
./tests/grpc_integration_test.sh local
./tests/grpc_integration_test.sh staging
```

### 3. `test_harness/grpc_helpers.rs`

Helper utilities for gRPC testing:
- Service endpoint configuration
- Connection pool management
- Test scenario builders
- Health check utilities

## Test Scenarios

### Scenario 1: Identity Service → Realtime Chat Service

**Flow:**
1. 在 identity-service 建立測試使用者
2. 透過 `AuthService.GenerateToken` 取得 access token
3. realtime-chat-service 使用 token 呼叫 `ValidateSession` 取得 caller claims
4. 驗證 conversation metadata 回傳的 user profile 與 identity-service 一致

**Test Command:**
```bash
SERVICES_RUNNING=true cargo test test_identity_service_validates_realtime_chat -- --nocapture --ignored
```

### Scenario 2: Realtime Chat Service → Identity Service

**Flow:**
1. realtime-chat-service 產生訊息事件
2. 透過 Auth gRPC 查 sender profile
3. 再查 recipient profile
4. 在訊息存檔時同時寫入 profile snapshot

**Test Command:**
```bash
SERVICES_RUNNING=true cargo test test_realtime_chat_queries_identity_profiles -- --nocapture --ignored
```

### Scenario 3: Concurrent Cross-Service Calls

**Flow:**
1. Spawn 10 concurrent gRPC requests
2. Each task queries different services
3. Verify no connection pool exhaustion
4. Validate all responses succeed

**Test Command:**
```bash
SERVICES_RUNNING=true cargo test test_concurrent_cross_service_calls -- --nocapture --ignored
```

### Scenario 4: E2E Message Flow

**Flow:**
1. 透過 identity-service 建立 User A 與 User B
2. 在 realtime-chat-service 建立 conversation
3. User A 傳送訊息
4. realtime-chat-service 驗證 token 並查詢 identity profile
5. User B 拉取訊息並收到 sender profile snapshot

**Test Command:**
```bash
SERVICES_RUNNING=true cargo test test_e2e_message_with_user_lookup -- --nocapture --ignored
```

## Configuration

### Environment Variables

```bash
# Enable testing against running services
export SERVICES_RUNNING=true

# Set custom service endpoints
export IDENTITY_SERVICE_ENDPOINT="http://127.0.0.1:50051"
export REALTIME_CHAT_SERVICE_ENDPOINT="http://127.0.0.1:50052"
export GRAPH_SERVICE_ENDPOINT="http://127.0.0.1:9083"

# Set timeout values
export GRPC_CONNECTION_TIMEOUT="5s"
export GRPC_REQUEST_TIMEOUT="10s"
```

### Kubernetes Namespaces

The test script validates deployments in:
- `nova-user` - User Service namespace
- `nova-messaging` - Messaging Service namespace
- `nova-auth` - Auth Service namespace

## Troubleshooting

### Services Not Reachable

**Problem:** `Connection failed: Service at 127.0.0.1:9081 not reachable within timeout`

**Solution:**
```bash
# Check if service is running
lsof -i :9081  # Check User Service
lsof -i :9085  # Check Messaging Service

# Start the service
cargo run -p user-service

# Check logs
cargo run -p user-service 2>&1 | grep -i grpc
```

### grpcurl Not Installed

**Solution:**
```bash
# macOS
brew install grpcurl

# Ubuntu/Debian
apt-get update && apt-get install -y grpcurl

# Verify
grpcurl --version
```

### Test Timeout

**Problem:** Tests timeout waiting for services

**Solution:**
```bash
# Increase timeout
GRPC_REQUEST_TIMEOUT=30s cargo test --test grpc_cross_service_integration_test -- --nocapture --ignored

# Or check service logs
docker-compose logs user-service
docker-compose logs messaging-service
```

### Connection Pool Issues

**Problem:** "Connection pool exhausted" errors

**Solution:**
```bash
# Check service resource limits
kubectl describe pod user-service -n nova-user

# Scale up if needed
kubectl scale deployment user-service --replicas=5 -n nova-user

# Monitor connections
kubectl logs user-service -n nova-user | grep connection
```

## Performance Metrics

The tests monitor:
- Request latency (p50, p95, p99)
- Throughput (requests/second)
- Connection pool utilization
- Error rates
- Timeout occurrences

**View metrics:**
```bash
# Prometheus endpoint (if monitoring enabled)
curl http://127.0.0.1:9090/api/v1/query?query=grpc_server_handled_total

# In Kubernetes
kubectl port-forward -n monitoring prometheus-0 9090:9090
```

## CI/CD Integration

### GitHub Actions

Add to `.github/workflows/integration-tests.yml`:

```yaml
name: gRPC Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
      redis:
        image: redis:7
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - run: make test-grpc-integration
```

### Pre-commit Hook

Add to `.githooks/pre-commit`:

```bash
#!/bin/bash
echo "Running gRPC integration tests..."
make test-grpc-integration || exit 1
```

## Best Practices

1. **Service Startup Order**
   - Auth Service first (required for JWT validation)
   - User Service second
   - Messaging Service last

2. **Test Data**
   - Use deterministic IDs for reproducibility
   - Clean up test data after tests
   - Use transactions to rollback data

3. **Timeouts**
   - Set generous timeouts (10s minimum)
   - Handle graceful degradation
   - Log timeout events

4. **Monitoring**
   - Enable gRPC metrics collection
   - Monitor connection pools
   - Track error rates

5. **Debugging**
   - Use `RUST_LOG=debug` for detailed logs
   - Enable gRPC protocol tracing
   - Capture network packets if needed

## References

- [Tonic gRPC Framework](https://docs.rs/tonic/)
- [Protocol Buffers](https://developers.google.com/protocol-buffers)
- [grpcurl Documentation](https://github.com/fullstorydev/grpcurl)
- [Kubernetes gRPC Best Practices](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-service/)

## Next Steps

1. Deploy services to staging environment
2. Run full integration test suite
3. Monitor gRPC metrics in Prometheus
4. Validate connection pooling behavior
5. Test failover and recovery scenarios
6. Load test with concurrent connections

## Support

For issues or questions:
1. Check service logs: `make logs`
2. Run health check: `make health`
3. Verify connectivity: `./tests/grpc_integration_test.sh local`
4. Check gRPC status: `grpcurl -plaintext localhost:9081 list`
