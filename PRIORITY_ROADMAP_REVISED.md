# 🗓️ Nova 项目优先级路线图 - 修正版

**更新日期**: 2025-10-25
**决策**: 优先交付用户可见功能，消息加密推后
**规划周期**: 今天 → 12月中旬

---

## 📊 优先级矩阵 (修正版)

```
影响力 ↑
        │
   高  │  P1A: Stories          P1B: 推送通知
        │  P1C: iOS 视频上传
        │
   中  │  P2A: 评论回复链        P2B: 直播流
        │
   低  │  P3A: 消息加密*         P3B: 高级搜索
        │  (*现在是占位符+at-rest)
        └─────────────────────────────→ 工时
         少              多
```

**关键决策**：
- ✅ 前端 E2E 加密 → 移至 P3 (不阻塞用户功能)
- ✅ Stories + 推送 → 提升至 P1 (用户看得到)
- ✅ 视频上传 → 保留 P1 (核心功能)

---

## 🎯 P1: 用户可见功能 (1-2 周)

### P1A: Stories 系统 (4-5 天)

**概述**: 类似 Instagram/Snapchat 的短期内容

**工作项**:

#### 后端准备 (1 天)
- [ ] 数据库: stories 表
  - id, user_id, media_url, caption, created_at, expires_at (24h)
- [ ] API 端点
  - `POST /stories` - 创建
  - `GET /users/{id}/stories` - 获取
  - `DELETE /stories/{id}` - 删除

#### 前端实现 (2 天)
- [ ] `StoriesView.tsx` - 主组件
  - 竖直滚动轮播
  - 用户头像显示
  - 进度条 (故事停留时间)
  - 自动翻页

- [ ] `StoryUpload.tsx` - 上传组件
  - 拍照/选择图片
  - 文字标注
  - 预览

- [ ] 状态管理
  - `storiesStore.ts` (Zustand)
  - 故事列表、当前位置、过期处理

**预期完成**: 10月31日

---

### P1B: 推送通知集成 (3-4 天)

**概述**: 用户离线时接收消息、Like、评论通知

**工作项**:

#### 后端准备 (1 天)
- [ ] FCM 配置 (Android)
- [ ] APNs 配置 (iOS)
- [ ] 通知 API 端点
  - `POST /notifications/send`
  - `GET /notifications` - 列表
  - `DELETE /notifications/{id}`

#### 前端实现 (1 天)
- [ ] Web: 浏览器推送
  - Service Worker 集成
  - 权限请求
  - 通知处理

- [ ] 通知数据库
  - 未读通知计数
  - 通知历史

#### iOS 实现 (1.5 天)
- [ ] APNs 证书配置
- [ ] Push 处理
  - 后台接收
  - 本地通知转换
  - 点击导航

#### 测试 (0.5 天)
- [ ] 发送通知并验证显示
- [ ] 离线场景测试

**预期完成**: 11月2日

---

### P1C: iOS 视频上传 (3-4 天)

**概述**: iOS 应用中的视频上传 (创建 post)

**工作项**:

#### 后端准备 (1 天)
- [ ] 视频上传端点
  - `POST /videos/upload-url` - 获取 S3 签名 URL
  - `POST /posts/create-with-video` - 创建包含视频的 post

#### iOS 实现 (2 天)
- [ ] 视频拾取器
  - 从相机或相册选择
  - 压缩/优化

- [ ] 分块上传
  ```swift
  // 大视频分块上传到 S3
  // 每块 5MB
  // 支持重试
  ```

- [ ] 进度跟踪
  - UI 显示上传进度
  - 暂停/恢复

- [ ] 断点续传
  ```swift
  // 如果上传中断，下次可以续传
  // 记录已上传块数
  ```

#### 测试 (0.5 天)
- [ ] 正常上传测试
- [ ] 网络中断恢复测试
- [ ] 大文件上传测试 (>100MB)

**预期完成**: 11月5日

---

## 📅 P1 时间表

```
第1周 (今天-周日)
├─ Mon-Tue: Stories 后端 + 前端基础
├─ Wed-Thu: Stories 完成 + 推送通知后端
└─ Fri-Sun: 推送通知前端 + iOS 视频上传基础

第2周 (11月1-5日)
├─ Mon-Tue: iOS 视频上传完成
├─ Wed: 集成测试 + bug 修复
└─ Thu-Fri: 部署准备 + 文档

预期交付: 11月7日 (P1 全部完成)
```

**关键里程碑**:
- 10月31日: Stories 上线 ✓
- 11月2日: 推送通知上线 ✓
- 11月5日: iOS 视频上传完成 ✓

---

## 🔄 P2: 基础设施和高级功能 (11月8-22日)

### P2A: 消息加密系统 (升级为 P2) [1 周]

**为什么降级到 P2？**
- 当前消息系统有 at-rest 加密 (localStorage)
- 占位符 E2E 虽然不是真正加密，但已工作
- 推送通知 > 消息加密的优先级（用户看得到）

**但重要性不降低**：
- 规划已完成 (`P1_REVISED_PLAN.md`)
- 一旦开始，应该完整实现

**预计**: 11月8-15日 (1 周专注实现)

---

### P2B: 评论回复链 (3-4 天)

**概述**: 实现评论的嵌套回复结构

**当前状态**: 评论是扁平列表
**目标状态**: 评论可以回复其他评论

**工作**:
- 数据库: 添加 `reply_to` 字段
- API: 支持嵌套查询
- UI: 树形展示评论

**预期**: 11月16-19日

---

### P2C: 高级搜索 (2-3 天)

**概述**: 支持按用户、标签、日期搜索

**工作**:
- 后端: 搜索索引 (Elasticsearch 或 ClickHouse)
- 前端: 搜索 UI
- iOS: 搜索集成

**预期**: 11月20-22日

---

## 🔮 P3: 未来功能 (11月23+)

- **直播流系统** - 实时视频
- **私聊加密** - 真正的端到端
- **推荐算法 v2** - 深度学习
- **离线内容同步** - 预下载

---

## 📊 工作量总结

| 优先级 | 工作项 | 工时 | 完成日期 |
|-------|--------|------|--------|
| **P1** | | **15-18h** | |
| | Stories | 4-5h | 10/31 |
| | 推送通知 | 5-6h | 11/2 |
| | iOS 视频上传 | 6-7h | 11/5 |
| **P2** | | **10-12h** | |
| | 消息加密 (E2E) | 6-8h | 11/15 |
| | 评论回复 | 3-4h | 11/19 |
| | 高级搜索 | 2-3h | 11/22 |
| **P3** | | TBD | 11/23+ |
| **总计** | | **25-30h** | **11/22** |

---

## 🎯 P1 详细设计

### Stories 系统架构

**后端数据库**:
```sql
CREATE TABLE stories (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  media_url TEXT NOT NULL,
  caption TEXT,
  created_at TIMESTAMP,
  expires_at TIMESTAMP,  -- 24小时后过期
  viewed_by JSONB,       -- [user_id, ...]
  deleted BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_stories_user_expires
  ON stories(user_id, expires_at);
```

**前端数据流**:
```
┌─────────────────┐
│  StoriesView    │
│  (主轮播组件)   │
└────────┬────────┘
         │
         ↓
┌─────────────────────────┐
│  storiesStore.ts        │
│  (状态管理)             │
├─────────────────────────┤
│ - currentIndex          │
│ - stories: Story[]      │
│ - viewedStories: Set    │
│ - autoPlay: boolean     │
└────────┬────────────────┘
         │
         ↓
┌─────────────────────────┐
│  API Calls              │
│  GET /users/{id}/stories│
│  POST /stories/{id}/view│
└─────────────────────────┘
```

**前端 UI 草图**:
```
┌──────────────────────┐
│  [故事用户头像]  X   │  (关闭)
│  [════════════════]  │  (进度条)
│                      │
│  [全屏图片/视频]     │
│                      │
│  [文字标注]          │
│  [Like] [评论] [分享]│
└──────────────────────┘
```

**手势**:
- 横向滑动: 上一个/下一个故事
- 点击左半屏: 暂停/播放
- 点击右半屏: 下一个
- 长按: 暂停

---

### 推送通知流程

**触发点**:
```
用户 A 发送消息给用户 B
  ↓
后端检查 B 是否在线
  ├─ 在线: 发送实时消息 (WebSocket)
  └─ 离线:
     ├─ 保存消息
     ├─ 生成通知
     ├─ 发送 FCM (Android)
     ├─ 发送 APNs (iOS)
     └─ 保存通知历史
```

**通知数据格式**:
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "type": "message|like|comment|story",
  "related_user": {
    "id": "uuid",
    "name": "Alice",
    "avatar_url": "..."
  },
  "title": "Alice 给你发来一条消息",
  "body": "你好，怎么样...",
  "click_action": "/messages/conversation/uuid",
  "created_at": "2025-10-25T10:00:00Z",
  "read": false
}
```

**iOS APNs 集成**:
```swift
import UserNotifications

// 1. 请求权限
UNUserNotificationCenter.current().requestAuthorization(
  options: [.alert, .sound, .badge]
) { granted, _ in
  DispatchQueue.main.async {
    UIApplication.shared.registerForRemoteNotifications()
  }
}

// 2. 处理推送
func userNotificationCenter(
  _ center: UNUserNotificationCenter,
  didReceive response: UNNotificationResponse,
  withCompletionHandler completionHandler: @escaping () -> Void
) {
  let userInfo = response.notification.request.content.userInfo

  // 解析通知数据
  if let conversationId = userInfo["click_action"] as? String {
    // 导航到对应的对话
    navigateTo(conversationId: conversationId)
  }

  completionHandler()
}
```

---

### iOS 视频上传流程

**整体流程**:
```
用户选择视频
  ↓
获取 S3 签名 URL (从后端)
  ↓
分块上传 (5MB 每块)
  ├─ 块 1: http://s3.../parts/1
  ├─ 块 2: http://s3.../parts/2
  └─ ...
  ↓
通知后端上传完成
  ↓
后端生成 transcode job
  ↓
创建 Post (包含 video_url)
```

**实现关键点**:
```swift
// 1. 获取签名 URL
let signedURLRequest = try await api.getUploadURL(
  fileName: "video_\(UUID()).mp4",
  fileSize: videoSize
)

// 2. 分块上传
let chunkSize = 5 * 1024 * 1024  // 5MB
for (index, chunk) in chunks.enumerated() {
  let partNumber = index + 1

  // 使用 S3 Multipart Upload API
  let part = try await uploadChunk(
    url: signedURLRequest.uploadURL,
    partNumber: partNumber,
    data: chunk
  )

  uploadedParts.append(part)

  // 更新进度
  progress = Double(index + 1) / Double(chunks.count)
  updateProgressUI(progress)
}

// 3. 完成上传
let uploadedVideoURL = try await completeMultipartUpload(
  uploadURL: signedURLRequest.uploadURL,
  parts: uploadedParts
)

// 4. 创建 Post
let post = try await createPost(
  caption: caption,
  videoURL: uploadedVideoURL
)
```

---

## ⚡ 快速启动清单

### 立即行动 (今天)

- [ ] 确认这个优先级顺序
- [ ] 创建 JIRA/任务板
  - P1A: Stories
  - P1B: 推送通知
  - P1C: iOS 视频上传
- [ ] 分配工作

### 本周 (开发)

- [ ] Mon-Tue: Stories 后端开发
- [ ] Wed: Stories 前端开发
- [ ] Thu: 推送通知规划和后端准备
- [ ] Fri: iOS 视频上传开发

### 下周 (测试和交付)

- [ ] 集成测试
- [ ] 性能测试
- [ ] 安全审查 (推送通知)
- [ ] 部署

---

## 📝 文档待办

- [ ] Stories API 文档
- [ ] 推送通知集成指南
- [ ] iOS 视频上传步骤
- [ ] E2E 测试计划

---

## 🔗 相关文档

- ✅ `FRONTEND_CODE_REVIEW.md` - 前端代码审查
- ✅ `P1_REVISED_PLAN.md` - 消息加密详细计划 (现为 P2)
- 📋 `00_START_HERE.md` - P0 交付清单
- 📋 `INTEGRATION_VERIFICATION_CHECKLIST.md` - P0 验证

---

## 🎬 总结

**今天的决策**:
- ✅ 推迟 E2E 消息加密 → P2 (不阻塞用户功能)
- ✅ 优先 Stories + 推送通知 + 视频上传 → P1
- ✅ 保留加密计划完整性，下周开始执行

**预期成果**:
- 11月7日: P1 全部完成
- 11月15日: P2 消息加密完成
- 11月22日: P2 其他功能完成

**风险**:
- 低: 所有工作项都有清晰的设计
- 低: 没有重大依赖关系阻塞
- 中: 消息加密延后带来的安全考虑（但 at-rest 加密已有）

---

**由 Linus 制定**
**关键原则**: "先交付用户可见的价值，基础设施随后"

May the Force be with you.
