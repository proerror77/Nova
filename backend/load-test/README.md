# Nova Performance Load Testing

## 概述

性能基准测试套件,用于验证优化效果和回归检测。

## 测试工具

### Artillery (推荐)
```bash
npm install -g artillery@latest
artillery -V
```

### k6 (备选)
```bash
brew install k6
k6 version
```

## 测试场景

### 1. Feed 生成压测
模拟用户刷新 Feed 场景

**目标**:
- 并发: 1000 用户
- 持续: 5 分钟
- P95 延迟: < 500ms

**执行**:
```bash
artillery run feed-load-test.yml
```

### 2. GraphQL 复杂查询
嵌套查询性能测试

**目标**:
- 查询深度: 3 层
- 并发: 500 用户
- P99 延迟: < 1000ms

### 3. 数据库连接池压测
验证连接池配置是否充足

**目标**:
- 峰值连接: < 75/100
- 等待时间: < 50ms

## 基准指标

### 优化前 (Baseline)
```
Feed Generation:
  P50: 420ms
  P95: 1,240ms
  P99: 2,800ms
  Throughput: 150 req/s

GraphQL Query:
  P50: 180ms
  P95: 520ms
  P99: 1,100ms
```

### 优化后 (Target)
```
Feed Generation:
  P50: 85ms   (-80%)
  P95: 220ms  (-82%)
  P99: 480ms  (-83%)
  Throughput: 1,000+ req/s

GraphQL Query:
  P50: 35ms   (-81%)
  P95: 95ms   (-82%)
  P99: 180ms  (-84%)
```

## 执行流程

### 1. 准备环境
```bash
# 启动所有服务
docker-compose up -d

# 等待服务就绪
./scripts/wait-for-services.sh

# 生成测试数据
cargo run --bin seed-test-data -- --users 1000 --posts 10000
```

### 2. 运行基准测试
```bash
# Feed 压测
artillery run feed-load-test.yml --output results/feed-baseline.json

# GraphQL 压测
artillery run graphql-load-test.yml --output results/graphql-baseline.json

# 数据库压测
artillery run database-load-test.yml --output results/db-baseline.json
```

### 3. 生成报告
```bash
# HTML 报告
artillery report results/feed-baseline.json --output reports/feed.html

# CSV 导出 (Prometheus)
artillery report results/feed-baseline.json --output reports/feed.csv
```

### 4. 对比优化效果
```bash
# 运行优化后测试
artillery run feed-load-test.yml --output results/feed-optimized.json

# 生成对比报告
node scripts/compare-results.js \
  results/feed-baseline.json \
  results/feed-optimized.json
```

## 监控检查

### Prometheus 查询
```promql
# gRPC P95 延迟
histogram_quantile(0.95, rate(grpc_request_duration_seconds_bucket[5m]))

# 数据库连接池利用率
db_pool_connections_active / db_pool_connections_max * 100

# 缓存命中率
sum(rate(cache_operations_total{result="hit"}[5m])) /
sum(rate(cache_operations_total{operation="get"}[5m])) * 100
```

### Grafana 仪表板
访问: http://localhost:3000/d/nova-performance

## 故障排查

### 高延迟
```bash
# 检查慢查询
psql -d nova -c "SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"

# 检查连接池
curl http://localhost:8080/metrics | grep db_pool
```

### 错误率高
```bash
# 检查服务日志
docker-compose logs feed-service | grep ERROR

# 检查 Circuit Breaker 状态
curl http://localhost:8080/health/circuit-breakers
```

## CI/CD 集成

### GitHub Actions
```yaml
# .github/workflows/performance-test.yml
name: Performance Regression Test

on:
  pull_request:
    branches: [main]

jobs:
  load-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: npm install -g artillery
      - run: docker-compose up -d
      - run: ./scripts/wait-for-services.sh
      - run: artillery run load-test/feed-load-test.yml
      - run: artillery run load-test/graphql-load-test.yml
      - name: Check Performance
        run: |
          P95=$(cat artillery-report.json | jq '.aggregate.latency.p95')
          if [ $P95 -gt 500 ]; then
            echo "FAIL: P95 latency $P95ms > 500ms threshold"
            exit 1
          fi
```

## 最佳实践

1. **逐步加压**: 从低并发开始,避免系统崩溃
2. **预热**: 前 30s 低流量预热缓存
3. **真实数据**: 使用生产级数据量
4. **监控**: 同时监控所有系统指标
5. **隔离**: 测试环境与生产隔离

## 参考资料

- [Artillery 文档](https://www.artillery.io/docs)
- [k6 文档](https://k6.io/docs/)
- [Grafana 性能测试](https://grafana.com/docs/k6/latest/)
