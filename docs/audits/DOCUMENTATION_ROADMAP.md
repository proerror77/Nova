# Nova 后端文档改进路线图

**目标**：在3个月内将文档覆盖率从 20% 提升到 95%+
**优先级**：P2（影响开发效率和 onboarding）
**所有者**：Backend Team Lead
**启动日期**：2025年11月22日

---

## 进展概览

```
Phase 1 (第1-2周): 解除阻塞    ████░░░░░░ 0%
Phase 2 (第3-4周): 完善API文档 ░░░░░░░░░░ 0%
Phase 3 (第5-6周): 部署和故障  ░░░░░░░░░░ 0%
Phase 4 (持续):   维护         ░░░░░░░░░░ 0%
```

---

## Phase 1: 解除阻塞（第1-2周）

**目标**：让新开发者在30分钟内理解系统架构

### Task 1.1：创建 SERVICES_OVERVIEW.md

**描述**：所有14个服务的清单，一页纸速查

**文件**：`backend/SERVICES_OVERVIEW.md`

**交付物**：
```markdown
# Nova 微服务清单

## 核心服务（8个）
| 服务 | 职责 | REST端口 | gRPC端口 | 依赖 |
|------|------|---------|---------|------|
| content-service | 发布、评论、故事 | 8081 | 9081 | postgres, redis |
| feed-service | Feed生成、推荐 | 8080 | 9080 | content, ranking |
| social-service | 关注、点赞、评论 | 8085 | 9085 | postgres |
| identity-service | 认证、用户身份 | 8083 | 9083 | postgres |
| media-service | 媒体上传、转码 | 8082 | 9082 | s3 |
| graph-service | 社交图谱 | - | 9090 | neo4j |
| notification-service | 推送通知 | 8000 | - | postgres |
| ranking-service | 多阶段排序 | - | 9088 | none |
| ... (6个更多服务) |

## 基础设施服务（6个）
...
```

**所有者**：@backend-lead
**估计工作量**：2小时
**Deadline**：2025年11月24日
**PR要求**：
- [ ] 信息准确（与代码同步）
- [ ] 所有依赖都列出
- [ ] 包含port映射

**验证方法**：
```bash
# 检查所有列出的端口是否在 Makefile 或 docker-compose 中存在
grep -r "8081\|8082\|8083" Dockerfile* docker-compose*.yml
```

---

### Task 1.2：为4个核心服务创建 README

**核心服务**：content-service, feed-service, social-service, identity-service

**文件**：
- `backend/content-service/README.md`
- `backend/feed-service/README.md`
- `backend/social-service/README.md`
- `backend/identity-service/README.md`

**交付物**：每个 README 包含：
1. 📋 概述（1段）
2. 🎯 核心职责（3-5项）
3. 🏗️ 架构（依赖关系 + 数据流）
4. 🚀 快速开始（本地启动步骤）
5. 📡 API 文档（REST/gRPC 端点列表）
6. ⚙️ 配置（关键环境变量）
7. 🔄 与其他服务的集成

**模板**：使用 `DOCUMENTATION_STANDARDS.md` 中的模板

**所有者**：
- content-service @alice
- feed-service @bob
- social-service @charlie
- identity-service @diana

**估计工作量**：5小时/服务 = 20小时
**Deadline**：2025年12月1日
**PR要求**：
- [ ] 包含完整的快速开始步骤
- [ ] 所有依赖都明确列出
- [ ] 端口号与实际代码一致
- [ ] 至少包含1个API示例

**验证方法**：
```bash
# 新开发者能否按照README在30分钟内启动？
# 运行 Dockerfile 中的命令，验证是否工作
```

---

### Task 1.3：验证和更新端口定义

**描述**：确保所有端口定义一致

**文件**：新建 `backend/PORTS.md`

**交付物**：
```markdown
# Nova 服务端口映射

## API 服务端口

| 服务 | REST | gRPC | WebSocket |
|------|------|------|-----------|
| content-service | 8081 | 9081 | - |
| feed-service | 8080 | 9080 | - |
| ...

## 数据库端口

| 系统 | 端口 | 用途 |
|------|------|------|
| PostgreSQL | 5432 | 主数据库 |
| Redis | 6379 | 缓存和会话 |
| ClickHouse | 8123 | 分析数据 |
| Neo4j | 7687 | 图数据库 |
| Elasticsearch | 9200 | 搜索引擎 |

## 消息队列

| 系统 | 端口 | 用途 |
|------|------|------|
| Kafka | 9092 | 事件流 |

## 监控

| 系统 | 端口 | 用途 |
|------|------|------|
| Prometheus | 9090 | 指标收集 |
| Grafana | 3000 | 可视化 |
```

**所有者**：@devops-lead
**估计工作量**：2小时
**Deadline**：2025年11月25日
**验证方法**：
```bash
# 交叉检查：每个端口是否在以下位置一致：
grep -h "PORT\|port" .env.example Makefile docker-compose*.yml Dockerfile*
```

---

### Task 1.4：为 Proto 文件添加文档注释

**描述**：在每个 Proto 文件的 RPC 方法和关键消息前添加详细注释

**文件**：所有 `proto/services_v2/*.proto` 文件（10个）

**交付物示例**：

```protobuf
/// GetFeed returns a personalized feed for the requesting user.
///
/// This endpoint aggregates posts from:
/// - Users the requester follows (70% weight)
/// - Trending posts (20% weight)
/// - Recommended posts (10% weight)
///
/// The feed respects user's blocking and muting preferences.
/// Posts are ranked by relevance score and pagination is cursor-based.
///
/// # Parameters
/// - user_id: UUID of the requesting user (must exist)
/// - limit: Max posts per page (1-100, default: 20)
/// - cursor: Opaque pagination token (base64, optional)
///
/// # Returns
/// GetFeedResponse containing:
/// - posts: Ranked posts for this page
/// - next_cursor: Token for next page (empty if no more)
/// - has_more: Whether more pages exist
///
/// # Errors
/// - NOT_FOUND: User doesn't exist
/// - INVALID_ARGUMENT: limit > 100 or invalid cursor
/// - PERMISSION_DENIED: User is blocked or deactivated
rpc GetFeed(GetFeedRequest) returns (GetFeedResponse);
```

**所有者**：@api-lead
**估计工作量**：4小时（20个proto文件）
**Deadline**：2025年11月27日
**PR要求**：
- [ ] 每个 RPC 方法有完整注释
- [ ] 关键 Message 类型有字段说明
- [ ] 包含参数范围和有效值
- [ ] 包含错误情况

---

### Task 1.5：更新 .env.example 中的注释

**描述**：添加详细的环境变量说明，包括：
- 格式和示例值
- 必须 vs 可选
- 默认值
- 推荐范围
- 改变此值的影响

**文件**：`backend/.env.example`

**交付物示例**：

```bash
# ┌─────────────────────────────────────┐
# │ Database - PostgreSQL (Unified)     │
# └─────────────────────────────────────┘
# PostgreSQL connection string for all services
# Format: postgresql://[user[:password]@][host][:port][/database]
# Examples:
#   postgresql://postgres:password@localhost:5432/nova
#   postgresql://user@dbhost:5432/nova
# Required for: content-service, identity-service, social-service
DATABASE_URL=postgresql://postgres:postgres@postgres:5432/nova

# Maximum number of database connections in the pool
# Recommendation: CPU_CORES * 4
# Too low: Connection exhaustion, request timeouts
# Too high: Memory usage increases, context switching overhead
# Typical values: 10-50
DATABASE_MAX_CONNECTIONS=10

# Time to wait for a connection from the pool
# Default: 30 seconds
# If you see "timeout acquiring connection": increase this value
DATABASE_ACQUIRE_TIMEOUT_SECS=30

# Idle connection timeout
# Connections unused for this duration are closed
# Saves memory but increases latency for occasional requests
# Typical: 300-600 seconds
DATABASE_IDLE_TIMEOUT_SECS=600
```

**所有者**：@infrastructure-lead
**估计工作量**：4小时
**Deadline**：2025年11月29日
**PR要求**：
- [ ] 所有变量都有详细说明
- [ ] 包含示例值和推荐范围
- [ ] 解释改变此值的影响
- [ ] 标注必须 vs 可选

---

### Task 1.6：更新后端主 README

**文件**：`backend/README.md`

**当前内容**：仅8行，说明 user-service 已退役

**更新为**：
```markdown
# Nova 后端微服务架构

## 🚀 快速开始

新开发者入门指南：[GETTING_STARTED.md](GETTING_STARTED.md)

## 📋 服务清单

所有14个微服务：[SERVICES_OVERVIEW.md](SERVICES_OVERVIEW.md)

## 🏗️ 架构

系统全景和数据流：[ARCHITECTURE.md](ARCHITECTURE.md)

## 📡 API 参考

REST 和 gRPC 端点：[API_REFERENCE.md](API_REFERENCE.md)

## ⚙️ 配置

环境变量和配置：[.env.example](.env.example)

## 🚢 部署

本地和生产部署：[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)

## 🔧 开发

本地开发环境设置：[DEVELOPMENT.md](DEVELOPMENT.md)

## 📊 监控

监控和告警：[MONITORING.md](MONITORING.md)

## 🐛 问题排查

常见问题和解决方案：[TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## 📚 标准

代码和文档标准：[DOCUMENTATION_STANDARDS.md](DOCUMENTATION_STANDARDS.md)

## 🗂️ 目录结构

```
backend/
├── {service-name}/              # 14个微服务目录
│   ├── README.md               # 服务文档
│   ├── Cargo.toml
│   ├── src/
│   ├── migrations/             # 数据库迁移
│   └── ...
├── libs/                        # 共享库
├── proto/                       # gRPC 定义
├── migrations/                  # 全局迁移脚本
├── k8s/                        # Kubernetes 配置
├── docs/                       # 架构和设计文档
└── README.md                   # 本文件
```

## 🤝 贡献

参与 Nova 后端开发？

1. 阅读 [DEVELOPMENT.md](DEVELOPMENT.md)
2. 遵循 [DOCUMENTATION_STANDARDS.md](DOCUMENTATION_STANDARDS.md)
3. 在 PR 中更新相关文档
4. 参考 [CODE_REVIEW.md](CODE_REVIEW.md) 的审查标准

## 📞 支持

- **文档问题**：提交 Issue 标签 `docs`
- **架构问题**：在 Slack #nova-architecture 讨论
- **开发帮助**：在 Slack #nova-backend 寻求帮助
```

**所有者**：@documentation-lead
**估计工作量**：2小时
**Deadline**：2025年12月1日

---

### Phase 1 汇总

| Task | 所有者 | 工作量 | Deadline | 状态 |
|------|--------|--------|----------|------|
| 1.1 SERVICES_OVERVIEW.md | @lead | 2h | 11/24 | 📝 |
| 1.2 核心服务README (4个) | @team | 20h | 12/01 | 📝 |
| 1.3 PORTS.md | @devops | 2h | 11/25 | 📝 |
| 1.4 Proto文档 | @api | 4h | 11/27 | 📝 |
| 1.5 .env.example | @infra | 4h | 11/29 | 📝 |
| 1.6 README更新 | @doc | 2h | 12/01 | 📝 |
| **总计** | - | **34h** | **12/01** | **👉 现在** |

---

## Phase 2: 完善API文档（第3-4周）

**目标**：API 文档覆盖率达到 95%+

### Task 2.1：为剩余10个服务创建 README

**服务**：
- analytics-service
- graph-service
- graphql-gateway
- media-service
- realtime-chat-service
- ranking-service（更新，非新建）
- search-service（更新，非新建）
- streaming-service
- trust-safety-service
- user-service（标记已退役）

**所有者**：各服务所有者
**估计工作量**：5h × 10 = 50小时
**Deadline**：2025年12月8日

---

### Task 2.2：创建 REST API 参考

**文件**：`backend/API_REFERENCE.md`

**内容**：
- 所有 REST 端点的一页纸速查
- 所有 gRPC 服务的列表
- 认证机制说明
- 通用错误代码
- 速率限制

**所有者**：@api-lead
**估计工作量**：8小时
**Deadline**：2025年12月6日

---

### Task 2.3：为 4 个有 REST API 的服务创建详细 API 文档

**服务**：
- content-service
- media-service
- notification-service（已有，需要审查）
- graphql-gateway

**文件**：`{service}/API_DOCUMENTATION.md`

**内容**（每个最少100行）：
- 所有端点的详细文档
- 请求/响应示例
- 错误代码和原因
- 速率限制和分页
- 认证示例

**所有者**：各服务所有者
**估计工作量**：6h × 4 = 24小时
**Deadline**：2025年12月8日

---

### Phase 2 汇总

| Task | 工作量 | Deadline | 状态 |
|------|--------|----------|------|
| 2.1 剩余服务README | 50h | 12/08 | 📋 |
| 2.2 API参考 | 8h | 12/06 | 📋 |
| 2.3 详细API文档 | 24h | 12/08 | 📋 |
| **总计** | **82h** | **12/08** | - |

---

## Phase 3: 部署和故障排查（第5-6周）

**目标**：让运维和新开发者能独立解决问题

### Task 3.1：创建部署指南

**文件**：`backend/DEPLOYMENT_GUIDE.md`

**内容**：
- 本地开发环境设置（30分钟 checklist）
- Docker Compose 启动步骤
- Kubernetes 部署步骤
- 环境变量配置
- 数据库迁移
- 验证清单（所有服务都启动了吗？）
- 常见部署问题和解决方案

**所有者**：@devops-lead
**估计工作量**：6小时
**Deadline**：2025年12月13日

---

### Task 3.2：创建故障排查指南

**文件**：`backend/TROUBLESHOOTING.md`

**内容**：
- 按症状分类的故障排查树
- 常见错误及原因
- 日志分析技巧
- 性能分析工具
- 网络调试（curl, grpcurl 示例）
- 数据库调试（SQL 查询）

**所有者**：@senior-dev
**估计工作量**：6小时
**Deadline**：2025年12月15日

---

### Task 3.3：添加性能调优指南

**文件**：`backend/PERFORMANCE_TUNING.md`

**内容**：
- 关键调优参数说明
- 推荐值（小/中/大规模部署）
- 性能测试方法
- 常见瓶颈及优化方法

**所有者**：@performance-lead
**估计工作量**：4小时
**Deadline**：2025年12月15日

---

### Phase 3 汇总

| Task | 工作量 | Deadline | 状态 |
|------|--------|----------|------|
| 3.1 部署指南 | 6h | 12/13 | 📋 |
| 3.2 故障排查 | 6h | 12/15 | 📋 |
| 3.3 性能调优 | 4h | 12/15 | 📋 |
| **总计** | **16h** | **12/15** | - |

---

## Phase 4: 维护和持续改进（持续）

### 月度文档审查

**频率**：每月第一个工作日
**所有者**：@documentation-lead
**检查项**：
- [ ] README 信息仍然准确？
- [ ] API 文档与代码一致？
- [ ] 端口和配置值准确？
- [ ] 链接有效？

### 代码审查清单

**在所有 PR 中检查**：
- [ ] 新公开函数有 /// 文档吗？
- [ ] 修改了 API？更新文档了吗？
- [ ] 改变了配置？更新 .env.example 了吗？

### 文档标签

**在 GitHub Issues 中使用**：
- `docs`: 文档相关
- `docs-update`: 文档需要更新
- `docs-outdated`: 文档过时
- `docs-priority`: 优先级高的文档任务

---

## 交付物汇总

### 新建文件（10个）

```
backend/
├── README.md (更新)                          # Phase 1.6
├── SERVICES_OVERVIEW.md                     # Phase 1.1
├── PORTS.md                                 # Phase 1.3
├── API_REFERENCE.md                         # Phase 2.2
├── DEPLOYMENT_GUIDE.md                      # Phase 3.1
├── TROUBLESHOOTING.md                       # Phase 3.2
├── PERFORMANCE_TUNING.md                    # Phase 3.3
├── DOCUMENTATION_STANDARDS.md               # 已完成
├── DOCUMENTATION_ASSESSMENT.md              # 已完成
├── DOCUMENTATION_ROADMAP.md                 # 本文件

# 服务级文档（14个）
├── analytics-service/README.md              # Phase 2.1
├── content-service/README.md                # Phase 1.2
├── content-service/API_DOCUMENTATION.md    # Phase 2.3
├── feed-service/README.md                   # Phase 1.2
├── graph-service/README.md                  # Phase 2.1
├── graphql-gateway/README.md                # Phase 2.1
├── graphql-gateway/API_DOCUMENTATION.md    # Phase 2.3
├── identity-service/README.md               # Phase 1.2
├── media-service/README.md                  # Phase 2.1
├── media-service/API_DOCUMENTATION.md      # Phase 2.3
├── notification-service/README.md           # Phase 2.1 (更新)
├── ranking-service/README.md                # Phase 1.2 (更新)
├── realtime-chat-service/README.md         # Phase 2.1
├── search-service/README.md                 # Phase 2.1 (更新)
├── social-service/README.md                 # Phase 1.2
├── social-service/API_DOCUMENTATION.md     # Phase 2.3
├── streaming-service/README.md              # Phase 2.1
├── trust-safety-service/README.md           # Phase 2.1
├── user-service/README.md                   # Phase 2.1 (标记已退役)

# Proto文档更新（20个文件，在现有文件中添加注释）
```

### 修改现有文件

- `.env.example` - 添加详细注释（Task 1.5）
- `ranking-service/README.md` - 添加快速开始（Task 1.2）
- `search-service/README.md` - 添加快速开始（Task 1.2）
- `notification-service/API_DOCUMENTATION.md` - 审查和更新（Task 2.3）
- 所有 `proto/services_v2/*.proto` - 添加注释（Task 1.4）
- 核心模块 `main.rs` 和业务逻辑文件 - 添加文档注释（持续）

---

## 预期结果

### Before（当前）
```
📊 文档覆盖率
├── Service README: 20% (3/15)
├── API Documentation: 13% (2/15)
├── Code Comments: 30% (不一致)
├── Deployment Guide: 20% (部分)
└── Troubleshooting: 0%

新开发者 Onboarding 时间：8-12 小时 ⏰
```

### After（3个月后）
```
📊 文档覆盖率
├── Service README: 100% (15/15)
├── API Documentation: 95% (14/15)
├── Code Comments: 80% (一致)
├── Deployment Guide: 100%
└── Troubleshooting: 100%

新开发者 Onboarding 时间：1-2 小时 ⏰

新开发者可以：
✅ 在30分钟内理解系统架构
✅ 在1小时内启动本地开发环境
✅ 独立查找和修复常见问题
✅ 理解API如何调用
✅ 知道如何部署变更
```

---

## 成功指标

### 定量指标

| 指标 | 当前 | 目标 | Timeline |
|------|------|------|----------|
| Service README 覆盖率 | 20% | 100% | 2周 |
| API 文档覆盖率 | 13% | 95% | 4周 |
| 代码注释覆盖率 | 30% | 80% | 6周 |
| 部署文档完整性 | 20% | 100% | 6周 |

### 定性指标

- **新开发者反馈**：能否在1小时内完成首个本地启动
- **代码审查效率**：文档检查是否显著加快（减少澄清问题）
- **故障排查时间**：常见问题解决时间从30分钟降至5分钟
- **系统可维护性**：新功能开发时是否更容易理解现有架构

---

## 风险和缓解

### 风险1：文档与代码不同步

**影响**：文档过时，浪费时间
**缓解**：
- 在 PR 中同时更新代码和文档
- 代码审查时检查文档
- 建立月度文档审查流程

### 风险2：工作量超预期

**影响**：无法按时交付
**缓解**：
- 优先完成 Phase 1（34小时）
- Phase 2-3 可延后，但 Phase 1 必须完成
- 可分批分配给多个人

### 风险3：难以维护新文档

**影响**：文档再次过时
**缓解**：
- 建立清晰的所有权（每个服务 1个owner）
- 自动检查（CI lint 检查）
- 定期审查

---

## 资源分配

### 所有者和责任

| 角色 | 职责 | 工作量 |
|------|------|--------|
| Documentation Lead | 协调整体，审查质量 | 20h |
| Backend Lead | 服务README和API | 40h |
| DevOps Lead | 部署和基础设施 | 10h |
| Senior Dev | 故障排查指南 | 6h |
| API Lead | gRPC 和REST API | 20h |
| Team Members | 各自服务的README | 50h |
| **Total** | - | **146h** |

**分配方式**：
- 146 小时 ÷ 6 周 = ~24小时/周
- 假设 10人 team：每人 ~2.4小时/周
- 可完全吸收于现有开发周期

---

## 关键日期

```
Week 1-2 (11/24 - 12/1):   Phase 1 - 解除阻塞
Week 3-4 (12/2 - 12/8):    Phase 2 - API文档
Week 5-6 (12/9 - 12/15):   Phase 3 - 部署和故障
Week 7+:                    Phase 4 - 持续维护

milestone: Phase 1 Complete ✅
milestone: Phase 2 Complete 🚀 (预计 12/8)
milestone: Phase 3 Complete 🎉 (预计 12/15)
```

---

## 沟通计划

### 周报

**每周五发送**（从2025年11月24日开始）

```
📄 文档改进周报

完成的任务：
- Task 1.1: SERVICES_OVERVIEW.md ✅
- Task 1.3: PORTS.md ✅

本周进度：4/34 小时 (12%)

下周计划：
- 完成4个核心服务的README
- 完成Proto文档注释

阻塞项：
- 无

反馈：
- 新开发者是否在使用新文档？
```

### Slack 频道

**#nova-documentation** - 每日进展同步

### GitHub Project

**Documentation Improvement** - 跟踪所有任务

---

## 审批和签字

| 角色 | 签字 | 日期 |
|------|------|------|
| Documentation Lead | __________ | ______ |
| Backend Lead | __________ | ______ |
| Engineering Manager | __________ | ______ |

---

## 附录

### A. 模板文件

所有文档模板已在 `DOCUMENTATION_STANDARDS.md` 中定义。
复制和填充即可。

### B. 工具建议

```bash
# Markdown 校验
npm install -g markdownlint-cli

# 链接检查
npm install -g markdown-link-check

# 目录生成
npm install -g doctoc

# 拼写检查
brew install aspell-en  # macOS
```

### C. CI/CD 集成

**计划**：在 GitHub Actions 中添加文档检查

```yaml
# .github/workflows/docs-check.yml
- name: Check markdown
  run: markdownlint backend/**/*.md

- name: Check links
  run: markdown-link-check backend/**/*.md

- name: Check no TODO files
  run: ! find backend -name "TODO*.md" -o -name "TEMP*.md"
```

---

**状态**：⏳ 待批准
**创建日期**：2025年11月22日
**下次审查**：2025年12月1日（Phase 1 完成后）
