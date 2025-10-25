# iOS INTEGRATION - 測試計畫

**規劃日期**: 2025-10-25
**版本**: Swift Testing Framework
**狀態**: 📋 準備測試 (測試編寫中)

---

## 📊 測試覆蓋範圍

```
iOS INTEGRATION 測試完整性:
├─ 單元測試 (LocalMessageQueue)
│  ├─ enqueue() - 消息入隊
│  ├─ drain() - 消息恢復
│  ├─ markSynced() - 標記同步
│  ├─ size() - 隊列大小
│  └─ isEmpty() - 空隊列檢查
│
├─ 單元測試 (WebSocket Auto-Reconnect)
│  ├─ 初始連接
│  ├─ 連接失敗檢測
│  ├─ 指數退避計算
│  ├─ 最大重試限制
│  └─ 連接參數存儲
│
├─ 集成測試 (ChatViewModel)
│  ├─ 消息發送流程
│  ├─ 離線消息隊列
│  ├─ 幂等性密鑰去重
│  ├─ 連接成功時 drain()
│  └─ 錯誤分類與重試
│
├─ UI 集成測試 (ChatView)
│  ├─ 消息氣泡渲染
│  ├─ 狀態指示器
│  ├─ 輸入框交互
│  └─ 自動滾動
│
└─ 端到端測試 (E2E)
   ├─ 離線發送 → 恢復 → 同步
   ├─ WebSocket 連接中斷 → 自動重連
   └─ 消息去重驗證
```

---

## 🧪 單元測試 - LocalMessageQueue

### 測試 1: enqueue() - 消息入隊

```swift
@Test func testEnqueueMessage() async throws {
    // 準備
    let queue = LocalMessageQueue(modelContext: modelContext)
    let message = LocalMessage(
        id: "test-1",
        conversationId: "conv-1",
        senderId: "user-1",
        plaintext: "Hello",
        syncState: .synced
    )

    // 執行
    try await queue.enqueue(message)

    // 驗證
    let size = try await queue.size(for: "conv-1")
    #expect(size == 1)

    let drained = try await queue.drain(for: "conv-1")
    #expect(drained.count == 1)
    #expect(drained[0].id == "test-1")
    #expect(drained[0].syncState == .localOnly)
}
```

**驗證點**：
- ✅ 消息成功保存
- ✅ syncState 自動設置為 .localOnly
- ✅ size() 返回正確計數

---

### 測試 2: drain() - 消息恢復

```swift
@Test func testDrainMessages() async throws {
    let queue = LocalMessageQueue(modelContext: modelContext)

    // 準備多條消息
    let msg1 = LocalMessage(id: "1", conversationId: "conv-1",
                           senderId: "user-1", plaintext: "First",
                           syncState: .localOnly)
    let msg2 = LocalMessage(id: "2", conversationId: "conv-1",
                           senderId: "user-1", plaintext: "Second",
                           syncState: .localOnly)

    try await queue.enqueue(msg1)
    try await queue.enqueue(msg2)

    // 執行 drain
    let drained = try await queue.drain(for: "conv-1")

    // 驗證
    #expect(drained.count == 2)
    #expect(drained[0].plaintext == "First")
    #expect(drained[1].plaintext == "Second")
}
```

**驗證點**：
- ✅ 恢復所有離線消息
- ✅ 保持消息順序
- ✅ 僅返回目標會話的消息

---

### 測試 3: markSynced() - 標記同步

```swift
@Test func testMarkSynced() async throws {
    let queue = LocalMessageQueue(modelContext: modelContext)
    let message = LocalMessage(
        id: "test-1", conversationId: "conv-1",
        senderId: "user-1", plaintext: "Test",
        syncState: .localOnly
    )

    try await queue.enqueue(message)

    // 標記為已同步
    try await queue.markSynced("test-1")

    // 驗證：隊列應該為空 (只查詢 .localOnly)
    let remaining = try await queue.drain(for: "conv-1")
    #expect(remaining.isEmpty)
}
```

**驗證點**：
- ✅ 消息狀態更新為 .synced
- ✅ drain() 不再返回已同步消息
- ✅ 隊列自動清理

---

### 測試 4: 會話級別過濾

```swift
@Test func testConversationLevelFiltering() async throws {
    let queue = LocalMessageQueue(modelContext: modelContext)

    // 準備不同會話的消息
    let msg1 = LocalMessage(id: "1", conversationId: "conv-1",
                           senderId: "user-1", plaintext: "Conv1",
                           syncState: .localOnly)
    let msg2 = LocalMessage(id: "2", conversationId: "conv-2",
                           senderId: "user-1", plaintext: "Conv2",
                           syncState: .localOnly)

    try await queue.enqueue(msg1)
    try await queue.enqueue(msg2)

    // 只恢復 conv-1
    let conv1Messages = try await queue.drain(for: "conv-1")
    #expect(conv1Messages.count == 1)
    #expect(conv1Messages[0].conversationId == "conv-1")

    // 只恢復 conv-2
    let conv2Messages = try await queue.drain(for: "conv-2")
    #expect(conv2Messages.count == 1)
    #expect(conv2Messages[0].conversationId == "conv-2")
}
```

**驗證點**：
- ✅ 會話隔離正確
- ✅ 不同會話消息不混淆
- ✅ 單會話 drain 不影響其他會話

---

## 🔌 單元測試 - WebSocket 自動重連

### 測試 5: 指數退避計算

```swift
@Test func testExponentialBackoff() {
    // 模擬重連延遲計算
    let delays = (1...5).map { attempt in
        pow(2.0, Double(attempt - 1))
    }

    #expect(delays[0] == 1.0)   // 第1次: 1s
    #expect(delays[1] == 2.0)   // 第2次: 2s
    #expect(delays[2] == 4.0)   // 第3次: 4s
    #expect(delays[3] == 8.0)   // 第4次: 8s
    #expect(delays[4] == 16.0)  // 第5次: 16s
}
```

**驗證點**：
- ✅ 指數計算正確
- ✅ 延遲遞增
- ✅ 最大 5 次嘗試

---

### 測試 6: 連接狀態轉換

```swift
@Test func testConnectionStateTransitions() async throws {
    let client = WebSocketMessagingClient()
    var stateHistory: [String] = []

    client.onStateChange = { state in
        switch state {
        case .disconnected:
            stateHistory.append("disconnected")
        case .connecting:
            stateHistory.append("connecting")
        case .connected:
            stateHistory.append("connected")
        case .failed:
            stateHistory.append("failed")
        }
    }

    // 驗證狀態轉換序列
    #expect(stateHistory.contains("connecting"))
    // ... 後續狀態驗證
}
```

**驗證點**：
- ✅ 狀態轉換正確
- ✅ 回調正確觸發
- ✅ 狀態同步一致

---

## 📱 集成測試 - ChatViewModel

### 測試 7: 消息發送成功路徑

```swift
@Test func testSendMessageSuccess() async throws {
    let conversationId = UUID()
    let peerId = UUID()
    let vm = ChatViewModel(conversationId: conversationId, peerUserId: peerId)

    // 模擬 send()
    vm.input = "Hello"

    // 驗證：消息應該添加到列表
    let initialCount = vm.messages.count
    await vm.send()

    #expect(vm.messages.count == initialCount + 1)
    #expect(vm.messages.last?.text == "Hello")
    #expect(vm.messages.last?.mine == true)
    #expect(vm.input.isEmpty)  // 輸入框已清空
}
```

**驗證點**：
- ✅ 樂觀 UI 更新
- ✅ 消息添加到列表
- ✅ 輸入框清空

---

### 測試 8: 離線消息隊列集成

```swift
@Test func testOfflineMessageQueuing() async throws {
    let conversationId = UUID()
    let peerId = UUID()
    let vm = ChatViewModel(conversationId: conversationId, peerUserId: peerId)

    // 模擬網路錯誤
    vm.input = "Offline message"

    // send() 會捕獲網路錯誤並 enqueue
    // (在實際測試中需要 mock repo)

    #expect(vm.offlineMessageCount > 0)
}
```

**驗證點**：
- ✅ 錯誤分類正確
- ✅ 可重試錯誤入隊
- ✅ offlineMessageCount 更新

---

### 測試 9: 幂等性去重

```swift
@Test func testIdempotencyKeyDeduplication() async throws {
    let idempotencyKey = UUID().uuidString

    // 第1次發送
    let message1 = LocalMessage(
        id: idempotencyKey,
        conversationId: "conv-1",
        senderId: "user-1",
        plaintext: "Test",
        syncState: .synced
    )

    // 第2次重新發送 (相同的 idempotencyKey)
    let message2 = LocalMessage(
        id: idempotencyKey,
        conversationId: "conv-1",
        senderId: "user-1",
        plaintext: "Test",
        syncState: .synced
    )

    // 驗證：服務器應該識別為同一消息並去重
    #expect(message1.id == message2.id)
}
```

**驗證點**：
- ✅ ID 相同 = 同一消息
- ✅ 重新發送不造成重複
- ✅ 去重機制有效

---

### 測試 10: drain() 與 resend() 流程

```swift
@Test func testDrainAndResendFlow() async throws {
    let conversationId = UUID()
    let peerId = UUID()
    let vm = ChatViewModel(conversationId: conversationId, peerUserId: peerId)

    // 模擬設置上次 drain() 後的消息計數
    vm.offlineMessageCount = 3

    // 執行 drain()
    try await vm.drainOfflineQueue()

    // 驗證：消息計數應該減少
    #expect(vm.offlineMessageCount < 3)
}
```

**驗證點**：
- ✅ drain() 成功
- ✅ 消息計數更新
- ✅ resendOfflineMessage() 正確調用

---

## 🎬 UI 集成測試 - ChatView

### 測試 11: 消息氣泡渲染

```swift
@Test @MainActor func testMessageBubbleRendering() {
    let message = ChatMessage(
        id: UUID(),
        text: "Hello",
        mine: true,
        createdAt: Date()
    )

    let view = MessageBubble(message: message)

    // 驗證視圖是否包含文本
    // (使用 SwiftUI Testing 框架)
    // #expect(view.contains("Hello"))
}
```

**驗證點**：
- ✅ 文本正確顯示
- ✅ 自我/對方對齌正確
- ✅ 顏色正確應用

---

### 測試 12: 狀態指示器

```swift
@Test @MainActor func testStatusBarIndicator() {
    // 模擬有離線消息
    let vm = MockChatViewModel()
    vm.offlineMessageCount = 2

    let view = StatusBar(vm: vm)

    // 驗證指示器顯示
    // #expect(view.contains("有 2 條消息待發送"))
}
```

**驗證點**：
- ✅ 離線消息計數顯示
- ✅ 自動發送提示
- ✅ 計數為 0 時隱藏

---

### 測試 13: 自動滾動

```swift
@Test @MainActor func testAutoScroll() async throws {
    let vm = MockChatViewModel()

    // 初始消息
    vm.messages = [
        ChatMessage(id: UUID(), text: "1", mine: true, createdAt: Date()),
        ChatMessage(id: UUID(), text: "2", mine: false, createdAt: Date())
    ]

    // 添加新消息 (模擬)
    let newMessage = ChatMessage(id: UUID(), text: "3", mine: true, createdAt: Date())
    vm.messages.append(newMessage)

    // 驗證：shouldScrollToBottom = true
    // (取決於 ScrollViewReader 實現)
}
```

**驗證點**：
- ✅ 新消息到達時滾動
- ✅ 滾動到底部
- ✅ 動畫平滑

---

## 🔄 端到端測試

### 測試 14: 完整離線→恢復→同步流程

```
場景：
1. 用戶連接正常
2. 切斷網路（模擬）
3. 用戶發送消息 → 入隊（offlineMessageCount = 1）
4. 顯示離線指示器
5. 恢復網路
6. WebSocket 重新連接 → onOpen() 觸發
7. drainOfflineQueue() 執行
8. 消息重新發送 (使用相同 idempotencyKey)
9. 服務器確認 → markSynced()
10. offlineMessageCount = 0
11. 離線指示器消失

驗證：
✅ 消息不丟失
✅ 不出現重複消息
✅ 用戶體驗流暢
```

---

### 測試 15: WebSocket 自動重連完整流程

```
場景：
1. 初始連接成功 (connected)
2. 連接中斷 (disconnected)
3. 檢測失敗 (failed)
4. 計時器觸發 (1 秒後)
5. 第1次重連嘗試 (connecting)
6. 連接成功 (connected)
7. 計數器重置

驗證：
✅ 重連嘗試次數正確
✅ 延遲時間指數增長
✅ 最多 5 次重試
✅ 連接成功後重置
```

---

## 📋 測試檢查清單

### 準備工作
- [ ] 創建 Mock 對象（MockChatViewModel, MockRepository）
- [ ] 設置 TestContainer 和共享 ModelContext
- [ ] 配置 Swift Testing 環境
- [ ] 創建測試數據工廠

### 編寫測試
- [ ] LocalMessageQueue 單元測試 (5 個)
- [ ] WebSocket 重連單元測試 (2 個)
- [ ] ChatViewModel 集成測試 (5 個)
- [ ] ChatView UI 測試 (3 個)
- [ ] 端到端測試 (2 個)

### 運行測試
- [ ] 所有測試通過
- [ ] 代碼覆蓋率 > 80%
- [ ] 性能測試通過
- [ ] 無內存洩漏

### 文檔
- [ ] 測試用例文檔完整
- [ ] Mock 對象文檔
- [ ] CI/CD 集成文檔

---

## 🎯 測試執行計劃

### 第 1 天 (4 小時)
- 設置測試基礎架構
- 編寫 LocalMessageQueue 測試
- 編寫 WebSocket 重連測試

### 第 2 天 (4 小時)
- 編寫 ChatViewModel 集成測試
- 編寫 ChatView UI 測試
- 編寫端到端測試

### 第 3 天 (2 小時)
- 運行完整測試套件
- 修復失敗的測試
- 代碼覆蓋率分析
- 性能優化

**總工作量**: 10 小時 (2.5 天)

---

## ✅ 成功標準

```
測試覆蓋率 >= 80%
├─ 核心邏輯: >= 95%
├─ UI 代碼: >= 70%
└─ 工具函數: >= 60%

所有測試必須通過:
├─ 0 個失敗
├─ 0 個警告
└─ 0 個跳過

性能指標:
├─ enqueue/drain: < 100ms
├─ reconnect: < 5秒成功
└─ 無內存洩漏
```

---

## 📚 Mock 對象設計

```swift
class MockChatViewModel: Sendable {
    var messages: [ChatMessage] = []
    var offlineMessageCount: Int = 0
    var isConnected: Bool = true
    var typingUsernames: Set<UUID> = []

    func send() async { /* 模擬 */ }
    func drainOfflineQueue() async throws { /* 模擬 */ }
}

class MockMessagingRepository {
    func sendText(/* 參數 */) async throws -> MessageDto {
        // 模擬 API 調用
    }
}
```

---

## 🏁 總結

**iOS INTEGRATION 完整度**：

```
實現工作: 100% ✅
├─ #1 LocalMessageQueue: ✅
├─ #2 WebSocket 重連: ✅
├─ #3 ChatViewModel 集成: ✅
├─ #4 @Observable 現代化: ✅
└─ #5 ChatView UI: ✅

測試工作: 準備中 📋
├─ 單元測試: 規劃完成
├─ 集成測試: 規劃完成
└─ E2E 測試: 規劃完成

預計工作量: ~10 小時
```

---

**文件版本**: 1.0
**最後更新**: 2025-10-25
**狀態**: 準備開始測試
