# CRITICAL FIX: Add Timeout Wrapper for ClickHouse Queries

**Issue**: `feed_ranking.rs:118-158` 的 ClickHouse 查询缺少超时保护
**Impact**: 慢查询可能阻塞 HTTP handler thread，导致级联失败
**Priority**: P0 (Blocker for staging deployment)

---

## Problem Analysis

### Current Code (backend/content-service/src/services/feed_ranking.rs:118-158)

```rust
pub async fn get_feed_candidates(
    &self,
    user_id: Uuid,
    limit: usize,
) -> Result<Vec<FeedCandidate>> {
    // ❌ NO TIMEOUT PROTECTION
    let (followees_result, trending_result, affinity_result) = tokio::join!(
        self.get_followees_candidates(user_id, source_limit),
        self.get_trending_candidates(source_limit),
        self.get_affinity_candidates(user_id, source_limit),
    );
    // ...
}
```

**Risk Scenario**:
1. ClickHouse 查询因复杂聚合运行 30+ 秒
2. `tokio::join!` 并发执行 3 个查询，全部 hang
3. HTTP handler thread 阻塞
4. 请求排队 → 连接池耗尽
5. Circuit Breaker 打开 → 所有 feed 请求失败

---

## Solution 1: tokio::time::timeout Wrapper (RECOMMENDED)

### Implementation

```rust
use tokio::time::{timeout, Duration};
use tracing::warn;

pub async fn get_feed_candidates(
    &self,
    user_id: Uuid,
    limit: usize,
) -> Result<Vec<FeedCandidate>> {
    debug!(
        "Fetching feed candidates for user {} (limit: {})",
        user_id, limit
    );

    let source_limit = limit.min(self.max_feed_candidates);

    // ✅ ADD TIMEOUT WRAPPER (5 seconds per query)
    let timeout_duration = Duration::from_secs(5);

    let (followees_result, trending_result, affinity_result) = tokio::join!(
        timeout(timeout_duration, self.get_followees_candidates(user_id, source_limit)),
        timeout(timeout_duration, self.get_trending_candidates(source_limit)),
        timeout(timeout_duration, self.get_affinity_candidates(user_id, source_limit)),
    );

    let mut all_candidates = Vec::new();

    // ✅ HANDLE TIMEOUTS GRACEFULLY
    match followees_result {
        Ok(Ok(mut followees)) => {
            debug!("Retrieved {} followees candidates", followees.len());
            all_candidates.append(&mut followees);
        }
        Ok(Err(e)) => {
            warn!("Followees candidates query failed: {}", e);
            // Continue with other sources
        }
        Err(_) => {
            warn!("Followees candidates query timeout (>5s)");
            // Timeout - gracefully degrade
        }
    }

    match trending_result {
        Ok(Ok(mut trending)) => {
            debug!("Retrieved {} trending candidates", trending.len());
            all_candidates.append(&mut trending);
        }
        Ok(Err(e)) => {
            warn!("Trending candidates query failed: {}", e);
        }
        Err(_) => {
            warn!("Trending candidates query timeout (>5s)");
        }
    }

    match affinity_result {
        Ok(Ok(mut affinity)) => {
            debug!("Retrieved {} affinity candidates", affinity.len());
            all_candidates.append(&mut affinity);
        }
        Ok(Err(e)) => {
            warn!("Affinity candidates query failed: {}", e);
        }
        Err(_) => {
            warn!("Affinity candidates query timeout (>5s)");
        }
    }

    debug!(
        "Retrieved {} total candidates from all sources",
        all_candidates.len()
    );

    Ok(all_candidates)
}
```

### Benefits

1. **Timeout Protection**: 每个查询最多 5 秒
2. **Graceful Degradation**: 超时不会导致整个请求失败
3. **Partial Results**: 即使部分源失败，仍返回可用数据
4. **Circuit Breaker Compatible**: 超时触发 Circuit Breaker，自动切换 fallback

---

## Solution 2: ClickHouse Client Timeout (Alternative)

### Implementation in ClickHouseClient

```rust
// backend/content-service/src/db/ch_client.rs

use clickhouse::Client;
use std::time::Duration;

pub struct ClickHouseClient {
    client: Client,
}

impl ClickHouseClient {
    pub fn new(url: &str, database: &str) -> Self {
        let client = Client::default()
            .with_url(url)
            .with_database(database)
            .with_option("max_execution_time", "10")  // ✅ 10 seconds server-side timeout
            .with_option("send_timeout", "5")         // ✅ 5 seconds network send timeout
            .with_option("receive_timeout", "5");     // ✅ 5 seconds network receive timeout

        Self { client }
    }

    pub async fn query_with_params<T, F>(
        &self,
        query: &str,
        bind_fn: F,
    ) -> Result<Vec<T>, clickhouse::error::Error>
    where
        T: clickhouse::Row + for<'de> serde::Deserialize<'de>,
        F: FnOnce(clickhouse::query::Query) -> clickhouse::query::Query,
    {
        let q = self.client.query(query);
        let q = bind_fn(q);

        // ✅ Client-side timeout wrapper
        tokio::time::timeout(Duration::from_secs(10), q.fetch_all())
            .await
            .map_err(|_| clickhouse::error::Error::Custom("Query timeout (>10s)".into()))?
    }
}
```

### Benefits

1. **Server-Side Timeout**: ClickHouse 自动终止慢查询
2. **Network Timeout**: 防止网络问题导致 hang
3. **Client-Side Fallback**: 双重保护

---

## Solution 3: Per-Query Timeout Configuration (BEST PRACTICE)

### Configuration-Driven Approach

```rust
// backend/content-service/src/config.rs

#[derive(Debug, Clone)]
pub struct ClickHouseTimeouts {
    pub followees_timeout_secs: u64,
    pub trending_timeout_secs: u64,
    pub affinity_timeout_secs: u64,
}

impl Default for ClickHouseTimeouts {
    fn default() -> Self {
        Self {
            followees_timeout_secs: 5,  // User-specific queries (fast)
            trending_timeout_secs: 3,   // Pre-aggregated data (very fast)
            affinity_timeout_secs: 5,   // ML-based queries (moderate)
        }
    }
}

impl From<&FeedConfig> for ClickHouseTimeouts {
    fn from(config: &FeedConfig) -> Self {
        Self {
            followees_timeout_secs: config.ch_followees_timeout_secs.unwrap_or(5),
            trending_timeout_secs: config.ch_trending_timeout_secs.unwrap_or(3),
            affinity_timeout_secs: config.ch_affinity_timeout_secs.unwrap_or(5),
        }
    }
}
```

### Implementation

```rust
pub async fn get_feed_candidates(
    &self,
    user_id: Uuid,
    limit: usize,
) -> Result<Vec<FeedCandidate>> {
    let source_limit = limit.min(self.max_feed_candidates);

    // ✅ Per-query timeout configuration
    let (followees_result, trending_result, affinity_result) = tokio::join!(
        timeout(
            Duration::from_secs(self.timeouts.followees_timeout_secs),
            self.get_followees_candidates(user_id, source_limit)
        ),
        timeout(
            Duration::from_secs(self.timeouts.trending_timeout_secs),
            self.get_trending_candidates(source_limit)
        ),
        timeout(
            Duration::from_secs(self.timeouts.affinity_timeout_secs),
            self.get_affinity_candidates(user_id, source_limit)
        ),
    );
    // ... handle results
}
```

### Environment Variables

```bash
# k8s/base/configmap.yaml
CLICKHOUSE_FOLLOWEES_TIMEOUT_SECS: "5"
CLICKHOUSE_TRENDING_TIMEOUT_SECS: "3"
CLICKHOUSE_AFFINITY_TIMEOUT_SECS: "5"
```

---

## Testing Plan

### 1. Unit Test: Timeout Behavior

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::{sleep, Duration};

    #[tokio::test]
    async fn test_query_timeout() {
        // Simulate slow query
        let slow_query = async {
            sleep(Duration::from_secs(10)).await;
            Ok::<Vec<FeedCandidate>, AppError>(vec![])
        };

        // Timeout should trigger
        let result = timeout(Duration::from_secs(2), slow_query).await;
        assert!(result.is_err()); // Timeout error
    }

    #[tokio::test]
    async fn test_partial_results_on_timeout() {
        let service = create_test_service();

        // One source times out, others succeed
        // Should still return partial results
        let candidates = service
            .get_feed_candidates(test_user_id(), 100)
            .await
            .unwrap();

        assert!(!candidates.is_empty()); // Partial results available
    }
}
```

### 2. Integration Test: ClickHouse Timeout

```bash
# Simulate slow query in ClickHouse
docker exec clickhouse-server clickhouse-client --query "
    SET max_execution_time = 1;
    SELECT sleep(10);
"
# Expected: Query interrupted after 1 second

# Test feed endpoint
curl -H "Authorization: Bearer $TOKEN" \
     http://localhost:8080/api/v1/feed?algo=ch&limit=20

# Expected: Falls back to PostgreSQL (Circuit Breaker triggers)
```

### 3. Load Test: Timeout Under Load

```javascript
// k6 load test
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '1m', target: 100 },  // Ramp up
    { duration: '5m', target: 100 },  // Sustained load
  ],
  thresholds: {
    'http_req_duration{endpoint:feed}': ['p(99)<1000'], // P99 < 1s
    'http_req_failed{endpoint:feed}': ['rate<0.01'],    // <1% errors
  },
};

export default function() {
  let res = http.get('http://staging.nova.app/api/v1/feed?algo=ch');

  check(res, {
    'status 200': (r) => r.status === 200,
    'has posts': (r) => JSON.parse(r.body).posts.length > 0,
    'response time OK': (r) => r.timings.duration < 1000,
  });

  sleep(1);
}
```

---

## Deployment Strategy

### Phase 1: Add Timeout Wrapper (2 hours)

1. **Modify**: `backend/content-service/src/services/feed_ranking.rs`
   - Add `tokio::time::timeout` wrapper
   - Update error handling

2. **Test**: Local integration test
   ```bash
   cargo test --package content-service test_query_timeout
   ```

3. **Deploy**: Staging environment
   ```bash
   kubectl rollout restart deployment/content-service -n nova
   ```

### Phase 2: Add ClickHouse Client Timeout (1 hour)

1. **Modify**: `backend/content-service/src/db/ch_client.rs`
   - Add server-side timeout configuration

2. **Verify**: Check ClickHouse query logs
   ```bash
   docker exec clickhouse-server tail -f /var/log/clickhouse-server/clickhouse-server.log | grep max_execution_time
   ```

### Phase 3: Configuration-Driven Timeouts (Optional)

1. **Add**: Environment variables for per-query timeouts
2. **Update**: ConfigMap in k8s
3. **Rollout**: Gradual deployment with monitoring

---

## Monitoring

### Metrics to Track

```rust
use prometheus::Histogram;

lazy_static! {
    static ref CH_QUERY_DURATION: Histogram = register_histogram!(
        "clickhouse_query_duration_seconds",
        "ClickHouse query execution time",
        vec![0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0, 10.0]
    ).unwrap();

    static ref CH_QUERY_TIMEOUTS: Counter = register_counter!(
        "clickhouse_query_timeouts_total",
        "Number of ClickHouse query timeouts"
    ).unwrap();
}

// In get_feed_candidates:
let start = Instant::now();
match timeout(Duration::from_secs(5), query).await {
    Ok(Ok(result)) => {
        CH_QUERY_DURATION.observe(start.elapsed().as_secs_f64());
        result
    }
    Err(_) => {
        CH_QUERY_TIMEOUTS.inc();
        warn!("Query timeout");
        vec![]
    }
}
```

### Alerts

```yaml
# prometheus/alerts.yml
- alert: ClickHouseQueryTimeoutHigh
  expr: rate(clickhouse_query_timeouts_total[5m]) > 0.1
  for: 5m
  annotations:
    summary: "ClickHouse query timeout rate > 10%"
    description: "Circuit breaker may trigger, investigate slow queries"
```

---

## Rollback Plan

If timeout causes issues:

1. **Remove timeout wrapper**:
   ```rust
   // Revert to original code without timeout
   let (followees_result, trending_result, affinity_result) = tokio::join!(
       self.get_followees_candidates(user_id, source_limit),
       self.get_trending_candidates(source_limit),
       self.get_affinity_candidates(user_id, source_limit),
   );
   ```

2. **Increase timeout**:
   ```rust
   let timeout_duration = Duration::from_secs(30); // Increase to 30s
   ```

3. **Disable ClickHouse**:
   ```yaml
   # ConfigMap
   CLICKHOUSE_ENABLED: "false"
   ```

---

## Expected Performance Impact

### Before Timeout Fix

- **Risk**: Unbounded query execution → system hang
- **P99 Latency**: >10s (under load with slow queries)
- **Error Rate**: 0% (but requests hang)

### After Timeout Fix

- **Guarantee**: Queries terminate within 5s
- **P99 Latency**: <1s (timeout + fallback)
- **Error Rate**: <1% (timeout triggers fallback)

### Success Criteria

✅ All ClickHouse queries complete within 5s OR timeout
✅ Timeout triggers fallback to PostgreSQL
✅ Circuit Breaker prevents cascade failures
✅ P99 latency < 1s under 100 concurrent users

---

**Estimated Implementation Time**: 2-3 hours
**Testing Time**: 1 hour
**Deployment Risk**: LOW (graceful degradation built-in)
