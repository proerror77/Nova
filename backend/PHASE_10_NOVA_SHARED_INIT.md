# Phase 10.1: nova-shared 库提取初始化

## 概述

nova-shared 是一个独立的 Rust workspace，包含 Nova 所有微服务都依赖的共享库。这是 polyrepo 转换的第一步。

## 库清单

### 核心库
1. **error-types** (508 行)
   - 统一错误类型定义
   - gRPC 错误处理
   - 所有服务依赖

2. **crypto-core** (324 行)
   - JWT 签名/验证
   - 加密原语
   - 密钥管理
   - auth-service 依赖

3. **db-pool** (256 行)
   - PostgreSQL 连接池
   - 健康检查
   - 迁移管理

### 消息队列 & 缓存
4. **redis-utils** (412 行)
   - Redis 连接管理
   - 缓存 helpers
   - Pub/Sub 包装

5. **event-schema** (198 行)
   - Kafka 事件定义
   - Event serialization
   - CDC 消息格式

### 推送通知
6. **nova-fcm-shared** (267 行)
   - Firebase Cloud Messaging
   - FCM 证书管理
   - 推送负载构建

7. **nova-apns-shared** (243 行)
   - Apple Push Notification
   - APNS 证书管理
   - 推送负载构建

### 视频处理
8. **video-core** (512 行)
   - 视频元数据类型
   - 转码状态机
   - 编码参数

### 通用工具
9. **error-handling** (189 行)
   - 自定义错误处理
   - 中间件错误处理
   - 错误日志记录

10. **s3-utils** (301 行)
    - S3 客户端封装
    - 上传助手
    - 预签名 URL 生成

**总计**: 10 个库，约 3,210 行代码

## 依赖图

```
error-types (根 - 无依赖)
├─ 所有库都导入 error-types
├─ crypto-core → 依赖 error-types
├─ db-pool → 依赖 error-types, sqlx
├─ redis-utils → 依赖 error-types, redis
├─ event-schema → 依赖 serde
├─ nova-fcm-shared → 依赖 error-types
├─ nova-apns-shared → 依赖 error-types
├─ video-core → 依赖 error-types, serde
├─ error-handling → 依赖 error-types
└─ s3-utils → 依赖 error-types, aws-sdk-s3
```

## 新的 nova-shared Cargo.toml (workspace 根)

```toml
[workspace]
members = [
    "error-types",
    "crypto-core",
    "db-pool",
    "redis-utils",
    "event-schema",
    "nova-fcm-shared",
    "nova-apns-shared",
    "video-core",
    "error-handling",
    "s3-utils",
]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2021"
authors = ["Nova Team <team@nova.dev>"]
license = "MIT"
rust-version = "1.75"

# 所有共享依赖定义
[workspace.dependencies]
# 与 monorepo 相同的版本...
```

## 迁移步骤

### Step 1: 文件系统准备
```bash
# 在 nova-shared 目录结构中:
nova-shared/
├── Cargo.toml              # workspace 根
├── error-types/
│   ├── Cargo.toml
│   └── src/
├── crypto-core/
│   ├── Cargo.toml
│   └── src/
├── db-pool/
│   ├── Cargo.toml
│   └── src/
├── ...其他库...
├── README.md
├── .gitignore
├── .github/
│   └── workflows/
│       └── ci.yml          # 库的 CI 流水线
└── Makefile                # 开发工具
```

### Step 2: Cargo.toml 修改
- 所有库改为相对路径依赖: `{ path = "../error-types" }`
- 创建统一的 workspace.dependencies
- 删除重复的 package 信息

### Step 3: CI/CD 配置
```yaml
# .github/workflows/ci.yml
name: Library CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --workspace
```

### Step 4: 发布到 Crates Registry

#### 选项 A: GitHub Packages (推荐用于私有)
```toml
# Cargo.toml 配置
[package]
name = "nova-error-types"
publish = ["github"]
registry = "github"
```

#### 选项 B: 自托管 Artifactory
```bash
# 在 ~/.cargo/config.toml
[registries.nova-internal]
index = "sparse+https://artifactory.nova.app/artifactory/api/cargo/"
```

#### 选项 C: Crates.io (公开)
```bash
cargo publish -p error-types
cargo publish -p crypto-core
# ... 发布所有库
```

**推荐**: 使用 GitHub Packages (内部私有)

## 版本管理

### 当前版本
- 所有库: `0.1.0`
- 与 monorepo 同步发布

### 发布流程
```bash
# 1. 更新所有 Cargo.toml 版本
# 2. 修改 CHANGELOG.md
# 3. 创建 git tag
git tag -a v0.1.0 -m "Release version 0.1.0"

# 4. 发布到 registry
cargo publish -p nova-error-types --registry github
cargo publish -p nova-crypto-core --registry github
# ... 所有库
```

## 独立编译验证

```bash
# 1. 确保没有外部依赖
cd nova-shared
cargo check --workspace

# 2. 运行所有测试
cargo test --workspace

# 3. 检查文档
cargo doc --no-deps --open

# 4. 检查代码质量
cargo clippy --workspace -- -D warnings
cargo fmt --all -- --check
```

## Monorepo 中的更新

在 nova-shared 发布后，所有服务需要：

```toml
# 在服务的 Cargo.toml 中
[dependencies]
nova-error-types = { version = "0.1", registry = "github" }
nova-crypto-core = { version = "0.1", registry = "github" }
# ... 其他共享库
```

## 替换现有导入

### 之前 (monorepo)
```rust
use error_types::*;
use crypto_core::jwt;
```

### 之后 (polyrepo)
```rust
use nova_error_types::*;
use nova_crypto_core::jwt;
```

## 时间表

| 任务 | 预期时间 |
|------|--------|
| 创建仓库结构 | 30 分钟 |
| 更新 Cargo.toml | 30 分钟 |
| 验证编译 | 15 分钟 |
| 配置 CI/CD | 30 分钟 |
| 发布到 registry | 15 分钟 |
| **总计** | **2-3 小时** |

## 检查清单

- [ ] nova-shared GitHub 仓库创建
- [ ] 10 个库完整复制
- [ ] workspace Cargo.toml 创建
- [ ] 所有相对路径依赖更新
- [ ] cargo check 成功
- [ ] cargo test --workspace 全部通过
- [ ] cargo clippy 无警告
- [ ] CI/CD 配置完成
- [ ] 发布到 registry 成功
- [ ] 文档更新 (README, CHANGELOG)
- [ ] 团队文档通知
- [ ] Monorepo 中的导入语句验证

## 成功标准

✅ **成功定义**:
1. nova-shared 可以独立编译
2. 所有 10 个库都发布到 registry
3. CI/CD 流水线自动化
4. 所有测试通过
5. Monorepo 中的服务可以导入新库版本

❌ **失败标准**:
1. 编译错误
2. 测试失败
3. 发布失败
4. Monorepo 服务无法更新导入

## 下一步 (Phase 10.2)

一旦 nova-shared 发布完成，开始 Phase 10.2:
- 提取 nova-auth-service
- 删除 monorepo 中的认证代码
- 更新 auth-service 依赖到 nova-shared registry

---

**创建日期**: 2024-10-30
**阶段**: 10.1 - nova-shared 库提取
**状态**: 初始化计划完成，准备执行
