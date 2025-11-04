# 🚀 Nova 后端架构重构 - Phase 1（实施概述）

**开始日期**: 2025-11-11 (Phase 0 完成后)
**预计完成**: 2026-01-20 (12 周)
**团队配置**: 4-5 人（2 架构师 + 3 后端工程师）

---

## 📋 Phase 1 目标

在 Phase 0 的蓝图基础上，Phase 1 将把 Nova 从**分布式单体**转变为**真正的微服务架构**。

### 关键成果

```
当前: 4/10 (分布式单体) → Phase 1 后: 7/10 (独立微服务)
- 故障隔离: 0% → 75%
- 独立部署: 不可能 → 1-2 天
- users 表 QPS: 500 → 5000+
```

---

## 🎯 Phase 1 核心任务（分为 3 个子阶段）

### Sub-Phase 1A: 基础设施和数据库分离 (Weeks 1-4)

#### 目标
创建 8 个独立的 PostgreSQL 实例，每个服务拥有自己的数据库。

#### 关键里程碑

**Week 1: 基础设施部署**
- T001: 部署 8 个独立 PostgreSQL 实例 (Kubernetes 或 managed)
- T002: 配置 PostgreSQL 自动备份和 WAL 归档
- T003: 设置主从复制 (HA/DR)
- T004: 配置监控告警 (Prometheus + Grafana)

**Week 2: 数据库初始化**
- T005: 创建 auth-service 数据库 + 迁移
- T006: 创建 messaging-service 数据库 + 迁移
- T007: 创建 content-service 数据库 + 迁移
- T008: 创建 user-service 数据库 + 迁移
- T009: 创建剩余 4 个服务数据库 + 迁移

**Week 3-4: 数据迁移**
- T010: 编写数据迁移脚本（每个服务）
- T011: 建立"兼容层" (PostgreSQL VIEW + 外数据包装器)
- T012: 执行初始数据同步
- T013: 建立持续同步机制（触发器或 CDC）
- T014: 验证数据一致性

#### 输出文件
- `docs/INFRASTRUCTURE_DEPLOYMENT.md` - 基础设施部署指南
- `backend/migrations/phase-1-*-split-database.sql` - 每个服务的迁移脚本
- `scripts/verify-data-consistency.sh` - 数据一致性验证脚本

---

### Sub-Phase 1B: gRPC API 实现和应用改造 (Weeks 5-9)

#### 目标
实现 gRPC 服务，将所有跨服务直接 SQL 调用转换为 gRPC RPC。

#### 关键里程碑

**Week 5: 生成 gRPC 代码**
- T015: 创建 tonic 生成的 auth-service gRPC 代码
- T016: 创建 messaging-service gRPC 代码
- T017: 创建 content-service gRPC 代码
- T018: 创建剩余 5 个服务的 gRPC 代码

**Week 6: 实现 gRPC 服务器**
- T019: 在 auth-service 中实现 GetUser, GetUsersByIds, CheckTokenValidity
- T020: 在 messaging-service 中实现 GetMessages, GetConversationMembers
- T021: 在 content-service 中实现 GetPost, GetPostsByIds
- T022: 在其他服务中实现对应的 gRPC 端点

**Week 7: 实现 gRPC 客户端 + 缓存**
- T023: 在 messaging-service 中使用 auth-service gRPC 客户端替代直接 SQL
- T024: 在 content-service 中实现对应替代
- T025: 在所有服务中实现 Redis 缓存（缓存 gRPC 响应）
- T026: 配置缓存失效策略

**Week 8-9: 错误处理 + 重试 + 超时**
- T027: 实现 gRPC 错误映射到应用错误
- T028: 实现 exponential backoff 重试策略
- T029: 配置超时 (P99 < 1s)
- T030: 实现断路器模式防止级联故障

#### 输出文件
- `backend/proto/services/*.proto` - gRPC 服务定义
- `backend/grpc-services/*/src/lib.rs` - gRPC 实现代码
- `backend/grpc-clients/*/src/lib.rs` - gRPC 客户端封装
- 各服务应用代码更新
- `docs/GRPC_IMPLEMENTATION_GUIDE.md` - 实现指南

---

### Sub-Phase 1C: 灰度发布、监控、验收测试 (Weeks 10-12)

#### 目标
确保新的微服务架构在生产环境安全、稳定地运行。

#### 关键里程碑

**Week 10: 测试和验证**
- T031: 编写集成测试（所有服务间 gRPC 调用）
- T032: 编写性能基准测试 (Criterion)
- T033: 编写故障恢复测试 (服务宕机场景)
- T034: 在测试环境进行完整灰度发布模拟

**Week 11: 灰度发布 (Production)**
- T035: 灰度 10% 流量 (新 gRPC 架构, 保留旧 SQL 作为回退)
- T036: 监控 P95 延迟、错误率、日志 (24 小时)
- T037: 灰度 50% 流量 (增量分析)
- T038: 完全切换到 100% (新架构)

**Week 12: 性能优化 + 文档**
- T039: 优化热路径（根据性能数据）
- T040: 配置 gRPC 连接池优化
- T041: 调整缓存 TTL 和策略
- T042: 清理回退逻辑（旧 SQL 代码）
- T043: 更新架构文档和运维手册

#### 输出文件
- `backend/tests/integration-grpc-*.rs` - 集成测试
- `ops/canary-deployment.yaml` - Kubernetes 灰度发布配置
- `scripts/phase-1-validation.sh` - 验收测试脚本
- `docs/PHASE_1_COMPLETION_REPORT.md` - 完成报告

---

## 📊 Phase 1 成功指标

所有以下指标必须在 Phase 1 完成后达成：

### 架构指标
- ✅ 8 个独立数据库运行 (0 个共享数据库)
- ✅ 0 个直接的跨数据库 FK
- ✅ 100% 的服务间通信使用 gRPC
- ✅ 故障隔离能力从 0% 提升到 75%

### 性能指标
- ✅ gRPC P95 延迟 < 100ms
- ✅ 缓存 hit rate > 85%
- ✅ users 表 QPS 从 500 提升到 5000+
- ✅ 新服务启动时间 < 5s (包含数据库连接)

### 可靠性指标
- ✅ 灰度发布期间 0 个生产事件
- ✅ 数据一致性验证 99.99% (没有数据损坏)
- ✅ 回滚时间 < 5 分钟
- ✅ 服务间 RPC 成功率 > 99.95%

### 代码质量指标
- ✅ 集成测试覆盖 > 90%
- ✅ 零 unwrap/expect in gRPC 路径
- ✅ 所有错误路径有明确的日志记录
- ✅ 代码审查: 所有 PR 有 2+ 批准

---

## 🔄 Phase 1 工作流程

### 每周节奏

**每周一**: 周计划会议 (1 小时)
- 复审上周完成情况
- 确认本周的 T00X 任务和分配
- 识别风险和依赖

**周二-周四**: 执行 (并行开发)
- 每个小组完成分配的任务
- 每日同步 15 分钟 (Slack/站会)

**周五**: 代码审查 + 验证
- 所有 PR 必须合并到 main
- 运行完整的集成测试
- 下周的提前准备

**周末**: 准备 + 文档
- 准备下周的演示或检查点
- 更新文档和进度报告

### 人员分配建议

```
团队 A (2 人): 基础设施 + 数据库迁移
  - 工程师 1: PostgreSQL 配置、备份、复制
  - 工程师 2: 数据迁移脚本、一致性验证

团队 B (2 人): gRPC 实现
  - 工程师 3: 生成 gRPC 代码，实现服务器
  - 工程师 4: 实现客户端，缓存层

团队 C (1 人): 测试 + 验收
  - 工程师 5: 集成测试，灰度发布，性能验证

架构师 (1 人): 监督全过程
  - 设计评审，决策，风险管理
```

---

## ⚠️ Phase 1 关键风险和缓解措施

### 风险 1: 数据迁移过程中数据不一致

**风险**: 新数据库和旧数据库数据不同步，导致应用看到不一致的数据

**缓解措施**:
- 实现 CDC (Change Data Capture) 同步机制
- 每小时运行一次数据一致性检查脚本
- 保留旧数据库作为"事实源" 72 小时
- 灰度发布时只切换 10% 流量，监控 24h

**责任**: 团队 A

---

### 风险 2: gRPC 性能不如预期

**风险**: 如果 gRPC 调用延迟 > 500ms，会影响用户体验

**缓解措施**:
- 在 Week 7 提前进行性能基准测试
- 实现多级缓存 (L1: 应用内存, L2: Redis)
- 使用 gRPC 连接复用和 http/2 多路复用
- 如果延迟超过阈值，可以保留关键路径的直接 SQL

**责任**: 团队 B

---

### 风险 3: gRPC 服务故障导致级联故障

**风险**: 如果 auth-service gRPC 宕机，所有其他服务都无法运行

**缓解措施**:
- 实现断路器模式 (fallback to cached data)
- 在客户端实现本地缓存
- 实现超时和快速失败
- 在灰度期间进行故障转移测试

**责任**: 团队 B

---

### 风险 4: 灰度发布过程中的路由配置错误

**风险**: 部分流量被路由到错误的版本，导致不一致的行为

**缓解措施**:
- 使用 Istio/Linkerd 进行精细的流量控制
- 在测试环境进行完整灰度模拟
- 灰度期间有专人监控指标
- 有明确的回滚触发条件 (>1% 错误率)

**责任**: 架构师 + DevOps

---

## 📈 Phase 1 进度追踪

使用以下模板追踪每周进度：

### 周报模板

```markdown
# Phase 1 - Week N Progress Report

**日期**: 2025-11-11 ~ 2025-11-17

## ✅ 完成的任务
- T001: ✅ 部署 8 个独立 PostgreSQL 实例
  - 成本: 24 工时
  - 完成日期: 2025-11-12

## 🔄 进行中的任务
- T002: 🔄 配置 PostgreSQL 自动备份
  - 进度: 60%
  - 预期完成: 2025-11-14

## ⚠️ 阻塞项
- None

## 📊 指标
- 代码变更: 4.2K 行
- PR 合并: 12
- 测试通过率: 98%
- 性能: P95 延迟 45ms (目标 100ms)

## 🎯 下周计划
- T003: 设置 HA/DR 复制
- T005: 启动 auth-service 数据库迁移

## 👥 出席者
- 工程师 1-4, 架构师
```

---

## 🎬 Phase 1 → Phase 2 的交接

Phase 1 完成后，团队应该有能力：

1. ✅ 部署和管理 8 个独立的数据库
2. ✅ 实现和维护 gRPC 服务间通信
3. ✅ 独立部署每个服务（无需协调）
4. ✅ 快速定位故障到单个服务

Phase 2 (Weeks 13-20) 将专注于：
- **Phase 2A**: Event-driven 架构 (Kafka + Outbox)
- **Phase 2B**: 缓存层优化 (Redis Cluster + Consistency)
- **Phase 2C**: 服务网格和高级路由 (Istio)

---

## 💡 Phase 1 最佳实践

### 1. 首先在测试环境验证

```bash
# Phase 1 的所有变更都应该先在测试环境运行
# 只有通过完整集成测试，才能进入灰度

./scripts/run-full-integration-test.sh
# 预期: ✅ All 500+ tests passed
```

### 2. 保留快速回滚能力

```bash
# 在 gRPC 路由器中同时支持新旧两个代码路径
match (use_new_architecture) {
    true => call_grpc_service(),
    false => call_sql_directly(),  // fallback
}

// 灰度时，将百分比从 0% 推进到 100%
let grpc_traffic_percentage = env::var("GRPC_TRAFFIC_PCT")
    .unwrap_or("0".to_string())
    .parse::<f64>()?;

if rand() * 100.0 < grpc_traffic_percentage {
    use_new_architecture = true;
} else {
    use_new_architecture = false;
}
```

### 3. 监控一切

```yaml
# Prometheus 告警规则（alerts.yaml）
- alert: GRPCLatencyHigh
  expr: histogram_quantile(0.95, grpc_request_duration_ms) > 100
  for: 5m
  action: page_oncall

- alert: GRPCErrorRateHigh
  expr: rate(grpc_request_errors[5m]) > 0.01
  for: 5m
  action: trigger_rollback
```

### 4. 文档和知识转移

在 Phase 1 进行中，持续更新：
- `docs/GRPC_TROUBLESHOOTING.md` - gRPC 常见问题
- `docs/DEPLOYMENT_GUIDE.md` - 部署指南
- 视频教程 - 如何调试 gRPC 问题

---

## 📚 参考资源

### 官方文档
- [Tonic gRPC Framework](https://docs.rs/tonic/)
- [PostgreSQL Foreign Data Wrapper](https://www.postgresql.org/docs/current/postgres-fdw.html)
- [Kafka Connect](https://kafka.apache.org/documentation.html)

### 相关 Nova 文档
- `ARCHITECTURE_PHASE_0_PLAN.md` - Phase 0 细节
- `ARCHITECTURE_DEEP_ANALYSIS.md` - 当前架构分析
- `docs/DATA_OWNERSHIP_MODEL.md` - Phase 0 输出

---

## ✅ Phase 1 启动检查清单

在启动 Phase 1 前，确保以下条件满足：

- [ ] Phase 0 所有交付物已完成 ✅
- [ ] 8 个服务的数据所有权已明确 ✅
- [ ] gRPC API 规范已签核 ✅
- [ ] 基础设施预算已批准 (PostgreSQL x8, 更多网络) ✅
- [ ] 团队成员已指定 (4-5 人) ✅
- [ ] 测试环境已准备好 ✅
- [ ] 部署工具 (Terraform/Helm) 已配置 ✅

---

## 📞 Phase 1 沟通计划

### 内部沟通
- **每日**: Slack 进度更新 (#nova-phase-1)
- **每周一**: 团队规划会议 (1h)
- **每周五**: 进度审查 + 风险讨论 (1h)

### 利益相关者沟通
- **每两周**: 管理层状态更新 (exec summary)
- **出现重大风险**: 立即升级通知
- **Phase 完成**: 完成报告 + lessons learned

---

**状态**: 📋 计划阶段（等待 Phase 0 完成）
**责任人**: 架构师 + 后端团队主管
**下次更新**: Phase 0 完成后
