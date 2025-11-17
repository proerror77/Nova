# Nova iOS - 功能实现清单

## 优先级 P0 (关键 - 影响核心功能)

### 网络和连接
- [ ] **TURN 服务器动态配置**
  - 文件: `/Services/WebRTC/WebRTCManager.swift` (第 18-29 行)
  - 实现: 从 API 端点 `GET /config/turn-servers` 获取配置
  - 优先级: 视频通话功能完整性
  - 工作量: 中等 (2-3 小时)

- [ ] **消息搜索 API 集成**
  - 文件: `/Network/Repositories/MessagingRepository.swift`
  - 实现: 添加 `searchMessages()` 方法
  - 端点: `GET /conversations/{id}/messages/search?q=...`
  - 优先级: UX 核心功能
  - 工作量: 小 (1-2 小时)

### 推送通知
- [ ] **APNs (Apple Push Notification Service)**
  - 实现点:
    1. 配置 APNs 证书
    2. 创建 NotificationManager
    3. 设备 token 注册到后端
    4. 处理远程通知
    5. 添加本地通知支持
  - 优先级: 用户交互关键
  - 工作量: 大 (8-10 小时)

### 群组消息
- [ ] **群组对话创建和管理**
  - 文件: `/Network/Repositories/MessagingRepository.swift`
  - 实现:
    1. `createGroupConversation()` 方法
    2. `addGroupMember()` 方法
    3. `removeGroupMember()` 方法
    4. `updateGroupInfo()` 方法
  - 优先级: 核心消息功能
  - 工作量: 大 (10-12 小时)

- [ ] **群组消息 UI**
  - 新文件: `/Views/Chat/GroupChatView.swift`
  - 新文件: `/Views/Chat/GroupManagementView.swift`
  - 优先级: 消息功能完整
  - 工作量: 中等 (6-8 小时)

---

## 优先级 P1 (重要 - 显著改进用户体验)

### 用户资料编辑
- [ ] **编辑用户资料**
  - 新文件: `/Views/User/EditProfileView.swift`
  - 新 ViewModel: `/ViewModels/User/EditProfileViewModel.swift`
  - 实现:
    1. 头像上传
    2. 个人信息编辑
    3. 密码修改
    4. 隐私设置
  - 优先级: 用户管理
  - 工作量: 中等 (5-7 小时)

### 分享和书签
- [ ] **分享功能**
  - 文件: `/Views/Feed/PostCell.swift` (TODO 注释)
  - 实现:
    1. 集成 ShareSheet
    2. 复制链接
    3. 分享到社交媒体
  - 优先级: 内容分发
  - 工作量: 小 (2-3 小时)

- [ ] **书签/收藏功能**
  - API 端点: `POST /posts/{id}/bookmark`
  - 实现:
    1. BookmarkRepository
    2. 书签列表视图
    3. 本地缓存
  - 优先级: 内容管理
  - 工作量: 小 (2-3 小时)

### 关注列表
- [ ] **关注者列表**
  - 新文件: `/Views/User/FollowersListView.swift`
  - API: `GET /users/{id}/followers`
  - 优先级: 社交功能
  - 工作量: 小 (2-3 小时)

- [ ] **关注中列表**
  - 新文件: `/Views/User/FollowingListView.swift`
  - API: `GET /users/{id}/following`
  - 优先级: 社交功能
  - 工作量: 小 (2-3 小时)

### 媒体消息
- [ ] **语音消息**
  - 新文件: `/MediaKit/Audio/AudioRecorder.swift`
  - 新文件: `/MediaKit/Audio/AudioPlayer.swift`
  - 实现:
    1. 音频录制
    2. 音频上传
    3. 播放和进度控制
    4. 消息集成
  - 优先级: 富媒体支持
  - 工作量: 大 (8-10 小时)

- [ ] **视频消息完整化**
  - 文件: `/MediaKit/Video/`
  - 实现:
    1. 视频上传到消息
    2. 自动转码
    3. 缩略图生成
  - 优先级: 富媒体支持
  - 工作量: 大 (10-12 小时)

### 深层链接完善
- [ ] **Deep Link 导航完整化**
  - 文件: `/DeepLinking/DeepLinkHandler.swift`
  - 实现: 完成所有 TODO 注释的导航
  - 优先级: 用户流程
  - 工作量: 小 (2-3 小时)

### 生物识别
- [ ] **FaceID/Touch ID 应用锁定**
  - 新文件: `/Services/Security/BiometricAuth.swift`
  - 实现:
    1. 本地认证集成
    2. 应用锁定
    3. 敏感操作确认
  - 优先级: 安全性
  - 工作量: 中等 (4-6 小时)

---

## 优先级 P2 (增强 - 高级功能)

### 故事功能 (Stories)
- [ ] **发布故事**
  - 新文件: `/Views/Stories/CreateStoryView.swift`
  - 新 ViewModel: `/ViewModels/Stories/StoryViewModel.swift`
  - 实现:
    1. 故事拍摄/选择
    2. 效果添加
    3. 发布
  - 优先级: 内容功能
  - 工作量: 大 (12-15 小时)

- [ ] **查看故事**
  - 新文件: `/Views/Stories/StoryViewerView.swift`
  - 实现:
    1. 故事列表
    2. 故事查看器
    3. 故事互动
  - 优先级: 内容消费
  - 工作量: 大 (10-12 小时)

### 内容举报和审核
- [ ] **举报功能**
  - 新文件: `/Views/Common/ReportView.swift`
  - 新 Repository: `/Network/Repositories/ReportRepository.swift`
  - 实现:
    1. 举报 UI
    2. 原因分类
    3. API 集成
  - 优先级: 社区管理
  - 工作量: 小 (3-4 小时)

### 推荐算法优化
- [ ] **个性化推荐**
  - 文件: `/ViewModels/Feed/FeedViewModel.swift`
  - 实现:
    1. 协作过滤
    2. 内容相似度
    3. 用户喜好学习
  - 优先级: UX 优化
  - 工作量: 大 (15-20 小时)

### 话题和标签
- [ ] **话题系统**
  - 新 Repository: `/Network/Repositories/TopicRepository.swift`
  - 实现:
    1. 话题搜索
    2. 话题页面
    3. 话题统计
  - 优先级: 内容分类
  - 工作量: 中等 (6-8 小时)

### 应用内浏览器
- [ ] **Safari 集成**
  - 新文件: `/Services/WebBrowser/WebBrowserManager.swift`
  - 实现:
    1. SFSafariViewController 包装
    2. 链接预览
    3. 阅读器模式
  - 优先级: 内容消费
  - 工作量: 小 (3-4 小时)

### 离线模式增强
- [ ] **完整离线支持**
  - 文件: `/LocalData/Managers/OfflineManager.swift`
  - 实现:
    1. 离线内容缓存
    2. 离线模式指示
    3. 冲突解决
  - 优先级: 可靠性
  - 工作量: 大 (10-12 小时)

### 实时视频直播
- [ ] **直播功能**
  - 新文件: `/Services/Streaming/StreamingManager.swift`
  - 实现:
    1. HLS 直播流
    2. 多人直播
    3. 直播聊天
    4. 礼物系统
  - 优先级: 高级功能
  - 工作量: 极大 (30-40 小时)

### AR 滤镜
- [ ] **ARKit 集成**
  - 新文件: `/Services/AR/ARFilterManager.swift`
  - 实现:
    1. 面部识别滤镜
    2. 虚拟背景
    3. 实时效果
  - 优先级: 高级功能
  - 工作量: 极大 (25-35 小时)

---

## 优先级 P3 (可选 - 扩展功能)

### 支付系统
- [ ] **StoreKit 2 集成**
  - 新文件: `/Services/Payments/PaymentManager.swift`
  - 实现:
    1. 产品配置
    2. 订阅管理
    3. 收据验证
  - 优先级: 商业功能
  - 工作量: 大 (12-15 小时)

### 位置服务
- [ ] **地理定位**
  - 新文件: `/Services/Location/LocationManager.swift`
  - 实现:
    1. 位置权限
    2. 位置分享
    3. 附近发现
  - 优先级: 社交功能
  - 工作量: 大 (10-12 小时)

### 云备份
- [ ] **iCloud 同步**
  - 新文件: `/Services/Cloud/CloudSyncManager.swift`
  - 实现:
    1. iCloud 备份
    2. 恢复流程
    3. 数据加密
  - 优先级: 可靠性
  - 工作量: 大 (12-15 小时)

### 蓝牙集成
- [ ] **NFC 和蓝牙**
  - 新文件: `/Services/Connectivity/BluetoothManager.swift`
  - 实现:
    1. NFC 扫描
    2. 蓝牙配对
    3. 近场分享
  - 优先级: 高级功能
  - 工作量: 大 (15-18 小时)

---

## 测试实现清单

### 单元测试增强
- [ ] **视频通话测试**
  - 文件: `/Tests/Unit/Calls/CallViewModelTests.swift`
  - 覆盖: 通话流程、信令、状态转换
  - 工作量: 中等 (4-6 小时)

- [ ] **WebRTC 测试**
  - 文件: `/Tests/Unit/WebRTC/WebRTCManagerTests.swift`
  - 覆盖: 连接、媒体流、ICE
  - 工作量: 中等 (4-6 小时)

### UI 测试
- [ ] **Feed 流测试**
  - 文件: `/Tests/UI/FeedViewTests.swift`
  - 覆盖: 滚动、刷新、加载
  - 工作量: 中等 (4-6 小时)

- [ ] **聊天测试**
  - 文件: `/Tests/UI/ChatViewTests.swift`
  - 覆盖: 消息发送、接收、编辑
  - 工作量: 中等 (4-6 小时)

### 集成测试
- [ ] **端到端消息流**
  - 文件: `/Tests/Integration/MessagingE2ETests.swift`
  - 工作量: 大 (8-10 小时)

- [ ] **视频通话流**
  - 文件: `/Tests/Integration/CallE2ETests.swift`
  - 工作量: 大 (10-12 小时)

### 性能测试
- [ ] **Feed 加载性能基准**
  - 文件: `/Tests/Performance/FeedPerformanceTests.swift`
  - 工作量: 小 (2-3 小时)

- [ ] **内存泄漏检查**
  - 文件: `/Tests/Performance/MemoryLeakTests.swift`
  - 工作量: 小 (2-3 小时)

---

## 代码质量改进

### 代码审查和重构
- [ ] **移除重复代码**
  - 优先级: 中等
  - 工作量: 持续 (每周 2-3 小时)

- [ ] **增加单元测试覆盖率**
  - 目标: 80%+
  - 优先级: 高
  - 工作量: 持续 (每周 3-5 小时)

- [ ] **文档完善**
  - 添加 API 文档
  - 添加使用示例
  - 优先级: 中等
  - 工作量: 持续 (每周 2-3 小时)

---

## 性能优化清单

- [ ] 列表虚拟化性能测试
- [ ] 图片压缩参数优化
- [ ] 缓存策略评估
- [ ] 内存占用分析
- [ ] 电池消耗优化
- [ ] 网络流量优化
- [ ] 启动时间优化

---

## 安全性改进

- [ ] HTTPS 证书锁定
- [ ] 密钥管理增强
- [ ] 输入验证加强
- [ ] SQL 注入防护
- [ ] XSS 防护
- [ ] CORS 配置检查
- [ ] 敏感数据加密

---

## 总工作量估计

| 优先级 | 功能数 | 总工作量 |
|--------|--------|---------|
| P0 | 4 | ~20-25 小时 |
| P1 | 10 | ~40-50 小时 |
| P2 | 8 | ~100-150 小时 |
| P3 | 5 | ~60-80 小时 |
| 测试 | 7 | ~30-40 小时 |
| **总计** | **34** | **~250-345 小时** |

---

## 建议实现顺序

### 第一阶段 (1-2 周)
1. TURN 服务器动态配置
2. 消息搜索 API
3. APNs 推送通知
4. 群组对话创建
5. 用户资料编辑

### 第二阶段 (2-3 周)
6. 分享和书签
7. 关注列表
8. 语音消息
9. 深层链接完善
10. FaceID/Touch ID

### 第三阶段 (3-4 周)
11. 故事功能
12. 内容举报
13. 推荐算法
14. 话题系统
15. 应用内浏览器

### 第四阶段 (4+ 周)
16. 实时直播
17. AR 滤镜
18. 支付系统
19. 位置服务
20. 云备份

---

## 记录

- 文档创建日期: 2025-10-26
- 基准代码行数: 37,637
- 基准 Swift 文件数: 442
- 基准测试覆盖率: ~60%

