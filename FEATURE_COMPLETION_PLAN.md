# Nova 平台 - 功能完成优先级计划

**创建日期**: 2025-10-25
**基于**: 全面功能审计报告
**目标**: 使Nova平台达到生产就绪状态

---

## 阶段1：P0缺陷修复（立即，1-2周）

这4个缺陷是**完全的功能阻塞**，用户无法使用核心功能。

### Task 1.1: 视频转码管道实现【5天】

#### 当前状态
- ❌ 视频上传到S3后什么都没发生
- ❌ 用户无法播放他们上传的视频
- ❌ `VideoService::start_processing()` 仅记录日志

#### 需要实现
1. **后台Worker基础设施**
   - 创建 `VideoTranscodingWorker` 任务队列
   - 实现 Kafka consumer 或定时轮询
   - 监听 `video.upload.completed` 事件

2. **转码管道**
   - 从S3下载原始视频
   - 使用FFmpeg生成多质量版本（360p, 480p, 720p, 1080p）
   - 生成HLS和DASH清单
   - 上传到CDN（使用现有的CDN服务）

3. **进度追踪**
   - 更新 `transcoding_progress` 表
   - 发布进度事件到Kafka
   - 允许客户端查询进度或接收WebSocket推送

4. **完成处理**
   - 更新video记录：status = "completed", cdn_url = "..."
   - 发布 `video.transcoding.completed` 事件
   - 清理本地临时文件

#### 文件修改
- `backend/user-service/src/services/video_job_queue.rs` - 实现job队列
- `backend/user-service/src/services/video_service.rs` - 连接到转码worker
- `backend/user-service/src/services/video_transcoding.rs` - 增强以支持多质量
- 可能需要新文件：`backend/user-service/src/workers/video_transcoding_worker.rs`

#### 验证标准
```
✅ 测试1: 上传视频后，自动开始转码
✅ 测试2: 转码完成后，CDN URL可访问
✅ 测试3: 进度能在数据库中跟踪
✅ 测试4: 完成后能在feed中播放视频
```

---

### Task 1.2: 直播Kafka集成【2天】

#### 当前状态
- ❌ `KafkaProducer` 定义但未使用
- ❌ 流开始/结束事件未发布
- ❌ 观众无法接收实时更新

#### 需要实现
1. **在StreamService中连接KafkaProducer**
   ```rust
   impl StreamService {
       pub async fn start_stream(...) {
           // 发布 stream.started 事件
           self.kafka_producer.publish("stream.started", {
               stream_id, user_id, title, created_at
           }).await?;
       }

       pub async fn end_stream(...) {
           // 发布 stream.ended 事件
           self.kafka_producer.publish("stream.ended", {
               stream_id, ended_at, viewer_count, duration
           }).await?;
       }
   }
   ```

2. **实现观众在线更新**
   - 每当用户加入/离开流，发布事件
   - 订阅者可以实时更新观众计数

3. **事件持久化**
   - 所有流事件保存到数据库（用于分析）

#### 文件修改
- `backend/user-service/src/services/streaming/stream_service.rs` - 添加Kafka发布
- 可能需要：`backend/user-service/src/workers/stream_event_consumer.rs`

#### 验证标准
```
✅ 测试1: 开始直播后，Kafka收到stream.started事件
✅ 测试2: 结束直播后，Kafka收到stream.ended事件
✅ 测试3: 事件包含正确的元数据
✅ 测试4: 消费者能处理这些事件
```

---

### Task 1.3: 直播WebSocket聊天集成【3天】

#### 当前状态
- ❌ 直播间聊天完全缺失
- ❌ 观众无法互动
- ❌ 评论都是单向的

#### 需要实现
1. **WebSocket端点**
   - 创建 `GET /ws/stream/{stream_id}/chat`
   - 连接到消息系统的WebSocket处理器
   - 用户加入时订阅 `stream.{stream_id}.chat` 频道

2. **聊天消息处理**
   - 接收客户端消息
   - 验证消息长度、速率限制
   - 发布到 `stream.{stream_id}.chat` Kafka主题
   - 广播给所有连接的观众

3. **持久化**
   - 所有聊天消息保存到数据库
   - 新观众可以看到历史聊天（最近50条）

#### 文件修改
- `backend/user-service/src/handlers/streams.rs` - 添加WebSocket endpoint
- 可能需要：`backend/user-service/src/services/streaming/chat_handler.rs`

#### 验证标准
```
✅ 测试1: 多个客户端可以连接到同一直播的聊天
✅ 测试2: 消息实时广播给所有连接
✅ 测试3: 新观众可以看到历史消息
✅ 测试4: 消息持久化到数据库
✅ 测试5: 速率限制生效（防止刷屏）
```

---

### Task 1.4: ONNX模型实际加载【3天】

#### 当前状态
- ❌ `onnx_serving.rs` 返回硬编码虚拟向量
- ❌ 推荐排序完全随机
- ❌ 用户无法获得个性化内容

#### 需要实现
1. **真实模型加载**
   ```rust
   pub async fn load_model(model_path: &str) -> Result<OnnxModel> {
       let bytes = tokio::fs::read(model_path).await?;
       let session = ort::Session::builder()?
           .commit_from_memory(&bytes)?;
       Ok(OnnxModel { session })
   }
   ```

2. **特征准备**
   - 从 Recommendation 输入获取用户特征
   - 标准化特征值
   - 准备模型输入张量

3. **推理执行**
   ```rust
   pub async fn inference(&self, features: &[f32]) -> Result<Vec<f32>> {
       let input = ndarray::arr1(features).into_dyn();
       let outputs = self.session.run(ort::inputs![input]?)?;
       // 提取输出
   }
   ```

4. **性能优化**
   - 确保 <100ms 延迟
   - 可能需要批量推理
   - 考虑模型缓存

#### 文件修改
- `backend/user-service/src/services/recommendation_v2/onnx_serving.rs` - 实际实现

#### 验证标准
```
✅ 测试1: 模型文件存在并可加载
✅ 测试2: 推理返回合理的向量（不是硬编码）
✅ 测试3: 推理延迟 <100ms
✅ 测试4: 不同输入产生不同输出
✅ 测试5: 推荐排序因此改变
```

---

## 阶段2：P1缺陷修复（第二周，4天）

### Task 2.1: 可恢复上传【3天】

#### 当前状态
- ⚠️ 上传在弱网络上可靠性差
- ⚠️ 中断的上传必须重新开始

#### 需要实现
1. **分块上传支持**
   - 使用AWS S3 multipart upload API
   - 将大文件分成5-100MB的块

2. **进度追踪**
   - 存储每个块的ETag
   - 允许客户端查询已完成的块

3. **恢复逻辑**
   - 如果传输中断，客户端可以：
     a) 查询已上传块
     b) 从下一块继续
     c) 上传完后提交

---

### Task 2.2: A/B测试框架【3天】

#### 当前状态
- ❌ 所有TODO未实现
- ❌ 无法运行推荐实验

#### 需要实现
1. **实验加载**
   - 从PostgreSQL读取活跃实验
   - 缓存到Redis（TTL: 7天）

2. **用户分配**
   - 基于user_id的哈希确定性分配
   - 同一用户总是进入相同变体

3. **事件追踪**
   - 所有推荐和点击事件发送到ClickHouse
   - 标记实验ID和变体

4. **分析**
   - 在ClickHouse中计算指标
   - 可视化实验结果

---

### Task 2.3: Feed发现页面【4天】

#### 当前状态
- ❌ 新用户无法发现内容
- ❌ 没有"发现"页面
- ❌ 用户困在关注的内容气泡

#### 需要实现
1. **热门内容页面** - `GET /api/v1/feed/discover/trending`
   - 显示最近7天热门的内容
   - 基于观看数、点赞数、分享数

2. **趋势标签页面** - `GET /api/v1/feed/discover/trending-tags`
   - 显示热门话题标签
   - 用户点击标签查看相关内容

3. **为你推荐** - `GET /api/v1/feed/discover/for-you`
   - 基于用户观看历史的个性化推荐
   - 推荐相似内容和热门内容的混合

---

### Task 2.4: 用户上传进度API【2天】

#### 需要实现
- `GET /api/v1/videos/{id}/transcoding-progress` - 查询转码进度
- `GET /api/v1/videos/{id}/transcoding-status` - 查询状态（转码中/完成/失败）
- WebSocket推送 - 实时推送进度更新

---

## 阶段3：验证和优化（第三周）

### Task 3.1: 端到端集成测试

创建完整的测试场景：
1. 用户上传视频 → 自动转码 → 在feed中播放
2. 用户开始直播 → 观众观看 → 实时聊天
3. 系统推荐视频 → 用户交互被追踪 → 影响未来推荐

### Task 3.2: 性能基准测试

- 视频转码时间 (1GB视频应该 <20分钟)
- 推理延迟 (<100ms)
- 直播延迟 (<5s)
- 聊天消息延迟 (<500ms)

### Task 3.3: 错误恢复测试

- 转码中断并恢复
- 网络断开时上传恢复
- Kafka消费者故障恢复
- 数据库故障时的降级

---

## 风险评估和缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| ONNX模型不存在 | 中 | 高 | 联系ML团队，如果不存在使用简单启发式 |
| FFmpeg在部署环境不可用 | 低 | 高 | 使用Docker确保依赖，或使用AWS MediaConvert |
| Kafka延迟影响用户体验 | 低 | 中 | 实现fallback到直接API调用 |
| 大规模视频转码导致CPU过载 | 中 | 高 | 实现优先级队列，限制并发转码 |

---

## 成功标准

### 最少可行产品（MVP）
- [ ] 用户可以上传视频并在10分钟内观看
- [ ] 用户可以开始直播，观众可以观看并聊天
- [ ] Feed显示个性化推荐（即使是简单的推荐）
- [ ] 所有操作在弱网络上可靠工作

### 生产就绪
- [ ] 所有P0缺陷修复
- [ ] 所有P1缺陷修复
- [ ] 性能测试通过
- [ ] 集成测试100%通过
- [ ] 可观测性完整（Fix #8已完成）
- [ ] 灾备和恢复测试通过

---

## 工作分配建议

如果有多个开发者：

**开发者A: 视频系统**
- Task 1.1: 视频转码管道
- Task 2.1: 可恢复上传
- Task 2.4: 进度API

**开发者B: 直播系统**
- Task 1.2: Kafka集成
- Task 1.3: WebSocket聊天
- Task 2.2: A/B测试（可选）

**开发者C: 推荐/Feed**
- Task 1.4: ONNX模型
- Task 2.3: 发现页面
- Task 3.2: 性能测试

**开发者D: 测试/DevOps**
- Task 3.1: 集成测试
- Task 3.3: 错误恢复测试
- 部署流程

---

## 时间表

```
第1周（立即开始）:
  - Mon-Tue: Task 1.2, 1.3（直播）
  - Tue-Wed: Task 1.4（ONNX）
  - Wed-Fri: Task 1.1（视频转码）

第2周:
  - Mon-Tue: Task 2.1（恢复上传）
  - Tue-Wed: Task 2.2（A/B测试）
  - Wed-Fri: Task 2.3（发现页面）

第3周:
  - Mon-Tue: Task 3.1（集成测试）
  - Tue-Wed: Task 3.2（性能测试）
  - Wed-Fri: Task 3.3（错误恢复测试）+ Bug修复

总计: 3周达到"可部署"状态
```

---

**策略**: 完成胜于完美。先做P0缺陷使核心功能可用，再逐步改进。
