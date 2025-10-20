# Feature Specification: 首页动态 Feed 显示系统

**Feature Branch**: `002-feed-query-system`
**Created**: 2025-10-18
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - 查看关注者贴文 (Priority: P1)

已登入用户打开应用首页，看到自己关注的所有用户发布的贴文列表，按发布时间从新到旧排序。这是应用的核心价值——个性化内容流。

**Why this priority**: 没有这个功能，用户看不到任何内容，无法进行社交互动。

**Independent Test**:
- 用户关注用户 A 和 B 后，A 发的贴文出现在 Feed 中
- 新贴文自动排在最上方
- 未关注的用户 C 的贴文不出现

**Acceptance Scenarios**:
1. **Given** 用户已关注 3 个用户，**When** 打开 Feed，**Then** 显示这 3 个用户的贴文，按时间新旧排序
2. **Given** Feed 中显示了贴文，**When** 下拉刷新，**Then** 新发布的贴文出现在顶部

---

### User Story 2 - Feed 分页加载 (Priority: P1)

当关注的用户很多且贴文数量超过一屏时，支持分页加载。用户下滑到底部自动加载更多贴文，无需主动操作。

**Why this priority**: 处理大数据集的必要优化，避免一次性加载卡顿。

**Independent Test**:
- 首次加载返回 20 条贴文
- 下滑到底部自动加载下一个 20 条
- 无重复、无遗漏

**Acceptance Scenarios**:
1. **Given** 关注用户有 60 条贴文，**When** 首次加载，**Then** 返回前 20 条 + next_token
2. **Given** 用户下滑到底部，**When** 触发加载下一页，**Then** 返回第 21-40 条，无重复

---

### User Story 3 - 下拉刷新最新内容 (Priority: P2)

用户可以通过下拉刷新操作获取最新发布的贴文，而无需关闭重启应用。

**Why this priority**: 提升用户体验，让内容实时感受到最新。

**Independent Test**:
- 下拉触发刷新请求
- 新贴文出现在顶部

**Acceptance Scenarios**:
1. **Given** 用户正在查看 Feed，**When** 下拉屏幕，**Then** 刷新请求发送至后端
2. **Given** 刷新完成，**When** 新贴文返回，**Then** 新贴文显示在列表顶部

---

### Edge Cases

- 用户还没有关注任何人时，Feed 应显示空状态提示
- 关注者的贴文被删除，该贴文应从 Feed 消失
- 分页查询时，中间页的某个用户删除了贴文，下一页查询是否稳定？预期：稳定，使用 ID 分页
- 用户取消关注某人后，该人的贴文应立即从 Feed 消失
- 网络超时时的重试机制

## Requirements

### Functional Requirements

- **FR-001**: System MUST query posts from all users followed by the authenticated user
- **FR-002**: System MUST return posts in reverse chronological order (newest first)
- **FR-003**: System MUST support pagination with limit parameter (default 20, max 100)
- **FR-004**: System MUST return only published posts (status = PUBLISHED)
- **FR-005**: System MUST exclude posts from deleted users
- **FR-006**: System MUST include post metadata: id, user info, image_url, thumbnail_url, caption, created_at, like_count, comment_count
- **FR-007**: System MUST indicate if authenticated user has liked each post (is_liked flag)
- **FR-008**: System MUST use index on (user_id, created_at) for optimized queries
- **FR-009**: System MUST handle empty follow list gracefully (return empty posts array)
- **FR-010**: System MUST return pagination token for fetching next page

### Key Entities

- **Feed Query**:
  - Input: user_id (authenticated), pagination params
  - Output: Array of Posts with aggregated counts and user engagement flags
  - Performance: Must return within 500ms for 50 posts

## Success Criteria

### Measurable Outcomes

- **SC-001**: Feed loads within 1 second for users following 10-50 people
- **SC-002**: Pagination returns consistent results (no duplicates, no gaps)
- **SC-003**: New posts appear in Feed within 5 seconds of publication
- **SC-004**: System handles 10,000 concurrent Feed queries without degradation
- **SC-005**: 99% of queries return results (no timeout failures)

