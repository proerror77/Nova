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

### Services Under Test

1. **User Service** (gRPC: port 9081)
   - 12 RPC methods for user profile and relationship management
   - gRPC endpoint: `http://127.0.0.1:9081`

2. **Messaging Service** (gRPC: port 9085)
   - 10 RPC methods for conversation and message management
   - gRPC endpoint: `http://127.0.0.1:9085`

3. **Auth Service** (gRPC: port 9086)
   - Core authentication and token validation
   - gRPC endpoint: `http://127.0.0.1:9086`

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
cargo run -p auth-service &
cargo run -p user-service &
cargo run -p messaging-service &

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

### Scenario 1: User Service → Messaging Service

**Flow:**
1. Create a user in User Service
2. Start a conversation in Messaging Service
3. User Service queries Messaging Service gRPC for conversation metadata
4. Validate response contains correct user references

**Test Command:**
```bash
SERVICES_RUNNING=true cargo test test_user_service_queries_messaging_service -- --nocapture --ignored
```

### Scenario 2: Messaging Service → User Service

**Flow:**
1. Messaging Service receives a message
2. Queries User Service gRPC for sender's profile
3. Queries User Service gRPC for recipient's profile
4. Stores message with user references

**Test Command:**
```bash
SERVICES_RUNNING=true cargo test test_messaging_service_queries_user_service -- --nocapture --ignored
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
1. Create User A and User B in User Service
2. Create conversation between A and B in Messaging Service
3. A sends message to B via Messaging Service
4. Messaging Service queries User Service for profile data
5. B retrieves message with sender's profile

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
export USER_SERVICE_ENDPOINT="http://127.0.0.1:9081"
export MESSAGING_SERVICE_ENDPOINT="http://127.0.0.1:9085"
export AUTH_SERVICE_ENDPOINT="http://127.0.0.1:9086"

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
