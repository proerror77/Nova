# k6 Load Testing Suite for Nova GraphQL Gateway

Performance testing scenarios for GraphQL subscriptions and queries under load.

## 📋 Overview

This k6 load testing suite provides comprehensive performance testing for:
- **GraphQL Queries**: Simple, medium, high, and extreme complexity
- **WebSocket Subscriptions**: Feed updates, notifications, multiple subscriptions
- **Backpressure Handling**: Queue management under high load
- **Concurrent Connections**: 50-200+ simultaneous WebSocket connections

## 🚀 Getting Started

### Installation

```bash
# Install k6 (macOS)
brew install k6

# Or download from https://k6.io/docs/getting-started/installation/
```

### Quick Start

```bash
# Run baseline test (10 VUs, 30s default)
k6 run load-test-graphql.js

# Run with custom VUs and duration
k6 run -u 100 -d 5m load-test-graphql.js

# Run subscription tests
k6 run load-test-subscriptions.js
```

## 📊 Test Scenarios

### Query Load Testing (`load-test-graphql.js`)

#### Stage 1: Ramp Up (30s)
- Linear increase from 0 to 100 users
- Tests connection establishment

#### Stage 2: Sustained Load (2m)
- Maintains 100 concurrent users
- Baseline performance measurement

#### Stage 3: Ramp Up High (1m)
- Increase from 100 to 500 users
- Tests mid-tier load handling

#### Stage 4: Stress Test (2m)
- 1000 concurrent users
- Tests system under extreme load

#### Stage 5: Ramp Down (30s)
- Graceful shutdown

### Query Complexity Tests

| Test | Complexity | Query Pattern |
|------|-----------|---------------|
| Simple Query | 10-20 | `{ user { id username } }` |
| Medium (Pagination) | 100-200 | `posts(first: 20) { edges { node { ... } } }` |
| High (Nested) | 500-1000 | Nested pagination with 50 items |
| Extreme (DoS) | 1000+ | Maximum nesting + pagination |

### Subscription Load Testing (`load-test-subscriptions.js`)

#### WebSocket Connection Tests
- Feed subscription (real-time updates)
- Notification subscription (events)
- Multiple subscriptions (parallel)

#### Backpressure Tests
- Queue state monitoring
- Event dropping behavior
- Critical threshold handling

#### Concurrent Connection Tests
- 50 simultaneous WebSocket connections
- 200+ concurrent connection stress test
- Message delivery latency measurement

## 🔧 Configuration

### Environment Variables

```bash
# Custom base URL
BASE_URL=http://staging.example.com k6 run load-test-graphql.js

# Custom WebSocket endpoint
WS_ENDPOINT=wss://api.example.com/graphql k6 run load-test-subscriptions.js

# Authentication token
AUTH_TOKEN=your_jwt_token k6 run load-test-graphql.js

# Custom VUs and duration
VUS=500 DURATION=10m k6 run load-test-graphql.js
```

### Threshold Configuration

Current thresholds in `load-test-graphql.js`:

```javascript
thresholds: {
  http_req_duration: ['p(95)<500', 'p(99)<1000'],
  http_req_failed: ['rate<0.1'],
  success_rate: ['rate>0.95'],
}
```

Adjust these based on your SLA:
- P95 < 500ms (ideal for user experience)
- P99 < 1000ms (acceptable for 99% of users)
- Success rate > 95% (5% error budget)
- Failure rate < 10%

## 📈 Metrics Collected

### Response Time Metrics
- `response_time_p95`: 95th percentile response time
- `response_time_p99`: 99th percentile response time
- `http_req_duration`: Full request duration

### Success/Failure Metrics
- `success_rate`: Percentage of successful requests
- `error_rate`: Percentage of failed requests
- `http_req_failed`: Total failed requests

### Complexity Metrics
- `query_complexity_violations`: Queries exceeding max complexity
- `backpressure_triggered`: Number of backpressure events

### Subscription Metrics
- `ws_active_connections`: Number of active WebSocket connections
- `ws_messages_received`: Total messages received
- `ws_message_latency`: Message delivery latency
- `ws_connection_errors`: WebSocket connection failures

## 🎯 Recommended Test Plans

### Development Testing
```bash
# Quick sanity check (10 VUs, 1m)
k6 run -u 10 -d 1m load-test-graphql.js
```

### Staging Performance Validation
```bash
# Moderate load (100 VUs, 5m)
k6 run -u 100 -d 5m load-test-graphql.js
k6 run -u 100 -d 5m load-test-subscriptions.js
```

### Production Capacity Planning
```bash
# High load stress test (500 VUs, 10m)
k6 run -u 500 -d 10m load-test-graphql.js

# Combined with subscriptions
k6 run -u 200 -d 10m load-test-subscriptions.js
```

### Spike Testing
```bash
# Sudden traffic spike (0 -> 1000 VUs in 10s)
k6 run --stage 10s:1000 --stage 5m:1000 load-test-graphql.js
```

## 💾 Saving Results

```bash
# JSON output
k6 run -o json=results.json load-test-graphql.js

# InfluxDB integration (requires setup)
k6 run --out influxdb=http://localhost:8086/k6 load-test-graphql.js

# CSV output
k6 run --out csv=results.csv load-test-graphql.js
```

## 📊 Result Interpretation

### Good Results
```
✓ http_req_duration.........: avg=100ms, p(95)=300ms, p(99)=600ms
✓ http_req_failed...........: 0.00%
✓ success_rate..............: 100%
```

### Warning Signs
```
⚠ http_req_duration.........: p(95)=1200ms, p(99)=2500ms  # Slow responses
⚠ http_req_failed...........: 2.5%                        # Higher error rate
⚠ query_complexity_violations: 150 events                 # Many blocked
⚠ backpressure_triggered...: 45 events                    # Queue pressure
```

### Critical Issues
```
✗ http_req_failed...........: 15%+                         # System failing
✗ success_rate..............: <85%                         # Majority failing
✗ active_subscriptions......: drops to 0                   # Connections lost
```

## 🔍 Troubleshooting

### Connection Refused
```
Error: dial tcp connection refused
```
**Solution**: Ensure GraphQL Gateway is running on the configured port
```bash
BASE_URL=http://localhost:8000 k6 run load-test-graphql.js
```

### WebSocket Handshake Failure
```
Error: WebSocket connection failed
```
**Solution**: Verify WebSocket endpoint is correctly configured
```bash
WS_ENDPOINT=ws://localhost:8000/graphql k6 run load-test-subscriptions.js
```

### High Error Rate
```
✗ success_rate: 45%
```
**Solution**: Check server logs for:
1. Query complexity violations (queries too expensive)
2. Backpressure events (reduce VUs or increase server capacity)
3. Authentication issues (verify AUTH_TOKEN)

## 📚 k6 Documentation

- [k6 Official Docs](https://k6.io/docs/)
- [k6 JavaScript API](https://k6.io/docs/javascript-api/)
- [k6 WebSocket API](https://k6.io/docs/javascript-api/k6-ws/)
- [k6 Thresholds](https://k6.io/docs/using-k6/thresholds/)

## 🎓 Learning Resources

### Example: Running Custom Load Test

```bash
# Test with specific user count and duration
k6 run \
  -u 250 \
  -d 10m \
  -e BASE_URL=http://api.staging.example.com \
  -e AUTH_TOKEN=eyJhbGc... \
  --out json=staging-results.json \
  load-test-graphql.js

# View results
cat staging-results.json | jq '.metrics'
```

### Example: Gradual Load Increase

```bash
k6 run \
  --stage 1m:50 \
  --stage 2m:100 \
  --stage 3m:200 \
  --stage 2m:500 \
  --stage 1m:0 \
  load-test-graphql.js
```

## 🔐 Security Notes

- **Never commit tokens**: Use environment variables or `.env` files
- **Test in staging**: Always run heavy tests in staging first
- **Monitor resources**: Watch CPU/memory during tests
- **Rate limit awareness**: Some endpoints may have rate limits

## 📞 Support

For issues or questions:
1. Check k6 documentation
2. Review server logs during test
3. Start with lighter tests (10 VUs) and gradually increase
4. Monitor server metrics (CPU, memory, connections)
