# Ranking Service

**Phase D: Candidate Recall + GBDT Ranking + Diversity Reranking**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Ranking Service                          │
│                                                             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐     │
│  │   Recall    │ → │   Ranking   │ → │  Diversity  │     │
│  │    Layer    │   │    Layer    │   │    Layer    │     │
│  └─────────────┘   └─────────────┘   └─────────────┘     │
│         ↓                  ↓                  ↓            │
│  ┌─────────────────────────────────────────────────┐      │
│  │         Multi-Strategy Candidate Recall         │      │
│  │  • Graph (Following)                            │      │
│  │  • Trending (Hot Posts)                         │      │
│  │  • Personalized (User Interests)                │      │
│  └─────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## Features

### 1. Recall Layer (召回層)
- **Graph Recall**: 基於用戶關注的召回 (200 candidates)
  - 調用 graph-service 獲取 following 列表
  - 召回這些用戶的最新帖子
- **Trending Recall**: 熱門召回 (100 candidates)
  - 從 Redis Sorted Set 獲取熱門帖子
- **Personalized Recall**: 個性化召回 (100 candidates)
  - 基於用戶興趣標籤召回相關帖子

### 2. Ranking Layer (排序層)
- **Feature Engineering**: 特徵提取
  - Engagement Score (互動分數)
  - Recency Score (時效分數)
  - Author Quality Score (作者質量)
  - Content Quality Score (內容質量)
- **Model Scoring**: GBDT 模型打分
  - Phase D: 線性加權簡化版
  - Phase E: 真實 ONNX 模型推理

### 3. Diversity Layer (多樣性層)
- **MMR Algorithm**: Maximal Marginal Relevance
  - λ = 0.7 (70% relevance + 30% diversity)
  - 避免連續推薦同一召回源的內容

## API

### gRPC Service

```protobuf
service RankingService {
  rpc RankFeed(RankFeedRequest) returns (RankFeedResponse);
  rpc RecallCandidates(RecallRequest) returns (RecallResponse);
}
```

### Example: Rank Feed

```bash
grpcurl -plaintext \
  -d '{"user_id":"user123","limit":20}' \
  localhost:9011 \
  ranking.v1.RankingService/RankFeed
```

## Configuration

See `.env.example` for all configuration options.

### Key Settings

- **Recall Limits**: Control candidate pool size
  - `GRAPH_RECALL_LIMIT=200`
  - `TRENDING_RECALL_LIMIT=100`
  - `PERSONALIZED_RECALL_LIMIT=100`

- **Recall Weights**: Balance recall strategies
  - `GRAPH_RECALL_WEIGHT=0.6`
  - `TRENDING_RECALL_WEIGHT=0.3`
  - `PERSONALIZED_RECALL_WEIGHT=0.1`

## Dependencies

### External Services
- **graph-service** (port 9008): User relationships
- **content-service** (port 9002): Post metadata (Phase E)
- **Redis**: Trending posts + user interests

### Libraries
- **ndarray**: Numerical arrays for ML features
- **tract-onnx**: ONNX model inference (Phase E)
- **tonic**: gRPC server/client

## Development

### Build

```bash
cd backend/ranking-service
cargo build
```

### Run

```bash
# Copy example config
cp .env.example .env

# Start service
cargo run
```

### Test

```bash
cargo test
```

## Phase Roadmap

### Phase D (Current) ✅
- [x] Multi-strategy recall (Graph, Trending, Personalized)
- [x] Basic ranking (linear weighted scoring)
- [x] Diversity reranking (MMR algorithm)
- [x] gRPC API

### Phase E (Next)
- [ ] Feature Store integration
- [ ] ONNX model inference (GBDT)
- [ ] Real-time feature computation
- [ ] A/B testing framework
- [ ] Model performance monitoring

## Ports

- **HTTP**: 8011 (health check, metrics)
- **gRPC**: 9011 (ranking service)

## Logging

```bash
RUST_LOG=info,ranking_service=debug cargo run
```
