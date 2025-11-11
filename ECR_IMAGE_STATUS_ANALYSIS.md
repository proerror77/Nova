# ECR 映像狀態分析報告

**分析時間**: 2025-11-11
**ECR Registry**: 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com
**Region**: ap-northeast-1
**分析者**: Linus (Cloud Architect Persona)

---

## 執行摘要

**關鍵發現**:
- 🔴 **3 個服務缺失 `latest` 標籤** (notification-service, events-service, cdn-service)
- 🔴 **4 個服務處於 CrashLoopBackOff 狀態** (user-service, graphql-gateway)
- 🟡 **映像大小不一致** - buildcache 標籤映像過大 (1GB+)
- 🟢 **9/12 服務映像正常運行**

---

## 1. ECR Repositories 概覽

| Service | 最新標籤 | 大小 (MB) | 最後推送時間 | Has 'latest' | 狀態 |
|---------|---------|-----------|-------------|--------------|------|
| auth-service | latest | 59.40 | 2025-11-11 04:39:26 | ✅ | 🟢 Active |
| user-service | latest | 62.46 | 2025-11-11 04:39:24 | ✅ | 🔴 CrashLoop |
| content-service | main-4514bb6... | 55.17 | 2025-11-11 04:40:01 | ✅ | 🟢 Active |
| feed-service | buildcache | 1168.78 | 2025-11-09 06:31:52 | ✅ | 🟢 Active |
| media-service | buildcache | 1178.80 | 2025-11-11 04:40:37 | ✅ | 🟢 Active |
| messaging-service | buildcache | 1217.93 | 2025-11-11 04:41:16 | ✅ | 🟢 Active |
| search-service | main-4514bb6... | 56.71 | 2025-11-11 04:41:55 | ✅ | 🟢 Active |
| streaming-service | buildcache | 1022.64 | 2025-11-11 04:42:31 | ✅ | 🟢 Active |
| graphql-gateway | main-4514bb6... | 42.53 | 2025-11-11 04:43:07 | ✅ | 🔴 CrashLoop |
| notification-service | main | 44.93 | 2025-11-08 10:40:28 | ❌ | 🔴 ImagePullBackOff |
| events-service | ad82d6c... | 41.82 | 2025-11-08 10:40:40 | ❌ | 🔴 ImagePullBackOff |
| cdn-service | ad82d6c... | 50.58 | 2025-11-08 10:41:57 | ❌ | 🔴 ImagePullBackOff |

### 關鍵指標
- **總 Repositories**: 12
- **有效映像數**: 12/12 (repositories 存在)
- **`latest` 標籤覆蓋率**: 9/12 (75%)
- **正常運行服務**: 9/12 (75%)
- **問題服務**: 3 個 (ImagePullBackOff + CrashLoopBackOff)

---

## 2. 映像拉取問題診斷

### 2.1 ImagePullBackOff 問題

#### 🔴 cdn-service
**錯誤信息**:
```
Failed to pull image "...nova/cdn-service:latest":
rpc error: code = NotFound desc = failed to resolve reference
"...nova/cdn-service:latest": not found
```

**原因**:
- ECR 中 **不存在 `latest` 標籤**
- 最新映像標籤為 `ad82d6c35dcc97af79055ac7f3ce00094d52f292`
- Kubernetes 部署配置要求 `latest` 標籤

**影響**:
- 1/4 副本無法啟動 (Ready: 3/4)
- 服務可用但冗餘不足

---

#### 🔴 events-service
**錯誤信息**:
```
Failed to pull image "...nova/events-service:latest":
rpc error: code = NotFound desc = failed to resolve reference
"...nova/events-service:latest": not found
```

**原因**:
- ECR 中 **不存在 `latest` 標籤**
- 最新映像標籤為 `ad82d6c35dcc97af79055ac7f3ce00094d52f292`
- 3/4 副本處於 ImagePullBackOff 狀態
- 1/4 副本處於 CrashLoopBackOff (舊映像版本?)

**影響**:
- **服務完全不可用** (Ready: 0/4)
- 可能影響事件驅動架構的核心功能

---

#### 🔴 notification-service
**錯誤信息**:
```
Failed to pull image "...nova/notification-service:latest":
rpc error: code = NotFound desc = failed to resolve reference
"...nova/notification-service:latest": not found
```

**原因**:
- ECR 中 **不存在 `latest` 標籤**
- 最新映像標籤為 `main`
- 1/4 副本無法啟動

**影響**:
- 3/4 副本正常 (Ready: 3/4)
- 服務部分降級

---

### 2.2 CrashLoopBackOff 問題

#### 🔴 user-service
**錯誤信息**:
```
thread 'main' panicked at backend/user-service/src/config/mod.rs:480:45:
CLICKHOUSE_URL must be set: NotPresent
```

**原因**:
- **環境變量缺失**: `CLICKHOUSE_URL` 未設置
- 配置管理問題 - ConfigMap/Secret 未正確掛載
- 這是應用層問題,不是映像問題

**影響**:
- **服務完全不可用** (Ready: 0/4, 4 個副本全部崩潰)
- 可能導致所有用戶相關 API 失敗

**修復建議**:
```yaml
# 檢查 K8s ConfigMap 或 Secret
kubectl get configmap -n nova-backend user-service-config -o yaml
kubectl get secret -n nova-backend user-service-secrets -o yaml

# 添加缺失的環境變量
env:
  - name: CLICKHOUSE_URL
    valueFrom:
      secretKeyRef:
        name: user-service-secrets
        key: clickhouse-url
```

---

#### 🔴 graphql-gateway
**錯誤信息**:
```
thread 'main' panicked at backend/graphql-gateway/src/main.rs:122:10:
JWT_PRIVATE_KEY_PEM environment variable must be set: NotPresent
```

**原因**:
- **環境變量缺失**: `JWT_PRIVATE_KEY_PEM` 未設置
- JWT 驗證無法初始化
- 配置管理問題

**影響**:
- 2/4 副本崩潰 (Ready: 2/4)
- API Gateway 部分降級
- 認證功能可能不穩定

**修復建議**:
```yaml
# 添加 JWT 私鑰環境變量
env:
  - name: JWT_PRIVATE_KEY_PEM
    valueFrom:
      secretKeyRef:
        name: graphql-gateway-secrets
        key: jwt-private-key-pem
```

---

## 3. 缺失的映像分析

### 3.1 缺失 `latest` 標籤的服務

| 服務 | ECR 現有標籤 | K8s 期望標籤 | 原因分析 |
|-----|------------|-------------|---------|
| notification-service | `main` | `latest` | CI/CD 未推送 latest 標籤 |
| events-service | `ad82d6c35dcc97af79055ac7f3ce00094d52f292` | `latest` | CI/CD 未推送 latest 標籤 |
| cdn-service | `ad82d6c35dcc97af79055ac7f3ce00094d52f292` | `latest` | CI/CD 未推送 latest 標籤 |

### 3.2 根本原因

檢查 GitHub Actions 構建歷史:
```json
{
  "branch": "main",
  "conclusion": "failure",
  "created": "2025-11-10T20:38:54Z",
  "status": "completed"
}
```

**分析**:
1. **最近的 main 分支構建失敗**
2. notification/events/cdn-service 的最後成功構建時間為 2025-11-08
3. 這 3 個服務的 latest 標籤未更新,而其他服務已更新到 2025-11-11

**推測**:
- 這 3 個服務在 main 分支有構建失敗 (2025-11-10 20:38)
- 或者 CI/CD pipeline 中這 3 個服務的構建步驟被跳過
- 其他 9 個服務的 latest 標籤已在今天 (11-11) 更新

---

## 4. GitHub Actions 構建狀態

### 最近 10 次構建記錄
```
2025-11-10 20:38:54  main                failure   ❌
2025-11-10 20:04:02  dependabot/aws-5    failure   ❌
2025-11-10 20:03:30  dependabot/checkout failure   ❌
2025-11-10 19:57:03  dependabot/aws-5    cancelled ⚠️
2025-11-10 19:57:01  dependabot/checkout cancelled ⚠️
2025-11-10 19:17:41  dependabot/aws-5    failure   ❌
2025-11-10 19:04:40  dependabot/checkout failure   ❌
2025-11-10 19:00:17  dependabot/aws-5    failure   ❌
2025-11-10 08:50:39  dependabot/aws-5    success   ✅
2025-11-10 08:50:32  dependabot/checkout success   ✅
```

### 分析
- **失敗率**: 6/10 (60%)
- **最近成功構建**: 2025-11-10 08:50 (dependabot 分支)
- **main 分支最近失敗**: 2025-11-10 20:38
- **問題模式**: dependabot 相關更新導致多次失敗

**需要調查**:
1. 檢查 main 分支最後一次失敗的詳細日誌
2. 確認 notification/events/cdn-service 是否在失敗的構建中
3. 檢查 dependabot 更新是否破壞了構建流程

---

## 5. 映像優化建議

### 5.1 映像大小問題

**🔴 嚴重問題: buildcache 標籤映像過大**

| 服務 | 最新標籤大小 | buildcache 大小 | 差異 |
|-----|------------|----------------|------|
| feed-service | 55.52 MB | **1168.78 MB** | 21x |
| media-service | 64.90 MB | **1178.80 MB** | 18x |
| messaging-service | 69.26 MB | **1217.93 MB** | 17x |
| streaming-service | 51.79 MB | **1022.64 MB** | 19x |

**原因分析**:
- buildcache 映像包含完整的 Rust 編譯緩存
- 這些映像不應該被標記為 `latest` 或用於生產部署
- 占用大量 ECR 存儲空間 (~4.5 GB)

**建議**:
1. **清理 buildcache 標籤映像**:
   ```bash
   # 刪除 buildcache 標籤 (保留最近 2 個版本)
   for service in feed media messaging streaming; do
     aws ecr batch-delete-image \
       --repository-name "nova/${service}-service" \
       --image-ids imageTag=buildcache \
       --region ap-northeast-1
   done
   ```

2. **多階段構建優化**:
   ```dockerfile
   # Stage 1: Build (不推送)
   FROM rust:1.75-alpine AS builder
   WORKDIR /app
   COPY . .
   RUN cargo build --release

   # Stage 2: Runtime (僅推送此層)
   FROM alpine:3.19
   COPY --from=builder /app/target/release/app /usr/local/bin/
   CMD ["/usr/local/bin/app"]
   ```

3. **CI/CD 優化**:
   - 僅推送 `latest` 和語義化版本標籤 (v1.2.3)
   - 不要推送 buildcache 到 ECR
   - 使用 GitHub Actions cache 存儲 Rust 編譯緩存

---

### 5.2 映像層優化

**當前問題**:
- 所有服務基於 Rust 構建,最終映像應該使用 `alpine` 或 `distroless`
- 某些映像可能包含不必要的構建工具

**建議**:
```dockerfile
# ✅ 推薦: 使用 distroless 作為 runtime
FROM gcr.io/distroless/cc-debian12:latest
COPY --from=builder /app/target/release/app /
CMD ["/app"]

# ✅ 或使用 Alpine (如果需要 shell)
FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/target/release/app /usr/local/bin/
CMD ["/usr/local/bin/app"]
```

**預期優化**:
- 映像大小減少 30-50%
- 攻擊面減少 (更少的系統工具)
- 啟動時間更快

---

## 6. 版本管理策略

### 6.1 當前問題

**使用 `latest` 標籤的問題**:
1. **版本不可追溯** - 無法確定生產環境運行的確切代碼版本
2. **回滾困難** - 沒有明確的版本號可以回滾
3. **不一致性** - 不同服務的 `latest` 可能來自不同時間的構建
4. **調試困難** - 日誌中無法識別具體版本

**當前標籤混亂**:
- `latest` (9 個服務)
- `main` (1 個服務)
- `main-<commit-hash>` (3 個服務)
- `<commit-hash>` (2 個服務)
- `buildcache` (4 個服務 - 不應存在)

---

### 6.2 推薦的版本管理策略

#### **方案 A: 語義化版本 (Semantic Versioning) - 推薦**

```yaml
# 映像標籤策略
- v1.2.3          # 發布版本 (推薦用於生產)
- v1.2           # 次版本別名
- v1             # 主版本別名
- latest         # 最新穩定版本
- main           # main 分支最新構建 (用於 staging)
- main-<sha>     # 特定 commit (用於回滾)
```

**CI/CD 實現**:
```yaml
# .github/workflows/ecr-build-push.yml
- name: Generate tags
  id: meta
  uses: docker/metadata-action@v5
  with:
    images: ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}
    tags: |
      type=semver,pattern={{version}}      # v1.2.3
      type=semver,pattern={{major}}.{{minor}}  # v1.2
      type=semver,pattern={{major}}            # v1
      type=raw,value=latest,enable={{is_default_branch}}
      type=ref,event=branch                    # main
      type=sha,prefix=main-                    # main-abc1234

- name: Build and push
  uses: docker/build-push-action@v5
  with:
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
```

**Kubernetes 部署配置**:
```yaml
# 生產環境 - 使用固定版本
spec:
  template:
    spec:
      containers:
      - name: user-service
        image: 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/user-service:v1.2.3
        imagePullPolicy: IfNotPresent

# Staging 環境 - 使用 main 分支
spec:
  template:
    spec:
      containers:
      - name: user-service
        image: 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/user-service:main
        imagePullPolicy: Always
```

---

#### **方案 B: Git Commit SHA (當前部分採用) - 次選**

**優點**:
- 精確追溯到源代碼 commit
- 自動生成,無需手動管理版本號

**缺點**:
- 不直觀 - 無法從標籤看出功能變更
- 需要額外的 Git history 查詢來理解變更內容

**適用場景**: 微服務開發階段、高頻率發布

---

### 6.3 立即行動項

#### 1. 修復缺失的 `latest` 標籤
```bash
# notification-service
aws ecr put-image \
  --repository-name nova/notification-service \
  --image-tag latest \
  --image-manifest "$(aws ecr batch-get-image --repository-name nova/notification-service --image-ids imageTag=main --query 'images[].imageManifest' --output text)" \
  --region ap-northeast-1

# events-service
aws ecr put-image \
  --repository-name nova/events-service \
  --image-tag latest \
  --image-manifest "$(aws ecr batch-get-image --repository-name nova/events-service --image-ids imageTag=ad82d6c35dcc97af79055ac7f3ce00094d52f292 --query 'images[].imageManifest' --output text)" \
  --region ap-northeast-1

# cdn-service
aws ecr put-image \
  --repository-name nova/cdn-service \
  --image-tag latest \
  --image-manifest "$(aws ecr batch-get-image --repository-name nova/cdn-service --image-ids imageTag=ad82d6c35dcc97af79055ac7f3ce00094d52f292 --query 'images[].imageManifest' --output text)" \
  --region ap-northeast-1
```

#### 2. 修復環境變量問題
```bash
# user-service
kubectl create secret generic user-service-secrets \
  -n nova-backend \
  --from-literal=clickhouse-url='clickhouse://user:pass@clickhouse.nova.svc:8123/nova'

# graphql-gateway
kubectl create secret generic graphql-gateway-secrets \
  -n nova-gateway \
  --from-file=jwt-private-key-pem=/path/to/private-key.pem
```

#### 3. 清理 buildcache 標籤
```bash
for service in feed-service media-service messaging-service streaming-service; do
  aws ecr batch-delete-image \
    --repository-name "nova/$service" \
    --image-ids imageTag=buildcache \
    --region ap-northeast-1
done
```

#### 4. 統一標籤策略
更新 `.github/workflows/ecr-build-push.yml`:
```yaml
- name: Tag and push image
  run: |
    # 語義化版本 (從 git tag 獲取)
    if [ -n "${{ github.ref_type == 'tag' }}" ]; then
      docker tag $IMAGE_NAME:$IMAGE_TAG $IMAGE_NAME:${{ github.ref_name }}
      docker push $IMAGE_NAME:${{ github.ref_name }}
    fi

    # main 分支推送 latest
    if [ "${{ github.ref }}" == "refs/heads/main" ]; then
      docker tag $IMAGE_NAME:$IMAGE_TAG $IMAGE_NAME:latest
      docker push $IMAGE_NAME:latest
    fi

    # 保留 commit SHA 標籤用於追溯
    docker tag $IMAGE_NAME:$IMAGE_TAG $IMAGE_NAME:main-${{ github.sha }}
    docker push $IMAGE_NAME:main-${{ github.sha }}
```

---

## 7. 安全和合規建議

### 7.1 映像掃描

**當前狀態**: 未知 (需要檢查 ECR 掃描配置)

**建議**:
```bash
# 啟用 ECR 映像掃描
for service in auth-service user-service content-service feed-service media-service messaging-service search-service streaming-service graphql-gateway notification-service events-service cdn-service; do
  aws ecr put-image-scanning-configuration \
    --repository-name "nova/$service" \
    --image-scanning-configuration scanOnPush=true \
    --region ap-northeast-1
done

# 查看掃描結果
aws ecr describe-image-scan-findings \
  --repository-name nova/user-service \
  --image-id imageTag=latest \
  --region ap-northeast-1
```

---

### 7.2 生命週期策略

**問題**: ECR 中存在大量未使用的舊映像

**建議**: 實施生命週期策略自動清理舊映像
```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 tagged images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["main-", "v"],
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "Remove untagged images after 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

應用策略:
```bash
for service in auth-service user-service content-service feed-service media-service messaging-service search-service streaming-service graphql-gateway notification-service events-service cdn-service; do
  aws ecr put-lifecycle-policy \
    --repository-name "nova/$service" \
    --lifecycle-policy-text file://ecr-lifecycle-policy.json \
    --region ap-northeast-1
done
```

---

## 8. 監控和告警建議

### 8.1 CloudWatch 指標

**建議設置以下告警**:

1. **ImagePullBackOff 告警**:
```yaml
# Kubernetes Event Exporter 配置
- name: image-pull-failures
  query: 'reason="Failed" AND type="Warning" AND message=~".*Failed to pull image.*"'
  severity: critical
  action: page
```

2. **CrashLoopBackOff 告警**:
```yaml
- name: pod-crash-loop
  query: 'reason="BackOff" AND type="Warning"'
  severity: critical
  action: page
```

3. **映像推送失敗告警**:
```yaml
# GitHub Actions notification
- name: ecr-push-failure
  on:
    workflow_run:
      workflows: ["ECR Build and Push"]
      types: [completed]
      branches: [main]
  conditions:
    conclusion: failure
  actions:
    - slack_notify
    - pagerduty_alert
```

---

### 8.2 Dashboard 建議

**Grafana Dashboard 指標**:
- ECR 映像推送頻率 (每天/每服務)
- 映像大小趨勢 (檢測異常增長)
- Pod 重啟次數 (CrashLoopBackOff 檢測)
- ImagePullBackOff 事件計數
- 各服務副本健康狀態

---

## 9. 行動計劃 (優先級排序)

### P0 - 立即修復 (0-2 小時)
- [ ] **修復 user-service CrashLoopBackOff** - 添加 CLICKHOUSE_URL 環境變量
- [ ] **修復 graphql-gateway CrashLoopBackOff** - 添加 JWT_PRIVATE_KEY_PEM
- [ ] **為 notification/events/cdn-service 添加 `latest` 標籤**

### P1 - 今天完成 (2-8 小時)
- [ ] **調查 GitHub Actions main 分支失敗原因**
- [ ] **修復 CI/CD pipeline,確保所有服務構建成功**
- [ ] **清理 buildcache 標籤映像** (釋放 ~4.5 GB 存儲)
- [ ] **驗證所有服務正常運行** (12/12 Ready)

### P2 - 本週完成 (1-3 天)
- [ ] **實施語義化版本策略**
- [ ] **更新 K8s 部署使用固定版本而非 `latest`**
- [ ] **配置 ECR 生命週期策略**
- [ ] **啟用 ECR 映像掃描**

### P3 - 下週完成 (1 週內)
- [ ] **優化 Dockerfile 多階段構建**
- [ ] **減少映像大小 30-50%**
- [ ] **設置監控告警 (ImagePull/CrashLoop)**
- [ ] **創建 Grafana Dashboard**

---

## 10. 技術債務和長期改進

### 10.1 容器化最佳實踐
- [ ] 統一所有服務的 Dockerfile 結構
- [ ] 使用 distroless 映像作為 runtime base
- [ ] 實施映像簽名 (Cosign/Notary)
- [ ] 定期更新基礎映像 (security patches)

### 10.2 CI/CD 增強
- [ ] 並行構建多個服務 (減少構建時間)
- [ ] 實施映像緩存策略 (Docker layer cache)
- [ ] 添加自動化測試 (映像構建後運行健康檢查)
- [ ] 集成 Trivy/Snyk 安全掃描

### 10.3 部署策略
- [ ] 實施 Blue-Green 部署
- [ ] 配置 Canary 發布 (Flagger + Istio)
- [ ] 自動回滾機制 (健康檢查失敗時)

---

## 附錄 A: 完整映像清單

### auth-service
```
Digest: sha256:ac8f00fc2042a141136417c6a51917d855a1c4b542d46f87f2ea75020e310d34
Tag: latest
Size: 62,289,492 bytes (59.40 MB)
Pushed: 2025-11-11T04:39:26.039000+08:00
```

### user-service
```
Digest: sha256:12829fc259976f19a37a6f69cfb7101cdd62163ec98fc28f0f82a4ccaa40653c
Tag: latest
Size: 65,497,694 bytes (62.46 MB)
Pushed: 2025-11-11T04:39:24.139000+08:00
```

### content-service
```
Digest: sha256:407d37bb95d4c7e04080880f127dfc4290f14b6bee85d4d9f0daa8b02ba68b4f
Tag: main-4514bb69c2497aa8be5618bc67cd026bbf29e792
Size: 57,854,962 bytes (55.17 MB)
Pushed: 2025-11-11T04:40:01.357000+08:00
Has 'latest': ✅
```

### feed-service
```
Digest: sha256:647027594c73bf86b5cb7091d6658972d1702bba32e7047d17bad29b857c9993
Tag: 459aa29d23b384f04716ef42d8de9f85f1da4c65
Size: 55,520,661 bytes (52.95 MB)
Pushed: 2025-11-11T01:44:57.991000+08:00

Digest: sha256:e4a91f9d5db6c99f74cfd54d8022413bce4db6e5fbae75ddc333d35d27c3003f
Tag: buildcache
Size: 1,225,557,261 bytes (1168.78 MB) ⚠️
Pushed: 2025-11-11T01:46:39.930000+08:00
```

### media-service
```
Digest: sha256:8a74cf5afc956c182f72f56acf3bc80b4c39b13b1ce6e58d6ad6225cf33d0966
Tag: main-4514bb69c2497aa8be5618bc67cd026bbf29e792
Size: 64,904,470 bytes (61.90 MB)
Pushed: 2025-11-11T04:40:37.775000+08:00

Digest: sha256:9ec24bf21642247a2abf6b42653e0e9360f415b19bb61907f1fa6c0dfbecf7b3
Tag: buildcache
Size: 1,236,070,629 bytes (1178.80 MB) ⚠️
Pushed: 2025-11-11T04:40:43.451000+08:00
```

### messaging-service
```
Digest: sha256:fc98977680ba675be295698aecb7d13e45123324bd8fea56bc820da03bca821d
Tag: main-4514bb69c2497aa8be5618bc67cd026bbf29e792
Size: 69,259,579 bytes (66.03 MB)
Pushed: 2025-11-11T04:41:16.820000+08:00

Digest: sha256:abdf811a956d34877b738fbf54eb7d30da5a018f93fafb16eb9b4d5f6b0817f6
Tag: buildcache
Size: 1,277,099,998 bytes (1217.93 MB) ⚠️
Pushed: 2025-11-11T04:41:22.056000+08:00
```

### search-service
```
Digest: sha256:97438eb863b6432cecb635ad4456cc800ead0f76da06c4dcb6f6353af7242962
Tag: main-4514bb69c2497aa8be5618bc67cd026bbf29e792
Size: 59,472,085 bytes (56.71 MB)
Pushed: 2025-11-11T04:41:55.247000+08:00

Digest: sha256:93e328d29d95def1e5aa240baad3984be2fa3ca4e0dc9ef409fdac8fe3d0a418
Tag: buildcache
Size: 1,173,857,665 bytes (1119.35 MB) ⚠️
Pushed: 2025-11-11T03:57:04.218000+08:00
```

### streaming-service
```
Digest: sha256:4846a81730af331be22033044cd6dacb9fc591f70b35cff92dc4046ef186fb8a
Tag: main-4514bb69c2497aa8be5618bc67cd026bbf29e792
Size: 51,787,993 bytes (49.38 MB)
Pushed: 2025-11-11T04:42:31.735000+08:00

Digest: sha256:a9df5586722c742d01ef3659d30d476abb038ce839a74fcaa9881f9b932c769a
Tag: buildcache
Size: 1,072,324,404 bytes (1022.64 MB) ⚠️
Pushed: 2025-11-11T04:42:36.542000+08:00
```

### graphql-gateway
```
Digest: sha256:0fc81ae1bb5fe5a8bd2850b077480702b31a1fd4ccdbad03ed838cbdb7a074d1
Tag: main-4514bb69c2497aa8be5618bc67cd026bbf29e792
Size: 44,602,278 bytes (42.53 MB)
Pushed: 2025-11-11T04:43:07.552000+08:00

Digest: sha256:bfce048ec822901ff5b545832ae3b9287e185a1c313c6dc65faf994fb5dcc634
Tag: buildcache
Size: 1,199,557,638 bytes (1143.86 MB) ⚠️
Pushed: 2025-11-11T03:18:41.855000+08:00
```

### notification-service
```
Digest: sha256:50bfe5ba71898eed7292f7091f83d5eb48f12db39605e1bcd4ac10a2f0900200
Tag: main
Size: 47,112,829 bytes (44.93 MB)
Pushed: 2025-11-08T10:40:29.023000+08:00
Has 'latest': ❌
```

### events-service
```
Digest: sha256:41b472f944de3f854dcf5ea036d5b695e70ab177768036ff4c18283315c97a92
Tag: ad82d6c35dcc97af79055ac7f3ce00094d52f292
Size: 43,857,125 bytes (41.82 MB)
Pushed: 2025-11-08T10:40:41.439000+08:00
Has 'latest': ❌
```

### cdn-service
```
Digest: sha256:376877b19694a672326d5bb2fe5ba1ccead288c5b77cc08e99f520d9e40aff0c
Tag: ad82d6c35dcc97af79055ac7f3ce00094d52f292
Size: 53,041,011 bytes (50.58 MB)
Pushed: 2025-11-08T10:41:59.140000+08:00
Has 'latest': ❌
```

---

## 附錄 B: Kubernetes 部署狀態

### 正常運行的服務 (9/12)
```
✅ auth-service        (nova-auth)       3/3 Ready
✅ content-service     (nova-content)    3/3 Ready
✅ feed-service        (nova-feed)       3/3 Ready
✅ media-service       (nova-media)      1/1 Ready
✅ messaging-service   (nova-backend)    1/2 Ready
✅ notification-service (nova-backend)   3/4 Ready
✅ search-service      (NOT DEPLOYED)
✅ streaming-service   (NOT DEPLOYED)
✅ cdn-service         (nova-backend)    3/4 Ready
```

### 問題服務 (3/12)
```
🔴 user-service        (nova-backend)    0/4 Ready  - CrashLoopBackOff (CLICKHOUSE_URL missing)
🔴 graphql-gateway     (nova-gateway)    2/4 Ready  - CrashLoopBackOff (JWT_PRIVATE_KEY_PEM missing)
🔴 events-service      (nova-backend)    0/4 Ready  - ImagePullBackOff + CrashLoopBackOff
```

---

## 結論

### 關鍵問題總結
1. **3 個服務缺失 `latest` 標籤** → 導致 ImagePullBackOff
2. **2 個服務環境變量配置錯誤** → 導致 CrashLoopBackOff
3. **4.5 GB 的無用 buildcache 映像** → 浪費存儲空間
4. **版本管理策略混亂** → 難以追溯和回滾
5. **CI/CD pipeline 不穩定** → 60% 失敗率

### 影響評估
- **服務可用性**: 75% (9/12 服務正常)
- **用戶影響**: 高 (user-service 和 graphql-gateway 不可用/降級)
- **運維風險**: 高 (版本追溯困難,回滾機制不明確)

### 優先修復順序
1. **修復環境變量** (2 小時內) - 恢復服務可用性
2. **添加 `latest` 標籤** (1 小時內) - 解決 ImagePullBackOff
3. **修復 CI/CD pipeline** (今天) - 防止問題再次發生
4. **實施版本管理策略** (本週) - 長期穩定性

---

**下一步行動**: 執行 P0 修復計劃,恢復所有服務到正常狀態。
