# Phase 4 Phase 3: Video Ranking & Feed APIs - Requirements Document

**Feature**: Video Ranking & Feed APIs (Phase 4 Phase 3)
**Status**: In Development
**Created**: 2025-10-19
**Dependencies**: Phase 4 Phase 1 (Schema), Phase 4 Phase 2 (Video Processing)

---

## 目標與邊界

- **目標**：建立視頻內容的個性化排序系統，通過深度學習模型和用戶交互信號為每個用戶生成定製化視頻Feed。支持趨勢發現（熱門視頻、聲音、標籤）。
- **邊界**：僅支持已發佈的視頻（status=published）；歷史視頻去重基於過去30天；趨勢計算基於過去24小時數據；不支持實時排序調整（A/B測試為第二階段）。

---

## Core Features

### 1. 視頻排序算法 (Video Ranking Algorithm)
- 基於 Phase 3 排序系統，擴展支持視頻內容
- 關鍵信號：
  - **新鮮度得分** (0.15權重): 視頻發佈時間衰減
  - **完成率信號** (0.40權重): 觀看完成度比例（視頻特定）
  - **互動得分** (0.25權重): 點讚、分享、評論標準化
  - **親和力得分** (0.15權重): 用戶-創作者互動歷史
  - **深度模型得分** (0.05權重): TensorFlow 嵌入相似度

### 2. Video Feed API (視頻Feed端點)
- `GET /api/v1/reels` - 獲取個性化視頻Feed
  - 支持分頁（cursor-based）
  - 返回30-50條視頻
  - P95延遲 ≤ 300ms (含深度召回)
  - 支持質量參數（720p/480p/360p）

### 3. 深度召回模型集成 (Deep Recall Model)
- 集成 TensorFlow Serving 模型
- 向量相似度搜索 (Milvus)
- 實時特徵提取：用戶特徵、視頻特徵
- 批量處理支持（100k+ 請求/小時）

### 4. 趨勢發現 (Trending Discovery)
- `GET /api/v1/reels/trending-sounds` - 熱門聲音（每5分鐘更新）
- `GET /api/v1/reels/trending-hashtags` - 熱門標籤（每5分鐘更新）
- `GET /api/v1/discover/creators` - 推薦創作者（每小時更新）
- `GET /api/v1/reels/challenges` - 活動挑戰（手動運營）

### 5. 視頻互動追蹤 (Engagement Tracking)
- POST /api/v1/reels/:id/watch - 記錄觀看事件
- POST /api/v1/reels/:id/like - 點讚行動
- POST /api/v1/reels/:id/comment - 評論行動
- POST /api/v1/reels/:id/share - 分享行動
- 即時更新 Redis + 異步寫入 ClickHouse

### 6. 搜索與發現 (Search & Discovery)
- 全文搜索視頻標題、描述、標籤
- 基於用戶觀看歷史的推薦
- 類似視頻推薦（嵌入相似度）
- 按創作者、分類搜索

---

## User Stories

### User Story 1: 觀看個性化視頻Feed (Priority: P0)
**As a** content consumer,
**I want to** scroll through an infinitely personalized video feed,
**So that** I can discover videos tailored to my interests without repetition.

**Acceptance Criteria:**
- Feed 視頻按相關性排序
- 第一次響應 ≤ 300ms
- 分頁光標有效期 ≥ 1小時
- 每個用戶的Feed 在30天內去重
- 緩存命中率 ≥ 95%

---

### User Story 2: 發現趨勢內容 (Priority: P0)
**As a** user exploring trends,
**I want to** see trending sounds, hashtags, and creators,
**So that** I can participate in popular challenges and follow trending creators.

**Acceptance Criteria:**
- 熱門聲音端點返回前100個（按使用次數）
- 熱門標籤返回前100個（按帖子數）
- 推薦創作者返回20個（按粉絲增長率）
- 列表每5分鐘或1小時更新一次
- 支持按分類過濾（音樂、喜劇、舞蹈等）

---

### User Story 3: 交互與推薦 (Priority: P1)
**As a** user,
**I want to** like, comment, and share videos,
**So that** I can engage with content and help personalize my feed.

**Acceptance Criteria:**
- 交互操作立即可見（樂觀更新）
- 計數器在1秒內更新
- 支持撤銷操作（取消點讚）
- 交互數據即時同步到排序引擎

---

### User Story 4: 搜索與發現 (Priority: P1)
**As a** user,
**I want to** search for videos by keywords, hashtags, and creators,
**So that** I can find specific content I'm interested in.

**Acceptance Criteria:**
- 全文搜索支持模糊匹配
- 搜索延遲 ≤ 200ms
- 支持多維度過濾（類型、時間範圍、創作者）
- 搜索結果按相關性排序

---

## Acceptance Criteria (System Level)

### Functional Requirements
- [ ] Video Feed API 返回排序後的視頻列表
- [ ] 深度召回模型推理延遲 < 200ms
- [ ] 視頻排序結合深度模型 + 互動信號
- [ ] Trending 端點每5分鐘更新
- [ ] 搜索支持全文檢索
- [ ] 支持類似視頻推薦

### Non-Functional Requirements

#### Performance
- Feed API P95 延遲: ≤ 300ms (含深度召回) 或 ≤ 100ms (緩存命中)
- 趨勢端點 P95 延遲: ≤ 100ms
- 搜索 P95 延遲: ≤ 200ms
- 深度模型推理: < 200ms
- ClickHouse 查詢: < 500ms

#### Reliability
- Feed API 可用性: ≥ 99.9% (SLA)
- 深度模型可用性: ≥ 99.5%
- 趨勢數據新鮮度: 99% 時間內 < 10分鐘延遲
- 緩存失敗時自動降級到全查詢

#### Scalability
- 支持 100k+ 並發 Feed 請求/小時
- 深度模型推理: 100k+ 請求/小時
- ClickHouse 聚合: 1M+ 事件/小時
- 趨勢計算無阻塞（非同步處理）

#### Security
- API 速率限制: 100 requests/min per user
- 視頻內容驗證（已發佈、非刪除）
- 用戶隱私：不洩露觀看歷史給其他用戶
- 搜索查詢日誌記錄（審計用途）

#### Compatibility
- API 版本控制: /api/v1/, /api/v2/ (future)
- 向後兼容性維護
- 支持舊版客戶端 (graceful degradation)
- 跨平台 (Web, iOS, Android)

---

## Data Model Extensions

### ClickHouse 新表
```sql
-- 視頻排序信號聚合
CREATE TABLE video_ranking_signals_1h (
  video_id UUID,
  hour DateTime,
  completion_rate Float32,
  engagement_score Float32,
  affinity_boost Float32,
  deep_model_score Float32
);

-- 趨勢計算（每小時）
CREATE TABLE trending_sounds_hourly (
  sound_id String,
  hour DateTime,
  video_count UInt32,
  usage_rank UInt32
);

CREATE TABLE trending_hashtags_hourly (
  hashtag String,
  hour DateTime,
  post_count UInt32,
  trend_rank UInt32
);

-- 用戶觀看歷史（實時）
CREATE TABLE user_watch_history_realtime (
  user_id UUID,
  video_id UUID,
  watched_at DateTime,
  completion_percent UInt8
);
```

### PostgreSQL 新表
```sql
-- 深度召回模型元數據
CREATE TABLE deep_recall_models (
  id UUID PRIMARY KEY,
  model_version String,
  deployed_at DateTime,
  performance_metrics JSONB,
  is_active Boolean DEFAULT false
);
```

---

## Integration Points

### 與 Phase 2 集成
- 使用 Phase 2 輸出的轉碼視頻 URL
- 使用 Phase 2 生成的嵌入向量
- 使用 Phase 2 的緩存層（Redis）

### 新的外部集成
- **深度學習**: TensorFlow Serving (已有)
- **向量 DB**: Milvus (已有)
- **搜索引擎**: Elasticsearch 或 ClickHouse 全文搜索
- **緩存**: Redis (existing)
- **消息隊列**: Kafka for events (existing)

---

## Success Metrics

| 指標 | 目標 | 測量方式 |
|------|------|---------|
| Feed CTR (視頻) | ≥ 25% vs images 15% | Events/API calls |
| 視頻完成率 | P50 ≥ 75%, P95 ≥ 55% | Video events |
| 深度模型效果 | +20% engagement lift | A/B test results |
| API P95 延遲 | ≤ 300ms | CloudWatch metrics |
| 緩存命中率 | ≥ 95% | Redis stats |
| 趨勢新鮮度 | < 10分鐘延遲 99% | ClickHouse query |

---

## Risks & Mitigations

| 風險 | 影響 | 緩解措施 |
|------|------|---------|
| 深度模型推理慢 | Feed 變慢 | Batch + cache, fallback to simpler model |
| ClickHouse 查詢超時 | Feed 失敗 | 查詢優化, materialized views, 降級到昨日數據 |
| 緩存 stampede | 大量 CH 查詢 | Cache warming + jitter + 分布式鎖 |
| 趨勢計算成本 | 基礎設施成本 | 異步計算, 聚合窗口優化 |
| 搜索索引延遲 | 搜索過期 | 雙寫策略, 可接受的一致性窗口 |
| 排序算法偏差 | 推薦質量下降 | 人工審查, feedback loops, A/B testing |

---

**文件版本**: 1.0
**最後更新**: 2025-10-19
**狀態**: Pending User Review
