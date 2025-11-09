---
description: Profile and optimize Rust microservice performance (CPU, memory, async runtime, database queries)
---

## User Input

```text
$ARGUMENTS
```

Expected format: `<service-name> [profile-type]`

Profile types:
- `cpu` - CPU profiling with flamegraph
- `memory` - Memory allocation profiling
- `async` - Tokio async runtime analysis
- `database` - Database query performance
- `all` - Run all profiling types (default)

Examples:
- `/perf.audit user-service`
- `/perf.audit content-service cpu`
- `/perf.audit feed-service database`

## Execution Flow

### 1. Parse Arguments

Extract:
- **Service name**: Target microservice (e.g., "user-service")
- **Profile type**: cpu | memory | async | database | all (default: all)

### 2. Invoke performance-auditor Agent

Use the Task tool to invoke the `performance-auditor` agent:

```
Task: Performance analysis and optimization recommendations
Agent: performance-auditor
Prompt: |
  Analyze performance for {service-name} with focus on {profile-type}:

  Service path: backend/{service-name}/

  Provide comprehensive analysis and actionable recommendations.
```

### 3. Run Profile-Type Specific Analysis

#### Profile Type: cpu

**CPU profiling workflow:**

1. **Setup flamegraph tooling**:
   ```bash
   cargo install flamegraph
   ```

2. **Run CPU profiler**:
   ```bash
   cd backend/{service-name}

   # For macOS (using Instruments)
   cargo flamegraph --bin {service-name} -- --bench-mode

   # For Linux (using perf)
   cargo flamegraph --bin {service-name} --root -- --bench-mode
   ```

3. **Analyze flamegraph**:
   - Open generated `flamegraph.svg`
   - Identify hot paths (widest spans)
   - Look for:
     - Unexpected blocking operations
     - Inefficient algorithms (O(n²) patterns)
     - Excessive allocations
     - Lock contention

4. **Generate optimization report**:
   ```markdown
   ### CPU Profiling Results

   **Total samples**: {samples}
   **Top hotspots**:

   | Function | % Time | Recommendation |
   |----------|--------|----------------|
   | {function1} | 25% | {optimization} |
   | {function2} | 18% | {optimization} |
   | {function3} | 12% | {optimization} |

   **Critical findings**:
   - 🔴 Blocking operation in async context: {location}
   - 🟡 High allocation rate in hot path: {location}
   - 🟢 Lock-free data structures performing well

   **Optimization priorities**:
   1. {priority1}
   2. {priority2}
   3. {priority3}
   ```

#### Profile Type: memory

**Memory profiling workflow:**

1. **Setup memory profiler**:
   ```bash
   cargo install cargo-valgrind
   # Or use heaptrack on Linux
   ```

2. **Run memory profiler**:
   ```bash
   cd backend/{service-name}

   # Using valgrind (massif)
   valgrind --tool=massif --massif-out-file=massif.out ./target/release/{service-name}

   # Analyze results
   ms_print massif.out > memory-report.txt
   ```

3. **Analyze memory usage**:
   - Identify memory leaks
   - Find excessive allocations
   - Check for memory fragmentation
   - Verify connection pools are bounded

4. **Generate memory report**:
   ```markdown
   ### Memory Profiling Results

   **Peak memory usage**: {peak} MB
   **Current usage**: {current} MB

   **Top allocators**:

   | Location | Size | Count | Type |
   |----------|------|-------|------|
   | {location1} | {size} | {count} | {type} |
   | {location2} | {size} | {count} | {type} |

   **Issues detected**:
   - 🔴 Memory leak in {component}: {details}
   - 🟡 Unbounded cache growth: {location}
   - 🟢 Connection pools properly configured

   **Recommendations**:
   1. Add memory limits to caches
   2. Implement TTL for cached items
   3. Use `Arc<str>` instead of `String` for shared data
   4. Consider using `smallvec` for small allocations
   ```

#### Profile Type: async

**Async runtime profiling:**

1. **Enable tokio-console**:

   Add to Cargo.toml:
   ```toml
   [dependencies]
   console-subscriber = "0.2"

   [features]
   tokio-console = ["console-subscriber"]
   ```

   Update main.rs:
   ```rust
   #[tokio::main]
   async fn main() {
       #[cfg(feature = "tokio-console")]
       console_subscriber::init();

       // Service code...
   }
   ```

2. **Run service with console enabled**:
   ```bash
   cd backend/{service-name}
   cargo run --features tokio-console
   ```

3. **Connect tokio-console**:
   ```bash
   tokio-console http://localhost:6669
   ```

4. **Analyze async runtime**:
   - Task spawn rates and durations
   - Idle vs busy time per task
   - Blocking operations in async context
   - Lock contention (async mutexes)

5. **Generate async runtime report**:
   ```markdown
   ### Async Runtime Analysis

   **Total tasks spawned**: {count}
   **Average task duration**: {duration} ms
   **Blocking operations detected**: {blocking-count}

   **Task breakdown**:

   | Task | Count | Avg Duration | Status |
   |------|-------|--------------|--------|
   | HTTP handlers | {count} | {duration} | {status} |
   | Database queries | {count} | {duration} | {status} |
   | Kafka consumers | {count} | {duration} | {status} |

   **Issues detected**:
   - 🔴 Blocking `std::fs` in async context: {location}
   - 🔴 Holding mutex across `.await`: {location}
   - 🟡 Long-running task blocking runtime: {location}
   - 🟢 Connection pools properly async

   **Recommendations**:
   1. Use `tokio::fs` instead of `std::fs`
   2. Release mutex before `.await` points
   3. Use `spawn_blocking` for CPU-intensive work
   4. Consider dedicated runtime for long-running tasks
   ```

#### Profile Type: database

**Database query profiling:**

1. **Enable PostgreSQL slow query log**:
   ```sql
   ALTER DATABASE {service-db} SET log_min_duration_statement = 100; -- Log queries > 100ms
   ```

2. **Enable pg_stat_statements**:
   ```sql
   CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
   ```

3. **Collect query statistics**:
   ```sql
   SELECT
       query,
       calls,
       total_exec_time,
       mean_exec_time,
       max_exec_time,
       rows
   FROM pg_stat_statements
   WHERE query LIKE '%{service-name}%'
   ORDER BY mean_exec_time DESC
   LIMIT 20;
   ```

4. **Analyze N+1 queries**:
   - Scan codebase for loops with database queries
   - Identify opportunities for batch loading
   - Check for missing eager loading

5. **Check index usage**:
   ```sql
   SELECT
       schemaname,
       tablename,
       indexname,
       idx_scan,
       idx_tup_read
   FROM pg_stat_user_indexes
   WHERE schemaname = '{service-schema}'
   ORDER BY idx_scan ASC;
   ```

6. **Generate database performance report**:
   ```markdown
   ### Database Performance Analysis

   **Slow queries detected**: {count}
   **Average query time**: {avg} ms
   **Missing indexes**: {missing-count}

   **Top slow queries**:

   | Query | Calls | Avg Time | Max Time | Recommendation |
   |-------|-------|----------|----------|----------------|
   | {query1} | {calls} | {avg} ms | {max} ms | Add index on ... |
   | {query2} | {calls} | {avg} ms | {max} ms | Rewrite with JOIN |

   **N+1 Query Patterns**:
   - 🔴 File: {file}:{line} - Fetching users in loop
   - 🔴 File: {file}:{line} - Loading posts one by one

   **Index Recommendations**:
   ```sql
   -- High-impact indexes
   CREATE INDEX CONCURRENTLY idx_{table}_{column}
     ON {table}({column});

   -- Composite index for common query
   CREATE INDEX CONCURRENTLY idx_{table}_{col1}_{col2}
     ON {table}({col1}, {col2} DESC);
   ```

   **Query Optimizations**:
   1. Replace N+1 with batch query using `ANY($1)`
   2. Add partial index for filtered queries
   3. Use `EXPLAIN ANALYZE` to verify execution plan
   ```

### 4. Run Comprehensive Benchmark Suite

For `all` profile type:

```bash
cd backend/{service-name}

# Run criterion benchmarks
cargo bench

# Generate benchmark report
open target/criterion/report/index.html
```

### 5. Generate Optimization Action Plan

Invoke **performance-auditor** to synthesize findings:

```
Task: Create optimization action plan
Agent: performance-auditor
Prompt: |
  Based on profiling results, create prioritized optimization plan:

  **Findings summary**:
  - CPU: {cpu-findings}
  - Memory: {memory-findings}
  - Async: {async-findings}
  - Database: {database-findings}

  Provide:
  1. Severity-ranked issues (P0/P1/P2)
  2. Estimated performance impact (High/Medium/Low)
  3. Implementation complexity (Easy/Medium/Hard)
  4. Code snippets for top 3 optimizations

  Use skills: rust-async-patterns, database-optimization
```

### 6. Output Comprehensive Report

```markdown
## Performance Audit: {service-name}

**Profile type**: {profile-type}
**Date**: {date}
**Baseline metrics**:
- Requests/sec: {rps}
- P50 latency: {p50} ms
- P99 latency: {p99} ms
- Memory usage: {memory} MB

---

{profile-specific-results}

---

## Optimization Action Plan

### P0 - Critical (Immediate Fix Required)

| Issue | Impact | Complexity | Estimated Gain |
|-------|--------|------------|----------------|
| {issue1} | High | Medium | 40% latency reduction |
| {issue2} | High | Easy | 30% memory reduction |

**Code fix for {issue1}**:

```rust
// Before (blocking in async)
async fn bad_example() {
    let data = std::fs::read_to_string("file.txt").unwrap();
    // ...
}

// After (non-blocking)
async fn good_example() {
    let data = tokio::fs::read_to_string("file.txt").await?;
    // ...
}
```

### P1 - High Priority

{p1-issues}

### P2 - Nice to Have

{p2-issues}

---

## Monitoring Setup

Add these Prometheus alerts to track regressions:

```yaml
groups:
- name: {service-name}-performance
  rules:
  - alert: HighLatency
    expr: histogram_quantile(0.99, rate({service-name}_request_duration_seconds[5m])) > 0.5
    for: 5m
    annotations:
      summary: "P99 latency above 500ms"

  - alert: HighMemoryUsage
    expr: process_resident_memory_bytes{{service="{service-name}"}} > 512000000
    for: 10m
    annotations:
      summary: "Memory usage above 512MB"
```

---

## Next Steps

1. Implement P0 fixes immediately
2. Benchmark after each fix to measure impact
3. Set up continuous profiling in staging
4. Add performance tests to CI pipeline
5. Schedule follow-up audit in 2 weeks

**Re-run audit after fixes**:
```bash
/perf.audit {service-name} {profile-type}
```
```

## Integration with Existing Tools

### Load Testing Integration

After optimizations, run load tests:

```bash
# Using k6
k6 run --vus 100 --duration 30s load-tests/{service-name}.js

# Using Apache Bench
ab -n 10000 -c 100 http://localhost:8080/health
```

### Continuous Profiling

Set up automated profiling in CI:

```yaml
# .github/workflows/performance.yml
name: Performance Regression Test

on:
  pull_request:
    paths:
      - 'backend/{service-name}/**'

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run benchmarks
        run: cargo bench --bench {service-name}
      - name: Compare with baseline
        run: cargo bench --bench {service-name} -- --save-baseline main
```

## Error Handling

- **Profiling tool not installed**: Display installation command
- **Service not running**: Prompt to start service first
- **Insufficient permissions**: Suggest using `sudo` for system profilers
- **Out of memory during profiling**: Reduce sample rate or duration

## Integration with Skills

This command automatically leverages:
- **rust-async-patterns**: Tokio runtime optimization
- **database-optimization**: Query and index optimization
- **grpc-best-practices**: gRPC service performance tuning
- **microservices-architecture**: Distributed system performance patterns
