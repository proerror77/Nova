# AWS Support 請求指南 - CodeBuild 帳戶限制

## 問題概述

無法在 AWS CodeBuild 項目上啟動構建。收到錯誤：

```
AccountLimitExceededException: Cannot have more than 0 builds in queue for the account
```

## 診斷信息

### 賬戶和環境信息
- **AWS 帳戶 ID**: 025434362120
- **IAM 用戶**: sonic-shih
- **區域**: ap-northeast-1
- **CodeBuild 項目**: nova-ecr-build

### 驗證的配置狀態

#### ✅ 已確認正常
1. **CloudFormation 堆棧** - 成功創建
   - 堆棧名稱: `nova-codebuild-stack`
   - 堆棧 ARN: `arn:aws:cloudformation:ap-northeast-1:025434362120:stack/nova-codebuild-stack/...`

2. **CodeBuild 項目** - 配置正確
   - 項目名稱: `nova-ecr-build`
   - 項目 ARN: `arn:aws:codebuild:ap-northeast-1:025434362120:project/nova-ecr-build`
   - 計算類型: `BUILD_GENERAL1_LARGE`
   - 映像: `aws/codebuild/standard:7.0`

3. **IAM 角色** - 權限正確
   - 角色名稱: `CodeBuildNovaECRRole`
   - 角色 ARN: `arn:aws:iam::025434362120:role/CodeBuildNovaECRRole`
   - 已附加策略: AmazonEC2ContainerRegistryPowerUser + 自定義策略

4. **CloudWatch 日誌** - 已創建
   - 日誌組: `/aws/codebuild/nova-ecr-build`
   - 保留期: 30 天

5. **服務配額** - 顯示值充足，應用值未設置
   ```
   Linux/Large environment (L-4DDC4A99):
   - 顯示值 (Value): 15.0 ✅
   - 應用值 (AppliedQuotaValue): None ❌
   - 實際並發限制: 0 (帳戶級別，待解除)

   Linux/Medium environment: 15.0
   Linux/Small environment: 15.0
   ```

   **關鍵發現**：AppliedQuotaValue = None 表示雖然配額顯示為 15.0，但帳戶級別的實際並發限制被設為 0

#### ❌ 失敗的操作
```bash
aws codebuild start-build --project-name nova-ecr-build --region ap-northeast-1
```

**錯誤**:
```
An error occurred (AccountLimitExceededException) when calling the StartBuild operation:
Cannot have more than 0 builds in queue for the account
```

## 已嘗試的解決方案

### 1. 增加服務配額
- ✅ 檢查了所有 CodeBuild 服務配額
- ✅ 確認所有環境類型的配額都足夠
- ✅ 未找到"builds in queue"相關的可調整配額

### 2. 驗證 IAM 權限
- ✅ 角色信任政策正確
- ✅ 內聯策略包含所有必要權限
- ✅ CodeBuild 和 ECR 權限已授予

### 3. 檢查 CloudFormation
- ✅ 模板驗證成功
- ✅ 堆棧創建完成
- ✅ 所有資源已正確配置

## 根本原因分析

此錯誤 **不能通過 API 或自動化方式解決**，因為它反映了 AWS 帳戶級別的限制。

### 技術根本原因

CodeBuild 的排隊上限 = 並發限制 × 5

- **顯示配額值 (Value)**：15.0
- **應用配額值 (AppliedQuotaValue)**：None（未初始化）
- **實際帳戶級並發限制**：0
- **實際排隊限制**：0 × 5 = 0

任何 start-build 都會被拒絕，因為排隊限制為 0。

### 可能的帳戶級別原因

1. **新帳戶限制** - 新 AWS 帳戶的 AppliedQuotaValue 可能未被初始化
2. **帳戶被禁用** - 由於安全、計費或其他原因，帳戶 CodeBuild 並發功能被禁用
3. **待結算餘額** - 帳戶有未支付的發票或待決的計費問題
4. **安全審查中** - 帳戶在安全審查中可能被暫時限制
5. **地區級別限制** - ap-northeast-1 的服務權限可能被限制

## AWS Support 申請步驟

### 步驟 1: 登錄 AWS 支持中心

訪問: https://console.aws.amazon.com/support/home

### 步驟 2: 創建新案例

點擊 **"Create case"** 按鈕

### 步驟 3: 選擇問題類型

```
Service: CodeBuild
Category: Account and Billing
```

### 步驟 4: 填寫案例詳情

**主題**:
```
Enable CodeBuild concurrency in ap-northeast-1 for account 025434362120
```

**描述**:
```
我的 AWS 帳戶無法啟動 CodeBuild 構建。

錯誤信息:
AccountLimitExceededException: Cannot have more than 0 builds in queue for the account

帳戶詳情:
- 帳戶 ID: 025434362120
- IAM 用戶: sonic-shih
- 區域: ap-northeast-1
- CodeBuild 項目: nova-ecr-build
- 配額代碼: L-4DDC4A99 (Concurrently running builds for Linux/Large environment)

根本原因:
服務配額顯示值為 15.0，但應用值 (AppliedQuotaValue) 為 None，導致實際帳戶級並發限制為 0。

所有專案層配置都正確：
✅ CloudFormation 堆棧: nova-codebuild-stack (成功創建)
✅ CodeBuild 項目: nova-ecr-build (配置正確)
✅ 專案層並發限制: concurrentBuildLimit = null (無限制)
✅ IAM 角色: CodeBuildNovaECRRole (權限正確)
✅ 服務配額顯示值: Linux/Large = 15.0

❌ 問題: AppliedQuotaValue = None (帳戶級限制)

請求:
1. 將 ap-northeast-1 的 "Concurrently running builds for Linux/Large environment" (代碼 L-4DDC4A99) 的應用值設為 ≥1
2. 解除此帳戶在 ap-northeast-1 的 CodeBuild 並發限制
3. 確認帳戶沒有其他的服務或計費問題

提交時附上：
- CloudFormation 堆棧 ARN: arn:aws:cloudformation:ap-northeast-1:025434362120:stack/nova-codebuild-stack/...
- CodeBuild 項目 ARN: arn:aws:codebuild:ap-northeast-1:025434362120:project/nova-ecr-build
- IAM 角色 ARN: arn:aws:iam::025434362120:role/CodeBuildNovaECRRole
```

### 步驟 5: 選擇優先級

```
Severity: High (Business Critical)
Urgency: Production System Down
```

### 步驟 6: 提交案例

點擊 **"Create"** 提交案例

## 預期響應時間

- **一般支持**: 12-24 小時
- **開發者支持**: 4-6 小時
- **商業支持**: 1-2 小時
- **企業支持**: 15 分鐘

## 聯繫方式

### 方式 1: AWS 控制台 (推薦)
- 網址: https://console.aws.amazon.com/support/home

### 方式 2: AWS 開發者論壇
- 論壇: https://forums.aws.amazon.com/forum.jspa?forumID=87

### 方式 3: 電話支持 (企業支持客戶)
- 撥打您收到的 AWS 支持號碼

## 臨時解決方案

在等待 AWS Support 回複期間，您可以使用本地 Docker 構建並推送到 ECR：

### 設置本地構建

1. **登錄 ECR**:
```bash
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com
```

2. **構建並推送單個服務**:
```bash
cd backend

REGISTRY="025434362120.dkr.ecr.ap-northeast-1.amazonaws.com"
SERVICE="auth-service"

docker buildx build --platform linux/amd64 --push \
  -f $SERVICE/Dockerfile \
  -t ${REGISTRY}/nova/$SERVICE:latest .
```

3. **批量構建所有服務**:
```bash
#!/bin/bash
cd backend

REGISTRY="025434362120.dkr.ecr.ap-northeast-1.amazonaws.com"
SERVICES=(
  "auth-service"
  "user-service"
  "content-service"
  "feed-service"
  "media-service"
  "messaging-service"
  "search-service"
  "streaming-service"
)

for service in "${SERVICES[@]}"; do
  echo "🔨 構建 $service..."
  docker buildx build --platform linux/amd64 --push \
    -f $service/Dockerfile \
    -t ${REGISTRY}/nova/$service:latest .
done
```

## 提交後的步驟

### 1. 案例確認
- AWS Support 會發送確認郵件，包含案例 ID
- 使用案例 ID 追蹤進度

### 2. 等待調查
- Support 工程師會檢查您的帳戶
- 可能會要求提供額外信息

### 3. 解決方案實施
- 一旦確認原因，AWS 會相應調整帳戶設置
- 您將收到解決步驟通知

### 4. 驗證解決方案
收到解決通知後，運行以下命令驗證：
```bash
aws codebuild start-build --project-name nova-ecr-build --region ap-northeast-1
```

## 相關文檔

- AWS CodeBuild 用戶指南: https://docs.aws.amazon.com/codebuild/
- AWS 服務配額: https://docs.aws.amazon.com/general/latest/gr/codebuild.html
- AWS Support: https://aws.amazon.com/support/

---

**重要**: 此問題不能通過自助方式解決，需要 AWS Support 介入。建議立即提交支持案例以解決此問題。

**建議優先級**: 高 (生產系統受阻)
