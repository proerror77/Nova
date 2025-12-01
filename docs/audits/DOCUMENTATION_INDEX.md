# Nova 后端文档索引

**最后更新**：2025年11月22日 | **维护者**：Backend Documentation Team

---

## 🚀 快速导航

### 我是新开发者，想快速上手
👉 阅读顺序：
1. [DOCUMENTATION_SUMMARY.md](DOCUMENTATION_SUMMARY.md) (5 min)
2. [SERVICES_OVERVIEW.md](SERVICES_OVERVIEW.md) (10 min) - *待创建*
3. [GETTING_STARTED.md](GETTING_STARTED.md) (30 min) - *待创建*
4. 对应服务的 README.md (20 min)

**预期**：1小时内启动本地环境

---

### 我想理解系统架构
👉 阅读顺序：
1. [ARCHITECTURE.md](ARCHITECTURE.md) - *待创建* (系统全景)
2. [SERVICES_OVERVIEW.md](SERVICES_OVERVIEW.md) - *待创建* (服务清单)
3. [API_REFERENCE.md](API_REFERENCE.md) - *待创建* (通信方式)
4. 相关 Proto 文件 (proto/services_v2/*.proto)

**预期**：2小时理解所有关键组件

---

### 我要修改某个服务
👉 阅读顺序：
1. 该服务的 `README.md` (架构概览)
2. 该服务的 `API_DOCUMENTATION.md` (如果有)
3. Proto 文件定义 (proto/services_v2/*.proto)
4. 相关代码 (src/*.rs)

**预期**：30分钟理解服务边界和API

---

### 我要部署或运维
👉 阅读顺序：
1. [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - *待创建*
2. [.env.example](.env.example) (配置参考)
3. [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - *待创建*
4. [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) - *待创建*
5. [MONITORING.md](MONITORING.md) - *待创建*

**预期**：能独立部署和排查问题

---

### 我要贡献代码
👉 阅读顺序：
1. [DEVELOPMENT.md](DEVELOPMENT.md) - *待创建*
2. [DOCUMENTATION_STANDARDS.md](DOCUMENTATION_STANDARDS.md) (文档规范)
3. [CLAUDE.md](CLAUDE.md) (代码审查标准)
4. 对应服务的 README.md

**预期**：理解开发流程和标准

---

## 📚 完整文档树

### 🎯 核心导航文档

这些文件帮助你找到其他文档。

| 文件 | 用途 | 状态 | 行数 |
|------|------|------|------|
| **DOCUMENTATION_SUMMARY.md** | 一页纸总结 | ✅ | 100 |
| **DOCUMENTATION_INDEX.md** | 本文件（导航） | ✅ | 300 |
| **DOCUMENTATION_ASSESSMENT.md** | 详细评估报告 | ✅ | 800+ |
| **DOCUMENTATION_STANDARDS.md** | 编写标准和模板 | ✅ | 500+ |
| **DOCUMENTATION_ROADMAP.md** | 3个月改进计划 | ✅ | 600+ |

### 📖 架构和设计

这些文件解释系统是**如何设计的**。

| 文件 | 内容 | 状态 | 优先级 |
|------|------|------|--------|
| **ARCHITECTURE.md** | 系统全景、数据流、组件关系 | ❌ 待建 | P0 |
| **SERVICES_OVERVIEW.md** | 14个服务的清单、职责、依赖 | ❌ 待建 | P0 |
| **API_REFERENCE.md** | REST和gRPC API总览 | ❌ 待建 | P0 |

### 🚀 入门和开发

这些文件告诉你**如何开始使用系统**。

| 文件 | 内容 | 状态 | 优先级 |
|------|------|------|--------|
| **GETTING_STARTED.md** | 新开发者快速入门（30分钟） | ❌ 待建 | P0 |
| **DEVELOPMENT.md** | 本地开发环境设置 | ❌ 待建 | P1 |
| **README.md** | 后端项目总览 | ⚠️ 需更新 | P0 |

### ⚙️ 配置和部署

这些文件说明**如何配置和部署**系统。

| 文件 | 内容 | 状态 | 优先级 |
|------|------|------|--------|
| **.env.example** | 环境变量参考（详细注释） | ⚠️ 需更新 | P0 |
| **PORTS.md** | 所有服务端口映射 | ❌ 待建 | P0 |
| **DEPLOYMENT_GUIDE.md** | 本地/K8s/Cloud部署步骤 | ❌ 待建 | P1 |
| **DOCKER_SETUP.md** | Docker Compose使用指南 | ❌ 待建 | P1 |

### 🐛 故障排查和性能

这些文件帮助你**解决问题和优化**。

| 文件 | 内容 | 状态 | 优先级 |
|------|------|------|--------|
| **TROUBLESHOOTING.md** | 常见问题和解决方案 | ❌ 待建 | P1 |
| **PERFORMANCE_TUNING.md** | 性能参数和优化方法 | ❌ 待建 | P1 |
| **DEBUGGING.md** | 调试技巧和工具 | ❌ 待建 | P2 |
| **MONITORING.md** | 监控和告警设置 | ❌ 待建 | P2 |

### 🛠️ 维护和贡献

这些文件说明**如何维护和贡献**。

| 文件 | 内容 | 状态 | 优先级 |
|------|------|------|--------|
| **DEVELOPMENT_WORKFLOW.md** | 提交、分支、PR流程 | ❌ 待建 | P2 |
| **CODE_REVIEW_GUIDE.md** | 代码审查标准和清单 | ❌ 待建 | P2 |
| **TESTING_GUIDE.md** | 单元和集成测试指南 | ❌ 待建 | P2 |
| **SECURITY_GUIDE.md** | 安全最佳实践 | ❌ 待建 | P2 |

---

## 🏗️ 服务级文档结构

每个服务应该有：

```
backend/{service}/
├── README.md                    # ✅ 必须（架构、API、配置）
├── API_DOCUMENTATION.md         # ⭕ 如果有REST API
├── DEPLOYMENT.md                # ⭕ 如果有特殊需求
├── TROUBLESHOOTING.md          # ⭕ 常见问题
└── src/main.rs                  # ✅ 必须有/// doc注释
```

### 核心服务文档

| 服务 | README | API Doc | Deploy | 状态 |
|------|--------|---------|--------|------|
| **content-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **feed-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **social-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **identity-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **graphql-gateway** | ❌ | ❌ | ❌ | 🔴 缺 |
| **media-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **notification-service** | ❌ | ✅ | ❌ | 🟡 部分 |
| **ranking-service** | ⚠️ | ❌ | ❌ | 🟡 部分 |
| **search-service** | ⚠️ | ❌ | ❌ | 🟡 部分 |
| **analytics-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **graph-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **realtime-chat-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **streaming-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **trust-safety-service** | ❌ | ❌ | ❌ | 🔴 缺 |
| **user-service** | ❌ | ❌ | - | 🟠 已退役 |

---

## 🗺️ 按任务分类文档

### 新开发者任务

**目标**：快速理解系统和启动开发环境

```
1. DOCUMENTATION_SUMMARY.md
2. GETTING_STARTED.md
3. [service]/README.md
4. DEVELOPMENT.md
5. CODE_REVIEW_GUIDE.md
```

### 运维/DevOps任务

**目标**：部署、监控、故障排查

```
1. DEPLOYMENT_GUIDE.md
2. DOCKER_SETUP.md (or KUBERNETES_GUIDE.md)
3. TROUBLESHOOTING.md
4. PERFORMANCE_TUNING.md
5. MONITORING.md
```

### 功能开发任务

**目标**：修改某个服务或API

```
1. SERVICES_OVERVIEW.md
2. ARCHITECTURE.md
3. [service]/README.md
4. [service]/API_DOCUMENTATION.md
5. Proto 文件 (proto/services_v2/*.proto)
6. 源代码
```

### 系统设计任务

**目标**：添加新服务或重构架构

```
1. ARCHITECTURE.md
2. SERVICES_OVERVIEW.md
3. API_REFERENCE.md
4. DOCUMENTATION_STANDARDS.md
5. [proposal discussion]
```

---

## 🔗 跨文档链接

### 文档之间的依赖关系

```
DOCUMENTATION_SUMMARY.md
├── DOCUMENTATION_ROADMAP.md
├── DOCUMENTATION_ASSESSMENT.md
├── DOCUMENTATION_STANDARDS.md
└── DOCUMENTATION_INDEX.md (本文件)

GETTING_STARTED.md
├── SERVICES_OVERVIEW.md
├── [service]/README.md
└── DEVELOPMENT.md

ARCHITECTURE.md
├── SERVICES_OVERVIEW.md
├── API_REFERENCE.md
└── [service]/README.md

DEPLOYMENT_GUIDE.md
├── DOCKER_SETUP.md
├── .env.example
└── TROUBLESHOOTING.md

TROUBLESHOOTING.md
├── DEBUGGING.md
├── PERFORMANCE_TUNING.md
└── MONITORING.md
```

---

## 📊 文档覆盖矩阵

**行**：文档类型 | **列**：服务 | **值**：完成状态

```
                  content feed social identity graphql media ...
README                ❌    ❌    ❌     ❌       ❌     ❌
API_DOCUMENTATION     ❌    ❌    ❌     ❌       ❌     ❌
DEPLOYMENT            ❌    ❌    ❌     ❌       ❌     ❌
TROUBLESHOOTING       ❌    ❌    ❌     ❌       ❌     ❌

Core Architecture:
ARCHITECTURE.md       ❌
API_REFERENCE.md      ❌
SERVICES_OVERVIEW.md  ❌
```

---

## 🎯 按优先级分类

### P0 - 必须有（本月）

所有新开发者和运维必需的文档：

- [ ] SERVICES_OVERVIEW.md（服务清单）
- [ ] 4个核心服务的README
- [ ] PORTS.md（端口定义）
- [ ] Proto文档（RPC方法说明）
- [ ] GETTING_STARTED.md（30分钟入门）

**预期效果**：新开发者能独立启动系统

### P1 - 应该有（1-2个月）

开发和运维需要的完善文档：

- [ ] 全部14个服务的README
- [ ] DEPLOYMENT_GUIDE.md（部署步骤）
- [ ] TROUBLESHOOTING.md（故障排查）
- [ ] ARCHITECTURE.md（系统设计）
- [ ] API_REFERENCE.md（API总览）

**预期效果**：90%的问题可自助解决

### P2 - 可以有（2-3个月）

优化和参考文档：

- [ ] PERFORMANCE_TUNING.md
- [ ] SECURITY_GUIDE.md
- [ ] MONITORING.md
- [ ] DEBUGGING.md
- [ ] DEVELOPMENT_WORKFLOW.md

**预期效果**：团队能高效地维护和扩展系统

---

## 🔄 维护流程

### 新文档发布前

**检查清单**：
- [ ] 文档完整（无[TODO]占位符）
- [ ] 格式一致（遵循DOCUMENTATION_STANDARDS.md）
- [ ] 链接有效（无404）
- [ ] 信息准确（与代码同步）
- [ ] 拼写和语法（无明显错误）

### 月度审查

**每月第一个工作日**：
1. 检查README信息的准确性
2. 验证API文档与实现一致
3. 更新版本号和日期
4. 检查链接有效性

### 标记过时文档

如果发现过时文档：
```markdown
⚠️ [OUTDATED - 2025-11-22]
This document is no longer accurate. See [new location] instead.
```

---

## 🛠️ 文档工具

### 编辑

- **VS Code** (推荐) - 安装 "Markdown All in One" 扩展
- **GitHub Web** - 直接编辑和预览
- **任何文本编辑器** - 都可以编写Markdown

### 验证

```bash
# 检查Markdown语法
npm install -g markdownlint-cli
markdownlint backend/**/*.md

# 检查链接
npm install -g markdown-link-check
markdown-link-check backend/**/*.md

# 生成目录
npm install -g doctoc
doctoc backend/DOCUMENTATION_INDEX.md
```

### CI/CD集成

计划中：自动检查Markdown格式和链接有效性

---

## 📞 联系和支持

### 文档相关问题

| 问题类型 | 联系方式 |
|---------|---------|
| 文档不准确 | 提交 Issue 标签 `docs` |
| 缺少文档 | 提交 Issue 标签 `docs-request` |
| 建议改进 | 讨论 or Pull Request |
| 文档维护 | 联系文档主导 |

### 反馈

- 提交 GitHub Issue
- Slack #nova-documentation
- 邮件给 documentation-lead@

---

## 📝 版本历史

| 版本 | 日期 | 内容 |
|------|------|------|
| 1.0 | 2025-11-22 | 初始版本，索引已有和待建文档 |

---

## ✅ 快速检查清单

### 我找不到答案怎么办？

1. [ ] 检查本索引中的"快速导航"部分
2. [ ] 搜索相关关键词的文件
3. [ ] 查看 DOCUMENTATION_ASSESSMENT.md 了解缺少什么
4. [ ] 提交 Issue 或在 Slack 提问

### 我想贡献新文档怎么办？

1. [ ] 阅读 DOCUMENTATION_STANDARDS.md
2. [ ] 使用提供的模板
3. [ ] 按照检查清单审查
4. [ ] 提交 Pull Request
5. [ ] 获得维护者批准

---

## 🚀 下一步

**如果你是新开发者**：
→ 阅读 [DOCUMENTATION_SUMMARY.md](DOCUMENTATION_SUMMARY.md) (5 min)
→ 按照"我是新开发者"的快速导航

**如果你是维护者**：
→ 阅读 [DOCUMENTATION_ROADMAP.md](DOCUMENTATION_ROADMAP.md)
→ 开始 Phase 1 任务

**如果你发现文档缺失或过时**：
→ 提交 Issue or PR
→ 参考 DOCUMENTATION_STANDARDS.md 的模板

---

**维护者**：Backend Documentation Team
**最后更新**：2025年11月22日
**下次审查**：2025年12月1日
