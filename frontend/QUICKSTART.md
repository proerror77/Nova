# Quick Start - Post Creator

## 启动前端

```bash
cd /Users/proerror/Documents/nova/frontend

# 安装依赖（如果还没安装）
npm install

# 开发模式
npm run dev

# 浏览器访问: http://localhost:5173
```

## 使用 Post Creator

1. **打开应用**: 浏览器访问 `http://localhost:5173`

2. **默认打开 "Create Post" 标签页**

3. **添加照片**:
   - 点击 "📷 Add Photos" 按钮
   - 选择一个或多个照片文件
   - 支持格式: JPEG, PNG, WebP, HEIC
   - 大小限制: 100KB - 50MB

4. **添加视频**:
   - 点击 "🎥 Add Videos" 按钮
   - 选择一个或多个视频文件
   - 支持格式: MP4, QuickTime, WebM
   - 大小限制: 最大 500MB

5. **编写 Caption**:
   - 在文本框输入描述（可选）
   - 最多 2200 字符

6. **预览**:
   - 查看所有已选择的文件
   - 点击 "×" 按钮删除不需要的文件

7. **上传**:
   - 点击 "Create Post" 按钮
   - 查看实时上传进度
   - 成功后会弹出提示

## 注意事项

### 后端服务需要运行

确保后端服务在运行：
```bash
# user-service 应该运行在 http://localhost:8080
# 检查是否运行:
curl http://localhost:8080/health
```

### 认证 Token

上传功能需要认证。确保 localStorage 中有 `auth_token`:

```javascript
// 在浏览器控制台设置测试 token
localStorage.setItem('auth_token', 'YOUR_JWT_TOKEN');
```

### 环境变量

检查 `.env.development`:
```bash
VITE_API_BASE=http://localhost:8080
VITE_WS_BASE=ws://localhost:8085
```

## 故障排除

### 上传失败

1. **检查网络**: 确保后端服务运行
   ```bash
   curl http://localhost:8080/api/v1/posts/upload/init
   ```

2. **检查认证**: 查看浏览器控制台是否有 401 错误
   - 确保 `auth_token` 存在且有效

3. **检查文件大小**:
   - 照片: 100KB - 50MB
   - 视频: 最大 500MB

4. **检查文件类型**:
   - 照片: JPEG, PNG, WebP, HEIC
   - 视频: MP4, QuickTime, WebM

### 构建错误

```bash
# 清理并重新安装
rm -rf node_modules package-lock.json
npm install

# 重新构建
npm run build
```

### CORS 错误

确保后端配置允许前端域名：
```rust
// backend/user-service/src/main.rs
.wrap(
    Cors::default()
        .allowed_origin("http://localhost:5173")
        .allowed_methods(vec!["GET", "POST", "PUT", "DELETE"])
        .allowed_headers(vec![header::AUTHORIZATION, header::CONTENT_TYPE])
)
```

## 测试上传流程

### 快速测试（使用 curl）

1. 初始化上传:
```bash
curl -X POST http://localhost:8080/api/v1/posts/upload/init \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "test.jpg",
    "content_type": "image/jpeg",
    "file_size": 1048576,
    "caption": "Test post"
  }'
```

2. 使用返回的 presigned_url 上传文件:
```bash
curl -X PUT "PRESIGNED_URL" \
  -H "Content-Type: image/jpeg" \
  --data-binary "@/path/to/test.jpg"
```

3. 完成上传:
```bash
curl -X POST http://localhost:8080/api/v1/posts/upload/complete \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "post_id": "POST_ID_FROM_STEP_1",
    "upload_token": "UPLOAD_TOKEN_FROM_STEP_1",
    "file_hash": "FILE_SHA256_HASH",
    "file_size": 1048576
  }'
```

## 开发技巧

### 热重载

Vite 支持热重载，修改代码后自动刷新浏览器。

### 调试

在浏览器开发者工具中：
1. **Network 标签**: 查看 API 请求
2. **Console 标签**: 查看日志和错误
3. **Application > Local Storage**: 查看 auth_token

### 组件开发

```tsx
// 单独使用 PostCreator
import PostCreator from './components/PostCreator/PostCreator';

<PostCreator
  onSuccess={(postId) => {
    console.log('Created post:', postId);
  }}
  onError={(error) => {
    console.error('Error:', error);
  }}
/>
```

## 下一步

- 查看 `IMPLEMENTATION_SUMMARY.md` 了解技术细节
- 查看 `src/components/PostCreator/README.md` 了解组件文档
- 运行测试: `npm test`
