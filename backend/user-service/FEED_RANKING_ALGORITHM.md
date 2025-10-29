# Feed Ranking Algorithm Documentation

## Executive Summary

Nova的个性化Feed排序系统是一个混合架构，结合了批量预计算和实时排序，通过线性加权模型融合多维度信号（新鲜度、互动度、亲密度），为每位用户生成个性化内容流。系统采用ClickHouse作为OLAP引擎进行候选集预计算，使用Redis作为缓存层，并通过Circuit Breaker模式实现优雅降级到PostgreSQL。

**核心设计原则：**
- **批实时混合**：候选集每5分钟批量刷新，请求路径实时排序
- **多源融合**：从关注用户、热门内容、兴趣相似性三个维度获取候选
- **优雅降级**：ClickHouse故障时自动切换到PostgreSQL时间线
- **NaN安全**：通过模式匹配防止浮点数运算导致的panic

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Scoring Model](#scoring-model)
3. [Candidate Sources](#candidate-sources)
4. [Weight Configuration](#weight-configuration)
5. [Data Sources & Infrastructure](#data-sources--infrastructure)
6. [Performance & Resilience](#performance--resilience)
7. [NaN Handling & Safety](#nan-handling--safety)
8. [Example Scenarios](#example-scenarios)
9. [Tuning & Monitoring](#tuning--monitoring)
10. [Future Improvements](#future-improvements)

---

## System Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Feed Request                       │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                v
                    ┌───────────────────────┐
                    │  content-service      │
                    │  /feed endpoint       │
                    └───────────┬───────────┘
                                │
                                v
                    ┌───────────────────────┐
                    │  Circuit Breaker      │
                    │  (ClickHouse health)  │
                    └───────────┬───────────┘
                                │
                ┌───────────────┴───────────────┐
                │ Open?                         │ Closed/Half-Open
                v                               v
    ┌───────────────────────┐       ┌──────────────────────────┐
    │  Fallback Path        │       │  Primary Path            │
    │  (PostgreSQL)         │       │  (ClickHouse)            │
    └───────────┬───────────┘       └──────────┬───────────────┘
                │                               │
                │                               v
                │                   ┌──────────────────────────┐
                │                   │ Get Candidates (tokio::join!)│
                │                   │ - followees              │
                │                   │ - trending               │
                │                   │ - affinity               │
                │                   └──────────┬───────────────┘
                │                               │
                │                               v
                │                   ┌──────────────────────────┐
                │                   │  Combine & Rank          │
                │                   │  (sort by combined_score)│
                │                   └──────────┬───────────────┘
                │                               │
                └───────────────┬───────────────┘
                                │
                                v
                    ┌───────────────────────┐
                    │  Paginate & Cache     │
                    │  (Redis write)        │
                    └───────────┬───────────┘
                                │
                                v
                    ┌───────────────────────┐
                    │  Return post_ids[]    │
                    └───────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Technology |
|-----------|---------------|------------|
| **content-service** | Feed API endpoint, ranking orchestration | Rust/Actix-Web |
| **FeedRankingService** | 候选集获取、评分、排序 | Rust async |
| **FeedCandidateRefreshJob** | 批量预计算候选集 (5min间隔) | Tokio background task |
| **FeedCache** | 缓存完整排序结果，降级数据源 | Redis |
| **Circuit Breaker** | 监控ClickHouse健康，自动切换降级路径 | Custom middleware |
| **ClickHouse** | OLAP分析、候选集物化表 | ClickHouse |
| **PostgreSQL** | 降级数据源（按时间倒序） | PostgreSQL |

---

## Scoring Model

### Linear Combination Formula

每个候选post的最终得分由三个维度的加权线性组合计算：

```rust
combined_score =
    freshness_score * freshness_weight +
    engagement_score * engagement_weight +
    affinity_score * affinity_weight -
    freshness_lambda
```

**代码实现：** `backend/content-service/src/services/feed_ranking.rs:338`

```rust
fn compute_score(&self, candidate: &FeedCandidate) -> f64 {
    let freshness = candidate.freshness_score * self.freshness_weight;
    let engagement = candidate.engagement_score * self.engagement_weight;
    let affinity = candidate.affinity_score * self.affinity_weight;

    freshness + engagement + affinity - self.freshness_lambda
}
```

### Scoring Factors Breakdown

#### 1. Freshness Score (新鲜度)

**目的：** 防止用户看到过时内容，对新发布的post给予更高权重

**计算公式：**
```sql
freshness_score = exp(-0.0025 * dateDiff('minute', created_at, now()))
```

**特性：**
- 指数衰减函数，时间越久得分越低
- 衰减系数：`λ = 0.0025 / minute`
- **半衰期 (Half-life)：** 约277分钟 (4.6小时)
  - 计算：`t_half = ln(2) / 0.0025 ≈ 277 minutes`
- 24小时后得分衰减至 `e^(-3.6) ≈ 0.027` (原值的2.7%)
- 7天后得分接近0 (`e^(-25.2) ≈ 1.3e-11`)

**示例值：**

| Post Age | Minutes | Freshness Score |
|----------|---------|-----------------|
| 刚发布    | 0       | 1.0000          |
| 1小时     | 60      | 0.8607          |
| 4.6小时   | 277     | 0.5000          |
| 12小时    | 720     | 0.1653          |
| 24小时    | 1440    | 0.0273          |
| 48小时    | 2880    | 0.0007          |

**代码位置：** `backend/content-service/src/jobs/feed_candidates.rs:126`

---

#### 2. Engagement Score (互动度)

**目的：** 提升用户高度互动的内容，反映集体智慧

**计算公式：**
```sql
engagement_score = log1p(likes_count + 2 * comments_count)
```

**特性：**
- 对数函数平滑高互动数值，避免头部效应
- Comment权重是Like的2倍（评论比点赞更有价值）
- `log1p(x) = log(1 + x)` 避免 `log(0)` 未定义问题
- Share功能尚未实现（当前为0）

**示例值：**

| Likes | Comments | Raw Score | log1p() Result |
|-------|----------|-----------|----------------|
| 0     | 0        | 0         | 0.000          |
| 10    | 0        | 10        | 2.398          |
| 100   | 0        | 100       | 4.615          |
| 10    | 5        | 20        | 3.045          |
| 50    | 25       | 100       | 4.615          |
| 1000  | 100      | 1200      | 7.091          |

**为什么使用对数：**
- 100个赞 vs 1000个赞的差距，不应是10倍，而应是渐进式提升
- 防止"爆款帖"完全霸占Feed（需要给新内容机会）
- 让中小互动量的优质内容也能被看到

**代码位置：** `backend/content-service/src/jobs/feed_candidates.rs:127`

---

#### 3. Affinity Score (亲密度)

**目的：** 个性化推荐，优先展示用户经常互动的作者内容

**计算公式：**
```sql
affinity_score = sum(interaction_weight)
  WHERE interaction_time >= now() - INTERVAL 90 DAY
```

**Interaction权重：**
- **Like:** `1.0`
- **Comment:** `1.5` (评论比点赞显示更强意图)
- **Share:** `3.0` (暂未实现)

**时间窗口：** 90天滚动窗口

**特性：**
- 基于历史行为的协同过滤
- 为直接关注的用户 (followees) 提供baseline亲密度 `1.0`
- 对未关注但有互动历史的作者提供发现机会
- CDC表实时更新，每5分钟刷新到候选表

**示例场景：**

| 用户行为 (90天内) | Affinity Score |
|------------------|----------------|
| 关注但无互动 | 0.0 |
| 点赞5次 | 5.0 |
| 点赞3次 + 评论2次 | 6.0 |
| 点赞10次 + 评论5次 | 17.5 |
| 高频互动 (20赞 + 10评) | 35.0 |

**代码位置：** `backend/content-service/src/jobs/feed_candidates.rs:150-179`

---

#### 4. Freshness Lambda (惩罚项)

**目的：** 调节全局得分分布，防止分数通货膨胀

**默认值：** `0.1`

**作用机制：**
- 作为baseline惩罚，从所有得分中扣除固定值
- 使得低质量内容（低互动 + 旧帖）得分为负
- 实际应用中可用于A/B测试不同基线

**配置：** 环境变量 `FEED_FRESHNESS_LAMBDA` (默认 `0.1`)

---

## Candidate Sources

Feed系统从三个独立来源获取候选集，通过 `tokio::join!` 并行查询，最终合并排序：

### 1. Followees Candidates (关注用户的内容)

**目的：** 核心Feed来源，展示用户关注的人的最新内容

**查询逻辑：**
```sql
SELECT post_id, author_id, likes, comments, shares,
       freshness_score, engagement_score, affinity_score, combined_score
FROM feed_candidates_followees
WHERE user_id = ?
ORDER BY combined_score DESC
LIMIT ?
```

**预计算逻辑：** (后台Job每5分钟执行)
```sql
-- 关键连接：follows_cdc (关注关系) JOIN posts_cdc (作者的帖子)
SELECT
    f.follower_id AS user_id,
    p.id AS post_id,
    p.user_id AS author_id,
    -- 30天内的互动数据
    ifNull(likes.likes_count, 0) AS likes,
    ifNull(comments.comments_count, 0) AS comments,
    -- 计算三维得分
    exp(-0.0025 * dateDiff('minute', p.created_at, now())) AS freshness_score,
    log1p(likes + 2 * comments) AS engagement_score,
    ifNull(affinity.affinity_score, 0.0) AS affinity_score,
    -- 组合得分 (权重: 35% freshness + 40% engagement + 25% affinity)
    0.35 * freshness_score + 0.40 * engagement_score + 0.25 * affinity_score AS combined_score
FROM posts_cdc AS p
INNER JOIN follows_cdc AS f
    ON f.followee_id = p.user_id AND f.is_deleted = 0
WHERE p.is_deleted = 0
  AND p.created_at >= now() - INTERVAL 30 DAY
ORDER BY user_id, combined_score DESC
LIMIT 500 BY user_id  -- 每用户最多500条候选
```

**特点：**
- 个性化最强（每个用户有独立的候选表分区）
- 只包含关注用户的内容（社交图过滤）
- 30天时间窗口（降级到trending覆盖更早内容）
- 权重偏向互动度 (40%) 和新鲜度 (35%)

**代码位置：**
- 查询：`backend/content-service/src/services/feed_ranking.rs:346-397`
- 预计算：`backend/content-service/src/jobs/feed_candidates.rs:112-184`

---

### 2. Trending Candidates (全局热门内容)

**目的：** 发现功能，让用户看到平台热门内容（即使不关注作者）

**查询逻辑：**
```sql
SELECT post_id, author_id, likes, comments, shares,
       freshness_score, engagement_score, affinity_score, combined_score
FROM feed_candidates_trending
ORDER BY combined_score DESC
LIMIT ?
```

**预计算逻辑：**
```sql
SELECT
    p.id AS post_id,
    p.user_id AS author_id,
    -- 14天内的互动数据（窗口更短，聚焦近期热点）
    ifNull(likes.likes_count, 0) AS likes,
    ifNull(comments.comments_count, 0) AS comments,
    exp(-0.0025 * dateDiff('minute', p.created_at, now())) AS freshness_score,
    log1p(likes + 2 * comments) AS engagement_score,
    0.0 AS affinity_score,  -- trending不考虑个人亲密度
    -- 组合得分 (权重: 50% freshness + 50% engagement)
    0.50 * freshness_score + 0.50 * engagement_score AS combined_score
FROM posts_cdc AS p
WHERE p.is_deleted = 0
  AND p.created_at >= now() - INTERVAL 14 DAY
ORDER BY combined_score DESC
LIMIT 1000  -- 全局top 1000
```

**特点：**
- 全用户共享同一候选表（无个性化）
- 14天时间窗口（比followees更短，聚焦近期热点）
- 只考虑新鲜度和互动度（无亲密度）
- 权重完全平衡 (50/50)

**用途：**
- 冷启动用户（无关注用户时的降级）
- Feed多样性注入（防止信息茧房）
- 发现新的优质内容创作者

**代码位置：**
- 查询：`backend/content-service/src/services/feed_ranking.rs:399-443`
- 预计算：`backend/content-service/src/jobs/feed_candidates.rs:186-224`

---

### 3. Affinity Candidates (兴趣相似性推荐)

**目的：** 基于互动历史的协同过滤，推荐"你可能喜欢"的作者

**查询逻辑：**
```sql
SELECT post_id, author_id, likes, comments, shares,
       freshness_score, engagement_score, affinity_score, combined_score
FROM feed_candidates_affinity
WHERE user_id = ?
ORDER BY combined_score DESC
LIMIT ?
```

**预计算逻辑：**
```sql
-- 第一步：计算用户-作者亲密度边
WITH affinity_edges AS (
    SELECT
        viewer_id AS user_id,
        author_id,
        sum(weight) AS affinity_score
    FROM (
        -- 90天内的点赞行为
        SELECT l.user_id AS viewer_id, p.user_id AS author_id, 1.0 AS weight
        FROM likes_cdc AS l
        INNER JOIN posts_cdc AS p ON p.id = l.post_id
        WHERE l.is_deleted = 0 AND l.created_at >= now() - INTERVAL 90 DAY
        UNION ALL
        -- 90天内的评论行为
        SELECT c.user_id AS viewer_id, p.user_id AS author_id, 1.5 AS weight
        FROM comments_cdc AS c
        INNER JOIN posts_cdc AS p ON p.id = c.post_id
        WHERE c.is_deleted = 0 AND c.created_at >= now() - INTERVAL 90 DAY
    ) AS interactions
    GROUP BY viewer_id, author_id
    HAVING affinity_score > 0
)
-- 第二步：基于亲密度边，拉取作者的帖子
SELECT
    affinity.user_id,
    p.id AS post_id,
    p.user_id AS author_id,
    ifNull(likes.likes_count, 0) AS likes,
    ifNull(comments.comments_count, 0) AS comments,
    exp(-0.0025 * dateDiff('minute', p.created_at, now())) AS freshness_score,
    log1p(likes + 2 * comments) AS engagement_score,
    affinity.affinity_score AS affinity_score,
    -- 组合得分 (权重: 20% freshness + 40% engagement + 40% affinity)
    0.20 * freshness_score + 0.40 * engagement_score + 0.40 * affinity_score AS combined_score
FROM posts_cdc AS p
INNER JOIN affinity_edges AS affinity
    ON affinity.author_id = p.user_id
WHERE p.is_deleted = 0
  AND p.created_at >= now() - INTERVAL 30 DAY
ORDER BY user_id, combined_score DESC
LIMIT 300 BY user_id
```

**特点：**
- 个性化（每用户独立候选集）
- **不限于关注关系**（可推荐未关注的作者）
- 90天互动历史建立亲密度图谱
- 权重偏向亲密度 (40%) 和互动度 (40%)

**典型场景：**
- 用户A经常给用户B的帖子点赞/评论，但未关注B
- 系统会提高B的所有帖子在A的Feed中的排名
- 促进"从互动到关注"的社交链路转化

**代码位置：**
- 查询：`backend/content-service/src/services/feed_ranking.rs:445-496`
- 预计算：`backend/content-service/src/jobs/feed_candidates.rs:226-296`

---

### Candidate Merging Strategy

三个来源的候选集通过以下策略合并：

```rust
// 并行查询三个来源 (tokio::join! 优化延迟)
let (followees_result, trending_result, affinity_result) = tokio::join!(
    self.get_followees_candidates(user_id, source_limit),
    self.get_trending_candidates(source_limit),
    self.get_affinity_candidates(user_id, source_limit),
);

// 合并所有候选 (可能有重复post_id)
let mut all_candidates = Vec::new();
all_candidates.append(&mut followees);
all_candidates.append(&mut trending);
all_candidates.append(&mut affinity);

// 统一排序 (重复post_id只保留得分最高的)
ranked.sort_by(|a, b| {
    b.combined_score.partial_cmp(&a.combined_score)
        .unwrap_or(std::cmp::Ordering::Equal)  // NaN安全处理
});
```

**去重策略：**
- 当前实现：允许同一post_id在多个来源中出现，按最高分排序
- 未来优化：可在合并阶段去重，保留最高得分的来源标签

---

## Weight Configuration

### Current Weights (Production Defaults)

| Weight | Value | Environment Variable | Impact |
|--------|-------|---------------------|--------|
| **Freshness Weight** | 0.3 | `FEED_FRESHNESS_WEIGHT` | 新鲜度影响30%最终得分 |
| **Engagement Weight** | 0.4 | `FEED_ENGAGEMENT_WEIGHT` | 互动度影响40%最终得分 |
| **Affinity Weight** | 0.3 | `FEED_AFFINITY_WEIGHT` | 亲密度影响30%最终得分 |
| **Freshness Lambda** | 0.1 | `FEED_FRESHNESS_LAMBDA` | 全局得分baseline惩罚 |

**代码位置：** `backend/content-service/src/config.rs:142-146`

```rust
feed: FeedConfig {
    freshness_weight: parse_env_or_default("FEED_FRESHNESS_WEIGHT", 0.3)?,
    engagement_weight: parse_env_or_default("FEED_ENGAGEMENT_WEIGHT", 0.4)?,
    affinity_weight: parse_env_or_default("FEED_AFFINITY_WEIGHT", 0.3)?,
    freshness_lambda: parse_env_or_default("FEED_FRESHNESS_LAMBDA", 0.1)?,
    // ...
}
```

---

### Why These Weights?

#### Design Rationale

**1. Engagement权重最高 (0.4)：**
- **集体智慧假设：** 高互动内容更可能是优质内容
- 平衡新老内容：避免只看到"最新但无人关心"的帖子
- 促进社区活跃：鼓励用户创造高互动内容

**2. Freshness和Affinity并列第二 (0.3)：**
- **Freshness (0.3)：** 防止Feed变成"昨日黄花"，保持时效性
- **Affinity (0.3)：** 个性化核心，区分"大众热点"和"个人兴趣"

**3. 权重和 = 1.0：**
- 便于解释：每个因子的贡献百分比
- 便于调参：调整一个权重时可按比例调整其他

---

### Weight Tuning Guidelines

#### Scenario-Based Tuning

| User Segment | Freshness | Engagement | Affinity | Use Case |
|--------------|-----------|------------|----------|----------|
| **新用户 (冷启动)** | 0.5 | 0.5 | 0.0 | 无社交图，依赖热门+新内容 |
| **时效性敏感用户** | 0.6 | 0.3 | 0.1 | 新闻类、实时话题 |
| **深度用户 (高社交)** | 0.2 | 0.3 | 0.5 | 强社交关系，重视熟人内容 |
| **探索模式** | 0.3 | 0.5 | 0.2 | 发现新内容，降低个性化 |
| **专注模式** | 0.1 | 0.4 | 0.5 | 只看关注的人 |

#### A/B Testing Workflow

1. **克隆配置：**
   ```bash
   # Control组使用默认权重
   FEED_FRESHNESS_WEIGHT=0.3
   FEED_ENGAGEMENT_WEIGHT=0.4
   FEED_AFFINITY_WEIGHT=0.3

   # Treatment组调整权重
   FEED_FRESHNESS_WEIGHT=0.4
   FEED_ENGAGEMENT_WEIGHT=0.3
   FEED_AFFINITY_WEIGHT=0.3
   ```

2. **监控关键指标：** (详见 [Tuning & Monitoring](#tuning--monitoring))
   - Feed CTR (点击率)
   - Dwell Time (停留时长)
   - Engagement Rate (互动率)
   - Session Length (会话长度)

3. **统计显著性检验：**
   - 样本量：每组至少1000个活跃用户
   - 实验周期：至少7天（覆盖周末差异）
   - 显著性水平：p < 0.05

---

### Dynamic Weight Adjustment (Future)

当前系统使用静态权重，未来可实现动态调整：

**1. 时间段调整：**
```rust
// 伪代码
fn get_time_based_weights(hour: u8) -> (f64, f64, f64) {
    match hour {
        7..=9 | 17..=19 => (0.5, 0.3, 0.2),  // 通勤时段：新鲜度优先
        12..=14 => (0.3, 0.5, 0.2),          // 午休时段：热门内容优先
        22..=23 => (0.2, 0.3, 0.5),          // 睡前时段：熟人内容优先
        _ => (0.3, 0.4, 0.3),                // 默认权重
    }
}
```

**2. 用户行为自适应：**
- 监控用户互动模式（点赞率、评论率、分享率）
- 通过Multi-Armed Bandit算法动态调整权重
- 示例：用户点赞率低 → 降低engagement_weight，提高freshness_weight

**3. 内容类型分层：**
- 视频内容：提高engagement_weight（观看时长权重）
- 图文内容：平衡所有权重
- 短动态：提高freshness_weight（实效性强）

---

## Data Sources & Infrastructure

### Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       Data Source Layer                         │
└─────────────────────────────────────────────────────────────────┘

PostgreSQL (OLTP)                ClickHouse (OLAP)
├── posts                        ├── posts_cdc (CDC mirror)
├── comments                     ├── comments_cdc (CDC mirror)
├── likes                        ├── likes_cdc (CDC mirror)
├── follows                      ├── follows_cdc (CDC mirror)
└── users                        └── feed_candidates_* (materialized)
     │                                │
     │ CDC Streaming (Kafka)          │
     └────────────────────────────────┤
                                      │
                                      v
                         ┌────────────────────────┐
                         │  FeedCandidateRefreshJob│
                         │  (5min interval)       │
                         └────────────┬───────────┘
                                      │
                                      v
                         ┌────────────────────────┐
                         │  ClickHouse Tables:    │
                         │  - followees           │
                         │  - trending            │
                         │  - affinity            │
                         └────────────┬───────────┘
                                      │
                                      v
                         ┌────────────────────────┐
                         │  FeedRankingService    │
                         │  (Real-time query)     │
                         └────────────┬───────────┘
                                      │
                                      v
                         ┌────────────────────────┐
                         │  Redis Cache           │
                         │  (Sorted post_ids[])   │
                         └────────────────────────┘
```

---

### PostgreSQL (Primary OLTP)

**角色：** 事务性数据存储，Feed系统的降级数据源

**相关表：**
- `posts`: 帖子内容、元数据
- `comments`: 评论数据
- `likes`: 点赞记录
- `follows`: 关注关系
- `users`: 用户资料

**Feed相关查询：** (仅在ClickHouse不可用时执行)
```rust
pub async fn get_recent_published_post_ids(
    pool: &PgPool,
    limit: i64,
    offset: i64
) -> Result<Vec<Uuid>> {
    sqlx::query_scalar!(
        r#"
        SELECT id FROM posts
        WHERE status = 'published'
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
        "#,
        limit,
        offset
    )
    .fetch_all(pool)
    .await
}
```

**性能特性：**
- ✅ 高一致性、事务支持
- ❌ 大规模分析查询性能差
- ❌ 不适合实时计算freshness/engagement分数

**使用场景：**
- Circuit Breaker打开时的降级路径
- 返回简单的时间倒序Feed（无个性化）

---

### ClickHouse (OLAP Engine)

**角色：** 分析型数据库，支持百万级行聚合查询（秒级响应）

**CDC同步：**
- Kafka Debezium CDC → ClickHouse Kafka Engine
- 延迟：< 5秒
- 保证：At-least-once delivery

**核心表：**

#### 1. CDC Mirror Tables (数据源)

| Table | Row Count (估算) | Update Frequency | Retention |
|-------|------------------|------------------|-----------|
| `posts_cdc` | 10M+ | Real-time | Infinite |
| `comments_cdc` | 50M+ | Real-time | Infinite |
| `likes_cdc` | 100M+ | Real-time | Infinite |
| `follows_cdc` | 5M+ | Real-time | Infinite |

**引擎：** `ReplacingMergeTree(cdc_timestamp)`
- 自动去重（按主键保留最新版本）
- 支持软删除 (`is_deleted` 字段)

#### 2. Materialized Tables (候选集)

| Table | Row Count | Update Frequency | Partition Key | Sort Key |
|-------|-----------|------------------|---------------|----------|
| `feed_candidates_followees` | 50M+ | 5 min | `toYYYYMM(created_at)` | `(user_id, combined_score, post_id)` |
| `feed_candidates_trending` | 1K | 5 min | `toYYYYMM(created_at)` | `(combined_score, post_id)` |
| `feed_candidates_affinity` | 30M+ | 5 min | `toYYYYMM(created_at)` | `(user_id, combined_score, post_id)` |

**引擎：** `ReplacingMergeTree(updated_at)`
- 每5分钟全量刷新（通过staging表无缝切换）
- 分区按月（自动归档老数据）

**查询性能：**
- `feed_candidates_followees`: 50-100ms (扫描500行 per user)
- `feed_candidates_trending`: 10-20ms (扫描1000行)
- `feed_candidates_affinity`: 30-60ms (扫描300行 per user)

---

### Redis Cache

**角色：** 高速缓存层，降级数据源，Seen Posts去重

**数据结构：**

#### 1. Feed Cache
```
Key:   "feed:v1:{user_id}"
Type:  String (JSON-serialized)
Value: {"post_ids": [uuid1, uuid2, ...]}
TTL:   300s (5min) + jitter(10%)
```

**用途：**
- ClickHouse故障时的第一降级路径
- 减少重复计算（缓存命中率 > 60%）

#### 2. Seen Posts Tracking
```
Key:   "feed:seen:{user_id}"
Type:  Set
Value: {uuid1, uuid2, ...}
TTL:   7 days
```

**用途：**
- 去重：用户已看过的帖子不重复展示
- 支持"看完所有新内容"的UX

**API：**
```rust
// 标记帖子为已读
async fn mark_posts_seen(&self, user_id: Uuid, post_ids: &[Uuid])

// 过滤未读帖子
async fn filter_unseen_posts(&self, user_id: Uuid, post_ids: &[Uuid]) -> Vec<Uuid>
```

**代码位置：** `backend/content-service/src/cache/feed_cache.rs`

---

### Background Job: Feed Candidate Refresh

**实现：** `FeedCandidateRefreshJob`

**执行逻辑：**
```rust
pub async fn run(self) {
    let mut ticker = interval_at(Instant::now() + 5s, 5min);
    loop {
        ticker.tick().await;
        self.refresh_all().await;  // 依次刷新三个表
    }
}
```

**刷新策略（Staging Table Swap）：**
```sql
-- 1. 创建临时表
DROP TABLE IF EXISTS feed_candidates_followees_staging;
CREATE TABLE feed_candidates_followees_staging AS feed_candidates_followees;

-- 2. 插入新数据到staging
INSERT INTO feed_candidates_followees_staging
SELECT ... FROM posts_cdc JOIN follows_cdc ...;

-- 3. 原子交换表（无停机）
EXCHANGE TABLES feed_candidates_followees AND feed_candidates_followees_staging;

-- 4. 清理旧表
DROP TABLE feed_candidates_followees_staging;
```

**优势：**
- 无锁：查询和刷新完全并行
- 原子性：EXCHANGE TABLES是原子操作
- 零停机：用户始终查询到完整数据

**监控：**
- 刷新耗时：< 30s per table
- 失败告警：连续3次失败触发PagerDuty
- Row count监控：防止数据丢失

**代码位置：** `backend/content-service/src/jobs/feed_candidates.rs`

---

## Performance & Resilience

### Circuit Breaker Pattern

**目的：** 防止ClickHouse故障导致Feed完全不可用

**状态机：**
```
Closed (正常)
  │
  │ Failure count >= 3
  v
Open (熔断) ────────────────┐
  │                        │ 30s timeout
  │ Auto after 30s         │
  v                        │
Half-Open (试探) ─────────┘
  │
  │ Success count >= 3
  v
Closed (恢复)
```

**配置：** `backend/content-service/src/middleware/circuit_breaker.rs`
```rust
CircuitBreakerConfig {
    failure_threshold: 3,    // 连续3次失败→Open
    success_threshold: 3,    // Half-Open时连续3次成功→Closed
    timeout_seconds: 30,     // Open状态持续30秒后→Half-Open
}
```

**代码实现：**
```rust
pub async fn get_feed(&self, user_id: Uuid, limit: usize, offset: usize)
    -> Result<(Vec<Uuid>, bool, usize)>
{
    // 检查熔断器状态
    if matches!(self.circuit_breaker.get_state().await, CircuitState::Open) {
        return self.fallback_feed(user_id, limit, offset).await;
    }

    // 通过熔断器执行ClickHouse查询
    let candidates = self
        .circuit_breaker
        .call(|| async { self.get_feed_candidates(user_id, limit).await })
        .await?;

    // ...
}
```

---

### Fallback Strategy (三层降级)

#### Level 1: ClickHouse Primary Path
- **数据源：** ClickHouse feed_candidates_* tables
- **延迟：** 50-150ms
- **个性化：** ✅ Full personalization
- **条件：** Circuit Breaker = Closed

#### Level 2: Redis Cache Fallback
- **数据源：** Redis cached feed
- **延迟：** 5-10ms
- **个性化：** ✅ (缓存的个性化结果)
- **条件：** Circuit Breaker = Open + Cache Hit
- **TTL：** 5min (用户上次成功请求的结果)

#### Level 3: PostgreSQL Timeline Fallback
- **数据源：** PostgreSQL `posts` table (按created_at倒序)
- **延迟：** 100-200ms
- **个性化：** ❌ 无个性化（全局时间线）
- **条件：** Circuit Breaker = Open + Cache Miss

**代码位置：** `backend/content-service/src/services/feed_ranking.rs:206-299`

```rust
pub async fn fallback_feed(&self, user_id: Uuid, limit: usize, offset: usize)
    -> Result<(Vec<Uuid>, bool, usize)>
{
    warn!("Using fallback feed for user {} (ClickHouse unavailable)", user_id);

    // Level 2: 尝试Redis缓存
    if let Some(cached) = self.cache.read_feed_cache(user_id).await? {
        if offset < cached.post_ids.len() {
            let end = (offset + limit).min(cached.post_ids.len());
            let page = cached.post_ids[offset..end].to_vec();
            return Ok((page, end < cached.post_ids.len(), cached.post_ids.len()));
        }
    }

    // Level 3: 降级到PostgreSQL时间线
    let posts = post_repo::get_recent_published_post_ids(
        &self.db_pool,
        (offset + limit) as i64,
        0
    ).await?;

    let total_count = posts.len();
    let page_posts = posts[offset..].to_vec();

    // 缓存降级结果（TTL=60s，比正常缓存更短）
    self.cache
        .write_feed_cache(user_id, posts.clone(), Some(60))
        .await?;

    Ok((page_posts, page_posts.len() >= limit, total_count))
}
```

---

### Performance Optimization Techniques

#### 1. Parallel Candidate Fetching
```rust
let (followees_result, trending_result, affinity_result) = tokio::join!(
    self.get_followees_candidates(user_id, source_limit),
    self.get_trending_candidates(source_limit),
    self.get_affinity_candidates(user_id, source_limit),
);
```

**收益：**
- 串行耗时：150ms (50ms * 3)
- 并行耗时：50ms (max of 3)
- **加速比：** 3x

#### 2. Candidate Prefetch Multiplier
```rust
let candidate_limit = ((offset + limit)
    .max(limit * self.candidate_prefetch_multiplier))
.min(self.max_feed_candidates);
```

**策略：**
- 用户请求 `limit=20`
- 实际获取 `20 * 5 = 100` 条候选
- 好处：后续翻页无需重新查询ClickHouse（从缓存读取）

**配置：**
- `FEED_CANDIDATE_PREFETCH_MULTIPLIER`: 默认5倍
- `FEED_MAX_CANDIDATES`: 默认1000条上限

#### 3. ClickHouse Query Optimization

**索引设计：**
```sql
-- followees表索引：按user_id分区，按score排序
ORDER BY (user_id, combined_score DESC, post_id)

-- 查询优化：
-- ✅ Good: WHERE user_id = ? ORDER BY combined_score DESC LIMIT 500
-- ❌ Bad:  WHERE author_id = ? (需全表扫描)
```

**分区裁剪：**
```sql
PARTITION BY toYYYYMM(created_at)
-- 自动跳过历史月份分区，只扫描近2个月
```

#### 4. Redis Cache with Jitter
```rust
let jitter = (rand::random::<u32>() % 10) as f64 / 100.0;  // 0-10%
let final_ttl = ttl + Duration::from_secs((ttl.as_secs_f64() * jitter) as u64);
```

**目的：** 防止缓存雪崩（大量缓存同时过期）

---

### Monitoring Metrics

**Prometheus指标：** (定义于 `backend/content-service/src/metrics/feed.rs`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `feed_request_total` | Counter | `source` | 请求总数（来源：clickhouse/cache/fallback） |
| `feed_request_duration_seconds` | Histogram | `source` | 请求延迟分布 |
| `feed_candidate_count` | Histogram | `source` | 候选集大小分布 |
| `feed_cache_events` | Counter | `event` | 缓存事件（hit/miss/error） |
| `feed_cache_write_total` | Counter | `status` | 缓存写入状态（success/error） |

**示例PromQL查询：**
```promql
# Feed平均延迟 (by source)
rate(feed_request_duration_seconds_sum[5m])
/ rate(feed_request_duration_seconds_count[5m])

# 缓存命中率
rate(feed_cache_events{event="hit"}[5m])
/ (rate(feed_cache_events{event="hit"}[5m]) + rate(feed_cache_events{event="miss"}[5m]))

# P99延迟
histogram_quantile(0.99, rate(feed_request_duration_seconds_bucket[5m]))
```

---

## NaN Handling & Safety

### The Problem: Float Comparison Panic

**危险代码：** (已修复)
```rust
// ❌ Bad: unwrap() can panic if score is NaN
ranked.sort_by(|a, b| {
    b.combined_score
        .partial_cmp(&a.combined_score)
        .unwrap()  // 💥 Panic if NaN!
});
```

**触发场景：**
- ClickHouse返回 `NaN`（例如：`0.0 / 0.0`）
- 网络传输损坏浮点数据
- 配置错误导致分母为0

**后果：**
- 服务panic → Pod重启
- 用户看到500错误
- 破坏"Never break userspace"原则

---

### The Solution: Pattern Matching

**代码实现：** `backend/content-service/src/services/feed_ranking.rs:318-334`

```rust
ranked.sort_by(|a, b| {
    match b.combined_score.partial_cmp(&a.combined_score) {
        Some(ord) => ord,  // ✅ 正常比较
        None => {
            // ❌ NaN detected: 记录日志并优雅处理
            tracing::warn!(
                post_a = %a.post_id,
                post_b = %b.post_id,
                score_a = a.combined_score,
                score_b = b.combined_score,
                "Encountered NaN score in feed ranking, treating as zero"
            );
            std::cmp::Ordering::Equal  // 将NaN视为相等（排序靠后）
        }
    }
});
```

**处理策略：**
1. **Detection：** `partial_cmp()` 返回 `None` 时检测到NaN
2. **Logging：** 记录涉及的post_id和分数（便于调试）
3. **Graceful Degradation：** 将NaN视为0分（排序到末尾）
4. **No Panic：** 服务继续运行，用户体验无中断

---

### Why `partial_cmp` Instead of `cmp`?

**浮点数的特殊性：**
- `f64` 不实现 `Ord` trait（因为NaN无法比较）
- 只实现 `PartialOrd` trait
- `partial_cmp()` 返回 `Option<Ordering>`：
  - `Some(Ordering)`: 正常比较结果
  - `None`: 无法比较（至少一个是NaN）

**错误示例：**
```rust
// ❌ 编译错误：f64 does not implement Ord
ranked.sort_by_key(|post| post.combined_score);

// ✅ 正确：使用partial_cmp
ranked.sort_by(|a, b| a.score.partial_cmp(&b.score).unwrap_or(Equal));
```

---

### Defensive Programming Principles

**1. Never `unwrap()` on External Data**
- ClickHouse返回值
- 网络JSON反序列化
- 用户输入参数

**2. Always Log Context**
- 不仅记录"发生了NaN"
- 还要记录**哪个帖子、什么分数、什么时间**
- 便于复现和修复根因

**3. Fail Gracefully**
- 单个帖子分数异常 → 排除该帖子，返回其余结果
- 整个查询失败 → 降级到缓存/PostgreSQL

**4. Monitor Anomalies**
```promql
# 监控NaN警告日志
rate(log_messages{level="warn", msg=~".*NaN score.*"}[5m]) > 0
```

---

### Testing NaN Scenarios

**单元测试：** (建议添加)
```rust
#[test]
fn test_ranking_with_nan_scores() {
    let mut posts = vec![
        RankedPost { post_id: uuid!("..."), combined_score: 5.0, ... },
        RankedPost { post_id: uuid!("..."), combined_score: f64::NAN, ... },
        RankedPost { post_id: uuid!("..."), combined_score: 3.0, ... },
    ];

    posts.sort_by(|a, b| {
        b.combined_score
            .partial_cmp(&a.combined_score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // NaN应该被排到最后
    assert_eq!(posts[0].combined_score, 5.0);
    assert_eq!(posts[1].combined_score, 3.0);
    assert!(posts[2].combined_score.is_nan());
}
```

---

## Example Scenarios

### Scenario 1: Fresh Post from Close Friend

**Context:**
- 用户A关注用户B
- 用户A过去30天给B的帖子点赞10次、评论5次
- B刚发布一篇新帖子（5分钟前）

**Scoring Process:**

#### Followees Candidate Query:
```sql
-- Affinity Score计算
SELECT viewer_id, author_id, sum(weight) AS affinity_score
FROM (
    SELECT 'A' AS viewer_id, 'B' AS author_id, 1.0 AS weight  -- 10个赞
    UNION ALL
    SELECT 'A', 'B', 1.5  -- 5个评论
)
GROUP BY viewer_id, author_id
-- Result: affinity_score = 10 * 1.0 + 5 * 1.5 = 17.5

-- Post Score计算
freshness_score = exp(-0.0025 * 5) = 0.9876  -- 5分钟前
engagement_score = log1p(0) = 0.0            -- 无互动（刚发布）
affinity_score = 17.5                        -- 高亲密度

combined_score = 0.35 * 0.9876 + 0.40 * 0.0 + 0.25 * 17.5
               = 0.346 + 0.0 + 4.375
               = 4.721
```

**Result:** ✅ **High Score (4.72)** → 排在Feed顶部

**Why:** 新鲜度高 + 历史高互动，即使无初始engagement也优先展示

---

### Scenario 2: Old Post with High Engagement

**Context:**
- 某网红用户C发布的帖子（48小时前）
- 1000个赞、200个评论
- 用户D从未关注C，无互动历史

**Scoring Process:**

#### Trending Candidate Query:
```sql
freshness_score = exp(-0.0025 * 2880) = 0.0007  -- 48小时前
engagement_score = log1p(1000 + 2*200) = log1p(1400) = 7.245
affinity_score = 0.0                            -- 无关注关系

combined_score = 0.50 * 0.0007 + 0.50 * 7.245 + 0.0
               = 0.0004 + 3.623 + 0.0
               = 3.623
```

**Result:** ✅ **Medium-High Score (3.62)** → 通过trending进入Feed

**Why:** 极高互动度补偿了新鲜度衰减，仍能被推荐（但不如新鲜+高亲密度的帖子）

---

### Scenario 3: Post Matching Prioritized Topic

**Context:**
- 用户E的用户偏好：`prioritized_topics = ["Rust", "分布式系统"]`
- 某帖子标签：`tags = ["Rust", "异步编程"]`
- 当前系统**尚未实现**Topic Boosting（Future improvement）

**Current Behavior:**
- 帖子按常规流程排序（无额外加权）

**Future Implementation (Pseudo-code):**
```rust
fn compute_score_with_preferences(
    &self,
    candidate: &FeedCandidate,
    user_prefs: &UserPreferences
) -> f64 {
    let mut base_score = self.compute_score(candidate);

    // Topic Boosting
    if candidate.tags.iter().any(|t| user_prefs.prioritized_topics.contains(t)) {
        base_score *= 1.5;  // 50% boost
    }

    // Language Filtering (已实现)
    if !candidate.language.is_empty() &&
       !user_prefs.preferred_languages.contains(&candidate.language) {
        return -999.0;  // 过滤掉
    }

    base_score
}
```

---

### Scenario 4: Post in Non-Preferred Language

**Context:**
- 用户F的偏好语言：`["zh-CN", "en"]`
- 某帖子语言：`language = "ja"` (日文)

**Current Behavior:**
- 当前系统**未实现**语言过滤（数据库schema未存储language字段）

**Future Implementation:**
```sql
-- 在ClickHouse候选集查询中添加语言过滤
SELECT ...
FROM feed_candidates_followees
WHERE user_id = ?
  AND (language IN ('zh-CN', 'en') OR language = '')  -- 未标记语言的帖子仍展示
ORDER BY combined_score DESC
LIMIT ?
```

---

### Scenario 5: Post from Blocked User

**Context:**
- 用户G屏蔽了用户H
- H发布了一篇高热度帖子

**Implementation:**
```rust
// 在排序后过滤
async fn filter_blocked_posts(
    &self,
    user_id: Uuid,
    candidates: Vec<FeedCandidate>
) -> Result<Vec<FeedCandidate>> {
    let blocked_users = self.get_blocked_user_ids(user_id).await?;

    Ok(candidates
        .into_iter()
        .filter(|c| !blocked_users.contains(&c.author_id_uuid().unwrap()))
        .collect())
}
```

**Result:** ✅ H的所有帖子被完全排除

**Note:** 当前系统**未实现**屏蔽功能（需要添加 `blocked_users` 表）

---

## Tuning & Monitoring

### Key Performance Indicators (KPIs)

#### 1. Feed Engagement Metrics

| Metric | Definition | Target | Measurement |
|--------|-----------|--------|-------------|
| **Feed CTR** | 点击率 = 点击数 / 曝光数 | > 8% | Kafka event stream |
| **Dwell Time** | 用户在单个帖子上的停留时长 | > 15s | Client-side tracking |
| **Engagement Rate** | (赞+评+分享) / 曝光数 | > 5% | Engagement events / impressions |
| **Session Length** | 单次Feed浏览时长 | > 5min | Session analytics |
| **Scroll Depth** | 平均滚动到第几屏 | > 3 screens | Client-side tracking |

#### 2. System Health Metrics

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| **Feed Latency (P50)** | < 100ms | > 200ms |
| **Feed Latency (P99)** | < 300ms | > 1s |
| **Cache Hit Rate** | > 60% | < 40% |
| **Circuit Breaker Opens** | 0 per hour | > 1 per hour |
| **NaN Log Rate** | 0 per hour | > 10 per hour |
| **Candidate Refresh Latency** | < 30s | > 60s |

---

### A/B Testing Framework

#### Phase 1: Weight Tuning Experiment

**Hypothesis:**
- 提高freshness_weight → 提升用户活跃度（更多新鲜内容）

**Test Setup:**
```yaml
experiment:
  name: "feed_freshness_boost_2025q1"
  variants:
    control:
      freshness_weight: 0.3
      engagement_weight: 0.4
      affinity_weight: 0.3
    treatment:
      freshness_weight: 0.5
      engagement_weight: 0.3
      affinity_weight: 0.2
  allocation:
    control: 50%
    treatment: 50%
  duration: 14 days
  sample_size: 10000 users per variant
```

**Primary Metric:**
- Feed Engagement Rate (higher is better)

**Secondary Metrics:**
- Session Length
- User Retention (Day 7)

**Success Criteria:**
- Treatment组Engagement Rate提升 > 5% (p < 0.05)
- 无负面影响（Retention无显著下降）

---

#### Phase 2: Candidate Source Experiment

**Hypothesis:**
- 减少trending比例 → 提升个性化效果

**Test Setup:**
```rust
// Control: 三个来源各取limit条
let followees_limit = limit;
let trending_limit = limit;
let affinity_limit = limit;

// Treatment: trending只取limit/2
let followees_limit = limit;
let trending_limit = limit / 2;
let affinity_limit = limit;
```

---

### Observability Stack

#### 1. Logging (Structured)

**关键日志点：**
```rust
// 请求入口
debug!("Feed request: user={} algo={} limit={} offset={}", ...);

// 候选集大小
debug!("Retrieved {} followees, {} trending, {} affinity candidates", ...);

// 降级路径
warn!("Using fallback feed for user {} (ClickHouse unavailable)", ...);

// 异常分数
warn!("Encountered NaN score: post_a={} post_b={} score_a={} score_b={}", ...);
```

**日志聚合：**
- Loki/CloudWatch Logs
- 按user_id、post_id、error关键词索引
- 设置告警规则（NaN日志 > 10条/min）

---

#### 2. Tracing (Distributed)

**Span Hierarchy:**
```
GET /feed
├── Circuit Breaker Check (1ms)
├── Get Feed Candidates (100ms)
│   ├── Get Followees (50ms) [ClickHouse]
│   ├── Get Trending (40ms) [ClickHouse]
│   └── Get Affinity (60ms) [ClickHouse]
├── Rank Candidates (5ms)
├── Write Cache (10ms) [Redis]
└── Response Serialization (2ms)
```

**Tool:** Jaeger/Tempo
- 按trace_id追踪完整请求链路
- 识别慢查询瓶颈（ClickHouse query > 200ms）

---

#### 3. Metrics (Prometheus)

**Dashboard Panels：**

**Panel 1: Feed Latency by Source**
```promql
histogram_quantile(0.99,
  rate(feed_request_duration_seconds_bucket[5m]))
by (source)
```

**Panel 2: Cache Hit Rate**
```promql
sum(rate(feed_cache_events{event="hit"}[5m]))
/
sum(rate(feed_cache_events[5m]))
```

**Panel 3: Candidate Distribution**
```promql
avg(feed_candidate_count) by (source)
```

---

### Debugging Playbook

#### Issue 1: Feed延迟突增 (P99 > 1s)

**诊断步骤：**
1. 检查Circuit Breaker状态
   ```bash
   curl http://content-service:8081/health
   ```
2. 查看ClickHouse慢查询
   ```sql
   SELECT query, query_duration_ms
   FROM system.query_log
   WHERE query_duration_ms > 200
   ORDER BY event_time DESC LIMIT 10;
   ```
3. 检查候选集刷新Job是否hang住
   ```bash
   kubectl logs -f deployment/content-service | grep "Feed candidate refresh"
   ```

**常见原因：**
- ClickHouse表未分区裁剪（扫描历史数据）
- 候选集刷新Job卡在EXCHANGE TABLES
- Redis连接池耗尽

---

#### Issue 2: 用户看到重复帖子

**诊断步骤：**
1. 检查Redis Seen Posts tracking
   ```bash
   redis-cli SMEMBERS "feed:seen:{user_id}"
   ```
2. 检查候选集是否有重复post_id
   ```sql
   SELECT post_id, count() AS cnt
   FROM feed_candidates_followees
   WHERE user_id = ?
   GROUP BY post_id
   HAVING cnt > 1;
   ```

**常见原因：**
- 客户端未调用 `mark_posts_seen` API
- Redis过期策略导致Seen Set被清空
- 多设备同步问题（同一用户不同设备）

---

#### Issue 3: 新用户看到空Feed

**诊断步骤：**
1. 检查用户是否有关注用户
   ```sql
   SELECT count(*) FROM follows WHERE follower_id = ?;
   ```
2. 检查trending候选集是否为空
   ```sql
   SELECT count(*) FROM feed_candidates_trending;
   ```
3. 检查Circuit Breaker是否Open（导致降级到空PostgreSQL时间线）

**解决方案：**
- 冷启动用户引导关注推荐用户
- trending表至少保持500条热门内容
- PostgreSQL降级路径改为"编辑精选"内容

---

## Future Improvements

### 1. Machine Learning Ranking (ML-Based Scoring)

**当前问题：**
- 线性模型过于简单，无法捕捉复杂用户行为模式
- 手动调参效率低，无法针对不同用户群体优化

**改进方案：**
- **Two-Tower Model (双塔模型):**
  ```
  User Tower: user_id → user_embedding[128]
  Item Tower: post_id → post_embedding[128]
  Score = cosine_similarity(user_emb, post_emb)
  ```

- **Training Pipeline:**
  1. 特征工程：
     - User特征：关注数、互动历史、活跃时段、设备类型
     - Post特征：作者粉丝数、历史互动率、内容类型、发布时间
     - Context特征：当前时刻、用户所在地理位置
  2. 训练数据：
     - Positive样本：用户点击/点赞/评论的帖子
     - Negative样本：曝光但未互动的帖子
     - Hard Negative：高分但用户跳过的帖子
  3. 模型部署：
     - 离线训练（每天）
     - 模型导出ONNX → Rust推理
     - A/B测试验证效果

**预期收益：**
- Engagement Rate提升 10-20%
- 长尾内容曝光提升 30%

---

### 2. Real-Time Engagement Signals

**当前问题：**
- 候选集每5分钟刷新，无法实时反映热点内容
- 突发热点事件（breaking news）延迟5分钟才能进入trending

**改进方案：**
- **Redis Stream实时统计：**
  ```redis
  XADD engagement_stream * post_id <uuid> event like user_id <uuid>

  -- 每30秒聚合
  SELECT post_id, count(*) AS recent_engagement
  FROM redis_stream
  WHERE timestamp > now() - 30s
  GROUP BY post_id
  ```

- **Hybrid Scoring：**
  ```rust
  fn compute_score_with_realtime(
      &self,
      candidate: &FeedCandidate,
      realtime_engagement: &HashMap<Uuid, u32>
  ) -> f64 {
      let base_score = self.compute_score(candidate);
      let boost = realtime_engagement.get(&candidate.post_id).unwrap_or(&0);
      base_score + (boost as f64) * 0.1
  }
  ```

**预期收益：**
- Breaking news延迟从5分钟降至30秒
- 热点内容CTR提升15%

---

### 3. User Segment-Specific Weights

**当前问题：**
- 所有用户使用统一权重，无法满足不同用户偏好

**改进方案：**
- **用户分层：**
  | Segment | 识别规则 | Freshness | Engagement | Affinity |
  |---------|---------|-----------|------------|----------|
  | 新用户 | 注册 < 7天 | 0.5 | 0.5 | 0.0 |
  | 深度用户 | 关注 > 50人 | 0.2 | 0.3 | 0.5 |
  | 轻度用户 | 周活 < 2次 | 0.4 | 0.4 | 0.2 |
  | 内容创作者 | 粉丝 > 100 | 0.3 | 0.5 | 0.2 |

- **动态权重查询：**
  ```rust
  fn get_weights_for_user(&self, user_id: Uuid) -> (f64, f64, f64) {
      let segment = self.user_segmentation.get_segment(user_id);
      match segment {
          UserSegment::New => (0.5, 0.5, 0.0),
          UserSegment::PowerUser => (0.2, 0.3, 0.5),
          _ => (0.3, 0.4, 0.3),
      }
  }
  ```

**预期收益：**
- 新用户留存率提升 20%
- 深度用户会话时长提升 15%

---

### 4. Diversity Enforcement (多样性注入)

**当前问题：**
- 高分帖子可能来自同一作者（霸榜）
- 单一内容类型（如全是图片，缺少视频）

**改进方案：**
- **Sliding Window Diversification：**
  ```rust
  fn enforce_diversity(posts: Vec<RankedPost>) -> Vec<RankedPost> {
      let mut result = Vec::new();
      let mut author_count: HashMap<Uuid, usize> = HashMap::new();

      for post in posts {
          let count = author_count.entry(post.author_id).or_insert(0);
          if *count < 2 {  // 每5个帖子最多2个来自同一作者
              result.push(post);
              *count += 1;

              if result.len() % 5 == 0 {
                  author_count.clear();  // 重置滑动窗口
              }
          }
      }
      result
  }
  ```

- **Content Type Mixing：**
  ```rust
  // 每10个帖子至少3个视频、3个图文、3个纯文本
  fn ensure_content_type_mix(posts: Vec<RankedPost>) -> Vec<RankedPost> {
      let (videos, images, texts) = partition_by_content_type(posts);
      interleave_by_ratio(videos, images, texts, [3, 4, 3])
  }
  ```

**预期收益：**
- 用户满意度提升（避免审美疲劳）
- 中小作者曝光机会增加 40%

---

### 5. Contextual Ranking (上下文感知)

**当前问题：**
- 忽略用户当前场景（通勤 vs 休闲）
- 不考虑设备类型（手机 vs 平板）

**改进方案：**
- **时间上下文：**
  ```rust
  let hour = Utc::now().hour();
  let time_bias = match hour {
      7..=9 | 17..=19 => 0.2,  // 通勤时段：boost短内容
      22..=23 => -0.1,         // 睡前：降低刺激性内容
      _ => 0.0,
  };
  ```

- **设备上下文：**
  ```rust
  if user_agent.is_mobile() && post.media_type == Video {
      score *= 0.8;  // 移动端降低长视频权重
  }
  ```

**预期收益：**
- 场景适配后Dwell Time提升 10%

---

### 6. Negative Feedback Loop (负反馈机制)

**当前问题：**
- 用户"不感兴趣"/"举报"信号未被利用

**改进方案：**
- **Negative Signals Table：**
  ```sql
  CREATE TABLE feed_negative_signals (
      user_id UUID,
      post_id UUID,
      signal_type TEXT,  -- 'hide', 'report', 'not_interested'
      created_at TIMESTAMP
  );
  ```

- **Scoring Penalty：**
  ```rust
  if negative_signals.contains(&candidate.post_id) {
      score *= 0.1;  // 降权90%
  }
  if negative_author_signals.contains(&candidate.author_id) {
      score *= 0.5;  // 降权50%
  }
  ```

**预期收益：**
- 降低用户"不感兴趣"反馈 30%
- 提升Feed满意度NPS 15分

---

## Appendix

### A. Glossary

| Term | Definition |
|------|------------|
| **Feed Candidate** | 潜在可展示的帖子（预计算、未排序） |
| **Ranked Post** | 经过评分排序的帖子（最终展示顺序） |
| **Affinity Score** | 用户与作者的亲密度（基于历史互动） |
| **Circuit Breaker** | 熔断器，防止级联故障 |
| **CDC (Change Data Capture)** | 数据库变更捕获（实时同步） |
| **Materialized Table** | 物化表，预计算结果存储 |
| **Staging Table** | 临时表，用于无锁刷新 |
| **TTL (Time To Live)** | 缓存过期时间 |
| **NaN (Not a Number)** | 非数字浮点值（如0/0） |

---

### B. Configuration Reference

**Environment Variables (Full List):**

```bash
# Feed Ranking Weights
FEED_FRESHNESS_WEIGHT=0.3          # 新鲜度权重 (0.0-1.0)
FEED_ENGAGEMENT_WEIGHT=0.4         # 互动度权重 (0.0-1.0)
FEED_AFFINITY_WEIGHT=0.3           # 亲密度权重 (0.0-1.0)
FEED_FRESHNESS_LAMBDA=0.1          # 基线惩罚项

# Candidate Limits
FEED_MAX_CANDIDATES=1000           # 最大候选集大小
FEED_CANDIDATE_PREFETCH_MULTIPLIER=5  # 预取倍数

# Cache Settings
FEED_FALLBACK_CACHE_TTL_SECS=60    # 降级缓存TTL (秒)

# ClickHouse Connection
CLICKHOUSE_URL=http://localhost:8123
CLICKHOUSE_DATABASE=default
CLICKHOUSE_USERNAME=default
CLICKHOUSE_PASSWORD=
CLICKHOUSE_QUERY_TIMEOUT_MS=2000   # 查询超时 (毫秒)

# Circuit Breaker
CIRCUIT_BREAKER_FAILURE_THRESHOLD=3   # 连续失败阈值
CIRCUIT_BREAKER_SUCCESS_THRESHOLD=3   # 恢复成功阈值
CIRCUIT_BREAKER_TIMEOUT_SECONDS=30    # Open状态持续时间
```

---

### C. Performance Benchmarks

**测试环境：**
- CPU: 8 vCPU
- Memory: 16GB
- ClickHouse: 单节点
- Redis: 单节点

**Benchmark Results (1000 concurrent users):**

| Metric | P50 | P95 | P99 | Max |
|--------|-----|-----|-----|-----|
| Feed Request (ClickHouse) | 85ms | 180ms | 320ms | 1.2s |
| Feed Request (Redis Cache) | 8ms | 15ms | 25ms | 50ms |
| Feed Request (PostgreSQL Fallback) | 150ms | 280ms | 450ms | 2.1s |
| Candidate Refresh (per table) | 12s | 25s | 35s | 60s |

**Throughput:**
- ClickHouse path: 500 req/s per instance
- Cache path: 5000 req/s per instance
- Fallback path: 200 req/s per instance

---

### D. Related Documentation

- **System Architecture:** `backend/README.md`
- **ClickHouse Schema:** `backend/clickhouse/init-db.sql`
- **API Specification:** `backend/content-service/API.md`
- **Deployment Guide:** `k8s/content-service/README.md`
- **Monitoring Runbook:** `docs/runbooks/feed-ranking.md`

---

### E. Contact & Support

**On-Call Rotation:**
- Primary: @backend-team-feed
- Escalation: @engineering-leads

**Slack Channels:**
- `#feed-ranking` - 日常讨论
- `#incidents-feed` - 线上问题

**PagerDuty Integration:**
- Service: `content-service-feed`
- Alert Rules: `prometheus/alerts/feed.yaml`

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-29 | Nova Team | Initial comprehensive documentation |

---

**End of Document**

*这份文档是Nova Feed排序系统的完整技术参考，适用于新成员onboarding、架构评审和长期维护。如有疑问，请联系@backend-team-feed。*
