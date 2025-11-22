# Nova Staging API 完整验收指南

## ✅ 部署状态

当前 nova-staging 环境已成功部署以下服务：

| 服务 | 镜像版本 | 状态 | 副本数 |
|------|----------|------|--------|
| identity-service | 967bb450 | ✅ Running | 3/3 |
| content-service | 旧版本 | ✅ Running | 2/2 |
| realtime-chat-service | 6d901371 | ✅ Running | 1/1 |
| graphql-gateway | 967bb450 | ✅ Running | 2/2 |

### 数据库迁移

- ✅ **identity-service**: `004_add_devices_invites_and_channels.sql`
  - `devices` 表
  - `invitations` 表
  - `channel_subscriptions` 表

- ✅ **content-service**: `20251122_add_channels.sql`
  - `channels` 表
  - 5个种子频道已插入

### Gateway 地址

```
http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com
```

## 🚀 快速开始

### 一键设置测试环境

```bash
cd ~/Documents/nova

# 1. 运行自动化设置脚本
./scripts/setup-test-env.sh

# 此脚本将自动:
# - 从 AWS Secrets Manager 获取数据库凭证
# - 从数据库查询测试用户
# - 获取 JWT 签名密钥
# - 生成有效的 JWT token (24小时有效期)
# - 导出所有环境变量到 /tmp/nova-test-env.sh
```

### 运行完整测试

```bash
# 2. Source 环境变量
source /tmp/nova-test-env.sh

# 3. 运行完整的 smoke test
./scripts/staging-smoke-test.sh
```

## 📋 测试用户信息

setup 脚本会自动获取最新的测试用户，示例：

```
User ID:  31ba2bad-cd31-43d0-b5b2-2f5ea2f4e31a
Username: pf_test_1763737046
Email:    pf_test_1763737046@test.local
```

## 🧪 手动测试示例

如果你想手动测试单个端点：

```bash
# 确保先 source 环境变量
source /tmp/nova-test-env.sh

# 1. Health Check
curl -s "$GW_BASE/health"
# 预期: ok

# 2. Channels List
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/channels?limit=5" | jq

# 3. Get User Profile
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/users/$USER_ID" | jq

# 4. Current Device
curl -s -H "Authorization: Bearer $TOKEN" \
  "$GW_BASE/api/v2/devices/current" | jq

# 5. Generate Invitation Code
curl -s -X POST "$GW_BASE/api/v2/invitations/generate" \
  -H "Authorization: Bearer $TOKEN" | jq

# 6. Subscribe to a Channel
curl -s -X POST "$GW_BASE/api/v2/channels/subscribe" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"channel_ids":["11111111-1111-1111-1111-111111111111"]}' | jq
```

## 📚 完整 API 测试文档

详细的手动测试指南请参考:

```bash
cat scripts/README-STAGING-TEST.md
```

包含以下功能模块的完整测试用例：

1. **Profile Settings** - 用户资料 + 头像上传
2. **Channels** - 频道订阅管理
3. **Devices** - 设备列表 + 登出
4. **Invitations** - 邀请码生成
5. **Friends & Search** - 好友管理 + 用户搜索
6. **Group Chat** - 群组聊天
7. **Media Upload** - 通用媒体上传
8. **Alice** - AI 助手 (占位)

## 🔧 脚本说明

### `/scripts/setup-test-env.sh`
自动化环境设置脚本，获取所有必需的凭证和用户信息。

**依赖**:
- AWS CLI (已配置 ap-northeast-1 region)
- kubectl (已配置 nova-staging context)
- jq
- Python 3 + PyJWT

### `/scripts/generate-test-jwt.py`
JWT token 生成工具。

**用法**:
```bash
python3 ./scripts/generate-test-jwt.py <user_id> /tmp/jwt_private_key.pem
```

### `/scripts/staging-smoke-test.sh`
完整的 API smoke test 套件，自动测试所有端点。

**环境变量**:
- `TOKEN` - JWT token (必需)
- `USER_ID` - 测试用户 UUID (必需)
- `GW_BASE` - Gateway URL (可选，默认 ALB 地址)

## ⚠️ 注意事项

1. **JWT Token 有效期**: 默认 24 小时，过期后需重新运行 `setup-test-env.sh`

2. **content-service 旧版本**: 新版本因 social-service gRPC 依赖问题暂时保持旧版本

3. **Token 格式**: 所有 API 请求需要携带 `Authorization: Bearer <token>` header

4. **预期响应码**:
   - `200` - 成功
   - `401` - 未认证或 token 无效
   - `403` - 无权限
   - `404` - 资源不存在

## 🐛 常见问题

### Q: "Invalid or expired token"
**A**: 重新运行 `./scripts/setup-test-env.sh` 生成新 token

### Q: "Missing Authorization header"
**A**: 检查是否正确设置了 `TOKEN` 环境变量

### Q: 频道列表为空
**A**: 检查数据库迁移是否成功，应该有 5 个种子频道：
```sql
SELECT id, name FROM channels;
```

### Q: User not found
**A**: 确认 `USER_ID` 是数据库中实际存在的用户 UUID

## 📞 支持

如有问题，请检查：
1. `/scripts/deploy-verify.sh` - 原始部署验证脚本
2. `kubectl logs -n nova-staging deploy/graphql-gateway` - Gateway 日志
3. `kubectl get pods -n nova-staging` - 服务运行状态

---

**最后更新**: 2025-11-22
**环境**: nova-staging (ap-northeast-1)
**版本**: v2 (REST API + GraphQL)
