# Feature Specification: 用户关注系统

**Feature Branch**: `004-follow-system`
**Created**: 2025-10-18
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - 用户关注其他用户 (Priority: P1)

已登入用户在浏览其他用户的档案时，可以点击"关注"按钮来关注该用户。关注后，该用户的贴文将出现在自己的 Feed 中。这是建立社交网络的基础功能。

**Why this priority**: 没有关注功能，用户无法个性化自己的内容流，整个社交网络无法形成。

**Independent Test**:
- 用户 A 在用户 B 档案上点击关注
- 系统立即显示"取消关注"按钮
- 用户 B 的关注者数 +1
- 用户 A 的关注数 +1
- 刷新页面，关注关系保持

**Acceptance Scenarios**:
1. **Given** 用户未关注用户 B，**When** 点击关注，**Then** 按钮变为"取消关注"，关注数 +1
2. **Given** 关注关系已建立，**When** 用户打开 Feed，**Then** 用户 B 的贴文出现在 Feed 中

---

### User Story 2 - 用户取消关注 (Priority: P1)

用户可以随时点击"取消关注"按钮来移除对另一用户的关注。被取消关注用户的贴文立即从 Feed 消失，关注数减少。

**Why this priority**: 用户需要灵活管理自己的关注列表，这是基本的社交自主权。

**Independent Test**:
- 用户 A 在已关注的用户 B 档案上点击取消关注
- 系统立即显示"关注"按钮
- 用户 B 的关注者数 -1
- 用户 A 的关注数 -1
- 用户 B 的新贴文不出现在 Feed 中

**Acceptance Scenarios**:
1. **Given** 用户已关注用户 B，**When** 点击取消关注，**Then** 按钮变为"关注"，关注数 -1
2. **Given** 取消关注完成，**When** 用户打开 Feed，**Then** 用户 B 的贴文消失

---

### User Story 3 - 查看粉丝和关注列表 (Priority: P1)

用户可以在自己或他人的档案页中查看完整的粉丝列表和关注列表。列表分页加载，每个用户项显示头像、昵称、简介，以及快速关注/取消关注按钮。

**Why this priority**: 这是档案功能的核心组成部分，允许用户探索社交网络。

**Independent Test**:
- 打开用户档案，点击"粉丝"标签
- 显示分页粉丝列表（默认 20 人/页）
- 每个粉丝项显示头像、昵称、是否已关注
- 可以在列表中直接关注/取消关注
- 下滑加载下一页

**Acceptance Scenarios**:
1. **Given** 用户 A 有 50 个粉丝，**When** 打开粉丝列表，**Then** 显示前 20 个粉丝 + 分页按钮
2. **Given** 粉丝列表显示，**When** 点击某个粉丝的关注按钮，**Then** 按钮立即变为"取消关注"

---

### User Story 4 - 查看某用户是否已关注我 (Priority: P2)

在浏览他人档案时，用户能够快速判断该用户是否已关注自己。系统在其档案页显示清晰指示（如"正在关注我"标签）。

**Why this priority**: 提升用户体验，让关注关系更透明。

**Independent Test**:
- 用户 B 关注用户 A
- 用户 A 打开用户 B 的档案
- 档案上显示"正在关注我"标签
- 用户 A 未关注用户 B 时，标签不显示

**Acceptance Scenarios**:
1. **Given** 用户 B 关注用户 A，**When** 用户 A 打开用户 B 档案，**Then** 显示"正在关注我"标签

---

### Edge Cases

- 用户快速连续点击关注/取消关注按钮，系统如何处理？预期：防止竞态条件，最终状态与最后一次点击一致
- 用户 A 关注用户 B，随后用户 B 删除账号，用户 A 的关注列表应如何显示？预期：显示为已删除用户，关注数保持不变
- 关注列表中用户过多（超过 10 万），分页查询性能如何保证？预期：使用游标分页和适当索引，返回时间 < 500ms
- 两个用户互相关注是否允许？预期：允许

## Requirements

### Functional Requirements

- **FR-001**: System MUST create a Follow record when user clicks follow on another user's profile
- **FR-002**: System MUST delete Follow record when user clicks unfollow (toggle behavior)
- **FR-003**: System MUST enforce uniqueness constraint: one user can only follow another user once
- **FR-004**: System MUST prevent user from following themselves
- **FR-005**: System MUST update follower_count and following_count on user profiles atomically
- **FR-006**: System MUST return follower_count and following_count in user profile responses
- **FR-007**: System MUST support paginated follower list queries with limit parameter (default 20, max 100)
- **FR-008**: System MUST support paginated following list queries with limit parameter (default 20, max 100)
- **FR-009**: System MUST include is_following flag indicating if authenticated user follows each user in lists
- **FR-010**: System MUST include is_followed_by flag indicating if each user in lists follows the authenticated user
- **FR-011**: System MUST return followers/following lists sorted by follow_date (newest first)
- **FR-012**: System MUST trigger notification when user receives a new follower
- **FR-013**: System MUST handle unfollow cascading: when user deletes account, all follow records should be removed
- **FR-014**: System MUST use index on (user_id, follow_date) for optimized follower/following queries
- **FR-015**: System MUST prevent unauthenticated users from following (return 401 error)

### Key Entities

- **Follow**: user_id, following_user_id, created_at (unique constraint on user_id + following_user_id, no self-follow)
- **User** (enhanced):
  - follower_count (Int, denormalized for performance)
  - following_count (Int, denormalized for performance)

## Success Criteria

- **SC-001**: Users can follow/unfollow another user in under 200ms
- **SC-002**: Follower/following counts are consistent after all operations
- **SC-003**: Follower/following lists load within 500ms for users with 100k+ followers
- **SC-004**: Follower/following counts appear in user profile API responses immediately after follow/unfollow
- **SC-005**: 99% of follow/unfollow operations succeed without errors
