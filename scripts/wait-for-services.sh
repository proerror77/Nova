#!/usr/bin/env bash
# wait-for-services.sh
# 等待所有测试服务健康检查通过

set -e

echo "⏳ Waiting for test services to be ready..."

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Services to check
services=(
    "nova_test_postgres:5433:PostgreSQL"
    "nova_test_zookeeper:2181:Zookeeper"
    "nova_test_kafka:9093:Kafka"
    "nova_test_clickhouse:8124:ClickHouse"
    "nova_test_redis:6380:Redis"
)

# Maximum wait time (seconds)
MAX_WAIT=60
ELAPSED=0

check_service() {
    local container=$1
    local port=$2
    local name=$3

    if docker exec "$container" echo "ok" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name is running"
        return 0
    else
        echo -e "${YELLOW}⏳${NC} $name is starting..."
        return 1
    fi
}

check_postgres() {
    docker exec nova_test_postgres pg_isready -U test -d nova_test > /dev/null 2>&1
}

check_kafka() {
    docker exec nova_test_kafka kafka-broker-api-versions --bootstrap-server localhost:9093 > /dev/null 2>&1
}

check_clickhouse() {
    curl -s http://localhost:8124/ping > /dev/null 2>&1
}

check_redis() {
    docker exec nova_test_redis redis-cli ping > /dev/null 2>&1
}

echo ""
echo "Checking service health..."
echo "────────────────────────────"

while [ $ELAPSED -lt $MAX_WAIT ]; do
    all_ready=true

    # Check PostgreSQL
    if check_postgres; then
        echo -e "${GREEN}✓${NC} PostgreSQL is ready"
    else
        echo -e "${YELLOW}⏳${NC} PostgreSQL is not ready yet"
        all_ready=false
    fi

    # Check Kafka (which requires Zookeeper)
    if check_kafka; then
        echo -e "${GREEN}✓${NC} Kafka is ready"
    else
        echo -e "${YELLOW}⏳${NC} Kafka is not ready yet"
        all_ready=false
    fi

    # Check ClickHouse
    if check_clickhouse; then
        echo -e "${GREEN}✓${NC} ClickHouse is ready"
    else
        echo -e "${YELLOW}⏳${NC} ClickHouse is not ready yet"
        all_ready=false
    fi

    # Check Redis
    if check_redis; then
        echo -e "${GREEN}✓${NC} Redis is ready"
    else
        echo -e "${YELLOW}⏳${NC} Redis is not ready yet"
        all_ready=false
    fi

    if [ "$all_ready" = true ]; then
        echo ""
        echo -e "${GREEN}✓ All services are ready!${NC}"
        echo ""
        exit 0
    fi

    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo "────────────────────────────"
done

echo ""
echo -e "${RED}✗ Timeout: Services did not become ready in ${MAX_WAIT}s${NC}"
echo ""
echo "Check logs with:"
echo "  docker-compose -f docker-compose.test.yml logs"
exit 1
