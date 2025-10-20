# Accessibility & Deep Linking - Quick Start Guide

## 🚀 5 分钟快速上手

### 1. 使用可访问按钮

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        VStack {
            // ✅ 完全可访问的按钮
            AccessibleButton(
                "Sign In",
                icon: "person.fill",
                style: .primary,
                action: signIn
            )
            .accessibilityHint("Double tap to sign in to your account")

            // ✅ 图标按钮
            AccessibleIconButton(
                icon: "heart.fill",
                action: toggleLike,
                accessibilityLabel: "Like post",
                accessibilityHint: "Double tap to like this post"
            )
        }
    }
}
```

### 2. 为视图添加可访问性

```swift
struct PostCard: View {
    let post: Post

    var body: some View {
        VStack {
            // 内容
        }
        .feedPostAccessibility(
            author: post.author,
            content: post.content,
            timestamp: post.createdAt,
            likes: post.likesCount,
            comments: post.commentsCount,
            isLiked: post.isLiked,
            onLike: { toggleLike() },
            onComment: { openComments() },
            onShare: { sharePost() }
        )
    }
}
```

### 3. 处理深层链接

```swift
// 解析 URL
let url = URL(string: "novasocial://user/123")!
let route = deepLinkRouter.parse(url: url)

// 生成分享链接
let shareURL = DeepLinkBuilder.userProfile(userId: "123")
// https://nova.social/user/123

// 分享帖子
let activityItems = DeepLinkRoute.post(postId: "456")
    .activityItems(router: deepLinkRouter)
let activityVC = UIActivityViewController(
    activityItems: activityItems,
    applicationActivities: nil
)
```

### 4. 测试深层链接

**模拟器**:
```bash
xcrun simctl openurl booted "novasocial://user/123"
```

**真机** (Notes 或 Messages):
```
https://nova.social/user/123
```

### 5. 验证可访问性

**启用 VoiceOver**:
设置 → 辅助功能 → VoiceOver → 开启

**测试 Dynamic Type**:
设置 → 辅助功能 → 显示与文字大小 → 更大字体

**启用 Reduce Motion**:
设置 → 辅助功能 → 动态效果 → 减弱动态效果

---

## 📚 完整文档

- [Accessibility Checklist](Accessibility/AccessibilityChecklist.md)
- [Accessibility Audit Report](Documentation/AccessibilityAuditReport.md)
- [Deep Linking Guide](Documentation/DeepLinkingGuide.md)
- [Universal Links Setup](Config/UniversalLinksSetup.md)
- [Delivery Report](ACCESSIBILITY_DEEPLINKING_DELIVERY.md)

---

## ✅ 检查清单

- [ ] 所有按钮 >= 44x44pt
- [ ] 所有文本对比度 >= 4.5:1
- [ ] 所有图片有 `accessibilityLabel`
- [ ] 装饰性图片标记为 `accessibilityHidden(true)`
- [ ] 所有表单字段有标签
- [ ] 错误消息立即公告
- [ ] 动画尊重 Reduce Motion
- [ ] VoiceOver 测试通过
- [ ] Dynamic Type 测试通过
- [ ] 深层链接测试通过

---

## 🆘 常见问题

**Q: 如何确保按钮足够大？**

A: 使用 `AccessibleButton` 或添加 `.accessibleTouchTarget()`:
```swift
Button("Tap") { }
    .accessibleTouchTarget() // 自动扩展到 44x44pt
```

**Q: 如何测试对比度？**

A:
```swift
let ratio = Color.primary.contrastRatio(with: Color.background)
print("Contrast: \(ratio):1") // 应该 >= 4.5:1
```

**Q: Universal Links 不工作？**

A: 
1. 检查 `apple-app-site-association` 文件可访问
2. 验证 Team ID 匹配
3. 等待 24 小时让 Apple CDN 更新
4. 在真机上测试（不能用模拟器）

---

**就是这么简单！** 🎉
