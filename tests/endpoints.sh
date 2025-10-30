#!/bin/bash

# Nova API 端点测试脚本
# 用于测试新实现的贴文、上传、视频 API

set -e

# 配置
CONTENT_SERVICE_URL=${CONTENT_SERVICE_URL:-"http://localhost:8081"}
MEDIA_SERVICE_URL=${MEDIA_SERVICE_URL:-"http://localhost:8082"}
JWT_TOKEN=${JWT_TOKEN:-"your-jwt-token-here"}
USER_ID=${USER_ID:-"550e8400-e29b-41d4-a716-446655440000"}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========== Nova API 端点测试 ==========${NC}\n"

# 1. 健康检查
echo -e "${YELLOW}[1/7] 健康检查${NC}"
echo -e "  Content Service:"
curl -s "${CONTENT_SERVICE_URL}/api/v1/health" | jq . || echo "❌ Content Service 无响应"
echo -e "  Media Service:"
curl -s "${MEDIA_SERVICE_URL}/api/v1/health" | jq . || echo "❌ Media Service 无响应"
echo ""

# 2. 创建上传会话
echo -e "${YELLOW}[2/7] 启动上传会话${NC}"
UPLOAD_RESPONSE=$(curl -s -X POST "${MEDIA_SERVICE_URL}/api/v1/uploads" \
  -H "Authorization: Bearer ${JWT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "file_name": "photo.jpg",
    "file_size": 2048576
  }')

UPLOAD_ID=$(echo "${UPLOAD_RESPONSE}" | jq -r '.id // empty')
if [ -z "$UPLOAD_ID" ]; then
  echo -e "${RED}❌ 创建上传失败${NC}"
  echo "${UPLOAD_RESPONSE}" | jq . || echo "${UPLOAD_RESPONSE}"
  exit 1
fi
echo -e "${GREEN}✅ 上传会话已创建${NC}"
echo "   Upload ID: ${UPLOAD_ID}"
echo ""

# 3. 获取上传进度
echo -e "${YELLOW}[3/7] 查询上传进度${NC}"
curl -s -X GET "${MEDIA_SERVICE_URL}/api/v1/uploads/${UPLOAD_ID}" \
  -H "Authorization: Bearer ${JWT_TOKEN}" | jq . || echo "❌ 查询失败"
echo ""

# 4. 生成 S3 Presign URL
echo -e "${YELLOW}[4/7] 生成 S3 Presign URL${NC}"
PRESIGN_RESPONSE=$(curl -s -X POST "${MEDIA_SERVICE_URL}/api/v1/uploads/${UPLOAD_ID}/presigned-url" \
  -H "Authorization: Bearer ${JWT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "file_name": "photo.jpg",
    "content_type": "image/jpeg"
  }')

PRESIGN_URL=$(echo "${PRESIGN_RESPONSE}" | jq -r '.presigned_url // empty')
if [ -z "$PRESIGN_URL" ]; then
  echo -e "${RED}❌ 生成 Presign URL 失败${NC}"
  echo "${PRESIGN_RESPONSE}" | jq . || echo "${PRESIGN_RESPONSE}"
else
  echo -e "${GREEN}✅ Presign URL 已生成${NC}"
  echo "   URL: ${PRESIGN_URL}"
  echo "   有效期: $(echo "${PRESIGN_RESPONSE}" | jq '.expiration') 秒"
fi
echo ""

# 5. 创建贴文
echo -e "${YELLOW}[5/7] 创建贴文${NC}"
POST_RESPONSE=$(curl -s -X POST "${CONTENT_SERVICE_URL}/api/v1/posts" \
  -H "Authorization: Bearer ${JWT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "caption": "我的第一条贴文",
    "image_key": "uploads/'${UPLOAD_ID}'/photo.jpg",
    "content_type": "image/jpeg"
  }')

POST_ID=$(echo "${POST_RESPONSE}" | jq -r '.id // empty')
if [ -z "$POST_ID" ]; then
  echo -e "${RED}❌ 创建贴文失败${NC}"
  echo "${POST_RESPONSE}" | jq . || echo "${POST_RESPONSE}"
else
  echo -e "${GREEN}✅ 贴文已创建${NC}"
  echo "   Post ID: ${POST_ID}"
fi
echo ""

# 6. 获取贴文
if [ ! -z "$POST_ID" ]; then
  echo -e "${YELLOW}[6/7] 获取贴文详情${NC}"
  curl -s -X GET "${CONTENT_SERVICE_URL}/api/v1/posts/${POST_ID}" \
    -H "Authorization: Bearer ${JWT_TOKEN}" | jq . || echo "❌ 获取失败"
  echo ""
fi

# 7. 获取用户贴文
echo -e "${YELLOW}[7/7] 获取用户贴文列表${NC}"
curl -s -X GET "${CONTENT_SERVICE_URL}/api/v1/posts/user/${USER_ID}?limit=10&offset=0" \
  -H "Authorization: Bearer ${JWT_TOKEN}" | jq . || echo "❌ 获取失败"
echo ""

echo -e "${BLUE}========== 测试完成 ==========${NC}"
echo -e "\n${YELLOW}提示：${NC}"
echo "- 如果收到 401 Unauthorized，请设置正确的 JWT_TOKEN"
echo "- 如果收到 502 Bad Gateway，请确保服务已启动"
echo "- 使用 'export JWT_TOKEN=<your-token>' 设置 token"
echo "- 使用 'export USER_ID=<your-uuid>' 设置用户 ID"
