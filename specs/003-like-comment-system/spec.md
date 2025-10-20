# Feature Specification: 贴文互动系统（点赞与评论）

**Feature Branch**: `003-like-comment-system`
**Created**: 2025-10-18
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - 用户点赞贴文 (Priority: P1)

用户在 Feed 或贴文详情页点击"赞"按钮，系统立即更新UI并记录赞的动作。重复点击取消赞。赞数实时更新。

**Why this priority**: 核心社交互动功能，简单但必需。

**Independent Test**:
- 点赞后，like_count +1，赞按钮变成已赞状态
- 再点一次取消赞，like_count -1，按钮恢复
- 重新刷新页面，赞数保持

**Acceptance Scenarios**:
1. **Given** 用户未赞某贴文，**When** 点击赞，**Then** 赞数 +1，按钮高亮
2. **Given** 用户已赞该贴文，**When** 再点一次，**Then** 赞数 -1，按钮恢复

---

### User Story 2 - 用户评论贴文 (Priority: P1)

用户在贴文详情页输入文字评论并提交，评论立即出现在评论列表中，显示评论者信息和内容。

**Why this priority**: 直接的社交互动和讨论功能。

**Independent Test**:
- 提交评论后立即显示
- 新评论出现在列表中（底部或顶部）
- 显示评论者名字、时间、内容

**Acceptance Scenarios**:
1. **Given** 贴文有 2 条评论，**When** 用户添加第 3 条评论，**Then** 新评论显示在列表中
2. **Given** 评论提交成功，**When** 刷新页面，**Then** 评论仍然存在

---

### User Story 3 - 删除自己的评论 (Priority: P2)

用户可以删除自己发表的评论（或发布者可以删除他人在自己贴文下的评论）。删除后评论消失，评论数减少。

**Why this priority**: 用户内容管理和社区治理。

**Independent Test**:
- 自己的评论显示删除按钮
- 点击删除后评论消失
- comment_count -1

**Acceptance Scenarios**:
1. **Given** 用户看到自己的评论，**When** 点击删除，**Then** 评论立即消失，comment_count 减少

---

### Edge Cases

- 同一用户对同一贴文快速重复点赞，系统是否保证只有一条赞记录？预期：是
- 未登入用户尝试点赞或评论，应返回 401 未授权
- 用户点赞已被删除的贴文，应返回 404
- 评论内容为空或超过 300 字，应返回 400

## Requirements

### Functional Requirements

- **FR-001**: System MUST create a Like record when user clicks like on a post
- **FR-002**: System MUST delete Like record when user clicks like again (toggle behavior)
- **FR-003**: System MUST enforce uniqueness constraint: one user can only like a post once
- **FR-004**: System MUST create a Comment record with content, user_id, post_id
- **FR-005**: System MUST validate comment content: non-empty and max 300 characters
- **FR-006**: System MUST return updated like_count after each like/unlike action
- **FR-007**: System MUST return is_liked flag indicating if authenticated user has liked the post
- **FR-008**: System MUST allow only comment author or post author to delete comments
- **FR-009**: System MUST update comment_count when comments are added/deleted
- **FR-010**: System MUST trigger notification when post author receives a like/comment
- **FR-011**: System MUST return comments sorted by created_at (oldest or newest first, consistently)

### Key Entities

- **Like**: user_id, post_id, created_at (unique constraint on user_id + post_id)
- **Comment**: id, post_id, user_id, content, created_at

## Success Criteria

- **SC-001**: Users can like/unlike a post in under 500ms
- **SC-002**: Comments appear immediately after submission (< 1 second)
- **SC-003**: Like and comment counts are consistent after all operations
- **SC-004**: Duplicate likes are prevented (database enforces uniqueness)
- **SC-005**: 99% of like/comment operations succeed without errors
