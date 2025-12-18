# Matrix SDK 完整整合計劃

## 概覽

將所有聊天功能從 REST API/WebSocket 遷移到 Matrix SDK，實現完整的端到端加密聊天。

---

## Phase 1: 打字指示器 + 已讀回執 (高優先)

### 1.1 打字指示器整合

**目前狀態：** 使用 WebSocket 發送 `typing.start` / `typing.stop` 事件

**目標：** 改用 Matrix SDK 的 `setTyping()` 方法

**修改檔案：**

1. **ChatService.swift**
   - 修改 `sendTypingStart()` 和 `sendTypingStop()` 方法
   - 呼叫 `MatrixBridgeService.shared.setTyping()` 替代 WebSocket

2. **MatrixBridgeService.swift**
   - `setTyping()` 已存在，需確認正常運作
   - 整合 `onTypingIndicator` callback 到 ChatService

**實現步驟：**
```swift
// ChatService.swift
func sendTypingStart(conversationId: String) {
    Task {
        do {
            try await MatrixBridgeService.shared.setTyping(
                conversationId: conversationId,
                isTyping: true
            )
        } catch {
            #if DEBUG
            print("[ChatService] Failed to send typing via Matrix: \(error)")
            #endif
        }
    }
}

func sendTypingStop(conversationId: String) {
    Task {
        do {
            try await MatrixBridgeService.shared.setTyping(
                conversationId: conversationId,
                isTyping: false
            )
        } catch {
            #if DEBUG
            print("[ChatService] Failed to stop typing via Matrix: \(error)")
            #endif
        }
    }
}
```

### 1.2 已讀回執整合

**目前狀態：** 使用 REST API `POST /api/v1/conversations/:id/read`

**目標：** 改用 Matrix SDK 的 `markRoomAsRead()` 方法

**修改檔案：**

1. **ChatService.swift**
   - 修改 `markAsRead()` 方法
   - 呼叫 `MatrixBridgeService.shared.markAsRead()` 替代 REST

**實現步驟：**
```swift
// ChatService.swift
@MainActor
func markAsRead(conversationId: String, messageId: String) async throws {
    // 使用 Matrix SDK 標記已讀
    try await MatrixBridgeService.shared.markAsRead(conversationId: conversationId)

    #if DEBUG
    print("[ChatService] Marked as read via Matrix: \(conversationId)")
    #endif
}
```

---

## Phase 2: 編輯/刪除訊息 (高優先)

### 2.1 編輯訊息

**目前狀態：** 使用 REST API `PUT /api/v1/messages/:id`

**目標：** 使用 Matrix SDK 的 `timeline.edit()` 方法

**需新增到 MatrixService：**
```swift
func editMessage(roomId: String, eventId: String, newContent: String) async throws
```

**修改檔案：**
1. **MatrixService.swift** - 新增 `editMessage()` 方法
2. **MatrixBridgeService.swift** - 新增橋接方法
3. **ChatService.swift** - 修改 `editMessage()` 使用 Matrix

### 2.2 刪除/撤回訊息

**目前狀態：** 使用 REST API `DELETE /api/v1/messages/:id`

**目標：** 使用 Matrix SDK 的 `timeline.redact()` 方法

**需新增到 MatrixService：**
```swift
func redactMessage(roomId: String, eventId: String, reason: String?) async throws
```

**修改檔案：**
1. **MatrixService.swift** - 新增 `redactMessage()` 方法
2. **MatrixBridgeService.swift** - 新增橋接方法
3. **ChatService.swift** - 修改 `deleteMessage()` 和 `recallMessage()` 使用 Matrix

---

## Phase 3: GroupChatView 整合 (中優先)

**目前狀態：** GroupChatView.swift 有多個 TODO，未整合 Matrix

**修改檔案：**
1. **GroupChatView.swift**
   - 整合 Matrix SDK 發送訊息
   - 載入群組聊天記錄
   - 群組設定功能

**實現步驟：**
- 複用 ChatView 的 Matrix 邏輯
- 添加群組特有功能（成員管理、群組名稱等）

---

## Phase 4: 回覆訊息功能 (中優先)

**目前狀態：** Matrix SDK 支援 `inReplyTo` 參數，但未使用

**修改檔案：**

1. **MatrixService.swift**
   - 修改 `sendMessage()` 支援 `replyToEventId` 參數

2. **MatrixBridgeService.swift**
   - 修改 `sendMessage()` 傳遞回覆參數

3. **ChatService.swift**
   - 修改 `sendSecureMessage()` 支援 `replyToId`

4. **ChatView.swift / ChatViewModel.swift**
   - 添加回覆 UI（長按訊息 → 回覆）
   - 顯示被回覆的訊息預覽

**Matrix SDK 實現：**
```swift
func sendMessage(roomId: String, content: String, replyToEventId: String? = nil) async throws -> String {
    let timeline = try await getTimeline(for: roomId)

    let messageContent = RoomMessageEventContentWithoutRelation.text(
        body: content,
        formatted: nil
    )

    // 設置回覆關係
    let inReplyTo = replyToEventId.map { InReplyToDetails(eventId: $0) }

    let eventId = try await timeline.send(
        msg: messageContent,
        inReplyTo: inReplyTo
    )

    return eventId
}
```

---

## Phase 5: @提及 + 訊息搜尋 (低優先)

### 5.1 @提及功能

**Matrix SDK 支援：** `mentions` 參數

**實現步驟：**
1. 在輸入框偵測 `@` 字符
2. 顯示成員選擇器
3. 發送時包含 mentions 參數

### 5.2 訊息搜尋

**實現步驟：**
1. 使用 Matrix Room search API
2. 新增搜尋 UI
3. 整合到 ChatView

---

## Phase 6: 推送通知整合 (重要)

**目標：** 整合 Matrix Push Gateway，實現離線訊息推送

### 6.1 架構概覽

```
iOS App → APNs → Nova Backend → Matrix Push Gateway → Matrix Homeserver
                      ↓
              Sygnal (Matrix Pusher)
```

### 6.2 實現步驟

**後端需求：**
1. 部署 Sygnal (Matrix Push Gateway)
2. 配置 APNs 憑證
3. Matrix Homeserver 設定 pusher

**iOS 端：**
1. **MatrixService.swift** - 新增 `registerPusher()` 方法
2. **AppDelegate.swift** - 註冊 APNs token 到 Matrix
3. **NotificationService.swift** - 處理 Matrix 推送格式

**Matrix SDK 實現：**
```swift
func registerPusher(deviceToken: Data) async throws {
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

    try await client.setPusher(
        identifiers: PusherIdentifiers(
            pushkey: tokenString,
            appId: "com.nova.social"
        ),
        kind: .http,
        appDisplayName: "Nova Social",
        deviceDisplayName: UIDevice.current.name,
        profileTag: nil,
        lang: Locale.current.languageCode ?? "en",
        data: PusherData(
            url: "https://push.nova.social/_matrix/push/v1/notify",
            format: .eventIdOnly
        )
    )
}
```

### 6.3 通知內容處理

```swift
// NotificationService.swift (UNNotificationServiceExtension)
func didReceive(_ request: UNNotificationRequest,
                withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    // 從 Matrix 推送解析訊息
    guard let eventId = request.content.userInfo["event_id"] as? String,
          let roomId = request.content.userInfo["room_id"] as? String else {
        contentHandler(request.content)
        return
    }

    // 獲取並解密訊息內容
    Task {
        let content = try await MatrixService.shared.getEvent(roomId: roomId, eventId: eventId)
        // 更新通知內容
        let mutableContent = request.content.mutableCopy() as! UNMutableNotificationContent
        mutableContent.body = content.body
        contentHandler(mutableContent)
    }
}
```

---

## Phase 7: 訊息加密備份 (重要)

**目標：** 實現 Matrix Key Backup，確保換裝置後能解密歷史訊息

### 7.1 功能說明

- **Key Backup**: 將 E2EE 金鑰加密後備份到 Matrix Server
- **Recovery Key**: 用戶保存的恢復密鑰
- **Security Key**: 可選的額外安全層

### 7.2 實現步驟

**新增檔案：**
- `MatrixKeyBackupService.swift` - 金鑰備份管理

**UI 需求：**
- 設定頁面 - 啟用/查看備份狀態
- 恢復流程 - 輸入 Recovery Key
- 提示用戶保存 Recovery Key

**Matrix SDK 實現：**
```swift
class MatrixKeyBackupService {

    /// 檢查備份狀態
    func checkBackupStatus() async throws -> BackupStatus {
        let encryption = client.encryption()
        let state = try await encryption.backupState()
        return state
    }

    /// 創建新備份
    func createBackup() async throws -> String {
        let encryption = client.encryption()

        // 生成 recovery key
        let recoveryKey = try await encryption.resetRecoveryKey()

        // 啟用備份
        try await encryption.enableBackups()

        return recoveryKey
    }

    /// 從備份恢復
    func restoreFromBackup(recoveryKey: String) async throws {
        let encryption = client.encryption()
        try await encryption.recoverAndReset(recoveryKey: recoveryKey)
    }

    /// 備份所有金鑰
    func backupAllKeys() async throws {
        let encryption = client.encryption()
        try await encryption.backupRoomKeys()
    }
}
```

### 7.3 UI 流程

```
設定 → 安全性 → 訊息備份
     ├── 未啟用 → 「啟用備份」按鈕
     │            ↓
     │         顯示 Recovery Key
     │            ↓
     │         「我已保存」確認
     │
     └── 已啟用 → 備份狀態
                  ├── 上次備份時間
                  ├── 已備份金鑰數量
                  └── 「重置備份」選項
```

---

## Phase 8: 跨裝置驗證 (重要)

**目標：** 實現 Matrix Device Verification，確保 E2EE 安全性

### 8.1 功能說明

- **Device List**: 查看所有登入的裝置
- **Verification**: 驗證其他裝置的身份
- **Cross-signing**: 跨裝置信任鏈

### 8.2 驗證方式

1. **Emoji 驗證** - 雙方比對相同的 emoji 序列
2. **QR Code 驗證** - 掃描對方的 QR code
3. **Security Key 驗證** - 使用 Recovery Key

### 8.3 實現步驟

**新增檔案：**
- `MatrixVerificationService.swift` - 驗證流程管理
- `DeviceVerificationView.swift` - 驗證 UI

**Matrix SDK 實現：**
```swift
class MatrixVerificationService {

    /// 獲取裝置列表
    func getDevices() async throws -> [MatrixDevice] {
        let encryption = client.encryption()
        let devices = try await encryption.getDevices()
        return devices
    }

    /// 開始驗證流程
    func startVerification(deviceId: String) async throws -> VerificationRequest {
        let encryption = client.encryption()
        let request = try await encryption.requestVerification(deviceId: deviceId)
        return request
    }

    /// 確認 emoji 匹配
    func confirmEmoji(request: VerificationRequest) async throws {
        try await request.confirm()
    }

    /// 取消驗證
    func cancelVerification(request: VerificationRequest) async throws {
        try await request.cancel()
    }
}
```

### 8.4 UI 流程

```
設定 → 安全性 → 裝置管理
     ├── 當前裝置 ✓ (已驗證)
     ├── iPhone 14 Pro ⚠️ (未驗證) → 點擊驗證
     │                              ↓
     │                           選擇驗證方式
     │                           ├── Emoji 驗證
     │                           └── QR Code 驗證
     │                              ↓
     │                           比對 Emoji / 掃描 QR
     │                              ↓
     │                           驗證成功 ✓
     │
     └── 登出其他裝置
```

---

## Phase 9: 語音/視訊通話 (進階)

**目標：** 實現 Matrix VoIP，支援 1:1 和群組通話

### 9.1 技術架構

```
iOS App (WebRTC) ←→ Matrix Homeserver ←→ Other Client (WebRTC)
        ↓                   ↓
   CallKit 整合        TURN/STUN Server
```

### 9.2 依賴項

- **WebRTC**: Google WebRTC framework
- **CallKit**: iOS 原生通話整合
- **TURN Server**: NAT 穿透 (coturn)

### 9.3 實現步驟

**新增檔案：**
- `MatrixCallService.swift` - 通話管理
- `CallManager.swift` - CallKit 整合
- `WebRTCClient.swift` - WebRTC 封裝
- `CallView.swift` - 通話 UI
- `IncomingCallView.swift` - 來電 UI

**Matrix SDK 實現：**
```swift
class MatrixCallService: ObservableObject {
    private var webRTCClient: WebRTCClient?
    private let callManager = CallManager()

    @Published var callState: CallState = .idle
    @Published var remoteVideoTrack: RTCVideoTrack?

    /// 發起通話
    func startCall(roomId: String, isVideo: Bool) async throws {
        // 1. 創建 WebRTC offer
        let offer = try await webRTCClient?.createOffer()

        // 2. 發送 m.call.invite 事件
        try await sendCallInvite(roomId: roomId, offer: offer, isVideo: isVideo)

        // 3. 更新 CallKit
        callManager.startOutgoingCall(roomId: roomId)

        callState = .connecting
    }

    /// 接聽來電
    func answerCall(callId: String) async throws {
        // 1. 創建 WebRTC answer
        let answer = try await webRTCClient?.createAnswer()

        // 2. 發送 m.call.answer 事件
        try await sendCallAnswer(callId: callId, answer: answer)

        callState = .connected
    }

    /// 掛斷
    func hangup(callId: String) async throws {
        // 1. 發送 m.call.hangup 事件
        try await sendCallHangup(callId: callId)

        // 2. 關閉 WebRTC
        webRTCClient?.close()

        // 3. 更新 CallKit
        callManager.endCall()

        callState = .idle
    }

    /// 切換靜音
    func toggleMute() {
        webRTCClient?.toggleAudioMute()
    }

    /// 切換視訊
    func toggleVideo() {
        webRTCClient?.toggleVideo()
    }

    /// 切換鏡頭
    func switchCamera() {
        webRTCClient?.switchCamera()
    }
}
```

### 9.4 CallKit 整合

```swift
class CallManager: NSObject, CXProviderDelegate {
    private let provider: CXProvider
    private let callController = CXCallController()

    func reportIncomingCall(roomId: String, callerName: String) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: roomId)
        update.localizedCallerName = callerName
        update.hasVideo = true

        provider.reportNewIncomingCall(with: UUID(), update: update) { error in
            // Handle error
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // 接聽通話
        Task {
            try await MatrixCallService.shared.answerCall(callId: action.callUUID.uuidString)
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // 掛斷通話
        Task {
            try await MatrixCallService.shared.hangup(callId: action.callUUID.uuidString)
        }
        action.fulfill()
    }
}
```

### 9.5 UI 設計

**通話中畫面：**
```
┌─────────────────────────────┐
│                             │
│      [Remote Video]         │
│                             │
│  ┌─────┐                    │
│  │Local│                    │
│  │Video│                    │
│  └─────┘                    │
│                             │
│    00:05:32                 │
│                             │
│  [🔇] [📹] [🔄] [📞]        │
│  Mute Video Flip  End       │
└─────────────────────────────┘
```

---

## 實施順序

```
Week 1:
├── Phase 1.1: 打字指示器 → Matrix SDK
├── Phase 1.2: 已讀回執 → Matrix SDK
└── 測試 + 驗證

Week 2:
├── Phase 2.1: 編輯訊息 → Matrix SDK
├── Phase 2.2: 刪除訊息 → Matrix SDK
└── 測試 + 驗證

Week 3:
├── Phase 3: GroupChatView 整合
└── 測試 + 驗證

Week 4:
├── Phase 4: 回覆訊息功能
└── 測試 + 驗證

Week 5+:
├── Phase 5.1: @提及功能
├── Phase 5.2: 訊息搜尋
└── 其他進階功能
```

---

## 檔案修改清單

| 檔案 | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 |
|------|---------|---------|---------|---------|---------|
| MatrixService.swift | - | edit, redact | - | reply | mentions, search |
| MatrixBridgeService.swift | verify | bridge | - | bridge | bridge |
| ChatService.swift | typing, read | edit, delete | - | reply | - |
| ChatView.swift | - | UI | - | reply UI | mention UI |
| ChatViewModel.swift | - | - | - | reply | mention |
| GroupChatView.swift | - | - | 全面整合 | - | - |
| ConversationModels.swift | - | - | - | reply model | mention model |

---

## 測試計劃

每個 Phase 完成後：
1. 單元測試 - Matrix SDK 方法
2. 整合測試 - 端到端訊息流程
3. UI 測試 - 用戶互動
4. E2EE 驗證 - 加密正確性
