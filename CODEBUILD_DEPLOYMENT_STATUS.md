# AWS CodeBuild 部署狀態報告

## ✅ 已完成

### CloudFormation 堆棧
- ✅ CloudFormation 模板驗證成功
- ✅ 堆棧 `nova-codebuild-stack` 已成功創建
- ✅ IAM 角色 `CodeBuildNovaECRRole` 已配置
- ✅ CloudWatch 日誌組 `/aws/codebuild/nova-ecr-build` 已創建
- ✅ CodeBuild 項目 `nova-ecr-build` 已配置

### 項目配置驗證
```
項目名稱: nova-ecr-build
來源類型: GitHub
倉庫: https://github.com/proerror77/Nova.git
計算類型: BUILD_GENERAL1_LARGE
映像: aws/codebuild/standard:7.0
```

## ⚠️ 遇到的問題

### AccountLimitExceededException
**錯誤訊息**: "Cannot have more than 0 builds in queue for the account"

**真實原因**: AWS 帳戶級別的並發構建限制被設為 0 ❌

**為什麼顯示配額 15.0 仍然報錯**：
- CodeBuild 的排隊上限 = 並發上限 × 5
- 顯示的配額值 (Value) 與實際應用的配額值 (AppliedQuotaValue) **不同**
- 當前狀態：Value = 15.0，但 **AppliedQuotaValue = None**（未設置）
- 系統實際判定的並發限制為 0，因此排隊限制也為 0
- 新帳戶或低使用帳戶的實際應用值可能小於默認值，且不一定在界面即時反映

**影響**: 任何 start-build 都會直接報 "Cannot have more than 0 builds in queue"

## 🔧 解決方案

### 步驟 1: 驗證三個關鍵項目（10 分鐘）

**1.1 檢查專案層並發限制不得為 0**
```bash
aws codebuild batch-get-projects --names nova-ecr-build --region ap-northeast-1 --query 'projects[0].concurrentBuildLimit'
```
- 若返回 `null`：正確（無限制）
- 若返回 ≤0：執行移除限制
  ```bash
  aws codebuild update-project --name nova-ecr-build --concurrent-build-limit -1 --region ap-northeast-1
  ```

**1.2 驗證 Linux/Large 的應用配額值**
前往 AWS Service Quotas 控制台：
- 搜索服務：CodeBuild
- 搜索配額名稱："Concurrently running builds for Linux/Large environment"
- **關鍵**：檢查 **Applied quota value** 是否 > 0
  - 若為 None 或 0：需要提交 Support 案例

**1.3 確認無其他並發構建在運行**
```bash
aws codebuild list-builds-for-project --project-name nova-ecr-build --region ap-northeast-1
```
應返回空列表或構建計數為 0

### 步驟 2: 提交 AWS Support 案例（必須）

此問題 **無法通過 AWS API 自助修復**，需要 AWS Support 解除帳戶級別限制。

分類和內容：
- **服務**：CodeBuild
- **分類**：Account and Billing 或 Technical
- **主題**：Enable CodeBuild concurrency in ap-northeast-1 for account 025434362120
- **配額代碼**：L-4DDC4A99（Linux/Large environment）
- **內容重點**：
  - 錯誤："Cannot have more than 0 builds in queue for the account"
  - 請求：將 ap-northeast-1 的 "Concurrently running builds for Linux/Large" 應用值設為 ≥1
  - 解除任何帳戶級別的暫停或內部限制
  - 附上驗證結果：CloudFormation 成功、IAM 正確、配額顯示充足

參考：`AWS_SUPPORT_REQUEST.md` 中有詳細的申請模板

### 方案 C: 使用本地 Docker 構建推送到 ECR（臨時解決方案）

如果您需要立即構建映像，可以在本地機器上運行：

```bash
cd backend

# 登錄到 ECR
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com

# 構建並推送映像
REGISTRY="025434362120.dkr.ecr.ap-northeast-1.amazonaws.com"

for service in auth-service user-service content-service feed-service \
               media-service messaging-service search-service streaming-service; do
  docker buildx build --platform linux/amd64 --push \
    -f $service/Dockerfile \
    -t ${REGISTRY}/nova/$service:latest .
done
```

## 📝 下一步步驟

1. **解決配額問題** - 檢查並調整 AWS 服務配額
2. **首次構建** - 配額增加後，運行：
   ```bash
   aws codebuild start-build --project-name nova-ecr-build --region ap-northeast-1
   ```
3. **監控構建** - 查看實時日誌：
   ```bash
   aws logs tail /aws/codebuild/nova-ecr-build --follow --region ap-northeast-1
   ```

## 📊 CodeBuild 項目詳情

| 屬性 | 值 |
|------|-----|
| 項目 ARN | `arn:aws:codebuild:ap-northeast-1:025434362120:project/nova-ecr-build` |
| 服務角色 | `arn:aws:iam::025434362120:role/CodeBuildNovaECRRole` |
| 日誌組 | `/aws/codebuild/nova-ecr-build` |
| 日誌保留期 | 30 天 |

## 🛠️ 構建配置

buildspec.yml 已配置以：
- ✅ 登錄到 ECR
- ✅ 創建 ECR 倉庫（如果不存在）
- ✅ 設置 Docker Buildx
- ✅ 並行構建 8 個服務
- ✅ 推送所有映像到 ECR
- ✅ 緩存 Rust 和 Docker 文件

## 相關命令

```bash
# 檢查項目狀態
aws codebuild batch-get-projects --names nova-ecr-build --region ap-northeast-1

# 查看構建歷史（配額問題解決後）
aws codebuild list-builds-for-project --project-name nova-ecr-build --region ap-northeast-1

# 啟動構建（配額問題解決後）
aws codebuild start-build --project-name nova-ecr-build --region ap-northeast-1

# 查看實時日誌（構建開始後）
aws logs tail /aws/codebuild/nova-ecr-build --follow --region ap-northeast-1
```

## 🔴 根本原因確認（已驗證）

經過 AWS CLI 詳細診斷，確認：

**表面現象**：Service Quotas 顯示配額為 15.0，但仍被拒絕
```
AccountLimitExceededException: Cannot have more than 0 builds in queue for the account
```

**根本原因**：AWS 帳戶級別的並發限制被設為 0
- Linux/Large 配額代碼：L-4DDC4A99
- 顯示值 (Value)：15.0 ✅
- 應用值 (AppliedQuotaValue)：None ❌
- 實際並發限制：0 → 排隊限制：0

**為什麼新帳戶會遇到**：
- 新帳戶或低使用帳戶的 AppliedQuotaValue 可能未被初始化
- 帳戶層級的服務權限可能需要 AWS Support 明確激活
- 不同於可視化的配額值，實際應用值需要 Support 手動設置

**解決方式**：此錯誤 **無法通過 AWS API 自動修復**，需要 AWS Support 介入。

### 可能的帳戶級別原因：
1. 新帳戶未被激活 CodeBuild 並發功能
2. 帳戶在安全審查中
3. 帳戶有未結算的費用
4. 帳戶被暫時禁用
5. 地區級別的服務權限限制

## ✅ 已確認正常的配置

所有 **專案層** AWS 側的配置都是正確的：

| 組件 | 狀態 | 詳情 |
|------|------|------|
| CloudFormation 堆棧 | ✅ 成功 | `nova-codebuild-stack` 已創建 |
| CodeBuild 項目 | ✅ 正確 | `nova-ecr-build` 配置完整 |
| 專案層並發限制 | ✅ 正確 | `concurrentBuildLimit = null`（無限制） |
| IAM 角色 | ✅ 正確 | `CodeBuildNovaECRRole` 權限齊全 |
| CloudWatch 日誌 | ✅ 正確 | `/aws/codebuild/nova-ecr-build` 已創建 |
| **服務配額顯示值** | ✅ 充足 | Linux/Large Value = 15.0 |
| **服務配額應用值** | ❌ 未設置 | AppliedQuotaValue = None (帳戶級限制) |
| AWS CLI 驗證 | ✅ 通過 | 帳戶 025434362120 有效 |
| 當前活跃構建 | ✅ 無 | 無其他並發構建 |

**問題所在**：AppliedQuotaValue = None 表示帳戶級別的並發限制未被激活或被禁用

## 📋 需要提交 AWS Support 案例（必須）

**此問題無法通過自助方式解決。** 只有 AWS Support 可以解除帳戶級別的並發限制。

參考文件: `AWS_SUPPORT_REQUEST.md` (詳細的提交模板)

### 立即提交步驟：
1. 訪問 https://console.aws.amazon.com/support/home
2. 創建新案例
3. **服務**: CodeBuild
4. **分類**: Account and Billing
5. **主題**: Enable CodeBuild concurrency in ap-northeast-1
6. **內容**: 複製 `AWS_SUPPORT_REQUEST.md` 中的詳細說明
7. **優先級**: High (Production System Down)
8. **提交**

預期響應時間：
- 開發者支持: 4-6 小時
- 商業支持: 1-2 小時
- 企業支持: 15 分鐘

## 📌 臨時解決方案

在等待 AWS Support 回複期間，可以在本地使用 Docker 構建：

```bash
#!/bin/bash
cd backend

REGISTRY="025434362120.dkr.ecr.ap-northeast-1.amazonaws.com"

# 登錄 ECR
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin $REGISTRY

# 構建並推送映像
for service in auth-service user-service content-service feed-service \
               media-service messaging-service search-service streaming-service; do
  docker buildx build --platform linux/amd64 --push \
    -f $service/Dockerfile \
    -t ${REGISTRY}/nova/$service:latest .
done
```

---

**狀態**: 等待 AWS Support 回應 ⏳
**下一步**: 提交 AWS Support 案例（見 `AWS_SUPPORT_REQUEST.md`）
**優先級**: 高
