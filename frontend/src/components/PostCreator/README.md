# PostCreator Component

完整的 Post 创建组件，支持照片和视频上传。

## 功能特性

- 📷 **照片上传**: 支持 JPEG, PNG, WebP, HEIC 格式
- 🎥 **视频上传**: 支持 MP4, QuickTime, WebM 格式
- 📝 **Caption**: 最多 2200 字符
- 👁️ **实时预览**: 上传前预览所有媒体文件
- 📊 **上传进度**: 实时显示每个文件的上传进度
- ✅ **文件验证**: 自动验证文件类型和大小
- ♿ **可访问性**: 完整的 ARIA 标签和键盘导航

## 使用方法

```tsx
import PostCreator from './components/PostCreator/PostCreator';

function App() {
  return (
    <PostCreator
      onSuccess={(postId) => {
        console.log('Post created:', postId);
      }}
      onError={(error) => {
        console.error('Upload failed:', error);
      }}
    />
  );
}
```

## API 流程

### 照片上传流程

1. **初始化**: `POST /api/v1/posts/upload/init`
   - 请求: `{ filename, content_type, file_size, caption? }`
   - 响应: `{ presigned_url, post_id, upload_token, expires_in }`

2. **上传到 S3**: `PUT presigned_url`
   - 直接上传文件到 S3

3. **完成确认**: `POST /api/v1/posts/upload/complete`
   - 请求: `{ post_id, upload_token, file_hash, file_size }`
   - 响应: `{ post_id, status, message, image_key }`

### 视频上传流程

1. **获取上传 URL**: `POST /api/v1/videos/upload-url`
   - 响应: `{ video_id, presigned_url, expires_in }`

2. **上传到 S3**: `PUT presigned_url`
   - 直接上传文件到 S3

3. **创建元数据**: `POST /api/v1/videos`
   - 请求: `{ title, description?, hashtags?, visibility? }`
   - 响应: `{ video_id, status, created_at, title, hashtags }`

## 文件限制

### 照片
- **类型**: image/jpeg, image/png, image/webp, image/heic
- **最小**: 100 KB
- **最大**: 50 MB

### 视频
- **类型**: video/mp4, video/quicktime, video/webm
- **最大**: 500 MB

## 组件结构

```
PostCreator/
├── PostCreator.tsx       # 主组件
├── MediaPreview.tsx      # 媒体预览组件
├── README.md            # 文档
└── __tests__/
    └── PostCreator.test.tsx
```

## 状态管理

组件使用 React hooks 管理本地状态：
- `caption`: 文本内容
- `photos`: 已选择的照片文件数组
- `videos`: 已选择的视频文件数组
- `uploading`: 上传中标志
- `uploadProgress`: 每个文件的上传进度
- `error`: 错误消息

## 错误处理

所有错误都会：
1. 显示在 UI 中的错误消息区域
2. 调用 `onError` 回调
3. 在控制台输出详细信息

## 测试

```bash
npm test PostCreator
```

测试覆盖：
- ✅ 文件类型验证
- ✅ 文件大小验证
- ✅ 支持的格式检查

## 性能优化

- **Lazy loading**: 预览图按需生成
- **Memory cleanup**: 组件卸载时清理 URL.createObjectURL
- **Progressive upload**: 并行上传多个文件
- **Error recovery**: 失败的文件不影响其他文件上传

## 可访问性

- ✅ ARIA labels on all interactive elements
- ✅ Keyboard navigation support
- ✅ Screen reader friendly
- ✅ Focus management
- ✅ Error announcements via role="alert"

## 浏览器兼容性

- Chrome/Edge: ✅ Full support
- Firefox: ✅ Full support
- Safari: ✅ Full support
- Mobile browsers: ✅ Responsive design

## 未来改进

- [ ] 拖拽上传支持
- [ ] 批量裁剪照片
- [ ] 视频缩略图编辑
- [ ] 上传队列管理
- [ ] 离线上传支持
