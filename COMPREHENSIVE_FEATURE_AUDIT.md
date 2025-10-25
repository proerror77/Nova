# Nova 社交平台 - 全面功能审计报告

**审计日期**: 2025-10-25
**审计者**: Linus-style Architecture Review
**总体状态**: 🟡 部分完成，有关键缺口

---

## 执行摘要

Nova 平台已实现了核心的消息传递和WebSocket基础设施，但在以下关键领域存在**实现不完整**的问题：

| 功能域 | 实现度 | 优先级 | 关键缺陷 |
|--------|--------|--------|---------|
| **视频系统** | 🟡 60% | P0 | 转码管道未实现，CDN上传未实现 |
| **直播系统** | 🟡 50% | P0 | Kafka集成缺失，WebSocket聊天未集成 |
| **推荐算法** | 🟡 40% | P0 | ONNX模型加载未实现，A/B测试框架缺失 |
| **媒体上传** | 🟡 70% | P0 | S3集成完成，但恢复上传未实现 |
| **消息系统** | 🟢 95% | P1 | 基本完成，缺少高级功能 |
| **Feed系统** | 🟡 50% | P0 | 排序算法完成，发现功能缺失 |
| **社交功能** | 🟡 70% | P1 | Follow/Block完成，关系查询性能问题 |
| **认证系统** | 🟢 90% | P1 | OAuth完成，2FA和备份码有缺陷 |

---

## 第一部分：关键发现

### 发现#1: 视频系统设计正确但实现不完整

#### 现状分析

**已完成的部分：**
- ✅ 视频上传初始化（2阶段：生成URL → 上传完成）
- ✅ S3集成和presigned URL生成
- ✅ FFmpeg元数据提取（分辨率、编码、帧率、码率）
- ✅ 缩略图生成
- ✅ 数据库记录创建

**缺失的部分：**
- ❌ **转码管道完全未实现**
  - `VideoService::start_processing()` 仅记录日志，不执行实际处理
  - 8个处理阶段在 `VideoProcessingPipeline` 中定义但未实现
  - 多质量（360p, 480p, 720p, 1080p）转码未实现
  - HLS/DASH清单生成未连接到转码输出

- ❌ **CDN上传和分发未实现**
  - 转码后的视频没有上传到CDN逻辑
  - CDN失效和原点保护已定义但未在视频流程中使用
  - 流媒体清单生成有代码但未连接到处理管道

- ❌ **深度学习特征提取未完成**
  - 定义了EmbeddingGeneration阶段但未实现
  - 视频特征向量生成逻辑缺失

- ❌ **进度跟踪未实现**
  - TranscodingProgress结构已定义但不在管道中更新

#### 根本原因分析

**设计缺陷：**
```text
❌ 问题：VideoService::start_processing() 是 async 函数，但只记录日志
   影响：客户端认为视频已开始处理，但没有任何事实发生

❌ 问题：没有 job queue 或后台 worker 来执行实际的转码
   影响：转码无法异步执行，可能阻塞用户请求

❌ 问题：VideoProcessingPipeline 定义了8个阶段但代码中不存在实现
   影响：这是一个"骨架"，没有"血肉"
```

#### 用户影响

```text
用户上传视频后：
1. ✅ 获得presigned S3 URL，直接上传到S3 ← 工作
2. ✅ 调用 video_upload_complete endpoint ← 工作
3. ❌ 后台开始转码处理 ← 什么都没发生
4. ❌ 转码完成后上传到CDN ← 什么都没发生
结果：用户永远看不到他们的视频
```

#### P0 缺陷清单

1. **关键**: 没有实际的转码 worker
2. **关键**: CDN上传逻辑缺失
3. **高**: 进度跟踪不工作
4. **高**: 多质量生成不工作
5. **中**: 深度学习特征提取不工作

---

### 发现#2: 直播系统只有"外壳"，缺少"发动机"

#### 现状分析

**已完成的部分：**
- ✅ 流元数据数据库模型
- ✅ Redis计数器（在线观众跟踪）
- ✅ 流清单生成（HLS/DASH）
- ✅ 数据库仓储层

**缺失的部分：**
- ❌ **Kafka集成**
  - `stream_service.rs` 的注释：`kafka_producer: KafkaProducer, // TODO: Add Kafka integration`
  - 流事件（stream.started, stream.ended）无法发布
  - 聊天消息无法持久化到事件流

- ❌ **WebSocket聊天集成**
  - 注释：`Generate chat WebSocket URL (TODO: integrate with WebSocket service)`
  - 直播间聊天功能完全缺失
  - 观众无法互动

- ❌ **RTMP入站处理**
  - 定义了 `rtmp_webhook.rs` 但没有实际的RTMP服务器集成
  - 流创建者无法开始广播

- ❌ **视频转码集成**
  - 没有连接到视频转码服务
  - 直播流无法自适应比特率

#### 代码证据

在 `streaming/stream_service.rs` 中：
```rust
pub struct StreamService {
    // kafka_producer: KafkaProducer, // TODO: Add Kafka integration
    // ...
}

async fn start_stream(&mut self, ...) -> Result<()> {
    // TODO: Publish Kafka event: stream.started
    // 实际代码：什么都不做
}
```

#### 用户影响

```text
用户创建直播后：
1. ✅ 流记录在数据库中创建
2. ❌ RTMP URL 生成但不能实际使用（没有 RTMP 服务器）
3. ❌ 流开始事件未发布到观众
4. ❌ 聊天消息无处去（没有 WebSocket 聊天）
5. ❌ 观众无法看到广播质量自适应（没有转码）

结果：功能看起来存在但不工作
```

#### P0 缺陷清单

1. **关键**: Kafka事件发布未实现
2. **关键**: WebSocket聊天集成缺失
3. **关键**: RTMP服务器集成缺失
4. **高**: 观众在线计数工作但无处显示

---

### 发现#3: 推荐引擎是"玩具实现"，不能用于生产

#### 现状分析

**已完成的部分：**
- ✅ 混合排序器框架
- ✅ A/B 测试基础结构（定义）
- ✅ 协作过滤（定义）
- ✅ 基于内容的过滤（定义）

**缺失的部分：**
- ❌ **ONNX 模型服务**
  - `onnx_serving.rs` 中: `// TODO: Load ONNX model using tract`
  - `// TODO: Run ONNX inference`
  - `// TODO: Test with actual ONNX model file`
  - **实际代码**: 返回硬编码的虚拟向量
  - **影响**: 深度学习推荐不工作

- ❌ **A/B 测试框架**
  - `// TODO: Load experiments from PostgreSQL`
  - `// TODO: Check Redis cache first`
  - `// TODO: Cache result in Redis`
  - `// TODO: Insert into ClickHouse`
  - **实际代码**: 所有步骤都跳过，直接返回随机分组
  - **影响**: 无法进行任何实验

- ❌ **特征提取管道**
  - `// TODO: Load parquet file using arrow-rs when offline feature extraction is ready`
  - `// TODO: Query user interactions from ClickHouse`
  - **实际代码**: 空实现
  - **影响**: 无法使用实际用户数据

- ❌ **协作过滤**
  - `// TODO: Implement full user-based CF when user similarity matrix is available`
  - **实际代码**: 仅返回热门内容，不是真正的CF
  - **影响**: 无法基于用户相似性推荐

#### 代码证据

在 `recommendation_v2/onnx_serving.rs`：
```rust
pub async fn inference(&self, input: &[f32]) -> Result<Vec<f32>> {
    // TODO: Load ONNX model using tract
    // TODO: Run ONNX inference
    // Hardcoded dummy vector - this is NOT a real implementation
    Ok(vec![0.1, 0.2, 0.3, ...])
}
```

#### 用户影响

```text
用户打开Feed：
1. ✅ Feed加载显示内容
2. ❌ 排序完全随机（ONNX模型不工作）
3. ❌ 无法进行A/B测试来优化排序
4. ❌ 推荐完全不个性化

结果：所有用户看到相同的内容顺序
     推荐引擎v2是marketing材料，不是真实实现
```

#### P0 缺陷清单

1. **致命**: ONNX模型服务完全未实现（硬编码虚拟输出）
2. **致命**: A/B测试框架非功能性
3. **关键**: 特征提取管道缺失
4. **关键**: 用户相似性矩阵不存在
5. **中**: ClickHouse集成不完整

---

### 发现#4: 媒体上传工作但缺少高级功能

#### 现状分析

**已完成的部分：**
- ✅ S3集成（AWS SDK）
- ✅ Presigned URLs生成
- ✅ MIME类型验证
- ✅ 文件大小限制（10MB - 2GB范围）
- ✅ 并发上传追踪
- ✅ 上传进度监控

**缺失的部分：**
- ❌ **可恢复上传**
  - 中断的上传无法恢复
  - 网络问题时必须重新开始
  - **影响**: 用户体验差（特别是移动网络）

- ❌ **分块上传**
  - S3 multipart upload未实现
  - 大文件上传风险（一个上传失败=全部重来）
  - **影响**: 上传大视频时不稳定

- ❌ **签名URL缓存**
  - 每次都生成新的URL，没有缓存
  - **影响**: 不必要的S3 API调用

#### 用户影响

```text
用户场景：在4G网络上传500MB视频
1. ✅ 获得presigned URL
2. ✅ 开始上传
3. ❌ 网络断开（3分钟后）
4. ❌ 必须重新上传整个500MB
   （而不是从中断点继续）

改进后：
1. ✅ 获得presigned URL
2. ✅ 开始分块上传（每块5MB）
3. ❌ 网络断开（上传了300MB）
4. ✅ 获得新URL，从第61块继续
   （只需再上传200MB）
```

#### P1 缺陷清单

1. **高**: 没有分块上传支持
2. **中**: 没有恢复上传支持
3. **低**: 没有签名URL缓存

---

### 发现#5: Feed/发现系统只有排序，缺少发现

#### 现状分析

**已完成的部分：**
- ✅ Feed排序逻辑（但使用推荐引擎v2）
- ✅ 内容排名计算
- ✅ 时间线分页
- ✅ 用户关注的内容过滤

**缺失的部分：**
- ❌ **发现页面（Discover）**
  - 热门内容页面缺失
  - 趋势标签页面缺失
  - 探索推荐缺失
  - **影响**: 新用户无法发现内容

- ❌ **搜索功能**
  - 虽然有search-service，但与Feed系统未集成
  - 用户无法在应用中搜索
  - **影响**: 内容可发现性差

- ❌ **兴趣标签**
  - 虽然视频有hashtags，但没有基于标签的feed
  - **影响**: 用户无法关注兴趣

#### 用户影响

```text
新用户注册：
1. ✅ 看到follow的用户内容
2. ❌ 无法发现新内容
3. ❌ 无法找到感兴趣的话题
4. ❌ 搜索不可用

结果：用户陷入内容气泡，无法增长
```

#### P0 缺陷清单

1. **关键**: 发现页面完全缺失
2. **关键**: 搜索集成缺失
3. **中**: 基于标签的发现缺失

---

## 第二部分：细节分析

### 系统架构评估

#### 数据流分析

```
用户上传视频的真实流程：
1. POST /api/v1/videos/upload/init ✅
   ↓
2. 获得S3 presigned URL ✅
   ↓
3. 客户端直接上传到S3 ✅
   ↓
4. POST /api/v1/videos/upload/complete ✅
   ↓
5. 调用 VideoService::start_processing() ❌ ← 这里断掉了
   ↓
6. [应该触发] 后台视频转码 ❌ 不存在
   ↓
7. [应该执行] HLS/DASH清单生成 ❌ 不存在
   ↓
8. [应该执行] CDN上传 ❌ 不存在
   ↓
9. [应该返回] 流媒体URL到客户端 ❌ 不存在

结果：用户的视频在S3中，但无法播放
```

#### 关键架构问题

**问题1: 没有后台 worker/job queue**
```text
当前：
- API endpoint 调用 service 方法
- Service 方法同步执行或根本不执行

应该有：
- API endpoint 创建 job 记录
- 后台 worker (Kafka consumer 或 job queue worker) 处理
- Worker 更新数据库进度
- 完成后发送事件回到客户端

缺失组件：后台worker基础设施
```

**问题2: Kafka 事件流未使用**
```text
有 KafkaProducer 定义但：
- 直播流事件未发布
- 视频转码进度未发布
- 推荐更新未发布

这导致：
- 无法实时更新客户端进度
- 无法在微服务间解耦
```

**问题3: 特征工程管道未连接**
```text
有 ClickHouse 和 CDC，但：
- 视频特征未提取到 ClickHouse
- 用户交互未记录到 ClickHouse
- 推荐模型无法访问任何特征

这导致：
- ONNX 模型无法工作（没有输入特征）
- A/B 测试无法工作（没有事件数据）
```

---

## 第三部分：优先级建议

### 立即修复（1-2周）- P0 缺陷

#### 1. 视频转码管道 【必须】
**为什么关键**：
- 视频功能是平台的核心价值
- 目前用户无法观看他们上传的视频
- 这是**完全的功能缺失**，不是优化

**修复步骤**：
```
1. 实现后台 worker（使用 Tokio task 或 Kafka consumer）
2. 在 upload_complete endpoint 创建 job 记录
3. Worker 轮询或消费 job，执行：
   - 从S3下载原始视频
   - 运行FFmpeg转码（360p, 480p, 720p, 1080p）
   - 生成HLS/DASH清单
   - 上传到CDN
   - 更新数据库：status = "completed", cdn_url = "..."
4. 客户端轮询进度或使用 WebSocket 推送
```

**工作量**：3-5天

#### 2. 直播系统 Kafka 集成 【必须】
**为什么关键**：
- 直播功能无法工作（事件无法发布）
- 观众无法接收流更新

**修复步骤**：
```
1. 在 stream_service.rs 中连接 KafkaProducer
2. start_stream() 发布 stream.started 事件
3. end_stream() 发布 stream.ended 事件
4. 聊天消息发布到 stream.chat 主题
```

**工作量**：1-2天

#### 3. 直播 WebSocket 聊天 【必须】
**为什么关键**：
- 直播互动完全不工作
- 观众无法聊天

**修复步骤**：
```
1. 创建 /ws/stream/{stream_id}/chat WebSocket 端点
2. 连接到消息系统的 WebSocket 处理器
3. 在 stream.chat Kafka 主题中持久化聊天
```

**工作量**：2-3天

#### 4. ONNX 模型实际加载 【必须】
**为什么关键**：
- 推荐引擎返回虚拟数据
- 排序完全随机
- 用户无法获得个性化内容

**修复步骤**：
```
1. 使用 tract 库加载实际的 ONNX 模型文件
2. 从特征存储获取用户特征
3. 运行实际推理（不是返回硬编码向量）
4. 性能测试：确保 <100ms
```

**工作量**：2-3天（假设模型文件存在）

### 第一个迭代（第二周）- P1 缺陷

#### 5. 视频分块上传 【重要】
**为什么重要**：
- 用户在不稳定网络上无法上传大文件
- 当前实现不能恢复

**修复步骤**：
```
1. 使用 AWS S3 multipart upload API
2. 前端发送 initiate-multipart 请求
3. 分块上传每块（5-100MB）
4. 完成或中止时调用相应API
```

**工作量**：2-3天

#### 6. A/B 测试框架 【重要】
**为什么重要**：
- 无法测试推荐改进
- 无法优化排序算法

**修复步骤**：
```
1. 从PostgreSQL加载实验配置
2. 根据user_id哈希分配到变体
3. 在Redis缓存分配（TTL 7天）
4. 事件发送到ClickHouse
```

**工作量**：2-3天

#### 7. Feed 发现页面 【重要】
**为什么重要**：
- 新用户无法发现内容
- 用户增长受限

**修复步骤**：
```
1. 创建 GET /api/v1/feed/discover 端点
2. 实现热门内容排序
3. 实现趋势标签页面
4. 实现基于兴趣的推荐
```

**工作量**：3-4天

#### 8. 用户可恢复上传 【重要】
**为什么重要**：
- 移动用户体验差
- 浪费带宽

**修复步骤**：
```
1. 实现 upload session 概念
2. 存储分块哈希以验证完整性
3. 允许客户端查询已上传块
4. 从任意点继续上传
```

**工作量**：2-3天

### 后续改进（第三周+）- P2 项

- 推荐特征工程完整实现
- CDC 到 ClickHouse 管道完整连接
- 搜索与 Feed 集成
- 性能优化（缓存、索引、分片）

---

## 第四部分：根本问题分析

### 问题根源：不完整的实现模式

这个项目有一个**系统性的问题**：很多功能定义了**接口和数据模型**，但**没有实现实际逻辑**。

#### 模式识别

```
❌ 反复出现的模式：

1. 定义了结构体或enum（VideoProcessingPipeline, ProcessingStage）
2. 定义了接口方法（start_processing, extract_metadata）
3. 添加了TODO注释（// TODO: implement X）
4. 实际代码：
   - 什么都不做（return Ok(())）
   - 返回虚拟数据（Vec![0.1, 0.2, 0.3]）
   - 只记录日志（info!("doing X")）

这给人的假象是 "看起来完成了" 但 "实际不工作"
```

#### Linus 的评价

"这不是代码。这是一个**骗局**。你创建了看起来完整的接口，但没有内部。这就像买了一辆玩具车——有方向盘、有轮子，但没有发动机。"

#### 根本问题

```
❌ 问题1：项目管理问题
   - 功能被标记为"完成"，但实际上只是"定义"
   - 测试不覆盖实现（测试TODO也很多）
   - 代码审查没有catch这个问题

❌ 问题2：技术设计问题
   - 没有后台 worker 基础设施
   - Kafka 定义但未连接
   - 数据库模型定义但没有数据流

❌ 问题3：集成问题
   - 各个模块独立完成但未连接
   - VideoService 和 VideoTranscodingService 未集成
   - 推荐引擎 v2 与特征存储未集成
   - Kafka 事件与处理器未连接
```

---

## 第五部分：重构建议

### 针对Linus的"好品味"原则的改进

#### 1. 消除"虚拟实现"

**当前**：
```rust
async fn start_processing(&self, video_id: &Uuid, ...) -> Result<()> {
    info!("start processing video: {} - {}", video_id, title);
    Ok(())  // 什么都没做
}
```

**改进**：
```rust
async fn start_processing(&self, video_id: &Uuid, ...) -> Result<()> {
    // 不创建虚拟实现
    // 要么：返回 unimplemented!() 使其明显
    // 要么：返回 Err(AppError::NotImplemented(...))
    unimplemented!("Video transcoding pipeline not yet implemented")
}
```

这样代码会**明确失败**，而不是**悄悄什么都不做**。

#### 2. 重新设计数据流

**问题**：upload_complete endpoint 期望 VideoService 同步处理一个可能需要10分钟的任务。

**解决**：
```
而不是 upload_complete 直接调用处理：

POST /videos/{id}/upload/complete
  ↓
1. 验证S3上传完成
2. 创建 VideoTranscodingJob 记录
3. 发布 video.upload.completed 事件到 Kafka
4. 立即返回给客户端

后台：
kafka consumer（video-transcoding-worker）
  ↓
  接收 video.upload.completed
  ↓
  执行转码
  ↓
  发布 video.transcoding.completed
  ↓
  客户端通过 WebSocket 或轮询收到完成事件
```

#### 3. 修复推荐系统架构

**问题**：推荐引擎 v2 定义了5个不同的算法，但都是虚拟实现。

**解决**：选择**一个算法**，完全实现它，而不是5个都不完整：

```
选择：混合排序器 + 基于内容的过滤
      （比较简单，不需要用户相似性矩阵）

实现：
1. 从ClickHouse获取用户观看历史
2. 提取这些内容的特征
3. 找到相似内容
4. 混合排序：流行度 + 相似度 + 新鲜度
5. 完全移除不完整的其他算法（协作过滤、ONNX）
```

#### 4. 统一事件流

**问题**：Kafka定义了但未使用。

**解决**：
- 视频转码 → video.transcoding.* 事件
- 直播状态 → stream.* 事件
- 推荐更新 → recommendation.* 事件
- 所有事件都发布到 Kafka
- 所有消费者明确订阅

---

## 第六部分：生产就绪清单

### 当前状态：❌ 不能投入生产

#### 致命缺陷（MUST FIX）

- [ ] 视频无法播放（转码管道）
- [ ] 直播无法工作（Kafka + WebSocket）
- [ ] 推荐完全随机（ONNX模型）
- [ ] 上传在弱网上易失败（no resumable upload）

#### 严重问题（SHOULD FIX）

- [ ] Feed发现功能缺失
- [ ] A/B测试不工作
- [ ] 特征工程管道断开
- [ ] 后台worker基础设施不完整

#### 需要优化（NICE TO HAVE）

- [ ] 缓存策略优化
- [ ] 查询性能优化
- [ ] 错误处理和重试
- [ ] 可观测性改进（这部分已在Fix #8中完成）

---

## 结论

Nova平台目前处于**"看起来完成但实际功能缺失"**的状态。这反映了一个系统性的项目管理问题：

1. **代码定义了接口，但没有实现逻辑**
2. **多个服务独立开发，但未集成**
3. **没有明确的"功能完成"标准**

### 路径前进

1. **立即（1-2周）**：修复4个P0缺陷（视频、直播、推荐、上传）
2. **第一迭代（第二周）**：修复4个P1缺陷（分块上传、A/B测试、发现页面、可恢复上传）
3. **第二迭代**：完整的端到端测试和性能优化
4. **生产部署前**：所有功能必须端到端工作，不是"定义"而是"实现"

### Linus的最终评价

"这个项目的问题不是架构不对，而是你定义了架构但没有build它。你需要的不是更多的理论设计——你需要的是**完成工作**。从最关键的部分开始，逐个做完，确保每一个都真正工作。不要搞10个50%完成的功能，要搞2个100%完成的。"

---

**生成日期**: 2025-10-25
**审计员**: Linus-style Architecture Review
**建议**: 停止新功能开发，专注完成已开始的功能
