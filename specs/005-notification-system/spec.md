# Feature Specification: 通知系统

**Feature Branch**: `005-notification-system`
**Created**: 2025-10-18
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - 收到点赞通知 (Priority: P1)

当用户的贴文被他人点赞时，系统生成一条通知，用户在通知中心看到谁点赞了自己的贴文，并可以快速跳转到该贴文。这让用户感受到社交互动的即时反馈。

**Why this priority**: 社交应用的核心驱动力——实时反馈用户的内容被欣赏。没有这个功能，用户缺少动力继续创作。

**Independent Test**:
- 用户 A 给用户 B 的贴文点赞
- 用户 B 立即在通知中心看到"用户 A 赞了你的贴文"通知
- 通知显示用户 A 的头像和昵称
- 点击通知可以打开该贴文

**Acceptance Scenarios**:
1. **Given** 用户 A 给用户 B 的贴文点赞，**When** 用户 B 打开通知中心，**Then** 显示新的点赞通知，标记为未读
2. **Given** 点赞通知已显示，**When** 用户 B 点击通知，**Then** 跳转到该贴文详情页

---

### User Story 2 - 收到评论通知 (Priority: P1)

当用户的贴文收到新评论时，系统生成通知。用户可以看到谁评论了自己的贴文，评论摘要，并快速跳转查看完整评论。

**Why this priority**: 评论是比点赞更深度的互动，用户更希望看到这类通知。

**Independent Test**:
- 用户 A 评论用户 B 的贴文
- 用户 B 立即收到"用户 A 评论了你的贴文"通知
- 通知显示评论摘要（前 50 字）
- 点击通知打开贴文详情，评论已滚动到可见位置

**Acceptance Scenarios**:
1. **Given** 用户 A 评论用户 B 的贴文，**When** 用户 B 打开通知中心，**Then** 显示新的评论通知
2. **Given** 评论通知显示，**When** 用户 B 点击通知，**Then** 跳转到贴文详情并高亮该评论

---

### User Story 3 - 收到关注通知 (Priority: P1)

当用户被他人关注时，系统生成通知。用户可以从通知中快速查看关注者的档案或返回关注。

**Why this priority**: 关注是社交网络中的重要事件，用户希望及时了解新粉丝。

**Independent Test**:
- 用户 A 关注用户 B
- 用户 B 立即收到"用户 A 关注了你"通知
- 通知显示用户 A 的头像、昵称和简介
- 可以从通知直接关注返回

**Acceptance Scenarios**:
1. **Given** 用户 A 关注用户 B，**When** 用户 B 打开通知中心，**Then** 显示关注通知
2. **Given** 关注通知显示，**When** 点击"关注返回"，**Then** 用户 B 开始关注用户 A

---

### User Story 4 - 标记通知为已读 (Priority: P2)

用户可以标记单个通知为已读，或一键标记所有通知为已读。已读通知会变暗，未读通知高亮显示。

**Why this priority**: 用户需要管理通知状态，避免持续被未读标记干扰。

**Independent Test**:
- 用户有多条未读通知
- 点击单个通知后，该通知标记为已读并变暗
- 存在"全部标记为已读"按钮
- 点击后所有通知变暗

**Acceptance Scenarios**:
1. **Given** 用户有 5 条未读通知，**When** 点击某个通知，**Then** 该通知标记为已读
2. **Given** 有多条未读通知，**When** 点击"全部标记为已读"，**Then** 所有通知状态变为已读

---

### User Story 5 - 通知中心分页加载 (Priority: P2)

通知中心支持分页加载，用户下滑自动加载历史通知，最多查看 30 天内的通知。

**Why this priority**: 用户需要能回顾过去的互动记录，但无需加载全部历史。

**Independent Test**:
- 打开通知中心，首次加载最近 20 条通知
- 下滑到底部，自动加载下 20 条
- 30 天前的通知不加载

**Acceptance Scenarios**:
1. **Given** 用户有 100 条通知，**When** 首次打开，**Then** 显示最近 20 条
2. **Given** 用户滑到底部，**When** 触发加载，**Then** 加载下 20 条历史通知

---

### Edge Cases

- 用户在 5 秒内收到来自同一用户的多条点赞通知（一次性点赞多张贴文），系统应该聚合吗？预期：聚合为"用户 A 赞了你的 3 张贴文"
- 用户删除贴文，相关通知应该如何处理？预期：通知保留，但指向已删除贴文时显示"贴文已删除"
- 用户通知太多（超过 1 万条），分页查询的性能如何保证？预期：使用游标分页，查询时间 < 200ms
- 推送通知重复发送怎么处理？预期：使用幂等性 ID 防止重复

## Requirements

### Functional Requirements

- **FR-001**: System MUST create a Notification record when user's post receives a like
- **FR-002**: System MUST create a Notification record when user's post receives a comment
- **FR-003**: System MUST create a Notification record when user receives a new follow
- **FR-004**: System MUST include notification_type, actor_user_id, target_user_id, resource_id, and message in notification record
- **FR-005**: System MUST support read/unread status for each notification
- **FR-006**: System MUST allow user to mark single notification as read
- **FR-007**: System MUST allow user to mark all notifications as read
- **FR-008**: System MUST return notifications sorted by created_at (newest first)
- **FR-009**: System MUST support paginated notification queries with default 20 per page, max 100
- **FR-010**: System MUST aggregate notifications: multiple actions from same user within 5 minutes should be grouped into one notification
- **FR-011**: System MUST return unread_count in user profile/notification list responses
- **FR-012**: System MUST not create duplicate notifications (idempotent by notification_type, actor_user_id, target_user_id, resource_id within 5 minute window)
- **FR-013**: System MUST delete related notifications when post is deleted
- **FR-014**: System MUST delete related notifications when follow is removed
- **FR-015**: System MUST support push notification delivery to mobile clients with notification preference settings
- **FR-016**: System MUST include notification metadata: actor's avatar_url, username, action description, resource link

### Key Entities

- **Notification**: id, user_id, notification_type (LIKE/COMMENT/FOLLOW), actor_user_id, target_user_id, resource_id (post_id or comment_id), message, is_read, created_at
- **NotificationPreference**: user_id, push_enabled, email_enabled, notification_frequency (REAL_TIME/DAILY/WEEKLY)

## Success Criteria

- **SC-001**: Notifications are created and delivered within 2 seconds of triggering event (like/comment/follow)
- **SC-002**: Notification list loads within 200ms
- **SC-003**: Mark as read operation completes within 100ms
- **SC-004**: Aggregated notifications reduce notification count by 50%+ for active users
- **SC-005**: 99% of notifications are delivered without duplicates
