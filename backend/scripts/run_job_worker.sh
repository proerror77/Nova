#!/usr/bin/env bash
# 本地运行 job_worker (开发环境)
#
# 用法:
#   ./scripts/run_job_worker.sh

set -euo pipefail

echo "🚀 Starting Job Worker (Development Mode)"

# 切换到 backend 目录
cd "$(dirname "$0")/.."

# 检查环境变量
if [ -z "${REDIS_URL:-}" ]; then
    echo "⚠️  REDIS_URL not set, using default: redis://127.0.0.1:6379"
    export REDIS_URL="redis://127.0.0.1:6379"
fi

if [ -z "${CLICKHOUSE_URL:-}" ]; then
    echo "⚠️  CLICKHOUSE_URL not set, using default: http://localhost:8123"
    export CLICKHOUSE_URL="http://localhost:8123"
fi

# 设置日志级别
export RUST_LOG="${RUST_LOG:-job_worker=info,user_service=info,info}"

echo ""
echo "📋 Configuration:"
echo "  REDIS_URL: $REDIS_URL"
echo "  CLICKHOUSE_URL: $CLICKHOUSE_URL"
echo "  RUST_LOG: $RUST_LOG"
echo ""

# 运行 worker
exec cargo run --bin job_worker
