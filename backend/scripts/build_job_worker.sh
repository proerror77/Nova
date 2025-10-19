#!/usr/bin/env bash
# 构建 job_worker Docker 镜像
#
# 用法:
#   ./scripts/build_job_worker.sh [TAG]
#
# 示例:
#   ./scripts/build_job_worker.sh v1.0.0
#   ./scripts/build_job_worker.sh latest

set -euo pipefail

# 获取版本标签 (默认为 latest)
TAG="${1:-latest}"
IMAGE_NAME="nova/job-worker"

echo "🔨 Building job_worker image: ${IMAGE_NAME}:${TAG}"

# 切换到 backend 目录
cd "$(dirname "$0")/.."

# 构建镜像
docker build \
    -f Dockerfile.job_worker \
    -t "${IMAGE_NAME}:${TAG}" \
    --build-arg BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
    .

echo "✅ Image built successfully: ${IMAGE_NAME}:${TAG}"
echo ""
echo "📋 Next steps:"
echo "  1. Test locally:  docker run --rm ${IMAGE_NAME}:${TAG}"
echo "  2. Push to registry: docker push ${IMAGE_NAME}:${TAG}"
echo "  3. Deploy to K8s: kubectl apply -f infra/k8s/job-worker-deployment.yaml"
