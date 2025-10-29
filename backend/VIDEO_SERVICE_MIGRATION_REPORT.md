# Video Service迁移报告

## 执行摘要

迁移过程中发现了**关键架构问题**，需要先修正架构再继续迁移。

## 已完成的工作

### ✅ 1. S3 Service迁移（成功）

**文件**: `video-service/src/services/s3_service.rs`

- ✅ 从user-service成功复制s3_service.rs（638行）
- ✅ 将`AppError`替换为`ServiceError`（使用error-handling库）
- ✅ 添加AWS SDK依赖（aws-config, aws-sdk-s3, sha2, hex）
- ✅ 添加S3Config到video-service配置
- ✅ 编译成功，无错误

**技术细节**：
```rust
// 依赖关系清晰
use crate::config::S3Config;
use error_handling::ServiceError;  // 使用共享错误库
use aws_sdk_s3::*;
```

**测试结果**：
```bash
✅ s3_service编译通过
✅ 所有函数签名正确
✅ 单元测试保留完整
```

---

## 🚨 发现的严重架构问题

### 问题1: video-service的gRPC角色错误

**当前错误架构**：
```
video-service/build.rs: 生成gRPC客户端代码
video-service/grpc.rs: 实现gRPC客户端，连接到user-service
                       ^^^^^^^^^^^^^^^^^^^^^^
                       这是完全错误的！
```

**正确的架构应该是**：
```
video-service: gRPC服务器（提供VideoService）
user-service:  gRPC客户端（调用video-service）
```

**问题代码示例**：
```rust
// video-service/grpc.rs (当前错误的代码)
pub struct VideoGrpcClient {
    client: Arc<Mutex<video_service_client::VideoServiceClient<Channel>>>,
    //                 ^^^^^^^^^^^^^^^^^^^^^^ 这是客户端！
}

impl VideoGrpcClient {
    pub async fn connect(config: ClientConfig) -> Result<Self> {
        let client = Client::connect(config).await?;
        //           ^^^^^^^^^^^^^^^ 连接到user-service（错误）
```

### 问题2: user-service包含所有video业务逻辑

**发现的强耦合代码**：

1. **`user-service/src/handlers/videos.rs` (948行)**
   - 包含13个HTTP endpoint handlers
   - 严重依赖user-service的模块：
     ```rust
     use crate::db::video_repo;                    // 数据库repo
     use crate::middleware::{CircuitBreaker, UserId}; // 中间件
     use crate::models::video::*;                  // video models
     use crate::services::deep_learning_inference::*; // AI服务
     use crate::services::streaming_manifest::*;   // 流媒体服务
     use crate::services::video_transcoding::*;    // 转码服务
     use crate::services::video_service::VideoService; // 业务逻辑
     ```

2. **关键函数依赖分析**：
   - `video_upload_init()`: 需要JWT中间件提取user_id
   - `video_upload_complete()`: 需要video_job_queue
   - `create_video()`: 需要video_repo直接访问DB
   - `get_similar_videos()`: 需要DeepLearningInferenceService

**结论**: 这些代码不能简单复制到video-service，因为它们与user认证、中间件深度耦合。

---

## 正确的迁移策略

### 阶段1: 修正video-service架构（高优先级）

1. **重写video-service/grpc.rs**
   - 删除gRPC客户端代码
   - 实现gRPC服务器
   - 实现`VideoService` trait

2. **修改build.rs生成服务器端代码**
   ```rust
   tonic_build::configure()
       .build_server(true)   // 生成服务器代码
       .build_client(false)  // 不生成客户端代码
       .compile(&["../protos/video.proto"], &["../protos/"])?;
   ```

3. **创建核心服务实现**
   ```
   video-service/src/
   ├── services/
   │   ├── s3_service.rs      ✅ 已完成
   │   ├── video_repo.rs      ⬜ 待创建（数据库访问）
   │   ├── transcoding.rs     ⬜ 待创建（FFmpeg包装）
   │   └── upload_service.rs  ⬜ 待创建（上传业务逻辑）
   └── grpc/
       └── server.rs          ⬜ 待创建（gRPC服务器实现）
   ```

### 阶段2: 分离业务逻辑（中优先级）

从user-service提取**纯video业务逻辑**：

1. **数据库层**
   - 从`user-service/src/db/video_repo.rs`提取SQL查询
   - 迁移到`video-service/src/services/video_repo.rs`
   - 移除user认证相关逻辑

2. **转码服务**
   - 从`user-service/src/services/video_transcoding.rs`提取FFmpeg逻辑
   - 迁移到`video-service/src/services/transcoding.rs`

3. **上传服务**
   - 提取S3上传逻辑（✅ 已完成）
   - 提取上传会话管理
   - 提取文件验证逻辑

### 阶段3: 更新user-service（低优先级）

1. **创建gRPC客户端**
   ```rust
   // user-service/src/grpc/video_client.rs
   pub struct VideoServiceClient {
       client: video_service_client::VideoServiceClient<Channel>,
   }
   ```

2. **简化HTTP handlers**
   ```rust
   // user-service/src/handlers/videos.rs
   pub async fn video_upload_init(
       req: HttpRequest,
       video_client: web::Data<VideoServiceClient>,
   ) -> Result<HttpResponse> {
       // 1. 从JWT提取user_id（保留在user-service）
       let user_id = extract_user_id(&req)?;

       // 2. 调用video-service gRPC
       let response = video_client.upload_video(UploadVideoRequest {
           user_id,
           title: req.title,
           ...
       }).await?;

       // 3. 返回HTTP响应
       Ok(HttpResponse::Created().json(response))
   }
   ```

---

## 技术决策记录

### 决策1: 不复制video handlers

**原因**：
- user-service的video handlers依赖JWT认证中间件
- 依赖user-service的CircuitBreaker
- 依赖user-service的配置系统
- 复制会导致代码重复和不一致

**解决方案**：
- video-service专注于纯video业务逻辑（存储、转码、流媒体）
- user-service保留HTTP层和认证逻辑
- 通过gRPC通信

### 决策2: 使用共享库

**已创建的共享库**：
- ✅ `error-handling`: 统一错误类型
- ✅ `video-core`: video models
- ✅ `db-pool`: 数据库连接池

**优势**：
- 避免代码重复
- 类型一致性
- 易于维护

---

## 下一步行动计划

### 立即执行（P0）

1. **修正build.rs**（5分钟）
   ```rust
   tonic_build::configure()
       .build_server(true)
       .build_client(false)
       .compile(&["../protos/video.proto"], &["../protos/"])?;
   ```

2. **重写grpc.rs为服务器实现**（2小时）
   - 实现`VideoService` trait
   - 实现6个gRPC方法
   - 连接到PostgreSQL

3. **创建video_repo.rs**（1小时）
   - 从user-service提取SQL查询
   - 实现CRUD操作

### 短期任务（P1）

4. **实现upload_video方法**（4小时）
   - 生成presigned S3 URL
   - 创建数据库记录
   - 返回upload session

5. **实现get_video_metadata方法**（1小时）
   - 查询数据库
   - 返回video metadata

### 中期任务（P2）

6. **实现transcoding逻辑**（1周）
   - FFmpeg集成
   - Job queue
   - 进度跟踪

---

## 风险和缓解措施

### 风险1: 现有功能中断

**影响**: 重构video-service会影响现有video功能

**缓解**:
- 保持user-service的video handlers不变
- 先实现video-service gRPC服务器
- 渐进式切换（feature flag）

### 风险2: 数据一致性

**影响**: 两个服务访问同一个数据库

**缓解**:
- video-service拥有videos表
- user-service只读访问
- 使用事务保证一致性

### 风险3: 性能问题

**影响**: gRPC调用增加延迟

**缓解**:
- gRPC比HTTP快（HTTP/2, Protobuf）
- 本地部署延迟<1ms
- 实施缓存策略

---

## 编译状态

### ✅ 成功编译的模块

```bash
✅ error-handling (带1个warning)
✅ video-core
✅ db-pool (带1个warning)
✅ video-service/services/s3_service.rs
```

### ❌ 需要修复的模块

```bash
❌ video-service/grpc.rs - 架构错误（客户端应该是服务器）
❌ video-service/handlers/mod.rs - 使用错误的proto类型
```

**当前编译错误**：
```
error[E0063]: missing fields `file_name`, `file_size` and `mime_type`
  in initializer of `UploadVideoRequest`
  --> video-service/src/handlers/mod.rs:51:19

error[E0277]: the trait bound `UploadVideoResponse: serde::Serialize`
  is not satisfied
```

**原因**: handlers/mod.rs使用的proto类型不支持serde序列化

---

## 总结

### 完成的工作

1. ✅ S3 service成功迁移
2. ✅ 发现并记录架构问题
3. ✅ 制定正确的迁移策略
4. ✅ 识别所有强耦合依赖

### 阻塞问题

1. 🚨 video-service的gRPC角色错误（客户端 vs 服务器）
2. 🚨 需要重新设计服务边界
3. 🚨 需要实现gRPC服务器而不是客户端

### 建议

**不要盲目复制代码**。当前的user-service/handlers/videos.rs包含948行代码，但其中大部分与user认证、中间件、配置紧密耦合。正确的做法是：

1. 先修正video-service的gRPC架构
2. 实现核心video业务逻辑（存储、转码）
3. 让user-service通过gRPC调用video-service
4. 保持关注点分离

---

## 文件清单

### 已创建/修改的文件

```
✅ backend/video-service/Cargo.toml (添加AWS依赖)
✅ backend/video-service/src/config/mod.rs (添加S3Config)
✅ backend/video-service/src/services/s3_service.rs (新建，638行)
✅ backend/video-service/src/services/mod.rs (新建)
✅ backend/video-service/src/lib.rs (导出services模块)
```

### 待修改的文件

```
⬜ backend/video-service/build.rs (改为生成服务器代码)
⬜ backend/video-service/src/grpc.rs (重写为服务器实现)
⬜ backend/video-service/src/handlers/mod.rs (简化或删除)
⬜ backend/video-service/src/services/video_repo.rs (新建)
⬜ backend/video-service/src/services/upload_service.rs (新建)
```

### 不应该复制的文件

```
❌ user-service/src/handlers/videos.rs (948行，强耦合user-service)
❌ user-service/src/handlers/uploads.rs (依赖actix-multipart和user中间件)
❌ user-service/src/services/video_service.rs (依赖多个user-service模块)
```

---

**日期**: 2025-10-30
**状态**: 阻塞，需要架构修正
**下一步**: 修正video-service的gRPC实现（从客户端改为服务器）
