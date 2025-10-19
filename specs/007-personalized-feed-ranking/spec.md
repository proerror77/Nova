# Feature Specification: 實時個性化 Feed 排序系統（Phase 3）

**Feature Branch**: `007-personalized-feed-ranking`
**Created**: 2025-10-18
**Status**: Draft

## 目標與邊界

- **目標**：將 Feed 從時序流升級為「個性化排序 + 熱門混排」，事件至可見延遲 ≤ 5 秒。
- **邊界**：僅做圖片貼文流；Reels/視頻與深度召回另起 Phase 4。

## 數據流架構

```
App 事件 ──→ Events API ──→ Kafka (events topic)
PostgreSQL ──→ Debezium ──→ Kafka (CDC topics)
                          ↓
                ClickHouse (物化視圖)
                ├─ events (行為明細)
                ├─ posts/follows (CDC)
                ├─ post_metrics_1h (聚合)
                └─ user_author_90d (親和度)
                       ↓
Feed Service (排序 + 快取 + 回退)
```

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 查看個性化排序 Feed (Priority: P1)

用戶打開首頁，看到由關注者貼文、全站熱榜、作者親和推薦混合組成的排序流。每個貼文按新鮮度（指數衰減）、參與度（likes/comments/shares 加權）、親和度（與作者的互動歷史）三維混合排序，呈現最相關的內容。

**Why this priority**: 核心用戶體驗升級，直接驅動留存與參與度。時序流轉排序流是推薦系統的基礎。

**Independent Test**:
- 用戶 A 關注 B、C 兩個作者，獲取 Feed 返回 50 條混合候選
- 驗證：新發貼文排在前面，高互動老貼文也有機會出現
- Redis 命中率 ≥ 90%，命中時 P95 ≤ 150ms

**Acceptance Scenarios**:
1. **Given** 用戶 A 關注 B、C，**When** 調用 GET /api/v1/feed?algo=ch，**Then** 返回 50 條混合候選，按最終排序分數 DESC
2. **Given** Redis 中無快取，**When** 首次查詢，**Then** 從 ClickHouse 讀取、計算排序、回寫 Redis (TTL 120s)
3. **Given** 前次查詢後 30s 內再次查詢，**When** GET /api/v1/feed，**Then** 直接返回快取 ≤ 50ms

---

### User Story 2 - 發現全站熱榜與建議用戶 (Priority: P1)

用戶可查看全站實時熱榜（近 24h 最高參與度貼文），並獲得基於 follow 圖協同過濾的建議用戶列表。熱榜與建議更新頻率 < 1 分鐘。

**Why this priority**: 社交發現與冷啟動。新用戶轉化的關鍵路徑。

**Independent Test**:
- 獲取 GET /api/v1/feed/trending?window=1h 返回 Top 200 貼文
- 獲取 GET /api/v1/discover/suggested-users 返回 10–20 建議用戶
- 熱榜更新 ≥ 每 60s 一次；建議計算 < 5s

**Acceptance Scenarios**:
1. **Given** 過去 24h 有 1000+ 互動，**When** GET /api/v1/feed/trending?window=1h，**Then** 返回 Top 200 貼文
2. **Given** 用戶 A 關注 B、C、D，**When** GET /api/v1/discover/suggested-users，**Then** 返回推薦，按分數排序

---

### User Story 3 - 上報行為事件 (Priority: P1)

App 客戶端上報用戶行為事件（impression/view/like/comment/share/dwell），累積形成推薦基礎。事件非同步批量送達，批量 ≤ 100 條，支持重試與去重。

**Why this priority**: 推薦數據基礎。無行為數據，個性化排序無法運轉。

**Independent Test**:
- 客戶端組裝事件，POST /api/v1/events，100 條/批
- Events API 驗證、去重、批量寫入 Kafka
- 事件端到端延遲 < 1s；消費滯後 < 10s；去重率 = 100%

**Acceptance Scenarios**:
1. **Given** 用戶滑動 5 條貼文，**When** 客戶端每 30s 批量上報，**Then** Events API 收到準確的事件與 dwell_ms
2. **Given** 同一事件重複上報，**When** 計算 idempotent_key，**Then** 僅插入 1 條記錄

---

### User Story 4 - 快取與故障回退 (Priority: P2)

Feed 查詢優先讀 Redis (120s TTL)，未命中則查 ClickHouse、計算分數、回寫快取。若 ClickHouse 故障，自動回退至 PostgreSQL 時序流，保障可用性。

**Why this priority**: 系統穩定性與客戶體驗保障。故障時，用戶仍能看到 Feed。

**Independent Test**:
- Redis 命中返回 ≤ 50ms，命中率 ≥ 90%
- CH 超時（>2s）或故障：自動回退，返回時序流 ≤ 500ms

**Acceptance Scenarios**:
1. **Given** Redis 中有快取，**When** GET /api/v1/feed，**Then** 直接返回 ≤ 50ms
2. **Given** CH 故障，**When** GET /api/v1/feed，**Then** 回退至 PostgreSQL 時序流 ≤ 500ms

---

### User Story 5 - 監控與告警 (Priority: P2)

系統實時監控 CDC 消費滯後、ClickHouse 查詢延遲、Redis 命中率、Feed API 響應時間等關鍵指標。超過閾值自動告警。日常看板展示熱榜變化、推薦效果、系統健康度。

**Why this priority**: 運維可觀測性。支持快速故障定位與性能優化決策。

**Independent Test**:
- 系統採集 CH query_log、Kafka lag、Redis 命中率，匯入 Grafana
- 告警：Kafka lag > 30s、CH P95 > 800ms、Feed API P95 > 500ms、Redis 命中率 < 80%

**Acceptance Scenarios**:
1. **Given** Kafka 消費滯後達 30s，**When** 系統檢測到，**Then** 發送告警，包含滯後量與建議
2. **Given** 每天 00:00–01:00，**When** 自動生成報告，**Then** 包含前日性能指標

---

### Edge Cases

- 同一用戶在快取 TTL 內連續多次查詢，是否保證分頁一致？預期：是，使用遊標分頁確保一致性
- 用戶 A 剛關注 B，B 的新貼文何時出現？預期：≤ 2 分鐘（CDC 同步 + 下次查詢）
- 某作者大量發貼（10+ 條/分鐘），是否會壓垮系統或造成刷屏？預期：去重策略限制單作者相鄰距離 ≥ 3
- CH 連續故障 > 2 分鐘，系統是否保持穩定？預期：回退時序流，API 持續可用
- 舊貼文被挖出來（高參與），排序分數如何變化？預期：高參與度會推升最終排序

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST sync PostgreSQL changes (users/follows/posts/comments/likes) to ClickHouse via Debezium CDC within 10 seconds
- **FR-002**: System MUST ingest user behavior events into ClickHouse within 2 seconds of receipt
- **FR-003**: System MUST compute candidate set from 3 sources: (a) Followees posts (72h, ≤500), (b) Trending (24h, Top 200), (c) Author affinity (90d, ≤200)
- **FR-004**: System MUST rank candidates using: freshness (exp(-0.1*age_h)) + engagement (log1p(engagement_metrics)) + affinity (log1p(author_interactions)); final_score = 0.30*fresh + 0.40*eng + 0.30*aff
- **FR-005**: System MUST return top 50 ranked candidates via GET /api/v1/feed?algo=ch&limit=50
- **FR-006**: System MUST cache feed results in Redis (TTL 120s) and return cache hit within 50ms
- **FR-007**: System MUST fall back to PostgreSQL time-series feed if ClickHouse query fails or exceeds 2s timeout
- **FR-008**: System MUST deduplicate already-viewed posts within 24h window
- **FR-009**: System MUST enforce author saturation: max 1 post per author in top-5, distance between same-author posts ≥ 3
- **FR-010**: System MUST support GET /api/v1/feed/trending?window=1h returning top 200 posts by engagement in past 1h
- **FR-011**: System MUST support GET /api/v1/discover/suggested-users returning 10–20 users via collaborative filtering
- **FR-012**: System MUST expose POST /api/v1/events accepting batch JSON (≤100 events) and produce idempotently to Kafka
- **FR-013**: System MUST track Kafka lag, CH query latency, Redis hit rate, Feed API P95 in real-time metrics
- **FR-014**: System MUST trigger alerts if Kafka lag > 30s, CH P95 > 800ms, Feed API P95 > 500ms, Redis hit rate < 80%
- **FR-015**: System MUST provide GET /api/v1/feed/metrics returning daily CTR, dwell P50, recommendation conversion rate

### Key Entities

- **Events**: event_time, user_id, post_id, author_id, action, dwell_ms, device, app_ver; TTL 30 days; PARTITION BY toYYYYMM(event_date); ORDER BY (user_id, event_time)
- **Posts (CDC)**: post_id, user_id, created_at, deleted; ReplacingMergeTree for eventual consistency
- **Follows (CDC)**: follower_id, following_id, created_at, deleted; ReplacingMergeTree
- **PostMetrics1h**: post_id, window_start, views, likes, comments, shares, dwell_ms_sum, exposures; SummingMergeTree; TTL 90 days
- **UserAuthor90d**: user_id, author_id, likes, comments, views, dwell_ms, last_ts; SummingMergeTree; TTL 120 days
- **Redis Keys**: feed:v1:{user} (TTL 120s), hot:posts:1h (TTL 60s), suggest:users:{user} (TTL 10m), seen:{user}:{post} (TTL 24h)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Event-to-visible latency P95 ≤ 5 seconds
- **SC-002**: GET /api/v1/feed API response P95 ≤ 150ms (Redis hit), ≤ 800ms (CH fallback)
- **SC-003**: Redis cache hit rate ≥ 90% during steady-state
- **SC-004**: Kafka consumer lag < 10 seconds for 99.9% of time
- **SC-005**: Feed queries ≤ 800ms for ClickHouse, supporting 10k concurrent queries
- **SC-006**: System availability ≥ 99.5% (including graceful fallback)
- **SC-007**: Duplicate post deduplication rate = 100%
- **SC-008**: Author saturation rule enforced 100% (no more than 3 posts from same author in top 50)
- **SC-009**: Trending and suggested users API respond ≤ 200ms (Redis) or ≤ 500ms (CH)
- **SC-010**: Daily metrics dashboard tracks CTR, dwell P50, recommendation conversion, system health

### Qualitative Measures

- **SC-011**: Users perceive feed as "personalized and relevant" (≥ 4/5 rating)
- **SC-012**: No support tickets related to "same content repeatedly shown"
- **SC-013**: Recommended users have ≥ 30% follow-through rate within 7 days

---

## Assumptions

- PostgreSQL 與 ClickHouse 間允許最終一致性（≤ 30 秒）
- Debezium snapshot mode 可在營運時間進行，不影響 OLTP
- Kafka broker 可支持 10k+ events/sec，複製因子 3
- Redis 單節點或小集群足以支持 feed 快取；容量規劃 ≥ 2.5GB
- ClickHouse 單節點 dev 可支持 100M+ 行數查詢，P95 ≤ 2s
- iOS/Android App 支持背景事件上報
- 初期關注圖規模：100k users，平均 50 followees，≤ 5M follow relations

---

## Out of Scope

- 深度學習推薦模型（Phase 4）
- Reels / 短視頻流（Phase 4）
- 即時消息系統（另行規劃）
- 用戶檔案完整重構（保持現有 001–006 功能）
- A/B 測試框架（可選，Phase 4）

---

## Implementation Timeline

**14 小時落地計畫（可並行，2 人小組）**：

| Hours | Task | Output |
|-------|------|--------|
| H1–H2 | ClickHouse 基建、Kafka topics、Debezium connectors | CH namespace, connectors online |
| H3–H4 | CH 表、MV、物化視圖驗證 | All DDL in place, data flowing |
| H5 | 全量回填 & 一致性驗證 | OLTP ↔ CH count match |
| H6–H7 | 排序 SQL、熱榜生成 | Ranking query OK, hot:posts:1h job |
| H8 | Feed Service 接入 (/feed?algo=ch) | API live, fallback tested |
| H9 | 建議用戶 + 協同過濾 | GET /discover/suggested-users OK |
| H10 | Events API + 客戶端集成 | POST /events working, 1k RPS tested |
| H11 | Grafana dashboard、告警 | Metrics live |
| H12 | 質量關卡：E2E 延遲 ≤ 5s | Pass 30m continuous test |
| H13 | 參數調優、權重配置 | fresh/eng/aff = 0.3/0.4/0.3 fixed |
| H14 | 文檔、灰度開關、移交 | Runbook done, 10% rollout ready |

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| CH 查詢壓力過大 | Feed 延遲 > 5s | 降級只用關注時序流；提高 TTL；預計算物化視圖 |
| Kafka 積壓 | 行為數據滯後 | 提高消費並發；暫時拉長聚合窗口；監控告警 |
| CDC 全量快照阻塞 | OLTP 讀寫變慢 | 離線時間或邏輯複製避免鎖表 |
| 推薦噪音（刷屏） | 用戶體驗下降 | 作者飽和度 ≥ 3；Beta 平滑去重 |
| 新用戶冷啟動 | 無個性化推薦 | 依賴熱榜 + 建議用戶；初期回退時序流 |

---

## 定義完成 (DoD)

- ✅ 事件→CH→/feed 可視延遲 ≤ 5s（連續 30 分鐘）
- ✅ /feed?algo=ch 命中率 ≥ 90%，P95 ≤ 150ms；回退正常
- ✅ 熱榜與建議用戶 API 返回合規資料並可灰度
- ✅ Runbook 與回退預案可演練通過

