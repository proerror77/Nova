# Staging API 验收测试指南

## 前置条件

### 1. 获取 JWT Token

从 AWS Secrets Manager 或现有登录流程获取 JWT token：

```bash
# 方法1: 如果你已经有用户凭证,可以通过登录接口获取
curl -X POST "$GW_BASE/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"your@email.com","password":"yourpassword"}' | jq -r '.token'

# 方法2: 从 graphql-gateway pod 的环境变量中查看配置(仅用于理解系统)
kubectl exec -n nova-staging deploy/graphql-gateway -- env | grep JWT
```

### 2. 获取测试用 User ID

```bash
# 通过 identity-service 的 pod 直接查询
kubectl exec -n nova-staging deploy/identity-service -- \
  sh -c 'apk add postgresql-client && psql -h postgres -U novauser -d nova_auth -t -c "SELECT id FROM users LIMIT 1;"'

# 或者使用已有的 user_id (如果你知道的话)
```

### 3. 设置环境变量

```bash
export GW_BASE="http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com"
export TOKEN="<your_jwt_token_here>"
export USER_ID="<your_user_uuid_here>"
```

## 运行完整测试

```bash
cd /Users/proerror/Documents/nova
./scripts/staging-smoke-test.sh
```

## 手动测试指南

如果自动化脚本有问题,可以逐个手动测试:

### 0. Health Check

```bash
curl -s "$GW_BASE/health"
# 预期: ok
```

### 1. Profile Settings

```bash
# 获取用户资料
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/users/$USER_ID" | jq

# 更新 Profile
curl -s -X PUT "$GW_BASE/api/v2/users/$USER_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "Test",
    "last_name": "User",
    "bio": "Staging test user",
    "location": "Taipei"
  }' | jq

# 请求头像上传 URL
curl -s -X POST "$GW_BASE/api/v2/users/avatar" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "file_name": "avatar.jpg",
    "file_size": 123456,
    "content_type": "image/jpeg"
  }' | jq
```

### 2. Channels

```bash
# 列出频道
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/channels?limit=5" | jq

# 获取第一个频道的 ID
export CHANNEL_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/channels?limit=1" | jq -r '.[0].id')

# 频道详情
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/channels/$CHANNEL_ID" | jq

# 查看用户订阅的频道
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/users/$USER_ID/channels" | jq

# 订阅频道
curl -s -X POST "$GW_BASE/api/v2/channels/subscribe" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"channel_ids\":[\"$CHANNEL_ID\"]}" | jq

# 取消订阅
curl -s -X DELETE "$GW_BASE/api/v2/channels/unsubscribe" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"channel_ids\":[\"$CHANNEL_ID\"]}" | jq
```

### 3. Devices

```bash
# 设备列表
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/devices" | jq

# 当前设备
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/devices/current" | jq

# 登出所有设备(谨慎使用!)
curl -s -X POST "$GW_BASE/api/v2/devices/logout" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"all": true}' | jq
```

### 4. Invitations

```bash
# 生成邀请码
curl -s -X POST "$GW_BASE/api/v2/invitations/generate" \
  -H "Authorization: Bearer $TOKEN" | jq
```

### 5. Friends & Search

```bash
# 好友列表
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/friends" | jq

# 搜索用户
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/search/users?q=test&limit=5" | jq

# 推荐联系人
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/friends/recommendations?limit=5" | jq

# 添加好友
export FRIEND_ID="<another_user_uuid>"
curl -s -X POST "$GW_BASE/api/v2/friends/add" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\":\"$FRIEND_ID\"}" | jq
```

### 6. Group Chat

```bash
# 创建群组
export OTHER_USER_ID="<another_user_uuid>"
curl -s -X POST "$GW_BASE/api/v2/chat/groups/create" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Test Group\",
    \"member_ids\": [\"$USER_ID\", \"$OTHER_USER_ID\"],
    \"description\": \"Staging test group\"
  }" | jq

# 获取 conversation ID
export CONV_ID="<conversation_id_from_above>"

# 对话详情
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/chat/conversations/$CONV_ID" | jq

# 消息列表
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/chat/messages?conversation_id=$CONV_ID&limit=20" | jq
```

### 7. Media Upload

```bash
# 上传文件(需要实际文件)
curl -s -X POST "$GW_BASE/api/v2/media/upload" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@/path/to/your/test.jpg" | jq
```

## 预期响应码

- **200**: 成功
- **401**: 未认证 (Missing Authorization header)
- **403**: 无权限
- **404**: 资源不存在
- **500**: 服务器错误

## 常见问题

### Q: 收到 "Missing Authorization header"
A: 检查 TOKEN 环境变量是否正确设置

### Q: 收到 "Invalid token"
A: JWT token 可能已过期,需要重新获取

### Q: 收到 "User not found"
A: 检查 USER_ID 是否正确

### Q: 频道列表为空
A: 确认数据库迁移已成功执行,应该有5个种子频道

## 部署状态

当前 staging 环境部署状态:

| 服务 | 版本 | 状态 |
|------|------|------|
| identity-service | 6d901371 | ✅ Running |
| content-service | 旧版本 | ✅ Running |
| realtime-chat-service | 6d901371 | ✅ Running |
| graphql-gateway | 967bb450 | ✅ Running |

数据库迁移:
- ✅ identity-service: devices, invitations, channel_subscriptions 表
- ✅ content-service: channels 表 + 5个种子频道

## 联系方式

如有问题,请联系 DevOps 团队或查看 `/scripts/deploy-verify.sh` 获取更多调试命令。
