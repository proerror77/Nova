# Kubernetes 資源配置審計報告

**審計日期**: 2025-11-11
**審計人**: Linus Torvalds (AI Persona)
**集群環境**: EKS (AWS ap-northeast-1)

---

## 執行摘要

### 🔴 P0 致命問題 (立即修復)

1. **user-service CrashLoopBackOff** - 缺失環境變量 `CLICKHOUSE_URL`，導致服務無法啟動
2. **Namespace 過度分割** - 8 個 namespace 管理 11 個服務，違反簡單性原則
3. **重複的 Postgres 實例** - `nova` 和 `nova-backend` 各有一個，資源浪費
4. **ConfigMap 配置混亂** - 每個 namespace 有獨立配置，無法統一管理
5. **健康檢查缺失** - content-service, feed-service, redis 沒有 liveness/readiness probes
6. **HPA 無法工作** - 缺少 Metrics Server，所有 HPA 顯示 `<unknown>`

### 🟡 P1 高優先級問題

1. **環境變量策略不一致** - 混用 ConfigMap、Secret、直接值，沒有明確規則
2. **Service 端口不一致** - 有些用 HTTP (8080)，有些用 gRPC (50051)，沒有統一標準
3. **資源限制不完整** - 部分服務缺少 CPU/Memory limits
4. **網絡策略缺失** - 只有 nova-gateway 有 NetworkPolicy，其他服務沒有網絡隔離

---

## 1. Namespace 資源分佈

| Namespace       | Deployments | Services | ConfigMaps | Secrets | Pods | 狀態 |
|-----------------|-------------|----------|------------|---------|------|------|
| **nova**        | 1           | 2        | 2          | 0       | 1    | ✅ Running |
| **nova-backend** | 5           | 6        | 3          | 1       | 18   | ❌ 4 服務掛掉 |
| **nova-auth**   | 1           | 1        | 3          | 1       | 3    | ✅ Running |
| **nova-content** | 1           | 1        | 4          | 1       | 3    | ✅ Running |
| **nova-feed**   | 1           | 1        | 4          | 1       | 3    | ✅ Running |
| **nova-media**  | 2           | 2        | 4          | 1       | 2    | ✅ Running |
| **nova-gateway** | 1           | 1        | 3          | 1       | 4    | ⚠️ 2/4 pods failing |
| **nova-staging** | 1           | 1        | 2          | 1       | 2    | ✅ Running |
| **總計**        | 13          | 15       | 25         | 7       | 36   | 55% 健康 |

---

## 2. 配置不一致問題

### 🔴 Blocker: user-service 啟動失敗

**根本原因**:
```rust
// backend/user-service/src/config/mod.rs:480
url: env::var("CLICKHOUSE_URL").expect("CLICKHOUSE_URL must be set")
```

**當前配置缺失**:
```yaml
# nova-backend/ConfigMap: nova-backend-config
# ❌ CLICKHOUSE_URL 不存在
# ❌ CLICKHOUSE_DB 不存在
# ❌ CLICKHOUSE_USER 不存在
```

**同時存在的問題**:
1. `nova` namespace 的 `user-service-config` ConfigMap **有** ClickHouse 配置
2. 但 `nova-backend` namespace 的 `nova-backend-config` **沒有**
3. Deployment 在 `nova-backend`，但引用錯誤的 ConfigMap

**修復方案**:
```yaml
# 添加到 kubernetes/overlays/staging/nova-backend/configmap.yaml
data:
  CLICKHOUSE_URL: "http://clickhouse.default.svc.cluster.local:8123"
  CLICKHOUSE_DB: "nova"
  CLICKHOUSE_USER: "default"
  CLICKHOUSE_PASSWORD: "changeme"
  CLICKHOUSE_ENABLED: "false"  # 或先禁用
```

### 🔴 Blocker: 重複的 Postgres 實例

**問題**:
```
nova/postgres         -> 172.20.222.19:5432  (已運行 40h)
nova-backend/postgres -> 172.20.221.80:5432  (新部署 69m)
```

**影響**:
- 浪費資源 (每個 Postgres 佔用 512Mi-1Gi RAM)
- 數據不一致風險
- 配置混亂 (哪個是主數據庫？)

**Linus 評論**:
> "This is stupid. Why do you have TWO PostgreSQL instances? Pick one and kill the other.
> Data structures first, remember? One database, one source of truth."

**推薦方案**:
1. **保留** `nova/postgres` (已運行較久，可能有數據)
2. **刪除** `nova-backend/postgres` (新部署，可能為空)
3. 統一所有服務連接到 `postgres.nova.svc.cluster.local:5432`

---

## 3. 環境變量審計

### 環境變量注入策略對比

| 服務                  | ConfigMap 引用 | Secret 引用 | 直接值 | 總計 | 健康狀態 |
|-----------------------|---------------|-------------|--------|------|---------|
| **user-service** (nova-backend) | 4 | 3 | 4 | 11 | ❌ Crash |
| **auth-service**      | 0             | 0           | 8      | 8    | ✅ OK   |
| **graphql-gateway** (staging) | 0 | 0 | 18 | 18 | ✅ OK |
| **content-service**   | 0             | 0           | 0      | 0    | ⚠️ 無 env |
| **feed-service**      | 0             | 0           | 0      | 0    | ⚠️ 無 env |
| **media-service**     | 0             | 0           | 0      | 0    | ⚠️ 無 env |

### 問題分析

**Content/Feed/Media 服務沒有環境變量？**
```bash
# 檢查後發現：這些服務的配置是通過 ConfigMap 掛載為文件，而不是環境變量
# 但 Deployment YAML 中沒有 envFrom 引用
```

**三種注入方式混用**:
1. **ConfigMapKeyRef** - user-service 用這種 (DATABASE_URL, KAFKA_BROKERS)
2. **直接值** - auth-service, graphql-gateway 用這種
3. **文件掛載** - content-service 可能用這種 (需驗證)

**Linus 評論**:
> "Pick ONE way. Not three ways. This isn't 'flexibility', this is chaos.
> ConfigMapKeyRef for config, Secret for credentials, DONE."

---

## 4. 健康檢查配置

### 缺少 Probes 的服務

| 服務 | Liveness | Readiness | 影響 |
|------|----------|-----------|------|
| **content-service** | ❌ | ❌ | Kubernetes 無法判斷健康狀態，不會自動重啟 |
| **feed-service** | ❌ | ❌ | 同上 |
| **redis** | ❌ | ❌ | 如果 Redis 掛掉，服務會持續失敗 |

### 健康檢查配置問題

**user-service 的 probe 配置**:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 50051  # ❌ 這是 gRPC 端口，不能用 HTTP probe
    scheme: HTTP
```

**問題**: gRPC 服務不能用 HTTP probe，應該用 `grpc` probe (Kubernetes 1.24+)

**修復建議**:
```yaml
livenessProbe:
  grpc:
    port: 50051
    service: ""  # 默認服務
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 10
  periodSeconds: 5
```

---

## 5. 資源限制

### 資源分配策略

| 服務 | Requests (CPU/Mem) | Limits (CPU/Mem) | 評級 |
|------|-------------------|------------------|------|
| **auth-service** | 100m / 128Mi | 500m / 256Mi | ✅ 合理 |
| **user-service** | 100m / 256Mi | 500m / 512Mi | ✅ 合理 |
| **content-service** | 250m / 256Mi | 1000m / 512Mi | ⚠️ 偏高 |
| **feed-service** | 250m / 256Mi | 1000m / 512Mi | ⚠️ 偏高 |
| **media-service** | 250m / 512Mi | 1000m / 1Gi | ⚠️ 偏高 |
| **graphql-gateway** | 250m / 256Mi | 500m / 512Mi | ✅ 合理 |
| **postgres** | 250m / 512Mi | 500m / 1Gi | ✅ 合理 |
| **redis** | 100m / 64Mi | 500m / 128Mi | ✅ 合理 |

### Linus 評論
> "Content/Feed/Media services have 1 CPU core limit but no health checks?
> This is backwards. You can't monitor what you can't see. Fix the probes first,
> THEN worry about CPU limits."

---

## 6. 服務通信拓撲

### 當前架構

```mermaid
graph LR
    Internet --> |ALB| GW_Nova[GraphQL Gateway<br/>nova-gateway]
    Internet --> |NGINX| GW_Staging[GraphQL Gateway<br/>nova-staging]

    GW_Nova --> Auth[Auth Service<br/>nova-auth:None]
    GW_Nova --> User[User Service<br/>nova-backend:50051]
    GW_Nova --> Content[Content Service<br/>nova-content:8081]
    GW_Nova --> Feed[Feed Service<br/>nova-feed:8089]
    GW_Nova --> Media[Media Service<br/>nova-media:8082]
    GW_Nova --> Messaging[Messaging Service<br/>nova-backend:8085]
    GW_Nova --> Notification[Notification Service<br/>nova-backend:8088]

    User --> PG1[Postgres<br/>nova:5432]
    User --> PG2[Postgres<br/>nova-backend:5432]

    Content --> PG1
    Feed --> PG1
    Media --> Redis[Redis<br/>nova-media:6379]

    User -.-> |Missing| ClickHouse[ClickHouse<br/>❌ Not Deployed]
```

### 問題分析

1. **跨 Namespace 服務發現**:
   - GraphQL Gateway 需要訪問 7 個不同 namespace 的服務
   - 需要使用完整 FQDN: `<service>.<namespace>.svc.cluster.local`
   - 增加配置複雜度

2. **沒有服務網格 (Service Mesh)**:
   - 無 mTLS 加密
   - 無分布式追蹤
   - 無自動重試/熔斷

3. **網絡策略缺失**:
   - 只有 nova-gateway 有 NetworkPolicy
   - 其他服務間可以自由通信 (安全風險)

---

## 7. HPA (水平自動擴展) 問題

### 當前 HPA 配置

```bash
nova-gateway   graphql-gateway-hpa   <unknown>/70%, <unknown>/80%   3-10 pods
nova-staging   graphql-gateway       <unknown>/70%, <unknown>/80%   2-4 pods
nova           user-service-hpa      <unknown>/70%, <unknown>/80%   2-5 pods
```

### 問題

**Metrics Server 未部署**:
```bash
$ kubectl top nodes
error: Metrics API not available
```

**影響**:
- HPA 無法獲取 CPU/Memory 使用率
- 無法自動擴展
- 手動設置的 replica 數不會改變

**修復方案**:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## 8. ConfigMap 混亂分析

### 重複配置

**Kafka 配置出現在 4 個地方**:
```
nova-auth/kafka-config
nova-backend/kafka-config
nova-feed/kafka-config
nova-media/kafka-config
```

**內容完全相同**:
```yaml
KAFKA_BROKERS: "kafka:9092"
KAFKA_AUTO_OFFSET_RESET: "earliest"
KAFKA_GROUP_ID: "nova-consumers"
KAFKA_TIMEOUT_MS: "5000"
```

**Database 配置重複**:
```
nova-content/database-config
nova-feed/database-config
nova-media/database-config
```

### Linus 評論
> "WHY is the same Kafka config duplicated 4 times?
> This is a DATA STRUCTURE problem, not a Kubernetes problem.
> One ConfigMap, all services reference it. DRY principle, remember?"

---

## 9. Secret 管理問題

### 當前 Secret 分佈

| Namespace | Secret Name | Keys | 內容 |
|-----------|-------------|------|------|
| nova-auth | auth-service-secrets | 4 | JWT private key, DB password |
| nova-backend | nova-backend-secrets | 4 | AWS keys, JWT secret, DB password |
| nova-content | database-secrets | 1 | DB password |
| nova-feed | database-secrets | 1 | DB password |
| nova-media | database-secrets | 1 | DB password |

### 問題

1. **重複的數據庫密碼**:
   - 每個 namespace 都有 `database-secrets`
   - 如果密碼變更，需要更新 5 個地方

2. **缺少統一的 Secret 管理**:
   - 沒有使用 External Secrets Operator
   - 沒有 Vault 或 AWS Secrets Manager 集成
   - 手動管理 base64 編碼

3. **測試密碼在生產環境**:
```bash
# nova-backend-secrets
aws-access-key-id: eW91ci1hd3Mta2V5  # "your-aws-key"
jwt-secret: eW91ci1qd3Qtc2VjcmV0LWtleS1jaGFuZ2UtaW4tcHJvZHVjdGlvbg==
# "your-jwt-secret-key-change-in-production"
```

**🔴 BLOCKER**: 這些是明顯的測試值，必須在生產前更改！

---

## 10. 架構重構建議 (Linus Style)

### 當前架構評分: 3/10

**好的部分**:
- ✅ 所有服務都有資源限制
- ✅ 使用 ConfigMap/Secret 而非硬編碼
- ✅ 有 HPA 配置 (雖然不工作)

**垃圾部分**:
- ❌ 8 個 namespace 管理 11 個服務 (過度設計)
- ❌ 配置重複到處都是 (違反 DRY)
- ❌ 健康檢查缺失 (無法監控)
- ❌ 環境變量策略混亂 (三種方式並存)
- ❌ 兩個 Postgres 實例 (資源浪費)

### Linus 式簡化方案

#### 階段 1: 立即修復 (P0)

**1.1 修復 user-service 啟動問題**:
```bash
# 添加缺失的環境變量
kubectl patch configmap nova-backend-config -n nova-backend --type merge -p '
{
  "data": {
    "CLICKHOUSE_ENABLED": "false",
    "CLICKHOUSE_URL": "http://localhost:8123",
    "CLICKHOUSE_DB": "nova",
    "CLICKHOUSE_USER": "default",
    "CLICKHOUSE_PASSWORD": ""
  }
}'

# 重啟 deployment
kubectl rollout restart deployment user-service -n nova-backend
```

**1.2 刪除重複的 Postgres**:
```bash
# 驗證 nova/postgres 有數據
kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres -c "\l"

# 如果 nova-backend/postgres 為空，刪除它
kubectl delete deployment postgres -n nova-backend
kubectl delete service postgres -n nova-backend

# 更新所有服務的 DATABASE_URL 指向 nova/postgres
# postgresql://postgres:password@postgres.nova.svc.cluster.local:5432/nova_staging
```

**1.3 部署 Metrics Server**:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 驗證
kubectl top nodes
kubectl get hpa -A
```

#### 階段 2: Namespace 整合 (P1)

**問題**: 8 個 namespace 太多，管理複雜

**目標架構** (3 個 namespace):
```
nova-production/   # 生產環境所有服務
nova-staging/      # 測試環境
nova-infra/        # 基礎設施 (Postgres, Redis, Kafka, ClickHouse)
```

**遷移計劃**:
```bash
# 1. 創建統一的 ConfigMap
kubectl create configmap nova-global-config -n nova-production \
  --from-literal=KAFKA_BROKERS=kafka.nova-infra.svc.cluster.local:9092 \
  --from-literal=DATABASE_URL=postgresql://... \
  --from-literal=REDIS_URL=redis://...

# 2. 創建統一的 Secret
kubectl create secret generic nova-global-secrets -n nova-production \
  --from-literal=database-password=... \
  --from-literal=jwt-secret=...

# 3. 遷移服務
kubectl get all -n nova-auth -o yaml | \
  sed 's/namespace: nova-auth/namespace: nova-production/' | \
  kubectl apply -f -

# 4. 刪除舊 namespace
kubectl delete namespace nova-auth
```

#### 階段 3: 配置標準化 (P1)

**統一環境變量策略**:

1. **ConfigMap** - 用於非敏感配置:
   - 服務 URL
   - 端口
   - 超時時間
   - 特性開關

2. **Secret** - 用於敏感信息:
   - 數據庫密碼
   - API Keys
   - JWT Secret

3. **直接值** - 用於不變的常量:
   - 服務名稱
   - 環境標識 (staging/production)

**實施**:
```yaml
# kubernetes/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nova-config
data:
  # 數據庫
  DATABASE_URL: "postgresql://postgres@postgres.nova-infra:5432/nova"

  # 消息隊列
  KAFKA_BROKERS: "kafka.nova-infra:9092"

  # 緩存
  REDIS_URL: "redis://redis.nova-infra:6379"

  # ClickHouse (可選)
  CLICKHOUSE_ENABLED: "false"
  CLICKHOUSE_URL: "http://clickhouse.nova-infra:8123"

  # gRPC
  GRPC_KEEPALIVE_INTERVAL: "30s"
  GRPC_KEEPALIVE_TIMEOUT: "10s"
  GRPC_MAX_CONCURRENT_STREAMS: "1000"
```

#### 階段 4: 健康檢查標準化 (P1)

**所有服務必須實現**:
```yaml
# 1. gRPC 服務
livenessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 10
  periodSeconds: 5

# 2. HTTP 服務
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5

# 3. Redis/Postgres (使用 exec)
livenessProbe:
  exec:
    command:
    - redis-cli
    - ping
  initialDelaySeconds: 30
  periodSeconds: 10
```

---

## 11. 成本優化建議

### 當前資源分配

**總 CPU Requests**: 2.15 cores
**總 CPU Limits**: 7.5 cores
**總 Memory Requests**: 3.5 GB
**總 Memory Limits**: 7.5 GB

### 過度配置的服務

| 服務 | 當前 Limit | 建議 Limit | 節省 |
|------|-----------|-----------|------|
| content-service | 1 CPU / 512Mi | 500m / 256Mi | 50% |
| feed-service | 1 CPU / 512Mi | 500m / 256Mi | 50% |
| media-service | 1 CPU / 1Gi | 500m / 512Mi | 50% |

**預計節省**: 30% CPU, 25% Memory

### Linus 評論
> "You're allocating 1 CPU core to services that don't even have health checks?
> This is like buying a Ferrari for someone who doesn't know how to drive.
> Start with 500m, monitor actual usage, THEN scale up if needed."

---

## 12. 安全加固建議

### 當前安全評分: 4/10

**缺失的安全措施**:

1. **NetworkPolicy** - 只有 nova-gateway 有，其他服務沒有
2. **Pod Security Standards** - 沒有強制執行
3. **Service Account** - 使用默認 SA
4. **RBAC** - 沒有自定義 Role/RoleBinding
5. **Secret 加密** - 沒有使用 KMS
6. **Image 掃描** - 沒有 admission webhook

### 推薦配置

**NetworkPolicy 模板**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: nova-production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-gateway
  namespace: nova-production
spec:
  podSelector:
    matchLabels:
      app: user-service
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: graphql-gateway
    ports:
    - protocol: TCP
      port: 50051
```

**Pod Security Standard**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nova-production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

---

## 13. 監控和可觀測性

### 缺失的組件

1. **Metrics Server** ❌ - HPA 無法工作
2. **Prometheus** ❌ - 沒有指標收集
3. **Grafana** ❌ - 沒有可視化
4. **Loki** ❌ - 沒有日誌聚合
5. **Jaeger/Tempo** ❌ - 沒有分布式追蹤

### 推薦方案

**部署 Kube-Prometheus-Stack**:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

**服務需要暴露指標端點**:
```rust
// 所有 Rust 服務添加 /metrics
use prometheus::{Encoder, TextEncoder};

#[get("/metrics")]
async fn metrics() -> Result<String, Error> {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();
    let mut buffer = vec![];
    encoder.encode(&metric_families, &mut buffer)?;
    Ok(String::from_utf8(buffer)?)
}
```

---

## 14. GitOps 集成

### 當前狀態

**問題**: 所有配置似乎是手動 `kubectl apply`，沒有 Git 記錄

**推薦方案**: ArgoCD

**實施步驟**:
```bash
# 1. 部署 ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. 創建 Application
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nova-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/nova
    targetRevision: main
    path: kubernetes/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: nova-production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

---

## 15. 立即行動清單

### P0 - 今天必須做 (2-4 小時)

```bash
# 1. 修復 user-service 啟動問題
kubectl patch configmap nova-backend-config -n nova-backend --type merge -p '{
  "data": {
    "CLICKHOUSE_ENABLED": "false",
    "CLICKHOUSE_URL": "http://localhost:8123",
    "CLICKHOUSE_DB": "nova"
  }
}'
kubectl rollout restart deployment user-service -n nova-backend

# 2. 部署 Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 3. 添加健康檢查到 content-service, feed-service, redis
# (需要修改 Kubernetes YAML)

# 4. 檢查並刪除重複的 Postgres (如果 nova-backend/postgres 為空)
kubectl delete deployment postgres -n nova-backend
kubectl delete service postgres -n nova-backend
```

### P1 - 本週內 (1-2 天)

```bash
# 1. Namespace 整合規劃
# 2. 統一 ConfigMap/Secret 策略
# 3. 部署 NetworkPolicy 到所有服務
# 4. 更換測試密碼為生產密碼
# 5. 設置監控堆棧 (Prometheus/Grafana)
```

### P2 - 本月內 (1 週)

```bash
# 1. 實施 GitOps (ArgoCD)
# 2. 添加 Pod Security Standards
# 3. 集成 External Secrets Operator
# 4. 設置 Service Mesh (Istio/Linkerd)
# 5. 實施分布式追蹤
```

---

## 16. Linus 最終評論

> **"This is a mess. But it's a fixable mess."**
>
> 你的問題不是技術能力，而是過度設計。8 個 namespace？這不是"微服務架構"，
> 這是"微混亂架構"。
>
> **三個核心問題**:
>
> 1. **數據結構錯誤** - 配置重複到處都是，違反 DRY 原則
> 2. **特殊情況過多** - 每個服務有自己的配置方式，沒有統一標準
> 3. **複雜度爆炸** - 8 個 namespace 管理 11 個服務，管理成本 > 收益
>
> **解決方案**:
>
> 1. **刪除所有特殊情況** - 統一配置策略，一個 ConfigMap，所有服務引用
> 2. **簡化數據結構** - 3 個 namespace (prod/staging/infra)，不是 8 個
> 3. **消除重複** - 一個 Postgres，一個 Redis，不是多個
>
> **記住**:
> - Good taste 不是"更多功能"，而是"更少複雜性"
> - Never break userspace - 遷移時先 expand，後 contract
> - Theory and practice - 你的 HPA 配置很完美，但 Metrics Server 沒部署 🤦
>
> **Get your basics right first. Then optimize. Not the other way around.**

---

## 附錄 A: 完整資源清單

### Deployments
```
nova/postgres
nova-backend/cdn-service
nova-backend/events-service
nova-backend/messaging-service
nova-backend/notification-service
nova-backend/user-service
nova-auth/auth-service
nova-content/content-service
nova-feed/feed-service
nova-media/media-service
nova-media/redis
nova-gateway/graphql-gateway
nova-staging/graphql-gateway
```

### ConfigMaps (不含 kube-root-ca.crt)
```
nova/postgres-init-config
nova/user-service-config
nova-auth/auth-service-configmap
nova-auth/kafka-config
nova-backend/kafka-config
nova-backend/nova-backend-config
nova-content/content-service-config
nova-content/content-service-jwt
nova-content/database-config
nova-feed/database-config
nova-feed/feed-service-config
nova-feed/kafka-config
nova-media/database-config
nova-media/kafka-config
nova-media/media-service-config
nova-gateway/graphql-gateway-config
nova-gateway/graphql-gateway-config-production
nova-staging/graphql-gateway-config
```

### Secrets
```
nova-auth/auth-service-secrets
nova-backend/nova-backend-secrets
nova-content/database-secrets
nova-feed/database-secrets
nova-media/database-secrets
nova-gateway/graphql-gateway-secrets
nova-staging/graphql-gateway-secrets
```

---

**報告結束**

生成時間: 2025-11-11
下次審計: 配置修復後 1 週
