# Auth Service gRPC Testing Guide

This guide explains how to test the Auth Service gRPC implementation.

## Phase 1 Week 1-2: Testing Strategy

### Unit Tests (No Service Required)

Run unit tests that validate proto message structures and request validation:

```bash
cargo test --test auth_grpc_unit_tests
```

These tests verify:
- Message structure compliance with proto definitions
- Input validation (empty strings, bounds checking)
- Account lockout logic after 5 failed login attempts
- Soft delete pattern usage (deleted_at IS NULL)

### Integration Tests (Service Required)

Run integration tests against a running gRPC service:

```bash
# Terminal 1: Start the service
cargo run --bin auth-service

# Terminal 2: Run integration tests
cargo test --test grpc_integration_tests -- --ignored --nocapture
```

Integration tests verify:
- Service startup and readiness
- gRPC endpoint availability on port 9080
- RPC method correctness
- Error handling (NotFound, InvalidArgument, etc.)
- Connection pooling and concurrent requests

## Manual Testing with grpcurl

### Install grpcurl

```bash
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
```

### Test GetUser

```bash
grpcurl -plaintext \
  -d '{"user_id": "test-user-id"}' \
  localhost:9080 nova.auth_service.AuthService/GetUser
```

### Test GetUsersByIds

```bash
grpcurl -plaintext \
  -d '{
    "user_ids": ["user-1", "user-2", "user-3"]
  }' \
  localhost:9080 nova.auth_service.AuthService/GetUsersByIds
```

### Test VerifyToken

```bash
grpcurl -plaintext \
  -d '{
    "token": "your-jwt-token-here"
  }' \
  localhost:9080 nova.auth_service.AuthService/VerifyToken
```

### Test ListUsers

```bash
grpcurl -plaintext \
  -d '{
    "limit": 10,
    "offset": 0
  }' \
  localhost:9080 nova.auth_service.AuthService/ListUsers
```

## Testing with Postman

1. Enable gRPC support in Postman
2. Connect to `localhost:9080`
3. Select `nova.auth_service.AuthService`
4. Choose method and send requests

## Performance Testing

### Load Test with ghz

```bash
# Install ghz
go install github.com/bojand/ghz/cmd/ghz@latest

# Run load test (100 concurrent requests, 1000 total)
ghz --insecure \
  --proto ./proto/services/auth_service.proto \
  --call nova.auth_service.AuthService/GetUser \
  -d '{
    "user_id": "test-user"
  }' \
  -c 100 \
  -n 1000 \
  -m '{"user_id": "test-user"}' \
  localhost:9080
```

## Expected Performance Metrics (Phase 1 Target)

- P95 latency: < 200ms
- P99 latency: < 500ms
- Throughput: > 1000 requests/second (single instance)
- Error rate: < 0.1%

## Debugging

### Enable debug logging

```bash
RUST_LOG=debug cargo run --bin auth-service
```

### Enable gRPC tracing

```bash
GRPC_VERBOSITY=debug GRPC_TRACE=all cargo run --bin auth-service
```

### Check service health

```bash
curl http://localhost:8080/health
curl http://localhost:8080/readiness
curl http://localhost:8080/metrics
```

## Testing Checklist

- [ ] Unit tests pass (cargo test --test auth_grpc_unit_tests)
- [ ] Service starts successfully on port 8080 (REST) and 9080 (gRPC)
- [ ] Health checks return OK
- [ ] GetUser returns NotFound for non-existent users
- [ ] GetUsersByIds handles empty list gracefully
- [ ] VerifyToken validates JWT tokens correctly
- [ ] ListUsers respects pagination limits (1-100)
- [ ] CheckPermission returns correct authorization status
- [ ] RecordFailedLogin increments attempts and locks account after 5 failures
- [ ] All soft deletes (deleted_at IS NULL) work correctly
- [ ] gRPC connections support concurrent requests
- [ ] Performance metrics meet Phase 1 targets
- [ ] Error messages are clear and actionable

## Kubernetes Testing

Once deployed to Kubernetes, verify:

```bash
# Check service is running
kubectl get pods -n nova-auth

# Check service endpoints
kubectl get svc -n nova-auth

# Port forward to local machine
kubectl port-forward -n nova-auth svc/auth-service 9080:9080

# Then run grpcurl tests against localhost:9080
```

## Next Steps

Phase 2 will add:
- Outbox pattern for event publishing
- Kafka integration
- Distributed tracing with OpenTelemetry
- Advanced retry and circuit breaker patterns
- Rate limiting per service client
