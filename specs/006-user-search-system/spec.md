# Feature Specification: 用户搜索系统

**Feature Branch**: `006-user-search-system`
**Created**: 2025-10-18
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - 按昵称搜索用户 (Priority: P1)

用户在搜索框输入关键词，系统返回匹配的用户列表，按相关性排序。搜索支持模糊匹配，无需完全匹配。用户可以快速找到想要关注的人。

**Why this priority**: 用户发现和建立社交网络的关键功能。没有搜索，新用户难以找到关注对象。

**Independent Test**:
- 输入"张"，返回所有昵称包含"张"的用户
- 输入"zhang"，返回昵称包含"zhang"或拼音为 zhang 的用户
- 结果按昵称相似度排序，精确匹配排在最前
- 最多返回 50 个结果

**Acceptance Scenarios**:
1. **Given** 系统中有用户"张三"、"小张"、"张小三"，**When** 输入"张"，**Then** 返回这三个用户，"张三"排在最前
2. **Given** 系统中有用户"zhang wei"，**When** 输入"zhangw"，**Then** 返回"zhang wei"用户

---

### User Story 2 - 从搜索结果关注用户 (Priority: P1)

用户在搜索结果列表中找到想要关注的人，可以直接点击"关注"按钮关注，无需打开用户档案。这加快了社交网络建设的速度。

**Why this priority**: 降低用户操作成本，提升转化率。

**Independent Test**:
- 搜索得到结果列表
- 每个结果项显示头像、昵称、简介
- 点击"关注"按钮后立即变为"取消关注"
- 返回用户档案时，该用户已被关注

**Acceptance Scenarios**:
1. **Given** 搜索结果显示用户列表，**When** 点击某个用户的"关注"按钮，**Then** 按钮立即变为"取消关注"，该用户添加到关注列表

---

### User Story 3 - 查看搜索建议和搜索历史 (Priority: P2)

当用户在搜索框输入时，系统显示搜索建议（热门用户、可能匹配的用户）。用户还可以查看最近搜索历史，快速返回之前搜索的结果。

**Why this priority**: 提升用户体验，减少重复搜索操作。

**Independent Test**:
- 打开搜索框，显示近期搜索历史
- 输入关键词时，显示相关的用户建议
- 点击历史项可以重新执行该搜索
- 可以清除单条或全部搜索历史

**Acceptance Scenarios**:
1. **Given** 用户打开搜索框，**When** 显示空搜索框，**Then** 显示最近 10 条搜索历史
2. **Given** 用户输入"zhang"，**When** 显示搜索框，**Then** 显示包含"zhang"的热门用户建议

---

### User Story 4 - 查看热门用户推荐 (Priority: P2)

在搜索页面，系统展示当前热门的用户（按粉丝数、活跃度排序），帮助用户发现值得关注的内容创作者。

**Why this priority**: 用户发现，但优先级较低（搜索是主流程）。

**Independent Test**:
- 打开搜索页面
- 显示"热门推荐"区域
- 列出当前粉丝最多或最活跃的 10 个用户
- 可以从热门列表直接关注

**Acceptance Scenarios**:
1. **Given** 用户打开搜索页面，**When** 显示热门推荐用户，**Then** 按粉丝数从高到低排序

---

### Edge Cases

- 搜索关键词太短（1 个字），如何处理？预期：仍然搜索，但结果可能较多，返回前 50 个
- 搜索关键词为特殊字符或 SQL 注入尝试，如何处理？预期：过滤特殊字符，作为纯文本搜索
- 用户快速连续搜索，如何优化性能？预期：使用搜索去抖和缓存，避免过多数据库查询
- 用户搜索已删除的用户，应该显示吗？预期：不显示
- 搜索结果超大（百万级），分页如何保证性能？预期：使用游标分页和数据库全文索引，查询时间 < 200ms

## Requirements

### Functional Requirements

- **FR-001**: System MUST support user search by nickname/username with fuzzy matching
- **FR-002**: System MUST support search by Chinese pinyin (e.g., "zhangsan" matches "张三")
- **FR-003**: System MUST return search results sorted by relevance (exact matches first, then partial matches)
- **FR-004**: System MUST limit search results to 50 users per query
- **FR-005**: System MUST exclude deleted users from search results
- **FR-006**: System MUST exclude the authenticated user from search results
- **FR-007**: System MUST implement search debouncing (minimum 300ms between queries)
- **FR-008**: System MUST support pagination for search results with cursor-based pagination
- **FR-009**: System MUST store search history (max 50 most recent searches per user)
- **FR-010**: System MUST allow user to clear individual search history items
- **FR-011**: System MUST allow user to clear all search history
- **FR-012**: System MUST display search suggestions when search box is focused (recent searches + trending users)
- **FR-013**: System MUST return is_following flag indicating if authenticated user follows each search result user
- **FR-014**: System MUST implement full-text search on user nicknames and bios for better relevance
- **FR-015**: System MUST use indexed queries to ensure search completes within 200ms for typical queries
- **FR-016**: System MUST cache popular/trending users and refresh cache every hour

### Key Entities

- **SearchHistory**: user_id, search_query, created_at (indexed on user_id, created_at)
- **User** (enhanced): nickname (searchable index), bio (searchable index)

## Success Criteria

- **SC-001**: Search results return within 200ms for typical queries
- **SC-002**: Fuzzy matching correctly handles Chinese pinyin conversion
- **SC-003**: Search results are accurate with 90%+ relevance (top results contain user's search intent)
- **SC-004**: Pagination returns consistent, non-duplicated results
- **SC-005**: 99% of search queries complete successfully without timeout
