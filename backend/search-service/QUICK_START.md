# Search Service - Quick Start

## 🚀 快速开始

### 1. 设置环境变量

```bash
cp .env.example .env
# 编辑 .env 文件，设置正确的 DATABASE_URL
```

### 2. 编译和运行

```bash
# 开发模式
cargo run

# 生产模式
cargo build --release
./target/release/search-service
```

### 3. 验证服务

```bash
# 检查健康状态
curl http://localhost:8081/health

# 搜索用户
curl "http://localhost:8081/api/v1/search/users?q=test"

# 搜索帖子
curl "http://localhost:8081/api/v1/search/posts?q=hello"

# 搜索话题标签
curl "http://localhost:8081/api/v1/search/hashtags?q=tech"
```

或使用提供的测试脚本：

```bash
./test-endpoints.sh
```

## 📋 API 概览

| 端点 | 方法 | 描述 |
|------|------|------|
| `/health` | GET | 健康检查 |
| `/api/v1/search/users` | GET | 搜索用户 |
| `/api/v1/search/posts` | GET | 搜索帖子 |
| `/api/v1/search/hashtags` | GET | 搜索话题标签 |

所有搜索端点支持以下参数：
- `q` (string): 搜索查询
- `limit` (int): 结果数量限制（默认 20）

## 📚 更多文档

- [README.md](./README.md) - 完整的 API 文档
- [IMPLEMENTATION_STATUS.md](./IMPLEMENTATION_STATUS.md) - 实现状态和改进建议

## 🛠️ 开发

```bash
# 检查代码
cargo check

# 运行测试（待添加）
cargo test

# 格式化代码
cargo fmt

# Lint
cargo clippy
```
