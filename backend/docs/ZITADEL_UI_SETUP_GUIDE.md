# Zitadel UI 配置指南

本指南說明如何在 Zitadel 管理控制台中配置 Nova × Matrix SSO 整合所需的 OIDC 應用和 Action。

## 前置條件

1. Zitadel 已部署到 Kubernetes 並可通過 `https://id.staging.nova.app` 訪問
2. 已創建 Zitadel secrets (參考 `zitadel-secrets.yaml.template`)
3. identity-service 已部署並配置了 `INTERNAL_API_KEY`

---

## 步驟 1: 登入 Zitadel 管理控制台

1. 訪問 `https://id.staging.nova.app/ui/console`
2. 使用初始管理員帳號登入：
   - Username: `zitadel-admin@zitadel.localhost`
   - Password: 您在 secrets 中設置的 `ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD`

---

## 步驟 2: 創建 OIDC Application

### 2.1 進入 Projects
1. 點擊左側選單 **Projects**
2. 點擊 **Create** 創建新專案
3. 設定專案名稱: `Nova Platform`
4. 點擊 **Create**

### 2.2 添加 Application
1. 在專案頁面點擊 **+ New**
2. 選擇 **Web Application**
3. 配置如下：

| 欄位 | 值 |
|------|------|
| Name | `synapse-nova-staging` |
| Redirect URIs | `https://matrix.staging.nova.app/_synapse/client/oidc/callback` |
| Post Logout Redirect URIs | `https://matrix.staging.nova.app` |
| Auth Method | `CODE` (Authorization Code) |
| Grant Types | ✅ Authorization Code, ✅ Refresh Token |
| Response Types | Code |
| PKCE | Recommended (S256) |

4. 點擊 **Create**

### 2.3 記錄 Client Credentials
創建後會顯示：
- **Client ID**: 複製此值 (例如 `1234567890123456789`)
- **Client Secret**: 點擊生成並**安全保存**

> ⚠️ Client Secret 只顯示一次，請立即保存到 Kubernetes Secret

### 2.4 更新 Kubernetes Secrets

```bash
# 更新 Synapse OIDC secret
kubectl -n nova-backend create secret generic synapse-oidc-secrets \
  --from-literal=oidc_client_secret="<your-client-secret>" \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## 步驟 3: 配置 Backchannel Logout (選配)

1. 在 Application 設定頁面
2. 找到 **Backchannel Logout URI** 欄位
3. 填入: `https://matrix.staging.nova.app/_synapse/client/oidc/backchannel_logout`
4. 點擊 **Save**

---

## 步驟 4: 創建 Action (用戶 Claims 擴充)

### 4.1 進入 Actions
1. 點擊左側選單 **Actions**
2. 點擊 **+ New**

### 4.2 創建 Action Script
1. Name: `nova-user-claims`
2. 在腳本編輯器中貼上以下代碼：

```javascript
/**
 * Nova User Claims Action
 * Fetches additional user claims from Nova identity-service
 */
function novaUserClaims(ctx, api) {
  // Configuration
  var identityServiceUrl = 'http://identity-service.nova-backend.svc.cluster.local:8080';
  var apiKey = ctx.v1.getSecret('nova_identity_api_key');

  if (!apiKey) {
    console.log('Warning: nova_identity_api_key not configured');
    return;
  }

  var userId = ctx.v1.user.id;

  // Fetch claims from identity-service
  var response = ctx.v1.http.fetch(
    identityServiceUrl + '/internal/zitadel/user-claims/' + userId,
    {
      method: 'GET',
      headers: {
        'X-Internal-API-Key': apiKey,
        'Content-Type': 'application/json'
      }
    }
  );

  if (response.status === 200) {
    var claims = JSON.parse(response.body);

    // Set custom claims
    if (claims.preferred_username) {
      api.v1.claims.setClaim('preferred_username', claims.preferred_username);
    }
    if (claims.name) {
      api.v1.claims.setClaim('name', claims.name);
    }
    if (claims.picture) {
      api.v1.claims.setClaim('picture', claims.picture);
    }
    // Nova-specific claims
    if (claims.nova_user_id) {
      api.v1.claims.setClaim('nova_user_id', claims.nova_user_id);
    }
    if (claims.nova_username) {
      api.v1.claims.setClaim('nova_username', claims.nova_username);
    }
  } else {
    console.log('Failed to fetch Nova claims: ' + response.status);
  }
}
```

3. 點擊 **Create**

### 4.3 添加 Secret
1. 在 Actions 頁面點擊 **Secrets**
2. 點擊 **+ New**
3. 配置：
   - Key: `nova_identity_api_key`
   - Value: `<與 identity-service 配置相同的 API Key>`
4. 點擊 **Create**

### 4.4 綁定 Action 到 Flow

1. 點擊左側選單 **Flows**
2. 選擇 **Complement Token**
3. 點擊 **+ Add trigger**
4. 選擇 **Pre Access Token Creation**
5. 選擇 `nova-user-claims` Action
6. 點擊 **Save**

---

## 步驟 5: 配置 SSO Settings

### 5.1 Instance Settings
1. 點擊左側選單 **Settings** > **Login Behavior**
2. 配置：
   - MFA Policy: 根據需求設定
   - Session Lifetime: `12h`
   - Refresh Token Lifetime: `720h` (30 days)

### 5.2 Branding (選配)
1. 點擊 **Settings** > **Branding**
2. 上傳 Nova logo
3. 設置主題顏色: `#6366f1` (Nova 品牌色)

---

## 步驟 6: 驗證配置

### 6.1 測試 OIDC Discovery
```bash
curl https://id.staging.nova.app/.well-known/openid-configuration | jq
```

應返回包含以下端點的 JSON:
- `authorization_endpoint`
- `token_endpoint`
- `userinfo_endpoint`
- `jwks_uri`

### 6.2 測試 Token Flow
可使用 OAuth 2.0 Playground 或 Postman 測試：
1. Authorization Code Flow with PKCE
2. 驗證 ID Token 包含正確的 claims

---

## 常見問題

### Q: Action 無法連接 identity-service
**A**: 確認：
1. identity-service Pod 正常運行
2. Service 名稱和端口正確
3. API Key 在兩邊配置一致

### Q: Client Secret 遺失
**A**: 在 Zitadel Console 重新生成：
1. 進入 Application 設定
2. 點擊 **Regenerate Secret**
3. 更新 Kubernetes Secret

### Q: Synapse 無法獲取 Token
**A**: 檢查：
1. Redirect URI 完全匹配
2. Client ID 和 Secret 正確
3. 網路連通性 (Synapse → Zitadel)

---

## 參考資源

- [Zitadel Actions 文檔](https://zitadel.com/docs/apis/actions)
- [OIDC 配置參考](https://zitadel.com/docs/guides/integrate/login-ui/oidc-settings)
- [Nova OIDC SSO 架構文檔](./matrix-oidc-sso-phase0.md)
