# Nova Social Platform - 技术债务清单

**生成日期**: 2025-10-23
**优先级**: 🔴 严重 | 🟡 中等 | 🟢 低

---

## 快速参考

| 类别 | 数量 | 优先级 | 修复时间 |
|------|------|--------|---------|
| todo!()宏调用 | 15+ | 🔴 | 40小时 |
| 重复实现 | 3+ | 🔴 | 30小时 |
| Mock实现 | 20+ | 🔴 | 60小时 |
| 缺失功能 | 8+ | 🔴 | 200小时 |
| 不完整API | 12+ | 🟡 | 50小时 |
| 测试缺失 | 90% | 🔴 | 150小时 |

**总技术债务**: ~600小时 ≈ 15周（单人开发）

---

## 按严重程度分类

### 🔴 严重 - 会导致生产crash

#### 1. Recommendation V2完全未实现
```rust
// backend/user-service/src/services/recommendation_v2/mod.rs:46
pub async fn new(config: RecommendationConfig) -> Result<Self> {
    todo!("Implement RecommendationServiceV2::new")
}

pub async fn get_recommendations(&self, user_id: Uuid, limit: usize) -> Result<Vec<Uuid>> {
    todo!("Implement get_recommendations")
}
```

**影响**: 任何调用推荐API的用户会看到panic
**修复成本**: 200小时
**风险**: 线上crash

---

#### 2. 视频嵌入生成返回全零向量
```rust
// backend/user-service/src/services/deep_learning_inference.rs:56
let embedding = vec![0.0; self.config.embedding_dim];
```

**影响**: 
- 所有视频相似度计算都失败
- 推荐结果无用
- 无法检测垃圾视频

**修复成本**: 150小时（需要TensorFlow集成）
**风险**: 推荐系统完全失效

---

#### 3. Feed有三个互相冲突的实现
```
feed_service.rs (523行) - DEPRECATED
feed_ranking.rs (727行) - PRODUCTION？
feed_ranking_service.rs (474行) - ALTERNATIVE？
```

**哪个是正确的**？没人知道。

**影响**: 
- 没有一个完整
- 维护三倍工作量
- 无法同时升级

**修复成本**: 80小时重构
**风险**: 生产用哪个都是错的

---

#### 4. OAuth支持存在但不工作
```rust
// backend/user-service/src/services/oauth/
pub mod google;   // 存在但空
pub mod apple;    // 存在但空
pub mod facebook; // 存在但空
```

**影响**: 所有社交登录都失败
**修复成本**: 120小时
**用户体验**: ⭐ 0星

---

### 🟡 中等 - 功能缺失或性能问题

#### 5. ClickHouse查询未优化
```rust
// feed_ranking.rs: get_followees_candidates()
// 每次调用都是新查询，无缓存
// 应该用物化视图和Redis
```

**影响**: P95延迟 > 1秒（目标<200ms）
**修复成本**: 40小时
**用户体验**: 速度慢

---

#### 6. 消息搜索完全缺失
```
后端: search-service不存在
iOS: SearchRepository存在但无实现
```

**影响**: 用户无法搜索聊天记录
**修复成本**: 100小时
**功能完整度**: -10%

---

#### 7. 离线支持不完整
```swift
// iOS: LocalStorageManager定义了，但：
- SwiftData模型定义存在
- 数据库操作逻辑缺失
- 同步逻辑不完整
```

**影响**: 离线时应用不可用
**修复成本**: 80小时
**用户体验**: 网络不稳定时卡顿

---

### 🟢 低 - 代码质量问题

#### 8. Token Revocation未实现
```rust
// backend/user-service/src/services/token_revocation.rs
// 文件存在，内容为空
// 定义存在，实现为空
```

**影响**: 用户注销后token仍有效
**修复成本**: 20小时
**安全级别**: 🔴 中等风险

---

#### 9. 缺少输入验证
```rust
// handlers中没有充分的validation
// 例：CreatePostView允许无限长文本
```

**影响**: 缓冲区溢出、XSS等
**修复成本**: 30小时
**安全级别**: 🔴 高风险

---

#### 10. 没有真正的集成测试
```
后端: tests/目录基本为空
iOS: UI tests存在但不运行
```

**影响**: 无法验证端到端流程
**修复成本**: 150小时
**信心指数**: 📉 低

---

## 按模块的技术债务矩阵

```
┌─────────────────────────┬──────────┬────────────────┬──────────┐
│ 模块                     │ 完整度   │ 技术债         │ 优先级   │
├─────────────────────────┼──────────┼────────────────┼──────────┤
│ Authentication          │ 75%      │ OAuth缺失      │ 🔴 高    │
│ Feed Ranking            │ 50%      │ 3重实现        │ 🔴 高    │
│ Recommendation V2       │ 5%       │ 完全缺失       │ 🔴 高    │
│ Video Processing        │ 15%      │ 无生产实现     │ 🔴 高    │
│ Messaging               │ 75%      │ Reactions缺失  │ 🟡 中    │
│ Search                  │ 0%       │ 完全缺失       │ 🔴 高    │
│ Notifications           │ 30%      │ 消费逻辑缺失   │ 🟡 中    │
│ iOS UI                  │ 90%      │ 逻辑不完整     │ 🟡 中    │
│ iOS Network             │ 70%      │ WebSocket缺失  │ 🟡 中    │
│ iOS Local Storage       │ 40%      │ 数据库逻辑缺失 │ 🟡 中    │
└─────────────────────────┴──────────┴────────────────┴──────────┘
```

---

## 按修复难度排序

### 最容易（1-2天）
1. [ ] 删除重复的feed实现（保留feed_ranking.rs）
2. [ ] 完成token_revocation.rs
3. [ ] 添加基础输入验证

### 中等（1-2周）
4. [ ] 实现简单版推荐系统（trending only）
5. [ ] 集成OAuth（Apple必须，Google次要）
6. [ ] 完成消息搜索基础版
7. [ ] 完成视频处理管道的ffmpeg集成

### 困难（2-4周）
8. [ ] 完全重写推荐系统V2
9. [ ] 视频嵌入真实生成（需要TF serving）
10. [ ] 完整的离线支持
11. [ ] 性能调优（达到<200ms延迟）

### 非常困难（4周+）
12. [ ] 完整的A/B测试框架
13. [ ] ONNX模型部署和serving
14. [ ] 分布式追踪和性能监控

---

## 代码债务计分卡

```
代码覆盖率:          ████░░░░░░░░░░░░░░░░░░░░░░░░  15%
文档完整性:          ██████████░░░░░░░░░░░░░░░░░░  35%
测试覆盖率:          ██░░░░░░░░░░░░░░░░░░░░░░░░░░  5%
实现完整度:          ██████░░░░░░░░░░░░░░░░░░░░░░  25%
安全性:              █████░░░░░░░░░░░░░░░░░░░░░░░  20%
性能优化:            ██░░░░░░░░░░░░░░░░░░░░░░░░░░  5%
总体质量:            ████░░░░░░░░░░░░░░░░░░░░░░░░  20%
```

---

## 立即行动清单

### Week 1 (关键路径)
- [ ] 找出所有todo!()宏并标记
- [ ] 创建推荐系统简化版本（基于trending）
- [ ] 删除重复的feed实现
- [ ] 实现Apple OAuth

### Week 2
- [ ] 集成ffmpeg处理
- [ ] 完成消息搜索基础版
- [ ] 添加缺失的input validation
- [ ] 第一批集成测试

### Week 3+
- [ ] 视频嵌入真实生成
- [ ] 性能优化（缓存、查询优化）
- [ ] 完整的iOS WebSocket集成
- [ ] 离线支持

---

## 估算的发货时间表

**如果立即开始修复**:

| 优先级 | 功能 | 时间 | 累计 |
|--------|------|------|------|
| P0 | 删除冲突实现 | 8h | 8h |
| P0 | Trending推荐 | 40h | 48h |
| P0 | OAuth基础 | 30h | 78h |
| P1 | 视频处理基础 | 60h | 138h |
| P1 | Feed性能 | 30h | 168h |
| P1 | 集成测试 | 60h | 228h |
| P2 | 完整推荐算法 | 120h | 348h |
| P2 | 离线支持 | 60h | 408h |
| P3 | 性能优化 | 40h | 448h |

**总计**: 448小时 = 11周（单人）or 3周（4人）

---

## 建议：重新设计vs补丁修复

### 选项A：打补丁修复（短期）
- 优点：快速，能赶上deadline
- 缺点：留下大量债务，后续维护困难
- 成本：现在200小时 + 以后每月20小时维护债务

### 选项B：完整重构（长期）
- 优点：干净的代码，可维护性强
- 缺点：当前需要400小时
- 成本：现在400小时 + 以后每月5小时维护

**建议**: 折中方案
1. 立即修复critical bugs（week 1-2）
2. 实现简化版功能（week 3-4）
3. 逐步重构关键模块（后续）

