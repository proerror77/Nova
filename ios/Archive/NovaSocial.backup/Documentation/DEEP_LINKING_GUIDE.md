# Nova Social iOS 深层链接完整指南

## 🔗 支持的深层链接

### 自定义 URL Scheme
```
novassocial://user/{userId}              # 用户资料
novassocial://post/{postId}              # 帖子详情
novassocial://search?q={query}           # 搜索
novassocial://notifications              # 通知列表
novassocial://explore                    # 探索页面
novassocial://auth/verify?token={token}  # 邮箱验证
novassocial://                           # 首页
```

### Universal Links (推荐)
```
https://nova.social/user/{userId}
https://nova.social/post/{postId}
https://nova.social/search?q={query}
https://nova.social/notifications
https://nova.social/explore
https://nova.social/auth/verify?token={token}
https://nova.social/
```

---

## 🛠 项目配置

### 1. 配置 Info.plist (自定义 URL Scheme)

在 `Info.plist` 中添加:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.nova.social</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>novassocial</string>
        </array>
    </dict>
</array>
```

### 2. 配置 Associated Domains (Universal Links)

#### Xcode 项目设置
1. 选择项目 → Signing & Capabilities
2. 点击 `+ Capability` → 添加 `Associated Domains`
3. 添加域名:
   ```
   applinks:nova.social
   applinks:www.nova.social
   ```

#### 后端配置
在 `https://nova.social/.well-known/apple-app-site-association` 放置此文件:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAM_ID.com.nova.social",
        "paths": [
          "/user/*",
          "/post/*",
          "/search",
          "/notifications",
          "/explore",
          "/auth/verify"
        ]
      }
    ]
  }
}
```

**注意事项**:
- 文件必须通过 HTTPS 提供
- Content-Type 必须是 `application/json`
- 不能有重定向
- 文件大小 < 128KB

---

## 💻 代码实现

### DeepLinkRouter 使用示例

#### 1. 处理传入的深层链接

```swift
import SwiftUI

@main
struct NovaSocialApp: App {
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deepLinkRouter)
                .onOpenURL { url in
                    // 自动处理自定义 scheme 和 Universal Links
                    deepLinkRouter.handle(url)
                }
                .handleDeepLinks(router: deepLinkRouter)
        }
    }
}
```

#### 2. 生成分享链接

```swift
// 在帖子卡片中添加分享按钮
struct PostCell: View {
    let post: Post

    var body: some View {
        VStack {
            // ... 帖子内容

            Button("分享") {
                let route = DeepLinkRoute.postDetail(postId: post.id.uuidString)
                if let url = route.shareURL {
                    shareURL(url)
                }
            }
        }
    }

    func shareURL(_ url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // 显示分享面板
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}
```

#### 3. 编程式导航

```swift
struct NotificationCell: View {
    let notification: Notification
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter

    var body: some View {
        Button {
            // 根据通知类型导航
            switch notification.type {
            case .like, .comment:
                deepLinkRouter.navigateToPost(notification.postId)
            case .follow:
                deepLinkRouter.navigateToUser(notification.userId)
            }
        } label: {
            // 通知内容
            Text(notification.message)
        }
    }
}
```

---

## 🧪 测试深层链接

### 方法 1: Safari 浏览器测试

1. 在 iOS 模拟器或真机上打开 Safari
2. 输入深层链接:
   ```
   novassocial://user/123
   ```
3. 点击前往，应自动打开 Nova Social 应用

### 方法 2: 命令行测试（模拟器）

```bash
# 测试自定义 scheme
xcrun simctl openurl booted "novassocial://user/123"

# 测试 Universal Link
xcrun simctl openurl booted "https://nova.social/post/456"

# 测试搜索
xcrun simctl openurl booted "novassocial://search?q=hello"
```

### 方法 3: Xcode Scheme 参数测试

1. 编辑 Scheme（Product → Scheme → Edit Scheme）
2. Run → Arguments → Environment Variables
3. 添加:
   ```
   Key: _XCT_LAUNCH_URL
   Value: novassocial://user/123
   ```
4. 运行应用，会自动处理该 URL

### 方法 4: Notes 应用测试

1. 打开 Notes 应用
2. 输入链接:
   ```
   novassocial://user/123
   ```
3. 长按链接 → Open in Safari
4. 应自动打开 Nova Social

### 方法 5: 代码内测试

```swift
#if DEBUG
struct DeepLinkTestView: View {
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter

    var body: some View {
        List {
            Button("测试用户资料") {
                let url = URL(string: "novassocial://user/123")!
                deepLinkRouter.handle(url)
            }

            Button("测试帖子详情") {
                let url = URL(string: "novassocial://post/456")!
                deepLinkRouter.handle(url)
            }

            Button("测试搜索") {
                let url = URL(string: "novassocial://search?q=hello")!
                deepLinkRouter.handle(url)
            }

            Button("测试 Universal Link") {
                let url = URL(string: "https://nova.social/user/789")!
                deepLinkRouter.handle(url)
            }
        }
        .navigationTitle("深层链接测试")
    }
}
#endif
```

---

## 📱 真实场景示例

### 场景 1: 邮件验证链接

**用户收到邮件**:
```
感谢注册 Nova Social!

请点击以下链接验证邮箱:
https://nova.social/auth/verify?token=abc123xyz
```

**点击链接后**:
1. 打开 Nova Social 应用
2. 显示 `EmailVerificationView`
3. 自动调用后端 API 验证 token
4. 验证成功后跳转到首页

### 场景 2: 推送通知深层链接

**用户收到推送**:
```json
{
  "aps": {
    "alert": "John 点赞了你的帖子",
    "sound": "default"
  },
  "deepLink": "novassocial://post/456"
}
```

**点击推送后**:
1. 应用从后台唤醒
2. 处理 `deepLink` 字段
3. 打开帖子详情页

**代码实现**:
```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    let userInfo = response.notification.request.content.userInfo

    if let deepLinkString = userInfo["deepLink"] as? String,
       let url = URL(string: deepLinkString) {
        DeepLinkRouter.shared.handle(url)
    }

    completionHandler()
}
```

### 场景 3: 二维码扫描

**用户扫描二维码**:
```
QR Code 内容: novassocial://user/johndoe
```

**扫描后**:
1. iOS 相机识别 URL
2. 弹出"在 Nova Social 中打开"提示
3. 打开用户资料页

### 场景 4: 分享到社交媒体

**用户分享帖子到 Twitter**:
```
看看我在 Nova Social 的新帖子!
https://nova.social/post/789
```

**其他用户点击链接**:
- **已安装 Nova Social**: 直接打开应用显示帖子
- **未安装**: 打开 Web 版（需后端支持）

---

## 🔐 安全注意事项

### 1. 验证 URL 参数

```swift
func parse(_ url: URL) -> DeepLinkRoute? {
    // ✅ 好的做法: 验证参数格式
    let userId = extractId(from: path, prefix: "/user/")
    guard let userId = userId, UUID(uuidString: userId) != nil else {
        print("❌ 无效的 userId: \(userId)")
        return nil
    }

    // ❌ 坏的做法: 直接使用未验证的参数
    // return .userProfile(userId: path.replacingOccurrences(of: "/user/", with: ""))
}
```

### 2. 防止 URL 注入

```swift
// ✅ 使用白名单路由
let validPaths = ["/user/", "/post/", "/search", "/notifications"]
guard validPaths.contains(where: { path.hasPrefix($0) }) else {
    return nil
}

// ❌ 不要执行任意代码
// eval(url.query) // 危险!
```

### 3. 验证 Universal Link 域名

```swift
// 仅处理信任的域名
let trustedHosts = ["nova.social", "www.nova.social"]
guard let host = url.host, trustedHosts.contains(host) else {
    return nil
}
```

---

## 📊 分析和追踪

### 记录深层链接使用

```swift
private func logDeepLinkEvent(_ route: DeepLinkRoute) {
    // Firebase Analytics
    Analytics.logEvent("deep_link_opened", parameters: [
        "route": route.description,
        "source": "unknown" // 可以从 URL 参数获取来源
    ])

    // 或者使用自己的分析系统
    print("📊 [Analytics] DeepLink: \(route)")
}
```

### UTM 参数支持

```swift
func parseQuery(_ query: String?) -> [String: String] {
    guard let query = query else { return [:] }
    var params: [String: String] = [:]

    for component in query.components(separatedBy: "&") {
        let parts = component.components(separatedBy: "=")
        guard parts.count == 2 else { continue }
        params[parts[0]] = parts[1]
    }

    // 记录 UTM 参数
    if let source = params["utm_source"] {
        print("📊 来源: \(source)")
    }

    return params
}
```

**示例 URL**:
```
https://nova.social/user/123?utm_source=twitter&utm_campaign=summer2025
```

---

## 🐛 常见问题排查

### 问题 1: Universal Link 不工作

**可能原因**:
1. `apple-app-site-association` 文件配置错误
2. 域名未添加到 Associated Domains
3. 应用首次安装后需要重启设备

**解决方案**:
```bash
# 验证 AASA 文件
curl -v https://nova.social/.well-known/apple-app-site-association

# 检查是否返回正确的 JSON
# Content-Type: application/json
# 无重定向
```

### 问题 2: 自定义 Scheme 不工作

**可能原因**:
1. Info.plist 配置错误
2. Scheme 名称冲突

**解决方案**:
```bash
# 检查 Info.plist
plutil -p Info.plist | grep -A 10 CFBundleURLTypes

# 确保 CFBundleURLSchemes 包含 "novassocial"
```

### 问题 3: 深层链接打开空白页

**可能原因**:
1. 路由解析失败
2. 目标视图未正确初始化

**调试步骤**:
```swift
func handle(_ url: URL) {
    print("🔍 [Debug] 收到 URL: \(url)")

    guard let route = parse(url) else {
        print("❌ [Debug] 解析失败")
        return
    }

    print("✅ [Debug] 解析成功: \(route)")
    activeRoute = route
}
```

---

## 📚 最佳实践

### 1. 使用 Universal Links 优先

✅ **推荐**:
```
https://nova.social/user/123
```

❌ **不推荐**:
```
novassocial://user/123
```

**原因**:
- Universal Links 在 Safari 中可预览
- 未安装应用时可回退到 Web 版
- 更好的 SEO

### 2. 保持 URL 简洁

✅ **好**:
```
https://nova.social/post/123
```

❌ **坏**:
```
https://nova.social/posts/view?id=123&action=open&source=app
```

### 3. 提供回退方案

```swift
func handle(_ url: URL) {
    guard let route = parse(url) else {
        // 回退到首页
        activeRoute = .home
        return
    }

    activeRoute = route
}
```

### 4. 测试所有路由

```swift
#if DEBUG
func testAllRoutes() {
    let testURLs = [
        "novassocial://user/123",
        "novassocial://post/456",
        "novassocial://search?q=test",
        "https://nova.social/notifications"
    ]

    for urlString in testURLs {
        if let url = URL(string: urlString) {
            DeepLinkRouter.shared.handle(url)
        }
    }
}
#endif
```

---

## 🚀 进阶功能

### 延迟深层链接 (Deferred Deep Linking)

**场景**: 用户点击链接但未安装应用

**方案**:
1. 使用 Firebase Dynamic Links 或 Branch.io
2. 记录用户点击的链接
3. 应用首次安装后，恢复该链接

```swift
// Firebase Dynamic Links 示例
import FirebaseDynamicLinks

DynamicLinks.dynamicLinks().handleUniversalLink(url) { dynamicLink, error in
    guard let url = dynamicLink?.url else { return }
    DeepLinkRouter.shared.handle(url)
}
```

### 条件路由

```swift
func handle(_ url: URL) {
    guard let route = parse(url) else { return }

    // 检查用户是否登录
    if !AuthManager.shared.isAuthenticated {
        // 保存路由，登录后恢复
        UserDefaults.standard.set(url.absoluteString, forKey: "pendingDeepLink")
        // 显示登录页
        activeRoute = .home
        return
    }

    activeRoute = route
}
```

---

## 📖 参考资源

- [Apple Universal Links Documentation](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
- [Custom URL Schemes](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)
- [Branch.io Deep Linking Guide](https://help.branch.io/developers-hub/docs/ios-sdk-overview)
- [Firebase Dynamic Links](https://firebase.google.com/docs/dynamic-links)

---

## ✅ 检查清单

**配置检查**:
- [ ] Info.plist 包含 CFBundleURLTypes
- [ ] Associated Domains 已配置
- [ ] AASA 文件可访问（HTTPS）
- [ ] AASA 文件格式正确（JSON）

**代码检查**:
- [ ] `.onOpenURL` 已添加到 App
- [ ] DeepLinkRouter 正确处理所有路由
- [ ] 所有目标视图已实现
- [ ] 错误处理完善

**测试检查**:
- [ ] Safari 测试通过
- [ ] 模拟器命令行测试通过
- [ ] 真机测试通过
- [ ] 推送通知深层链接测试通过
- [ ] 分享功能测试通过

**安全检查**:
- [ ] URL 参数验证
- [ ] 域名白名单
- [ ] 防止注入攻击
- [ ] 用户授权检查

---

## 🎯 快速开始（5分钟）

1. **配置 Info.plist**:
   ```xml
   <key>CFBundleURLSchemes</key>
   <array><string>novassocial</string></array>
   ```

2. **添加处理代码**:
   ```swift
   .onOpenURL { url in
       DeepLinkRouter.shared.handle(url)
   }
   ```

3. **测试**:
   ```bash
   xcrun simctl openurl booted "novassocial://user/123"
   ```

完成! 🎉
