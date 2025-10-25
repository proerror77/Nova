# 🔧 P1 任务修正计划 - 基于代码审查 & 架构澄清

**审查完成时间**: 2025-10-25
**计划更新**: 2025-10-25 (改为 iOS Swift 实现)
**项目定位**: iOS 移动优先（无 Web 前端）
**更新原因**:
1. 代码审查发现 E2E 加密仍是占位符
2. 架构澄清：项目是 iOS 原生应用，不需要 Web 前端
3. 删除无用的 Web 前端，简化架构

---

## 📊 计划变更摘要

### 原计划 (误导性的)
```
❌ Web 前端: 消息加密 (TweetNaCl.js)
❌ iOS 视频上传
❌ Web + iOS 跨平台协调
```

### 修正计划 (正确的 iOS 优先)
```
P1: iOS 端到端加密系统 ⭐
├── CRITICAL: 实现真实 E2E 加密 (libsodium/Swift) - 3天
├── 密钥管理 (Option A: 密码派生) - 1.5天
├── 消息加密/解密 API - 1.5天
├── 离线消息加密 - 1天
└── 测试覆盖 + 安全审查 - 1day
小计: ~8天

P2: iOS 视频上传 & 流媒体
├── 分块上传实现 - 1.5天
├── 断点续传 - 1天
├── 进度跟踪 - 0.5天
├── 视频播放集成 - 1天
└── 测试 - 0.5天
小计: ~4.5天

P3: 功能完善
├── 推送通知 (APNs) - 1天
├── 离线同步 - 1天
└── 性能优化 - 0.5天
小计: ~2.5天

总计: ~15天 (8 + 4.5 + 2.5)
```

---

## 🎯 P1A: iOS E2E 加密系统 (8 天)

### 🔴 CRITICAL: E2E 加密实现 (3 天)

**问题根源**: iOS 消息加密是占位符
```swift
// ❌ 现在的代码 (不安全)
let ciphertext = plaintext.data(using: .utf8)?.base64EncodedString()
let nonce = UUID().uuidString

// ✅ 需要的代码 (真实加密)
// 使用 libsodium (通过 SwiftNaCl / sodium.swift)
```

**工作项**:

#### 1. 库选择与集成 (1天)

**推荐: libsodium.swift (Swift 包装)**
- ✅ Sodium library 官方支持
- ✅ 性能优异（C 实现）
- ✅ 功能完整（AEAD, secretbox, box）
- ✅ iOS 最佳实践

**安装**:
```swift
// Package.swift
.package(url: "https://github.com/jedisct1/swift-sodium.git", from: "0.9.1")
```

**验证**:
- [ ] 添加到 iOS 项目 SPM
- [ ] 编译通过
- [ ] 性能基准测试（加密 1KB 消息的耗时）

#### 2. 密钥管理设计 (1.5 天)

**选择 Option A: 密码派生密钥** (推荐用于 MVP)
```swift
// 使用用户密码派生加密密钥
// PBKDF2: 密码 + salt → 32 字节密钥
// 优点：无需额外基础设施
// 缺点：每个设备不同密钥（后续支持多设备）
```

**实现文件**: 新文件 `KeyManagement.swift`
```swift
import Sodium

struct KeyMaterial {
    let key: Bytes              // 32 字节 libsodium 密钥
    let salt: Bytes             // PBKDF2 salt
    let iterations: UInt32      // PBKDF2 迭代次数 (100,000)
}

class KeyManager {
    let sodium = Sodium()

    func deriveKeyFromPassword(
        password: String,
        salt: Bytes? = nil
    ) throws -> KeyMaterial {
        // PBKDF2 with 100,000 iterations
        // 返回 KeyMaterial
    }

    func verifyPasswordWithKey(
        password: String,
        keyMaterial: KeyMaterial
    ) -> Bool {
        // 验证密码是否匹配
    }
}
```

**密钥存储**:
- ✅ Keychain 存储密钥（安全）
- ✅ UserDefaults 存储 salt（非敏感）
- ✅ 内存中缓存密钥（应用生命周期）

#### 3. 消息加密/解密 API (1.5 天)

**新文件**: `MessageEncryption.swift`
```swift
import Sodium

struct EncryptedMessage {
    let v: Int                  // 版本
    let ciphertext: String      // base64
    let nonce: String           // base64
    let algorithm: String       // "sodium-secretbox"
}

class MessageCrypto {
    let sodium = Sodium()
    let keyManager: KeyManager

    func encryptMessage(
        plaintext: String,
        symmetricKey: Bytes
    ) throws -> EncryptedMessage {
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.invalidUTF8
        }

        // secretbox: authenticated encryption
        let nonce = sodium.randomBytes.buf(length: Sodium.SecretBox.NonceBytes)!
        let ciphertext = sodium.secretBox.seal(
            message: Bytes(data),
            secretKey: symmetricKey,
            nonce: nonce
        )!

        return EncryptedMessage(
            v: 1,
            ciphertext: ciphertext.base64EncodedString(),
            nonce: nonce.base64EncodedString(),
            algorithm: "sodium-secretbox"
        )
    }

    func decryptMessage(
        encrypted: EncryptedMessage,
        symmetricKey: Bytes
    ) throws -> String {
        guard let ciphertextBytes = Data(base64Encoded: encrypted.ciphertext),
              let nonceBytes = Data(base64Encoded: encrypted.nonce) else {
            throw CryptoError.invalidBase64
        }

        guard let plaintext = sodium.secretBox.open(
            sealedMessage: Bytes(ciphertextBytes),
            secretKey: symmetricKey,
            nonce: Bytes(nonceBytes)
        ) else {
            throw CryptoError.decryptionFailed
        }

        return String(bytes: plaintext, encoding: .utf8) ?? ""
    }
}

enum CryptoError: LocalizedError {
    case invalidUTF8
    case invalidBase64
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "Invalid UTF-8 encoding"
        case .invalidBase64:
            return "Invalid base64 encoding"
        case .decryptionFailed:
            return "Failed to decrypt message - corruption or wrong key"
        }
    }
}
```

**关键设计决策**:
- ✅ 使用 secretbox（对称密钥，简单）
- ✅ 每条消息随机生成新 nonce
- ✅ Fail-hard 错误处理（不隐藏错误）

### 📱 消息模型集成 (1 天)

**更新消息模型**:
```swift
// Message.swift
struct Message: Codable {
    let id: UUID
    let senderId: UUID
    let conversationId: UUID
    let encrypted: EncryptedPayload?    // ✅ 新字段
    let plaintext: String?              // 向后兼容
    let idempotencyKey: String
    let timestamp: Date
}

struct EncryptedPayload: Codable {
    let v: Int
    let ciphertext: String
    let nonce: String
    let algorithm: String
}
```

**集成点**:
- [ ] `MessagingRepository.swift` - `sendMessage()` 调用加密
- [ ] `WebSocketMessagingClient.swift` - `onMessage()` 调用解密
- [ ] 后端 API 已支持（向后兼容旧格式）

**代码示例**:
```swift
// MessagingRepository.swift
func sendMessage(
    conversationId: UUID,
    userId: UUID,
    plaintext: String,
    encryptionKey: Bytes
) async throws -> Message {
    let encrypted = try messageCrypto.encryptMessage(
        plaintext: plaintext,
        symmetricKey: encryptionKey
    )

    let payload = MessagePayload(
        senderId: userId,
        encrypted: encrypted,
        idempotencyKey: UUID().uuidString
    )

    let response = try await api.post(
        "/conversations/\(conversationId)/messages",
        body: payload
    )

    return try JSONDecoder().decode(Message.self, from: response)
}

// WebSocketMessagingClient.swift
func onMessage(_ payload: IncomingMessage) {
    do {
        var displayText: String

        if let encrypted = payload.message.encrypted {
            // 解密新消息
            displayText = try messageCrypto.decryptMessage(
                encrypted: encrypted,
                symmetricKey: currentEncryptionKey
            )
        } else {
            // 向后兼容旧消息
            displayText = payload.message.plaintext ?? "[无法解密]"
        }

        // 保存到本地数据库并更新 UI
        saveMessage(payload.message, displayText: displayText)
    } catch {
        logger.error("Decryption error: \(error)")
        // 显示错误，不隐藏
        showError("无法解密此消息")
    }
}
```

### 🧪 测试覆盖 (1.5 天)

**单元测试** (`MessageEncryptionTests.swift`):
```swift
import XCTest
@testable import NovaSocial

class MessageEncryptionTests: XCTestCase {
    var crypto: MessageCrypto!
    var testKey: Bytes!

    override func setUp() {
        super.setUp()
        crypto = MessageCrypto()
        testKey = Sodium().randomBytes.buf(length: 32)!
    }

    func testEncryptDecryptRoundTrip() async throws {
        let plaintext = "你好世界"

        let encrypted = try crypto.encryptMessage(
            plaintext: plaintext,
            symmetricKey: testKey
        )

        let decrypted = try crypto.decryptMessage(
            encrypted: encrypted,
            symmetricKey: testKey
        )

        XCTAssertEqual(decrypted, plaintext)
    }

    func testWrongKeyDecryptionFails() async throws {
        let wrongKey = Sodium().randomBytes.buf(length: 32)!
        let encrypted = try crypto.encryptMessage(
            plaintext: "secret",
            symmetricKey: testKey
        )

        XCTAssertThrowsError(
            try crypto.decryptMessage(
                encrypted: encrypted,
                symmetricKey: wrongKey
            )
        )
    }

    func testCorruptedCiphertextFails() async throws {
        var encrypted = try crypto.encryptMessage(
            plaintext: "secret",
            symmetricKey: testKey
        )

        // 破坏 ciphertext
        encrypted.ciphertext = "invalid"

        XCTAssertThrowsError(
            try crypto.decryptMessage(
                encrypted: encrypted,
                symmetricKey: testKey
            )
        )
    }
}
```

**集成测试** (`MessagingEncryptionIntegrationTests.swift`):
- [ ] 加密消息发送到后端
- [ ] 接收加密消息并解密
- [ ] 离线消息加密持久化
- [ ] 密钥派生验证
- [ ] 性能：1000 条消息加密耗时 < 1s

### 🔍 安全审查 (1 天)

**自检清单**:
- [ ] 没有硬编码密钥
- [ ] 密钥在 Keychain 中安全存储
- [ ] 使用加密学安全的随机数（`Sodium.randomBytes`）
- [ ] 错误不泄露加密细节
- [ ] 向后兼容旧消息
- [ ] 没有时序攻击风险
- [ ] Nonce 绝不重复（每条消息随机）

**建议**: iOS 安全专家审查（非阻塞）

---

## 📅 详细时间表

### Week 1 (本周) - 8 天

| 时段 | 任务 | 工时 | 状态 |
|------|------|------|------|
| Day 1 (今天) | ✅ 架构澄清 + 删除 Web 前端 | 1h | ✅ 完成 |
| Day 2 | libsodium.swift 库集成 + SPM 配置 | 4h | 📅 明天开始 |
| Day 3-4 | KeyManagement.swift + Keychain 存储 | 8h | 📅 周三-周四 |
| Day 5 | MessageEncryption.swift + 加密/解密 API | 6h | 📅 周五 |
| Day 6 | 消息模型集成 + Repository 修改 | 4h | 📅 周六 |
| Day 7 | 单元测试 + 基本集成测试 | 4h | 📅 周日 |
| Day 8 | 性能基准 + 文档 | 2h | 📅 周一 |

**预期完成**: 下周一 (11月3日)

### Week 2 (下周) - 4.5 天 (P2 视频上传)

| 时段 | 任务 | 工时 | 状态 |
|------|------|------|------|
| Day 1-2 | 分块上传实现 + 断点续传 | 6h | 📅 |
| Day 3 | 进度跟踪 UI | 2h | 📅 |
| Day 4 | 视频播放集成 | 4h | 📅 |
| Day 5 | 测试 + 文档 | 2h | 📅 |

**预期完成**: 第二周五 (11月7日)

---

## 🔄 优先级安排

### P1: iOS 端到端加密系统 ✅
**状态**: 优先级最高
**原因**: 安全基础，所有消息功能依赖
**预期完成**: 11月3日

### P2: iOS 视频上传 & 流媒体
**状态**: 次优先
**原因**: 消息系统不依赖视频，可并行开发
**预期完成**: 11月7日

### P3: 推送通知 + 离线同步
**状态**: 第三优先
**原因**: 用户体验优化，可在 P1/P2 之后
**预期完成**: 11月10日

---

## 🎯 成功指标

### P1 功能指标
- [ ] iOS 发送加密消息到后端
- [ ] iOS 接收并解密消息
- [ ] 密钥正确派生（PBKDF2）
- [ ] 旧消息（未加密）向后兼容显示
- [ ] 离线消息加密持久化到本地数据库
- [ ] 100% 加密覆盖（所有新消息）

### P1 性能指标
- [ ] 加密 1KB 消息 < 50ms
- [ ] 加密 1000 条消息 < 5s
- [ ] 内存增长 < 10MB
- [ ] Keychain 访问延迟 < 10ms

### P1 质量指标
- [ ] 单元测试覆盖率 > 85%
- [ ] 集成测试覆盖率 > 80%
- [ ] 安全审查通过
- [ ] 零加密相关的 crash（生产环境）
- [ ] 消息完整性：0% 损坏率

---

## ⚠️ 风险分析

### 高风险
1. **密钥管理错误**
   - 后果：所有消息都不安全，用户隐私泄露
   - 缓解：Keychain 存储，提前安全审查，从简单实现开始

2. **Keychain 访问失败**
   - 后果：用户无法读取消息
   - 缓解：优雅降级，清晰错误提示，日志记录

### 中风险
3. **向后兼容性破坏**
   - 后果：用户看不到旧消息
   - 缓解：同时支持加密和未加密格式

4. **性能下降**
   - 后果：UI 卡顿（输入延迟）
   - 缓解：异步加密，性能测试，缓存 nonce

5. **libsodium 库问题**
   - 后果：编译失败或运行时错误
   - 缓解：选择官方 swift-sodium，早期测试

### 低风险
6. **测试覆盖不足**
   - 后果：隐藏的 bug
   - 缓解：自动化测试，手动测试清单

---

## 💡 Linus 式总结

**问题 1**: 前端代码虚假的安全感（占位符加密）
**问题 2**: 架构错误（不需要 Web 前端）

**解决方案**:
1. ✅ 删除 Web 前端（无用的代码）
2. ✅ iOS 实现真实加密（libsodium）
3. ✅ 后端支持加密消息（已完成）

**核心原则**：
- **不要假装完成功能** - "加密"必须是真的
- **从简单的实现开始** - Option A 足够好，不要过度工程
- **移动优先** - 项目是 iOS，不是 Web
- **测试很关键** - 加密没有"基本能工作"，要么完美要么删除

**时间预期**：
- Day 1-2: 库集成 + 密钥管理 (3 天)
- Day 3-5: 加密/解密 API + 集成 (3 天)
- Day 6-8: 测试 + 文档 (2 天)
- **总计**: 8 天（不含 P2 视频上传）

---

## 📝 执行检查清单

### ✅ Day 1 (已完成)
- [x] 架构澄清：项目是 iOS 优先
- [x] 删除无用的 Web 前端
- [x] 创建修正计划

### 📅 Day 2 (明天开始)
- [ ] libsodium.swift 集成
- [ ] SPM 配置，编译通过
- [ ] 性能基准测试（加密 1KB）

### 📅 Day 3-4 (周三-周四)
- [ ] KeyManager 实现（PBKDF2）
- [ ] Keychain 集成
- [ ] 盐值存储和检索

### 📅 Day 5 (周五)
- [ ] MessageCrypto.swift 完成
- [ ] encryptMessage() 和 decryptMessage() 完成
- [ ] 错误处理（Fail-hard）

### 📅 Day 6 (周六)
- [ ] Message.swift 模型更新
- [ ] MessagingRepository 修改
- [ ] WebSocketMessagingClient 修改

### 📅 Day 7 (周日)
- [ ] 单元测试编写和运行
- [ ] 集成测试编写和运行
- [ ] 覆盖率检查 (> 80%)

### 📅 Day 8 (下周一)
- [ ] 性能基准验证
- [ ] 文档编写
- [ ] 安全审查准备

---

**最后确认**: 这个计划是否可以开始执行？

**下一步**: 我可以立即创建 Swift 源文件框架，让你开始实现。

May the Force be with you.
