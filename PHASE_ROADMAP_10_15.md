# Nova 项目阶段路线图 - Phase 10-15

## 项目进度概览

```
已完成 ✅        正在进行 🟡      规划中 📋
Phase 1-9        Phase 10         Phase 11-15
```

### Phase 历史回顾

| Phase | 目标 | 状态 |
|-------|------|------|
| 1-5 | 初始微服务分解 | ✅ 完成 |
| 6-7 | 特性实现与修复 | ✅ 完成 |
| 8 | User-service 完整清理 | ✅ 完成 (8,000+ 行代码删除) |
| 9 | 依赖优化与 CI/CD 并行化 | ✅ 完成 |

---

## 🟡 Phase 10: Polyrepo 基础建设 (3-4 周)

**目标**: 开始 polyrepo 转换，提取共享库和认证服务

### Phase 10.1: 提取 nova-shared 库
**时间**: Week 1

**工作内容**:
```bash
# 1. 从 monorepo 分离共享库
git clone --filter=blob:none nova-monorepo nova-shared
cd nova-shared
git filter-branch --subdirectory-filter backend/libs -- --all
git reset --hard
```

**目录结构**:
```
nova-shared/
├── Cargo.toml (workspace 根)
├── error-types/
│   ├── Cargo.toml
│   └── src/
├── crypto-core/
├── db-pool/
├── redis-utils/
├── nova-fcm-shared/
├── Makefile
├── .github/workflows/
│   └── ci.yml (库 CI)
└── README.md
```

**任务**:
- [ ] 创建 nova-shared 仓库
- [ ] 配置 Cargo workspace
- [ ] 发布到私有 crates registry
- [ ] 更新版本号到 0.1.0
- [ ] 测试独立编译和发布

**预期结果**: nova-shared 0.1.0 发布到内部 registry

---

### Phase 10.2: 提取 nova-auth-service
**时间**: Week 2-3

**工作内容**:

```bash
# 1. 创建新仓库
git init nova-auth-service
cd nova-auth-service

# 2. 从 monorepo 提取认证代码
git add ../nova-monorepo/backend/auth-service
git add ../nova-monorepo/backend/migrations/002*.sql
git commit -m "Initial auth-service from monorepo"
```

**新仓库结构**:
```
nova-auth-service/
├── Cargo.toml
├── src/
│   ├── handlers/
│   │   ├── auth.rs
│   │   └── oauth.rs
│   ├── services/
│   │   ├── jwt.rs
│   │   ├── oauth/
│   │   ├── two_fa.rs
│   │   └── email_service.rs
│   ├── db/
│   ├── grpc/
│   │   └── auth.proto
│   └── main.rs
├── migrations/
│   ├── 002_add_auth_logs.sql
│   ├── 006_add_two_factor_auth.sql
│   └── ...
├── protos/
│   └── auth.proto
├── Dockerfile
├── docker-compose.yml
├── .github/workflows/
│   ├── ci.yml
│   └── deploy.yml
└── k8s/
    ├── deployment.yaml
    └── service.yaml
```

**关键任务**:
- [ ] 从 nova-shared 更新依赖
- [ ] 配置 gRPC 服务定义 (auth.proto)
- [ ] 独立 CI/CD 流水线
- [ ] 本地 docker-compose 测试
- [ ] 所有测试通过

**预期结果**: nova-auth-service 可独立构建、测试、部署

---

### Phase 10.3: 设置服务通信基础设施
**时间**: Week 3

**工作内容**:

#### 创建 nova-auth-client 库

在 `nova-shared/` 中添加:
```
nova-shared/nova-auth-client/
├── Cargo.toml
└── src/
    └── lib.rs
```

**核心接口**:
```rust
// nova-shared/nova-auth-client/src/lib.rs
use tonic::transport::Channel;

#[derive(Clone)]
pub struct AuthClient {
    client: auth_service::AuthServiceClient<Channel>,
}

impl AuthClient {
    pub async fn verify_token(&self, token: &str) -> Result<UserClaims> {
        // gRPC 调用到 auth-service:8084
    }

    pub async fn get_user_id(&self, token: &str) -> Result<String> {
        // 验证并获取用户 ID
    }
}
```

**任务**:
- [ ] 定义 auth.proto (gRPC 接口)
- [ ] 创建 auth-client 库
- [ ] 在 user-service 中使用 auth-client
- [ ] 删除 user-service 中的 JWT 解析代码
- [ ] 所有测试通过

---

### Phase 10.4: 决策门点 (Decision Gate)
**时间**: Week 4 末

**评估指标**:

| 指标 | 成功标准 | 实际值 |
|------|--------|------|
| gRPC 延迟 | <100ms | ? |
| auth-service 启动时间 | <5s | ? |
| 认证验证速度 | <50ms | ? |
| 开发体验 | 无破坏性改动 | ? |
| 测试通过率 | 100% | ? |

**Go/No-Go 标准**:
- ✅ **Go**: 所有指标通过，开发体验无显著下降
- ❌ **No-Go**: gRPC 延迟 >200ms，需要重新评估架构

**决策**:
- ✅ 继续 Phase 11 (继续转换)
- ❌ 回滚到 monorepo (恢复单库)

---

## 📋 Phase 11: 核心服务迁移 (4-5 周)

**目标**: 提取 user-service 和 content-service

### Phase 11.1: 提取 nova-user-service
- 从 monorepo 分离代码
- 使用 nova-auth-client 进行认证
- 更新 gRPC 定义
- 配置 Neo4j 集成
- Kafka 生产者设置

### Phase 11.2: 提取 nova-content-service
- 从 monorepo 分离代码
- 依赖: user-service gRPC
- CDC 管道设置
- 搜索索引集成

### Phase 11.3: 更新 API Gateway
- 路由配置 user-service 调用
- 路由配置 content-service 调用
- 服务发现集成

---

## 📋 Phase 12: 高级服务迁移 (3-4 周)

**目标**: 提取 feed, media, messaging services

### Phase 12.1: 提取 nova-feed-service
- 依赖: user-service, content-service
- ClickHouse 集成
- 推荐模型 (ONNX) 部署
- A/B 实验框架

### Phase 12.2: 提取 nova-media-service
- S3 文件存储
- FFmpeg 转码
- WebP/AVIF 优化
- CDN 集成

### Phase 12.3: 提取 nova-messaging-service
- WebSocket 实时通信
- 端到端加密
- 消息搜索索引
- 离线消息队列

---

## 📋 Phase 13: 数据一致性与迁移 (2-3 周)

**目标**: 确保服务间数据同步

### Phase 13.1: CDC 管道验证
- PostgreSQL → Kafka → 各服务数据库
- 验证数据完整性
- 处理异常情况

### Phase 13.2: 双写架构
- Monorepo 和 polyrepo 同时运行
- 验证数据一致性
- 找出差异

### Phase 13.3: 逐步流量切换
- 10% 流量到新服务
- 50% 流量到新服务
- 100% 流量到新服务

---

## 📋 Phase 14: 生产切换与金丝雀部署 (2 周)

**目标**: 完整的灰度发布和故障转移

### Phase 14.1: 金丝雀部署策略
- Kubernetes Canary 部署
- 自动化 A/B 测试
- 流量百分比逐步递增

### Phase 14.2: 故障转移与回滚
- 自动健康检查
- 自动回滚机制
- 完整的观测

### Phase 14.3: 关闭 Monorepo
- 存档旧代码
- 更新文档
- 团队培训完成

---

## 📋 Phase 15: 可观测性与稳定化 (2-3 周)

**目标**: 完整的监控、日志、追踪

### Phase 15.1: 分布式追踪
- OpenTelemetry 集成
- Jaeger/Tempo 部署
- 服务级性能监控

### Phase 15.2: 日志聚合
- ELK Stack / Loki
- 跨服务日志关联
- 日志警告规则

### Phase 15.3: 指标与告警
- Prometheus 指标
- Grafana 仪表板
- PagerDuty 集成
- SLO/SLI 定义

---

## Phase 16: 文档与优化 (1-2 周)

**目标**: 完整的文档和性能优化

### Phase 16.1: 文档更新
- 架构文档
- 部署指南
- 故障排查指南
- API 文档

### Phase 16.2: 团队培训
- Polyrepo 工作流
- 服务通信模式
- 部署流程

### Phase 16.3: 性能优化
- 缓存优化
- 数据库查询优化
- 网络延迟优化

---

## 📊 完整时间表

```
现在              Week 1-4           Week 5-9          Week 10-12
 ↓                   ↓                  ↓                  ↓
Phase 9 完成 → Phase 10 (Polyrepo基础) → Phase 11-12 → Phase 13-14
                                          (服务迁移)      (切换)

Week 13-15        Week 16-18
    ↓                ↓
Phase 15        Phase 16
(可观测性)      (文档优化)
```

### 总时间线
- **Phase 10**: 3-4 周 (基础建设)
- **Phase 11-12**: 7-9 周 (服务迁移)
- **Phase 13-14**: 4-5 周 (数据与切换)
- **Phase 15-16**: 3-4 周 (监控与文档)

**总计**: 17-22 周 (约 4-5 个月)

---

## 🎯 Phase 10-16 关键里程碑

| 里程碑 | 时间 | 完成标志 |
|--------|------|--------|
| nova-shared 发布 | Week 1 | crates registry 版本 0.1.0 |
| nova-auth 独立运行 | Week 3 | 独立 CI/CD 通过 |
| 决策门点 | Week 4 | Go/No-Go 决定 |
| 所有服务 polyrepo | Week 9 | 8 个独立仓库 |
| 数据同步验证 | Week 12 | 100% 一致性 |
| 完整 polyrepo 生产 | Week 14 | Monorepo 关闭 |
| 完整可观测性 | Week 15 | Jaeger + ELK + Prometheus |
| 文档完成 | Week 16 | 所有页面更新 |

---

## 🚀 每个 Phase 的价值

| Phase | 价值 | 风险 |
|-------|------|------|
| 10 | 验证 polyrepo 可行性 | gRPC 延迟过高 |
| 11-12 | 完整服务分离 | 数据不一致 |
| 13-14 | 生产就绪 | 流量切换失败 |
| 15-16 | 生产支持 | 监控盲点 |

---

## 💡 成功标准

### Phase 10 成功
- ✅ nova-shared 发布到 registry
- ✅ nova-auth-service 独立构建
- ✅ gRPC 调用延迟 <100ms
- ✅ 所有测试通过

### Phase 11-12 成功
- ✅ 所有 8 个服务独立仓库
- ✅ 每个服务独立 CI/CD
- ✅ 服务间通信稳定
- ✅ 开发速度不低于当前

### Phase 13-14 成功
- ✅ 100% 数据一致性
- ✅ 自动故障转移
- ✅ <5 分钟回滚时间
- ✅ Monorepo 完全关闭

### Phase 15-16 成功
- ✅ 完整的端到端追踪
- ✅ <100ms P99 延迟
- ✅ 99.95% 可用性
- ✅ 团队培训完成

---

## 📝 何时停止

如果以下任何情况发生，立即停止并重新评估:

1. **gRPC 延迟 >500ms** - 选择其他通信方式
2. **服务启动时间 >30s** - 优化依赖加载
3. **开发体验严重恶化** - 简化开发流程
4. **数据一致性无法保证** - 重新设计 CDC
5. **团队对 polyrepo 有强烈反对** - 转换计划或放弃

---

**更新日期**: 2024-10-30
**状态**: 规划完成，准备开始 Phase 10
**下一步**: 开始 Phase 10.1 (nova-shared 提取)
