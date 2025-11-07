# Spec 007 Phase 1 运维手册

**版本**: 1.0
**日期**: 2025-11-07
**范围**: 用户数据库整合 - messaging-service orphan cleaner
**状态**: 生产就绪

---

## 1. 架构概览

### 1.1 核心变更

Phase 1 实现了 messaging-service 的 users 表向 auth-service 的迁移：

- **数据源**: messaging-service.users → auth-service.users
- **验证机制**: gRPC batch API (`get_users_by_ids`)
- **清理机制**: orphan_cleaner 后台任务
- **保留期**: 30天软删除缓冲期

### 1.2 依赖服务

```
messaging-service (client)
         ↓ gRPC
auth-service (source of truth)
```

**关键端点**:
- gRPC: `messaging-service:9080` → `auth-service:9080`
- Health: tonic-health `/grpc.health.v1.Health/Check`

---

## 2. 部署前检查清单

### 2.1 环境变量验证

```bash
# messaging-service 必需环境变量
✓ AUTH_SERVICE_URL=http://auth-service:9080
✓ DATABASE_URL=postgresql://...
✓ REDIS_URL=redis://...

# 验证命令
kubectl exec -n nova messaging-service-xxx -- env | grep AUTH_SERVICE_URL
```

### 2.2 依赖健康检查

```bash
# 检查 auth-service gRPC 健康状态
grpcurl -plaintext auth-service:9080 grpc.health.v1.Health/Check

# 预期输出
{
  "status": "SERVING"
}
```

### 2.3 数据库迁移

```bash
# Phase 1 不涉及 schema 变更
# 仅需确认连接池工作正常
cargo sqlx prepare --check
```

### 2.4 编译验证

```bash
# 所有服务编译通过
cd backend/messaging-service && cargo check
cd backend/streaming-service && cargo check
cd backend/content-service && cargo check
cd backend/feed-service && cargo check
```

---

## 3. 监控指标

### 3.1 关键指标

| 指标名称 | 类型 | 阈值 | 说明 |
|---------|------|------|------|
| `grpc_client_requests_total{service="auth"}` | Counter | - | auth-service gRPC 调用总数 |
| `grpc_client_request_duration_seconds{service="auth"}` | Histogram | P99 < 100ms | batch API 响应时间 |
| `orphan_cleaner_batch_calls_total` | Counter | - | 批量查询调用次数 |
| `orphan_cleaner_deleted_members_total` | Counter | - | 清理的成员记录数 |
| `grpc_client_errors_total{service="auth"}` | Counter | < 1% | gRPC 调用失败率 |

### 3.2 监控查询 (Prometheus)

```promql
# batch API 调用效率（应接近 1 call per 100 users）
rate(grpc_client_requests_total{service="auth",method="get_users_by_ids"}[5m])

# orphan cleaner 清理速率
rate(orphan_cleaner_deleted_members_total[1h])

# gRPC 错误率
sum(rate(grpc_client_errors_total{service="auth"}[5m]))
  / sum(rate(grpc_client_requests_total{service="auth"}[5m]))
```

### 3.3 日志检查

```bash
# 正常运行日志
kubectl logs -n nova messaging-service-xxx | grep "orphan_cleaner"

# 预期输出
INFO orphan_cleaner: Starting orphan cleaner (interval: 1h, batch: 100, retention: 30d)
INFO orphan_cleaner: Cleaned 15 orphaned members from 3 conversations

# 错误日志
kubectl logs -n nova messaging-service-xxx | grep -E "ERROR|WARN.*auth"
```

---

## 4. 常见问题排查

### 4.1 gRPC 连接失败

**症状**:
```
ERROR auth_client: Failed to connect: transport error
```

**排查步骤**:
1. 验证 auth-service 健康状态
   ```bash
   kubectl get pods -n nova | grep auth-service
   grpcurl -plaintext auth-service:9080 grpc.health.v1.Health/Check
   ```

2. 检查网络策略
   ```bash
   kubectl describe networkpolicy -n nova
   ```

3. 验证 DNS 解析
   ```bash
   kubectl exec -n nova messaging-service-xxx -- nslookup auth-service
   ```

**解决方案**:
- 重启 auth-service pod: `kubectl rollout restart deployment/auth-service -n nova`
- 检查 SERVICE_MESH 配置（如使用 Istio）

---

### 4.2 Batch API 性能下降

**症状**:
```
WARN orphan_cleaner: Batch API slow: took 2.3s for 100 users
```

**排查步骤**:
1. 检查 auth-service 资源使用
   ```bash
   kubectl top pod -n nova | grep auth-service
   ```

2. 查看数据库连接池状态
   ```sql
   SELECT count(*), state FROM pg_stat_activity
   WHERE application_name = 'auth-service'
   GROUP BY state;
   ```

3. 检查是否触发数据库慢查询
   ```sql
   SELECT query, calls, total_time, mean_time
   FROM pg_stat_statements
   WHERE query LIKE '%get_users_by_ids%'
   ORDER BY total_time DESC LIMIT 10;
   ```

**解决方案**:
- 增加 auth-service replicas: `kubectl scale deployment auth-service --replicas=3 -n nova`
- 调整数据库连接池大小（auth-service环境变量 `DATABASE_MAX_CONNECTIONS`）
- 添加数据库索引: `CREATE INDEX CONCURRENTLY idx_users_id ON users(id);`

---

### 4.3 Orphan Cleaner 未清理过期数据

**症状**:
```
# 30天前软删除的用户仍在 conversation_members
SELECT COUNT(*) FROM conversation_members cm
LEFT JOIN users u ON cm.user_id = u.id
WHERE u.deleted_at < NOW() - INTERVAL '30 days';
```

**排查步骤**:
1. 检查 orphan_cleaner 是否运行
   ```bash
   kubectl logs -n nova messaging-service-xxx | grep "orphan_cleaner" | tail -20
   ```

2. 验证 auth-service batch API 响应
   ```bash
   # 使用 grpcurl 测试
   grpcurl -plaintext -d '{"user_ids":["uuid1","uuid2"]}' \
     auth-service:9080 nova.auth_service.v1.AuthService/GetUsersByIds
   ```

3. 检查数据库事务锁
   ```sql
   SELECT pid, usename, state, query
   FROM pg_stat_activity
   WHERE state = 'active' AND query LIKE '%conversation_members%';
   ```

**解决方案**:
- 手动触发清理（需要重启 pod 或等待下一个调度周期）
- 检查 orphan_cleaner interval 配置（默认 1h）
- 验证软删除用户确实从 auth-service 返回为空

---

### 4.4 N+1 查询未消除

**症状**:
```
# 监控显示 100 users 产生了 100+ gRPC calls
grpc_client_requests_total{service="auth",method="get_user"} > 100
```

**排查步骤**:
1. 检查代码版本
   ```bash
   kubectl exec -n nova messaging-service-xxx -- cat /proc/1/cmdline
   ```

2. 验证是否使用批量 API
   ```bash
   kubectl logs -n nova messaging-service-xxx | grep "get_users_by_ids"
   ```

**解决方案**:
- **关键**: 确认部署了 spec007 Phase 1 版本（commit: `decdece4`）
- 检查是否有旧版本 pod 仍在运行: `kubectl get pods -n nova -o wide`
- 强制滚动更新: `kubectl rollout restart deployment/messaging-service -n nova`

---

## 5. 性能基准

### 5.1 Batch API 基准

| 用户数 | P50延迟 | P99延迟 | 调用次数 |
|-------|---------|---------|---------|
| 10    | 15ms    | 25ms    | 1       |
| 100   | 45ms    | 80ms    | 1       |
| 500   | 180ms   | 300ms   | 5       |
| 1000  | 350ms   | 600ms   | 10      |

**批处理大小**: 100 users/batch（硬编码于 orphan_cleaner）

### 5.2 Orphan Cleaner 性能

| 会话数 | 成员总数 | 执行时间 | 删除数 |
|-------|---------|---------|--------|
| 10    | 150     | 0.5s    | 5      |
| 100   | 1500    | 4.2s    | 50     |
| 1000  | 15000   | 38s     | 500    |

**调度间隔**: 1小时（可通过环境变量调整）

---

## 6. 回滚流程

### 6.1 紧急回滚步骤

如果发现关键问题（如大规模数据丢失），立即回滚：

```bash
# 1. 回滚到 Phase 0 版本（pre-spec007）
kubectl rollout undo deployment/messaging-service -n nova

# 2. 验证回滚成功
kubectl rollout status deployment/messaging-service -n nova

# 3. 检查日志无错误
kubectl logs -n nova messaging-service-xxx | grep -E "ERROR|FATAL"

# 4. 验证 messaging-service.users 表仍可访问
psql -h messaging-db -U postgres -d messaging -c "SELECT COUNT(*) FROM users;"
```

### 6.2 数据恢复

如果错误删除了会话成员：

```sql
-- 从备份恢复（假设每日备份）
-- 1. 识别错误删除的时间范围
SELECT conversation_id, user_id, deleted_at
FROM conversation_members_audit
WHERE deleted_at BETWEEN '2025-11-07 10:00' AND '2025-11-07 11:00';

-- 2. 从备份表恢复
INSERT INTO conversation_members (conversation_id, user_id, role, joined_at)
SELECT conversation_id, user_id, role, joined_at
FROM conversation_members_backup_20251107
WHERE (conversation_id, user_id) IN (
  -- 错误删除的记录
  SELECT conversation_id, user_id FROM deleted_members_list
);
```

### 6.3 回滚验证清单

- [ ] messaging-service pod 全部重启完成
- [ ] orphan_cleaner 日志无错误
- [ ] gRPC metrics 恢复正常
- [ ] 用户可以正常发送/接收消息
- [ ] 会话成员列表显示正确

---

## 7. 容量规划

### 7.1 资源需求

| 服务 | CPU | 内存 | 副本数 |
|------|-----|------|-------|
| messaging-service | 500m | 512Mi | 3 |
| auth-service | 300m | 256Mi | 2 |

**水平扩展触发条件**:
- CPU > 70%: 增加 1 副本
- Memory > 80%: 增加 1 副本
- gRPC 请求延迟 P99 > 200ms: 增加 auth-service 副本

### 7.2 数据库连接池

```yaml
# messaging-service
DATABASE_MAX_CONNECTIONS: 20  # 每个 pod
DATABASE_MIN_CONNECTIONS: 5

# auth-service
DATABASE_MAX_CONNECTIONS: 30  # 需支持 messaging-service 批量查询
DATABASE_MIN_CONNECTIONS: 10
```

**计算公式**:
```
总连接数 = (messaging-service replicas × 20) + (auth-service replicas × 30)
         = (3 × 20) + (2 × 30) = 120 connections

推荐 PostgreSQL max_connections ≥ 150
```

---

## 8. 维护窗口

### 8.1 定期任务

| 任务 | 频率 | 执行时间 | 负责人 |
|------|------|---------|--------|
| 验证 orphan_cleaner 执行 | 每日 | 09:00 UTC | SRE |
| 检查 gRPC 连接池健康 | 每周 | 周一 10:00 | 后端团队 |
| 审查删除数据统计 | 每月 | 月初第一天 | 数据团队 |
| 性能基准测试 | 每季度 | 季度末 | 性能团队 |

### 8.2 升级窗口

建议维护窗口：
- **时间**: 每周三 02:00-04:00 UTC（用户活跃度最低）
- **通知**: 提前 24 小时通知
- **回滚准备**: 维护窗口期间保持 Phase 0 镜像就绪

---

## 9. 联系方式

| 角色 | 联系方式 | 升级条件 |
|------|---------|---------|
| 一线 SRE | #sre-oncall Slack | 所有警报 |
| 后端负责人 | @backend-lead | P0/P1 事件 |
| 数据库 DBA | @dba-team | 数据库性能问题 |
| 架构师 | @architect | 架构设计变更 |

**紧急联系**:
- Slack: `#spec007-incidents`
- PagerDuty: `spec007-phase1`

---

## 10. 附录

### 10.1 相关文档

- [Spec 007 设计文档](../specs/spec007/spec.md)
- [Phase 1 任务分解](../specs/spec007/plan.md)
- [集成测试说明](../../backend/messaging-service/tests/batch_api_orphan_cleaner_test.rs)

### 10.2 快速命令参考

```bash
# 查看 orphan_cleaner 执行历史
kubectl logs -n nova messaging-service-xxx | grep orphan_cleaner | tail -50

# 检查 auth-service gRPC 健康
grpcurl -plaintext auth-service:9080 grpc.health.v1.Health/Check

# 监控 batch API 调用
kubectl exec -n nova messaging-service-xxx -- curl http://localhost:9091/metrics | grep grpc_client

# 手动触发 orphan_cleaner（重启 pod）
kubectl delete pod -n nova messaging-service-xxx

# 查看数据库连接数
kubectl exec -n nova postgres-xxx -- psql -U postgres -c "SELECT count(*), application_name FROM pg_stat_activity GROUP BY application_name;"
```

---

**版本历史**:
- v1.0 (2025-11-07): 初始版本，覆盖 Phase 1 基础运维
