# Implementation Plan: 個性化 Feed 排序 + ClickHouse OLAP 層集成

**Branch**: `007-personalized-feed-ranking` | **Date**: 2025-10-19 | **Spec**: `spec.md`
**Status**: Phase Design Complete | **Complexity**: High | **Duration**: 3 weeks

## Summary

升級 Nova Feed 排序系統，從 PostgreSQL 直接查詢（500ms 延遲）改進至 **ClickHouse OLAP 層** 驅動的特徵提取（100ms 延遲）。

關鍵設計：
- **Kafka 事件流** → ClickHouse 實時聚合（物化視圖）→ **特徵提取器**（Rust）→ Redis 快取 → ranking_engine
- **API 完全兼容**：ranking_engine 邏輯不變，只改變數據源
- **3x 性能提升**，**90% 成本節省**

## Technical Context

**Language/Version**: Rust 1.75+ | Kafka | ClickHouse 23.0+ | Redis 7.0+
**Primary Dependencies**:
- Backend: Actix-web, Tokio, reqwest, redis, serde_json, ClickHouse client
- Storage: ClickHouse (OLAP), PostgreSQL (OLTP 源), Redis (緩存)
- Event Bus: Kafka

**Storage Architecture**:
```
PostgreSQL (OLTP)                    ClickHouse (OLAP)
├─ posts                              ├─ posts_cdc (CDC, ReplacingMergeTree)
├─ events                             ├─ events_raw (Kafka, MergeTree, TTL 90d)
├─ follows                            ├─ post_metrics_1h (物化視圖, 1h 粒度)
└─ user_author_interactions           ├─ user_author_90d (ReplacingMergeTree)
                                      └─ post_ranking_scores (應用層查詢)
```

**Testing**: cargo test + integration tests + e2e tests + performance bench
**Target Platform**: Linux server (Kubernetes)
**Project Type**: Backend microservice (Rust)

**Performance Goals**:
| 指標 | 目標 | 當前 | 改進 |
|------|------|------|------|
| Query Latency (100 posts) | < 100ms | 200ms | 2.5x |
| Query Latency (1000 posts) | < 200ms | 500ms | 2.5x |
| Cache Hit (Redis) | < 5ms | - | 100x |
| Throughput | 10,000 req/s | 2,000 req/s | 5x |
| Cost | $500/月 | $5,000/月 | 90% 節省 |

**Constraints**:
- p95 latency: < 200ms (用戶體驗)
- Cache hit rate: > 80% (TTL 5min)
- Event lag: < 10s (實時性)
- Memory per node: < 4 GB
- Zero breaking changes (向後兼容)

## Constitution Check ✅

**核心設計原則對齐** (Linus 哲學):
1. ✅ **Good Taste** - 消除邊界情況: 單一 ClickHouse 源替代混合查詢
2. ✅ **Never break userspace** - 100% 向後兼容，ranking_engine API 不變
3. ✅ **實用主義** - 解決真實問題 (PostgreSQL 無法處理 500M+ 事件/天)
4. ✅ **簡潔執念** - 核心代碼 < 450 行

**無違規項**。

## Project Structure

### Documentation (this feature)

```
specs/007-personalized-feed-ranking/
├── spec.md                 # ✅ 功能規範
├── plan.md                 # ✅ 本文件 (實現計劃)
├── requirements.md         # 需求檢查
├── design.md               # 設計文檔
├── tasks.md                # ✅ 62 個任務 (已生成)
└── checklists/
    └── requirements.md     # 驗收清單
```

### Source Code (repository root)

```
backend/user-service/
└── src/services/
    ├── clickhouse_feature_extractor.rs  # ✅ 新增 (430 行)
    │   ├── ClickHouseClient
    │   ├── ClickHouseFeatureExtractor
    │   └── RankingSignalRow
    ├── feed_ranking_service.rs          # 修改 (集成特徵提取器)
    ├── ranking_engine.rs                # 不變
    ├── mod.rs                           # ✅ 修改 (添加模塊)
    └── tests/
        ├── clickhouse_feature_extraction_integration_test.rs
        ├── feed_ranking_e2e_clickhouse_test.rs
        └── clickhouse_performance_bench.rs

docs/
├── CLICKHOUSE_INTEGRATION_ARCHITECTURE.md   # ✅ 架構設計
├── CLICKHOUSE_INTEGRATION_GUIDE.md          # ✅ 實現指南
├── CLICKHOUSE_PERFORMANCE_TUNING.md         # ✅ 性能調優
├── CLICKHOUSE_INTEGRATION_SUMMARY.md        # ✅ 完整總結
└── CLICKHOUSE_QUICK_REFERENCE.md            # ✅ 快速參考

backend/clickhouse/
├── schema.sql              # ✅ 已存在 (MergeTree 表定義)
└── migrations/             # CDC 和 materialized views
```

## 實現路線圖

### Phase 1: 基礎設施 (1 週)
**時程**: Week 1
**交付物**: ClickHouse 查詢層 + Redis 快取層

- [x] 驗證 ClickHouse schema (schema.sql)
- [x] 實現 ClickHouseFeatureExtractor (430 行)
  - [x] get_ranking_signals() - 核心方法
  - [x] get_hot_posts() - 冷啟動
  - [x] get_user_author_affinity() - 親密度
  - [x] Redis 緩存層 (TTL 5min)
- [x] 單元測試覆蓋 (5 個測試)
- [x] 架構文檔完成

### Phase 2: 應用集成 (2 週)
**時程**: Week 2-3
**交付物**: 完整的 Feed 排序系統集成

- [ ] 修改 feed_ranking_service.rs
  - [ ] 注入 ClickHouseFeatureExtractor
  - [ ] 調用 get_ranking_signals()
  - [ ] 錯誤処理和降級
- [ ] 修改 main.rs
  - [ ] 初始化 ClickHouse 客戶端
  - [ ] 初始化 Redis 連接
  - [ ] 依賴注入設置
- [ ] 集成測試 (3 個)
  - [ ] 特徵提取集成測試
  - [ ] 端到端 Feed 排序測試
  - [ ] 性能基準測試
- [ ] 性能驗證
  - [ ] 單查詢 < 100ms
  - [ ] 緩存命中 < 5ms
  - [ ] 吞吐量 > 10,000 req/s

### Phase 3: 部署和優化 (1 週)
**時程**: Week 4
**交付物**: 生產就緒的代碼和監控

- [ ] 預發佈環境驗證
- [ ] A/B 測試 (10% 用戶)
- [ ] 灰度部署 (50% → 100%)
- [ ] 監控和告警配置
- [ ] 性能基準驗證
- [ ] 回滾測試完成

## 風險與緩解

| 風險 | 影響 | 緩解措施 |
|------|------|--------|
| ClickHouse 宕機 | Feed 服務失敗 | Graceful degradation 到 PostgreSQL 緩存 |
| Kafka 消費延遲 | 信號過時 (> 1h) | 監控告警, Kafka lag > 30min |
| 特徵計算錯誤 | 排序偏差 | A/B 測試驗證, 單調性檢查 |
| 緩存穿透 | Redis miss 導致查詢激增 | Bloom filter, 分布式預熱 |

## 複雜度追蹤 ✅

**設計簡單性**:
- ✅ 單一責任 (特徵提取只做一件事)
- ✅ 最小化狀態 (無本地快取, 依賴 Redis)
- ✅ 清晰的錯誤界限 (Graceful degradation)
- ✅ 向後兼容 (ranking_engine API 不變)

**無需複雜化的違規項**。

