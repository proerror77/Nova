# Nova Social Platform

> Instagram-like social media platform built with Rust backend and SwiftUI iOS frontend

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Rust](https://img.shields.io/badge/rust-1.75+-orange.svg)](https://www.rust-lang.org)
[![iOS](https://img.shields.io/badge/iOS-15.0+-black.svg)](https://developer.apple.com/ios/)

## 📋 项目概述

Nova Social Platform 是一个全功能的社交媒体应用，包含：

- 📸 **图片/视频发布** - 编辑工具、滤镜、标签
- 📖 **限时动态 (Stories)** - 24小时自动消失的短暂内容
- 🎬 **短视频 (Reels)** - 垂直滚动的短视频流
- 💬 **实时私信** - WebSocket 即时通讯
- 📡 **直播串流** - 低延迟实时视频
- 🔍 **智能推荐** - 基于 Rust 的推荐算法
- 👥 **社交网络** - 关注、互动、通知

## 🏗️ 架构设计

### 技术栈

**Backend (Rust 微服务)**
- Web框架：Actix-web / Axum
- 数据库：PostgreSQL + Redis + MongoDB/Cassandra
- 消息队列：Kafka / RabbitMQ
- 容器编排：Kubernetes
- API网关：自定义 Rust gateway

**Frontend (iOS)**
- UI框架：SwiftUI + UIKit
- 状态管理：Clean Architecture + Repository
- 网络层：URLSession with retry logic
- Rust集成：FFI bridge for core algorithms

**基础设施**
- 云平台：AWS / GCP
- CDN：CloudFront / Cloudflare
- 监控：Prometheus + Grafana
- CI/CD：GitHub Actions + Docker + K8s

### 核心原则

根据项目宪章 ([.specify/memory/constitution.md](.specify/memory/constitution.md))，我们遵循：

1. **微服务架构 (NON-NEGOTIABLE)** - Rust-first 独立服务
2. **跨平台核心共享** - Rust核心库编译为iOS/Android原生库
3. **TDD严格执行** - 红-绿-重构，80%测试覆盖率
4. **安全与隐私第一** - GDPR/App Store 合规，零信任模型
5. **用户体验至上** - 60fps，<200ms API响应
6. **可观测性** - 全链路监控与追踪
7. **持续集成/部署** - 自动化管线，多环境策略

## 📚 文档结构

```
docs/
├── PRD.md                    # 产品需求文档 ✅
├── NEXT_STEPS.md            # 后续步骤指南 ✅
├── architecture/            # 系统架构
│   ├── microservices.md    # 微服务设计
│   ├── data-model.md       # 数据模型
│   └── deployment.md       # 部署架构
├── api/                     # API 规范
│   ├── openapi.yaml        # OpenAPI 3.0
│   ├── auth.md             # 认证 API
│   ├── content.md          # 内容 API
│   └── websocket.md        # 实时通讯协议
└── design/                  # UI/UX 设计
    ├── figma-prototype.md  # Figma 链接
    └── swiftui-components.md
```

## 🚀 快速开始

### 前置要求

- **Rust**: 1.75+ (`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`)
- **Xcode**: 15.0+ (for iOS development)
- **Docker**: 20.10+ (for containerization)
- **Kubernetes**: kubectl + minikube/kind (for local K8s)
- **PostgreSQL**: 14+ (local or Docker)
- **Redis**: 7.0+ (local or Docker)

### 本地开发设置

#### 1. Clone 仓库

```bash
git clone <repository-url>
cd nova
```

#### 2. Backend 设置

```bash
# 创建后端服务结构
mkdir -p backend/{services,shared,infrastructure}

# 初始化用户服务
cd backend/services
cargo new user-service --bin
cd user-service

# 添加依赖 (Cargo.toml)
cargo add actix-web tokio sqlx redis

# 运行服务
cargo run
```

#### 3. 数据库设置

```bash
# PostgreSQL (Docker)
docker run --name nova-postgres \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=nova \
  -p 5432:5432 -d postgres:14

# Redis (Docker)
docker run --name nova-redis \
  -p 6379:6379 -d redis:7-alpine

# 运行迁移
sqlx migrate run
```

#### 4. iOS 设置

```bash
# iOS 项目位置
cd ios/NovaSocial

# 使用 Xcode 打开
open ICERED.xcodeproj
```

### 运行 iOS 应用

提供多种方式运行 iOS 应用：

```bash
# 方式 1: 快捷命令 (推荐)
./run                      # 默认 iPhone 17 Pro
./run "iPhone 15 Pro"      # 指定模拟器

# 方式 2: Make 命令
make ios                   # iPhone 17 Pro (默认)
make ios-iphone15          # iPhone 15 Pro
make ios-ipad              # iPad Pro 13-inch (M5)

# 方式 3: 完整脚本
./run-ios.sh "iPhone 17 Pro"
```

脚本会自动执行：
1. 启动指定的 iOS 模拟器
2. 构建 Xcode 项目 (Debug 配置)
3. 安装应用到模拟器
4. 启动应用

### 运行完整系统

```bash
# 1. 启动所有后端服务（Docker Compose）
docker-compose up -d

# 2. 运行 iOS 应用 (自动启动模拟器)
./run
```

## 🔄 开发工作流

### 上传代码到 GitHub

使用 `upload` 脚本自动完成: commit → update → push → 创建 PR

```bash
# 方式 1: 交互式 (会提示输入 commit message)
./upload

# 方式 2: 直接指定 commit message
./upload "feat: add new feature"

# 查看当前状态
./upload --status

# 查看帮助
./upload --help
```

**脚本执行流程:**

```
[1/5] 检查更改    → 显示待提交的文件
[2/5] 提交更改    → git add + git commit
[3/5] 同步远程    → git pull --rebase
[4/5] 推送到远程  → git push
[5/5] 处理 PR     → 创建新 PR 或显示现有 PR
```

### 快捷命令汇总

| 命令 | 说明 |
|------|------|
| `./run` | 构建并运行 iOS 应用 |
| `./upload` | 上传代码并创建 PR |
| `./upload --status` | 查看 git 和 PR 状态 |
| `make ios` | 运行 iOS 应用 |
| `make build` | 构建后端服务 |
| `make test` | 运行后端测试 |

## 📅 开发路线图

### Phase 1: MVP - 认证与核心社交 (8-10周) ⏳
- [x] 项目初始化
- [x] Constitution & PRD
- [ ] 用户认证服务
- [ ] 内容发布服务
- [ ] Feed & 社交关系
- [ ] iOS MVP UI

### Phase 2: Stories & Reels (5周)
- [ ] 限时动态功能
- [ ] 短视频 Reels
- [ ] 媒体处理管道

### Phase 3: 实时功能 (6周)
- [ ] WebSocket 私信
- [ ] 直播串流

### Phase 4: 搜索与发现 (4周)
- [ ] 全局搜索
- [ ] 推荐算法

### Phase 5: 测试与优化 (4周)
- [ ] 性能测试
- [ ] 安全审计
- [ ] App Store 准备

### Phase 6: 上架部署 (1周)
- [ ] 生产部署
- [ ] App Store 提交
- [ ] 监控与告警

## 🧪 测试

### 运行测试

```bash
# Backend 单元测试
cd backend/services/user-service
cargo test

# Backend 集成测试
cargo test --test integration

# iOS 单元测试
xcodebuild test -scheme NovaSocial -destination 'platform=iOS Simulator,name=iPhone 15'

# iOS UI 测试
xcodebuild test -scheme NovaSocialUITests -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 代码覆盖率

```bash
# Rust coverage (tarpaulin)
cargo tarpaulin --out Html

# iOS coverage (xcodebuild)
xcodebuild test -scheme NovaSocial -enableCodeCoverage YES
xcrun xccov view --report DerivedData/.../Coverage.xcresult
```

## 📦 部署

### Docker Build

```bash
# Build backend service
cd backend/services/user-service
docker build -t nova-user-service:latest .

# Push to registry
docker tag nova-user-service:latest registry.io/nova/user-service:v1.0.0
docker push registry.io/nova/user-service:v1.0.0
```

### Kubernetes Deploy

```bash
# Apply configurations
kubectl apply -f backend/infrastructure/kubernetes/

# Check deployment
kubectl get pods -n nova-platform
kubectl logs -f deployment/user-service -n nova-platform
```

## 🔧 开发工具

### 推荐 VSCode 插件

- **rust-analyzer** - Rust 语言服务
- **CodeLLDB** - Rust 调试器
- **Swagger Viewer** - API 文档预览
- **GitLens** - Git 增强

### 推荐 Xcode 工具

- **SwiftLint** - Swift 代码风格检查
- **Fastlane** - 自动化构建与部署
- **Reveal** - UI 调试工具

## 🤝 贡献指南

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 遵循 [Constitution](.specify/memory/constitution.md) 原则
4. 编写测试 (TDD)
5. 提交代码 (`git commit -m 'feat: add amazing feature'`)
6. 推送分支 (`git push origin feature/amazing-feature`)
7. 创建 Pull Request

### Commit 规范

遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```
feat: 新功能
fix: Bug 修复
docs: 文档更新
style: 代码格式（不影响功能）
refactor: 重构
test: 测试相关
chore: 构建/工具链
```

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 📞 联系方式

- **项目维护**: Nova Team
- **问题反馈**: [GitHub Issues](https://github.com/yourorg/nova/issues)
- **文档**: [docs/](./docs/)

---

**Built with ❤️ using Rust & SwiftUI**

**当前版本**: 0.1.0-alpha
**上次更新**: 2025-10-17
