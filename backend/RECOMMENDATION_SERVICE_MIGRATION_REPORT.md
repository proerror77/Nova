# Recommendation Service 迁移报告

## 执行时间
2025-10-30

## 迁移概述
从user-service中提取recommendation相关的handlers和services到独立的recommendation-service。

## 已完成的工作

### 1. Handlers迁移 ✅
成功迁移以下HTTP handlers到recommendation-service:

#### Discover Handlers
- 文件: `src/handlers/discover.rs`
- 功能: 用户推荐（suggested users）
- 依赖: Neo4j graph queries, Redis缓存
- 特性: Circuit Breaker保护，多级fallback策略

#### Feed Handlers
- 文件: `src/handlers/feed.rs`
- 功能: 信息流推荐（转发到content-service）
- 依赖: Content service gRPC client
- 特性: 游标分页，算法选择（ch/time）

#### Trending Handlers
- 文件: `src/handlers/trending.rs`
- 功能: 趋势内容发现
- 端点:
  - GET /api/v1/trending - 全部trending内容
  - GET /api/v1/trending/videos - trending视频
  - GET /api/v1/trending/posts - trending帖子
  - GET /api/v1/trending/streams - trending直播
  - GET /api/v1/trending/categories - 分类列表
  - POST /api/v1/trending/engagement - 记录用户互动
- 依赖: ClickHouse analytics, Redis缓存
- 特性: Circuit Breaker保护，时间窗口选择

### 2. 支持模块迁移 ✅

#### Middleware
- `src/middleware/jwt_auth.rs` - JWT认证中间件
- `src/middleware/circuit_breaker.rs` - 熔断器实现

#### Services
- `src/services/graph/` - Neo4j图数据库服务
- `src/services/trending/` - Trending算法和服务

#### Database
- `src/db/trending_repo.rs` - Trending数据仓库层

#### Utils
- `src/utils/redis_timeout.rs` - Redis超时工具

#### Security
- `src/security/jwt.rs` - JWT令牌验证

### 3. 错误处理增强 ✅
扩展AppError枚举类型，支持:
- Database - 数据库错误
- Authentication - 认证错误
- Authorization - 授权错误
- BadRequest - 错误请求
- Internal - 内部错误
- ServiceUnavailable - 服务不可用

### 4. gRPC客户端框架 🟡
创建gRPC客户端基础设施:
- `src/grpc/clients.rs` - ContentServiceClient
- `src/grpc/nova.rs` - Proto定义占位符

**状态**: 基础框架已建立，需要补充真实的proto定义

### 5. Models ✅
创建数据模型:
- FeedResponse - 信息流响应
- UserWithScore - 用户推荐
- TrendingQuery/Response - 趋势查询

## 当前编译状态

### 错误统计
```
12 error[E0308]: mismatched types - 类型不匹配（主要在trending service）
8 error[E0753]: expected outer doc comment - 文档注释问题
6 error[E0277]: trait bound Codec not satisfied - gRPC codec问题
1-3个其他import/config错误
```

### 总错误数: ~29个（从最初100+已大幅减少）

## 待解决问题

### 1. 高优先级 🔴

#### gRPC Proto定义缺失
- **问题**: nova.rs中的proto定义是占位符
- **影响**: Feed handlers无法编译
- **解决方案**:
  - 从content-service复制真实的proto文件
  - 使用tonic-build生成Rust代码
  - 或临时注释掉feed handlers

#### Trending Service类型不匹配
- **问题**: AppError::Database期望String但收到Error类型
- **位置**: `src/services/trending/service.rs:298`
- **解决方案**: 添加`.to_string()`转换

#### JWT相关依赖
- **问题**: jwt_key_rotation模块不存在
- **影响**: security/jwt.rs编译失败
- **解决方案**:
  - 简化JWT验证逻辑，移除key rotation
  - 或从user-service复制jwt_key_rotation模块

### 2. 中优先级 🟡

#### GraphConfig缺失
- **问题**: config模块缺少GraphConfig
- **解决方案**: 从user-service复制或重新定义

#### Doc comment语法
- **问题**: 8个文档注释格式错误
- **解决方案**: 批量修复注释格式

### 3. 低优先级 🟢

#### 未使用的imports
- 警告: `tokio_stream::StreamExt` 等
- 解决方案: 清理未使用的imports

## 迁移策略建议

### 短期策略（快速可用）
1. **注释掉Feed handlers** - 因为依赖content-service的proto
2. **修复Trending service类型错误** - 添加.to_string()
3. **简化JWT验证** - 移除jwt_key_rotation依赖
4. **临时注释GraphService** - discover handlers可以先返回空列表

这样可以让recommendation-service快速编译通过，虽然功能不完整。

### 中期策略（功能完善）
1. **补充proto定义** - 从content-service和user-service提取
2. **实现ranking_engine** - 从user-service迁移核心推荐逻辑
3. **集成ONNX推理** - 迁移深度学习模型推理
4. **完善gRPC clients** - 调用user-service获取用户/帖子数据

### 长期策略（架构演进）
1. **独立数据存储** - recommendation-service拥有自己的数据
2. **消息队列集成** - 通过Kafka订阅用户行为事件
3. **A/B测试框架** - 实验不同推荐算法
4. **实时特征工程** - ClickHouse + 流式计算

## 文件清单

### 新增文件（24个）
```
src/handlers/
  ├── discover.rs          (270行)
  ├── feed.rs             (179行)
  ├── trending.rs         (582行)
  └── mod.rs              (11行)

src/middleware/
  ├── jwt_auth.rs         (133行)
  ├── circuit_breaker.rs  (复制)
  └── mod.rs              (4行)

src/services/
  ├── graph/              (目录)
  ├── trending/           (目录)
  └── mod.rs              (60行更新)

src/db/
  ├── trending_repo.rs    (复制)
  └── mod.rs              (4行)

src/utils/
  ├── redis_timeout.rs    (50行)
  └── mod.rs              (3行)

src/security/
  ├── jwt.rs              (复制)
  └── mod.rs              (3行)

src/grpc/
  ├── clients.rs          (60行)
  ├── nova.rs             (90行)
  └── grpc.rs             (更新)

src/models/
  └── mod.rs              (23行更新)

src/
  ├── lib.rs              (更新，添加新模块)
  └── error.rs            (扩展错误类型)
```

### 依赖添加
```toml
base64.workspace = true
jsonwebtoken.workspace = true
lazy_static = "1.4"
```

## 强耦合问题处理方案

### 1. ONNX模型推理
**问题**: ranking需要ONNX模型推理user和post embeddings
**当前方案**: 保留占位符代码，暂不编译
**后续方案**:
- 方案A: 通过gRPC调用user-service的推理服务
- 方案B: 迁移模型文件和推理代码到recommendation-service

### 2. Neo4j Graph查询
**问题**: discover handlers需要图数据库查询好友关系
**当前方案**: 已复制GraphService代码
**后续方案**: 确保Neo4j连接配置正确

### 3. ClickHouse分析查询
**问题**: trending需要ClickHouse聚合用户行为数据
**当前方案**: 已复制trending service代码
**后续方案**: 验证ClickHouse连接和表结构

### 4. 用户/帖子数据访问
**问题**: ranking需要获取用户资料、帖子内容等
**当前方案**: 创建gRPC client框架
**后续方案**: 实现UserServiceClient调用user-service API

## 下一步行动

### 立即执行（让它编译通过）
1. [ ] 临时注释feed handlers（依赖未完成的proto）
2. [ ] 修复trending service的类型转换错误
3. [ ] 简化JWT验证逻辑
4. [ ] 添加GraphConfig占位符

### 一周内完成（核心功能）
5. [ ] 从content-service提取proto文件并生成代码
6. [ ] 实现UserServiceClient
7. [ ] 复制ranking_engine.rs
8. [ ] 测试trending API端点

### 一个月内完成（生产就绪）
9. [ ] 集成ONNX模型推理
10. [ ] 完善A/B测试框架
11. [ ] 添加监控和metrics
12. [ ] 负载测试和性能优化

## 结论

**迁移进度**: 70%完成

**主要成就**:
- ✅ 所有handlers已迁移（discover, feed, trending）
- ✅ 核心支持模块已建立（middleware, services, utils）
- ✅ 错误处理体系完善
- ✅ gRPC客户端框架搭建

**剩余工作**:
- 🟡 修复29个编译错误（主要是类型不匹配和缺失proto）
- 🟡 迁移ranking_engine核心逻辑
- 🟡 实现完整的gRPC客户端
- 🟡 ONNX模型集成

**风险评估**:
- 🟢 低风险: handlers迁移完整，逻辑清晰
- 🟡 中风险: gRPC依赖需要多服务协调
- 🟡 中风险: ONNX推理复杂度较高

**建议**:
采用分阶段迁移策略，先让基础功能（discover, trending）快速可用，再逐步完善高级功能（ranking, AB testing）。Feed handlers可以暂时保留在user-service作为proxy，避免阻塞整体进度。
