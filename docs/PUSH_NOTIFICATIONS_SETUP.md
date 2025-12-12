# Push Notifications Setup Guide

本指南說明如何為 Nova 應用程式設定 iOS (APNs) 和 Android (FCM) 推播通知。

## 目錄

- [APNs 設定 (iOS)](#apns-設定-ios)
- [FCM 設定 (Android)](#fcm-設定-android)
- [Kubernetes Secrets 設定](#kubernetes-secrets-設定)
- [驗證設定](#驗證設定)

---

## APNs 設定 (iOS)

### 步驟 1: 登入 Apple Developer Portal

1. 前往 [Apple Developer Portal](https://developer.apple.com/account)
2. 使用你的 Apple Developer 帳號登入
3. 需要 **Apple Developer Program** 會員資格 ($99 USD/年)

### 步驟 2: 建立 App ID (如果還沒有)

1. 前往 **Certificates, Identifiers & Profiles**
2. 點擊 **Identifiers** → **+** 按鈕
3. 選擇 **App IDs** → **Continue**
4. 選擇 **App** → **Continue**
5. 填寫：
   - **Description**: Nova Social
   - **Bundle ID**: `com.yourcompany.nova` (需與 Xcode 專案一致)
6. 在 **Capabilities** 中勾選 **Push Notifications**
7. 點擊 **Continue** → **Register**

### 步驟 3: 建立 APNs Key (推薦方式)

> **推薦使用 .p8 Key**：一個 Key 可用於所有 App，不會過期

1. 前往 **Certificates, Identifiers & Profiles** → **Keys**
2. 點擊 **+** 按鈕建立新 Key
3. 填寫：
   - **Key Name**: `Nova APNs Key`
   - 勾選 **Apple Push Notifications service (APNs)**
4. 點擊 **Continue** → **Register**
5. **重要**：下載 `.p8` 檔案（只能下載一次！）
6. 記錄以下資訊：
   - **Key ID**: 顯示在 Key 詳情頁面 (10 字元)
   - **Team ID**: 在右上角帳號名稱下方 (10 字元)

### 步驟 4: 儲存憑證資訊

請安全保存以下資訊：

```
APNs Key 檔案: AuthKey_XXXXXXXXXX.p8
Key ID: XXXXXXXXXX
Team ID: XXXXXXXXXX
Bundle ID: com.yourcompany.nova
```

---

## FCM 設定 (Android)

### 步驟 1: 建立 Firebase 專案

1. 前往 [Firebase Console](https://console.firebase.google.com/)
2. 點擊 **新增專案** 或選擇現有專案
3. 輸入專案名稱：`Nova Social`
4. 選擇是否啟用 Google Analytics（可選）
5. 點擊 **建立專案**

### 步驟 2: 新增 Android 應用程式

1. 在專案首頁點擊 **Android** 圖示
2. 填寫：
   - **Android 套件名稱**: `com.yourcompany.nova`
   - **應用程式暱稱**: Nova Social
   - **偵錯簽署憑證 SHA-1**: (可選，用於 Google 登入)
3. 點擊 **註冊應用程式**
4. 下載 `google-services.json` 並加入 Android 專案

### 步驟 3: 取得伺服器憑證

1. 在 Firebase Console 點擊 **專案設定** (齒輪圖示)
2. 選擇 **服務帳戶** 分頁
3. 點擊 **產生新的私密金鑰**
4. 確認後下載 JSON 檔案
5. 將檔案重新命名為 `fcm-credentials.json`

### 步驟 4: 儲存憑證資訊

請安全保存以下資訊：

```
FCM 憑證檔案: fcm-credentials.json
專案 ID: your-project-id (可在 JSON 中的 project_id 找到)
```

---

## Kubernetes Secrets 設定

### 建立 APNs Secret

```bash
# 方法 1: 使用 .p8 Key (推薦)
kubectl create secret generic apns-credentials \
  -n nova-staging \
  --from-file=apns-key.p8=/path/to/AuthKey_XXXXXXXXXX.p8 \
  --from-literal=key-id=YOUR_KEY_ID \
  --from-literal=team-id=YOUR_TEAM_ID \
  --from-literal=bundle-id=com.yourcompany.nova

# 方法 2: 使用 .p12 憑證 (傳統方式)
kubectl create secret generic apns-credentials \
  -n nova-staging \
  --from-file=apns-cert.p12=/path/to/push-cert.p12 \
  --from-literal=cert-password=YOUR_P12_PASSWORD
```

### 建立 FCM Secret

```bash
kubectl create secret generic fcm-credentials \
  -n nova-staging \
  --from-file=fcm-credentials.json=/path/to/fcm-credentials.json
```

### 更新 notification-service Deployment

在 `k8s/microservices/notification-service-deployment.yaml` 中新增：

```yaml
spec:
  template:
    spec:
      containers:
      - name: notification-service
        env:
        # FCM 設定
        - name: FCM_CREDENTIALS
          value: /etc/fcm/fcm-credentials.json
        # APNs 設定 (使用 .p8 Key)
        - name: APNS_KEY_PATH
          value: /etc/apns/apns-key.p8
        - name: APNS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: apns-credentials
              key: key-id
        - name: APNS_TEAM_ID
          valueFrom:
            secretKeyRef:
              name: apns-credentials
              key: team-id
        - name: APNS_BUNDLE_ID
          valueFrom:
            secretKeyRef:
              name: apns-credentials
              key: bundle-id
        volumeMounts:
        - name: fcm-credentials
          mountPath: /etc/fcm
          readOnly: true
        - name: apns-credentials
          mountPath: /etc/apns
          readOnly: true
      volumes:
      - name: fcm-credentials
        secret:
          secretName: fcm-credentials
      - name: apns-credentials
        secret:
          secretName: apns-credentials
```

---

## 驗證設定

### 檢查 Secrets 是否建立成功

```bash
# 列出 secrets
kubectl get secrets -n nova-staging | grep -E "fcm|apns"

# 檢查 secret 內容 (不顯示實際值)
kubectl describe secret fcm-credentials -n nova-staging
kubectl describe secret apns-credentials -n nova-staging
```

### 檢查 notification-service 日誌

```bash
kubectl logs -n nova-staging deployment/notification-service --tail=50 | grep -i "fcm\|apns\|push"
```

成功設定後應該看到：
```
INFO notification_service: FCM push notifications enabled
INFO notification_service: APNs push notifications enabled
```

### 測試推播通知

可以使用以下 API 端點測試：

```bash
# 發送測試推播 (需要有效的 device token)
curl -X POST https://api.nova.app/v1/notifications/test \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device_token": "YOUR_DEVICE_TOKEN",
    "platform": "ios",
    "title": "Test Notification",
    "body": "This is a test push notification"
  }'
```

---

## 常見問題

### Q: APNs Key 遺失怎麼辦？
A: Apple 只允許下載一次 .p8 檔案。如果遺失，需要撤銷舊 Key 並建立新的。

### Q: FCM 憑證可以重新下載嗎？
A: 可以。在 Firebase Console → 專案設定 → 服務帳戶，重新產生私密金鑰即可。

### Q: Staging 和 Production 需要不同憑證嗎？
A:
- **APNs**: 同一個 .p8 Key 可用於開發和生產環境，但需要設定不同的 endpoint
  - 開發: `api.sandbox.push.apple.com`
  - 生產: `api.push.apple.com`
- **FCM**: 通常建議不同環境使用不同的 Firebase 專案

### Q: 推播通知沒有收到？
檢查以下項目：
1. Device token 是否有效且未過期
2. App 是否有推播通知權限
3. 憑證是否正確設定
4. 網路是否能連接到 APNs/FCM 服務器

---

## 相關連結

- [Apple Push Notification service 文件](https://developer.apple.com/documentation/usernotifications)
- [Firebase Cloud Messaging 文件](https://firebase.google.com/docs/cloud-messaging)
- [APNs Provider API](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/sending_notification_requests_to_apns)

---

## 更新紀錄

| 日期 | 更新內容 |
|------|----------|
| 2024-12-13 | 初始版本 |
