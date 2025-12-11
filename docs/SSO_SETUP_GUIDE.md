# Apple Sign-In & Google OAuth 設定指南

## 1. Apple Developer Portal 設定

### 1.1 配置 App ID

1. 登入 [Apple Developer Portal](https://developer.apple.com/account)
2. 前往 **Certificates, Identifiers & Profiles**
3. 選擇 **Identifiers** → 找到你的 App ID (`com.libruce.icered`)
4. 點擊編輯，勾選 **Sign In with Apple**
5. 點擊 **Configure** 設定：
   - Primary App ID: 選擇你的主要 App ID
   - 點擊 Save

### 1.2 創建 Services ID（用於 Web/Backend OAuth）

1. 在 **Identifiers** 頁面，點擊 **+** 按鈕
2. 選擇 **Services IDs**，點擊 Continue
3. 填寫：
   - Description: `Nova Sign In with Apple`
   - Identifier: `com.libruce.icered.signin` (服務 ID，不同於 App ID)
4. 勾選 **Sign In with Apple**，點擊 **Configure**
5. 設定 Web Authentication Configuration：
   - Primary App ID: 選擇 `com.libruce.icered`
   - Domains and Subdomains: 添加你的 backend 網域，例如：
     - `localhost` (開發)
     - `api.yourdomain.com` (生產)
   - Return URLs: 添加回調 URL：
     - `http://localhost:8081/api/v2/auth/oauth/apple/callback` (開發)
     - `https://api.yourdomain.com/api/v2/auth/oauth/apple/callback` (生產)
6. 點擊 Save → Continue → Register

### 1.3 創建 Key（用於生成 Client Secret）

1. 前往 **Keys** 頁面，點擊 **+** 按鈕
2. 填寫：
   - Key Name: `Nova Sign In with Apple Key`
3. 勾選 **Sign In with Apple**，點擊 **Configure**
4. 選擇 Primary App ID: `com.libruce.icered`
5. 點擊 Save → Continue → Register
6. **重要**：下載 `.p8` 文件並安全保存（只能下載一次！）
7. 記錄 **Key ID**（例如：`ABC123DEFG`）

### 1.4 記錄必要資訊

完成後，你需要以下資訊來設定 backend：

| 變數名稱 | 說明 | 範例 |
|---------|------|------|
| `OAUTH_APPLE_TEAM_ID` | 開發者帳號 Team ID | `M49V64HVRF` |
| `OAUTH_APPLE_CLIENT_ID` | Services ID 的 Identifier | `com.libruce.icered.signin` |
| `OAUTH_APPLE_KEY_ID` | 下載的 Key 的 ID | `ABC123DEFG` |
| `OAUTH_APPLE_PRIVATE_KEY` | `.p8` 文件的內容 | `-----BEGIN PRIVATE KEY-----\n...` |

---

## 2. Google Cloud Console 設定

### 2.1 創建 OAuth 2.0 憑證

1. 登入 [Google Cloud Console](https://console.cloud.google.com)
2. 選擇或創建專案
3. 前往 **APIs & Services** → **Credentials**
4. 點擊 **Create Credentials** → **OAuth client ID**

### 2.2 配置 iOS 應用程式

1. Application type: **iOS**
2. Name: `Nova iOS App`
3. Bundle ID: `com.libruce.icered`
4. 點擊 Create
5. 記錄 **Client ID**（用於 iOS 原生登入，如果需要的話）

### 2.3 配置 Web 應用程式（用於 Backend）

1. Application type: **Web application**
2. Name: `Nova Backend`
3. Authorized JavaScript origins:
   - `http://localhost:8081` (開發)
   - `https://api.yourdomain.com` (生產)
4. Authorized redirect URIs:
   - `http://localhost:8081/api/v2/auth/oauth/google/callback` (開發)
   - `https://api.yourdomain.com/api/v2/auth/oauth/google/callback` (生產)
   - `icered://oauth/google/callback` (iOS 回調)
5. 點擊 Create
6. 記錄 **Client ID** 和 **Client Secret**

### 2.4 記錄必要資訊

| 變數名稱 | 說明 |
|---------|------|
| `OAUTH_GOOGLE_CLIENT_ID` | Web 應用程式的 Client ID |
| `OAUTH_GOOGLE_CLIENT_SECRET` | Web 應用程式的 Client Secret |
| `OAUTH_GOOGLE_REDIRECT_URI` | 回調 URL |

---

## 3. 設定 Backend 環境變數

將以下變數添加到你的 `.env` 文件或環境配置中：

```bash
# Apple Sign In
OAUTH_APPLE_TEAM_ID=YOUR_TEAM_ID
OAUTH_APPLE_CLIENT_ID=com.libruce.icered.signin
OAUTH_APPLE_KEY_ID=YOUR_KEY_ID
OAUTH_APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49...
...
-----END PRIVATE KEY-----"
OAUTH_APPLE_REDIRECT_URI=http://localhost:8081/api/v2/auth/oauth/apple/callback

# Google OAuth
OAUTH_GOOGLE_CLIENT_ID=YOUR_CLIENT_ID.apps.googleusercontent.com
OAUTH_GOOGLE_CLIENT_SECRET=YOUR_CLIENT_SECRET
OAUTH_GOOGLE_REDIRECT_URI=http://localhost:8081/api/v2/auth/oauth/google/callback
```

---

## 4. 測試

### iOS 測試
1. 在 Xcode 中打開專案
2. 確認 Signing & Capabilities 中有 "Sign In with Apple"
3. 使用真機測試（模擬器對 Sign In with Apple 支援有限）

### Backend 測試
```bash
# 測試 Google OAuth 開始流程
curl -X POST http://localhost:8081/api/v2/auth/oauth/google/start \
  -H "Content-Type: application/json" \
  -d '{"redirect_uri": "icered://oauth/google/callback"}'

# 測試 Apple OAuth 開始流程
curl -X POST http://localhost:8081/api/v2/auth/oauth/apple/start \
  -H "Content-Type: application/json" \
  -d '{"redirect_uri": "icered://oauth/apple/callback"}'
```

---

## 5. 常見問題

### Apple Sign In 錯誤
- **invalid_client**: 檢查 Services ID 配置和 Return URLs
- **invalid_grant**: Authorization code 可能已過期（5分鐘內有效）

### Google OAuth 錯誤
- **redirect_uri_mismatch**: 確認 Google Console 中的 Redirect URI 完全匹配
- **invalid_client**: 確認 Client ID 和 Secret 正確

---

## 6. 安全注意事項

1. **永遠不要**將 `.p8` 文件或 Client Secret 提交到版本控制
2. 生產環境使用 AWS Secrets Manager 或類似服務管理敏感資訊
3. 定期輪換 API 密鑰
4. 使用 HTTPS 進行所有 OAuth 回調（除了本地開發）
