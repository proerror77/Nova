# Feature Specification: 图片贴文发布与存储系统

**Feature Branch**: `001-post-publish-system`
**Created**: 2025-10-18
**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 用户发布图片贴文 (Priority: P1)

已登入用户可以从设备库中选择一张图片并添加描述，一键发布贴文。贴文立即出现在其个人档案中，并在其粉丝的 Feed 中显示。这是核心的内容创建功能。

**Why this priority**: 这是应用的核心价值主张——用户生成内容。没有这个功能，其他所有社交功能都无意义。

**Independent Test**:
- 用户登入后能找到"发布"按钮
- 能选择本地图片、添加描述、发布
- 发布后立即在个人档案中看到该贴文
- 其他已关注此用户的人能在 Feed 中看到该贴文

**Acceptance Scenarios**:

1. **Given** 用户已登入且无发布过贴文, **When** 用户点击发布按钮并选择图片和描述, **Then** 系统生成一个新贴文，立即显示在用户档案中，状态为 PUBLISHED
2. **Given** 贴文已发布，**When** 其他用户打开 Feed，**Then** 能看到该贴文，位置按发布时间排序
3. **Given** 用户正在上传图片，**When** 用户切换到其他 App，**Then** 上传在后台继续，不中断

---

### User Story 2 - 图片自动转码与缩略图生成 (Priority: P1)

系统自动处理上传的图片，生成适合在 Feed 中显示的缩略图和适合详情页的中图版本。用户无需等待处理完成，发布动作即时完成。

**Why this priority**: 影响用户体验，缩略图快速加载是 Feed 流畅的前提条件。

**Independent Test**:
- 上传 JPEG/PNG 图片后，系统生成三种版本
- Feed 使用缩略图，加载迅速
- 详情页使用原图高清显示

**Acceptance Scenarios**:

1. **Given** 用户上传一张 HEIC 格式照片，**When** 后端收到上传完成通知，**Then** 系统自动转换为 JPEG 并生成缩略图
2. **Given** 缩略图正在生成，**When** 用户打开 Feed，**Then** Feed 中该贴文显示占位符或正在加载状态，待生成完成后显示缩略图

---

### User Story 3 - 支持后台上传与断网重试 (Priority: P1)

iOS 用户在上传过程中切换应用或关闭屏幕时，上传任务继续进行。若网络中断，系统自动重试。用户无需留在应用中等待上传完成。

**Why this priority**: 提升用户体验，避免因网络波动导致的发布失败。

**Independent Test**:
- 上传过程中锁定设备屏幕，上传继续
- 暂断网络后恢复，上传自动继续而非重新开始

**Acceptance Scenarios**:

1. **Given** 图片上传进行中，**When** 用户按下 Home 键离开应用，**Then** 上传在后台继续，返回应用后显示进度
2. **Given** 上传过程中网络中断 3 秒，**When** 网络恢复，**Then** 上传继续而非从 0% 重新开始
3. **Given** 上传失败超过 3 次，**When** 用户返回应用，**Then** 系统提示失败并提供重试或放弃选项

---

### User Story 4 - 预签名 URL 直传到 S3 (Priority: P2)

客户端向后端请求上传权限，获得一个有效期 5 分钟的预签名 URL，直接将文件上传至 AWS S3，无需经过后端服务器中转。这减少后端负载并加快上传速度。

**Why this priority**: 性能和成本优化。虽然用户可能感受不到直传和中转的区别，但这是系统架构的关键决策。

**Independent Test**:
- 调用预签名 URL 接口返回有效的 S3 URL
- 使用该 URL 成功上传文件至 S3
- URL 过期后无法再使用

**Acceptance Scenarios**:

1. **Given** 用户请求上传权限，**When** 后端生成预签名 URL，**Then** URL 包含有效的 S3 bucket 地址和签名，有效期 5 分钟
2. **Given** URL 已签发，**When** 客户端使用该 URL 上传文件，**Then** 文件成功保存至 S3，无需通过后端

---

### User Story 5 - 验证图片格式与大小限制 (Priority: P2)

系统仅接受 JPEG 和 PNG 格式的图片，单个文件大小不超过 10MB。超出限制时给用户友好的错误提示。

**Why this priority**: 数据质量和成本控制，防止滥用存储空间。

**Independent Test**:
- 上传 BMP 格式被拒，提示"不支持该格式"
- 上传 15MB 文件被拒，提示"文件过大，最大 10MB"
- 上传符合要求的 JPEG/PNG 成功

**Acceptance Scenarios**:

1. **Given** 用户选择一个 5MB 的 JPEG 文件，**When** 点击上传，**Then** 上传成功
2. **Given** 用户选择一个 15MB 的图片，**When** 点击上传，**Then** 系统拒绝并显示"文件大小超出限制（最大 10MB）"

---

### User Story 6 - 描述文字验证与存储 (Priority: P2)

用户在贴文中可添加最多 300 字符的描述。超出限制时给出提示。支持 Unicode 字符和 Emoji。

**Why this priority**: 确保数据完整性和用户体验一致。

**Independent Test**:
- 输入 200 字字符能保存
- 输入 350 字提示"超出字符限制"
- 包含 Emoji 的描述能正确保存和显示

**Acceptance Scenarios**:

1. **Given** 用户输入 "Hello 😊" 作为描述，**When** 提交贴文，**Then** 描述正确保存并在 Feed 中显示为 "Hello 😊"
2. **Given** 用户输入超过 300 字的文本，**When** 尝试提交，**Then** 系统显示"描述不能超过 300 字符，当前已输入 XXX 字"

---

### Edge Cases

- 用户上传一张已损坏的 JPEG 文件，系统能否正确处理？预期：给出"图片文件损坏"的错误提示
- 贴文创建 API 返回成功，但 S3 上传实际失败，如何保证一致性？预期：后端定期清理孤立的贴文记录
- 用户在 5 分钟内未使用预签名 URL 导致过期，需要重新请求吗？预期：是，客户端提示"上传链接已过期，请重新开始"
- 同一用户快速发布 10 张贴文，系统如何处理并发？预期：所有贴文都应成功发布，无数据冲突
- 用户在描述中输入 SQL 注入尝试（如 `'; DROP TABLE posts; --`），系统如何处理？预期：作为纯文本保存，无害

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow authenticated users to request a pre-signed S3 upload URL with a 5-minute expiration time
- **FR-002**: System MUST accept image uploads directly to S3 using the pre-signed URL (no backend relay)
- **FR-003**: System MUST create a Post record in database after receiving upload completion notification from client
- **FR-004**: System MUST validate uploaded images are JPEG or PNG format (reject other formats with clear error message)
- **FR-005**: System MUST reject images exceeding 10MB with appropriate error message
- **FR-006**: System MUST support post captions up to 300 characters, including Unicode and Emoji characters
- **FR-007**: System MUST generate thumbnail (e.g., 300px width) and medium image (e.g., 600px width) versions after upload completion
- **FR-008**: System MUST automatically convert non-standard formats (e.g., HEIC) to JPEG for compatibility
- **FR-009**: System MUST store original, medium, and thumbnail URLs in the Post record for CDN distribution
- **FR-010**: System MUST expose uploaded images through CDN with proper caching headers
- **FR-011**: iOS client MUST support background image upload using URLSession background transfer tasks
- **FR-012**: System MUST set Post status to PROCESSING while image processing is in progress, then to PUBLISHED upon completion
- **FR-013**: System MUST handle upload retry on network failure (max 3 attempts with exponential backoff)
- **FR-014**: System MUST prevent unauthenticated users from accessing upload endpoints (return 401 error)
- **FR-015**: System MUST validate that Post data includes user_id, image_url, optional caption, and created_at timestamp

### Key Entities

- **Post**:
  - Attributes: `id` (UUID), `user_id` (UUID, foreign key), `image_url` (String, CDN URL), `thumbnail_url` (String, CDN URL), `caption` (Text, optional, max 300 chars), `created_at` (DateTime), `status` (Enum: PUBLISHED/PROCESSING/FAILED)
  - Relationships: Belongs to User; Has many Likes; Has many Comments
  - Indexing: Composite index on (user_id, created_at) for Feed queries; separate index on created_at for timeline queries

- **User** (existing):
  - Relationship: Has many Posts

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete a post publish workflow (select image → add caption → submit) in under 30 seconds on standard network conditions (4G)
- **SC-002**: Thumbnail images load in under 1 second on first view in Feed (via CDN)
- **SC-003**: Image upload completes successfully 99% of the time without user intervention (accounting for network resilience)
- **SC-004**: Post appears in user's profile immediately after creation (status = PUBLISHED or PROCESSING with visual indicator)
- **SC-005**: Posted images appear in followers' Feed within 5 seconds of publication
- **SC-006**: System processes and generates thumbnails for 100 uploaded images concurrently without degradation
- **SC-007**: 95% of image processing completes within 2 minutes of upload completion
- **SC-008**: Zero data loss or orphaned posts created due to concurrent upload operations

### Qualitative Measures

- **SC-009**: Users perceive upload as "instantaneous" (visual feedback shows completion < 2 seconds)
- **SC-010**: Clear, actionable error messages guide users on upload failures (format, size, network issues)
- **SC-011**: No user support tickets related to "image not appearing after upload" after first 1 week of launch

## Assumptions

- AWS S3 and CloudFront CDN are available and configured before feature implementation
- Image processing (thumbnail generation) can run as background async job without impacting API performance
- iOS target is iOS 14+ with URLSession background transfer support
- "Instant" publication means Post record creation succeeds before image processing begins (asynchronous processing)
- No real-time synchronization requirement; eventual consistency (within 5 seconds) is acceptable
- User has granted camera/photo library permissions before initiating upload (not a feature requirement here)

## Out of Scope

- Cropping or editing images before upload
- Applying filters or effects to images
- Uploading multiple images in a single post (single image per post)
- Video uploads
- GIF support
- Image compression quality tuning
- Watermarking or image signing
- Real-time upload progress updates via WebSocket

## API Contract Preview

```
POST /posts/upload-url
  Request: { content_type?: string }
  Response: { upload_url: string, file_key: string }

POST /posts
  Request: { file_key: string, caption?: string }
  Response: { id, user_id, image_url, thumbnail_url, caption, created_at, status }

GET /posts/{id}
  Response: { id, user_id, image_url, thumbnail_url, caption, created_at, status, like_count, comment_count }
```

