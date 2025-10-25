#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================="
echo "Messaging Service Setup Verification"
echo "=================================="
echo ""

# Check if Docker is running
echo -n "Checking Docker... "
if docker ps > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Docker is not running${NC}"
    exit 1
fi

# Check if docker-compose is available
echo -n "Checking docker-compose... "
if command -v docker-compose > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ docker-compose is not installed${NC}"
    exit 1
fi

# Check if services are running
echo ""
echo "Service Status:"
echo "=============="

check_service() {
    local name=$1
    local port=$2
    echo -n "  $name (port $port): "
    if curl -s http://localhost:$port/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

USER_SERVICE_OK=0
MESSAGING_SERVICE_OK=0

check_service "User Service" 8080 && USER_SERVICE_OK=1
check_service "Messaging Service" 8085 && MESSAGING_SERVICE_OK=1

echo ""

# Check compilation
echo "Compilation Status:"
echo "=================="
echo -n "  User Service: "
if cargo check --manifest-path backend/user-service/Cargo.toml > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo -n "  Messaging Service: "
if cargo check --manifest-path backend/messaging-service/Cargo.toml > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo ""

# Summary
echo "Summary:"
echo "========"
if [ $USER_SERVICE_OK -eq 1 ] && [ $MESSAGING_SERVICE_OK -eq 1 ]; then
    echo -e "${GREEN}✓ All services are running and healthy!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review MESSAGING_ENDPOINTS_TESTING.md for full testing guide"
    echo "  2. Run: docker-compose logs -f messaging-service  (to monitor)"
    echo "  3. Test endpoints using curl or provided test scripts"
    echo ""
    echo "Key Endpoints:"
    echo "  POST   http://localhost:8085/conversations"
    echo "  GET    http://localhost:8085/conversations/:id"
    echo "  POST   http://localhost:8085/conversations/:id/messages"
    echo "  GET    http://localhost:8085/conversations/:id/messages"
    echo "  GET    http://localhost:8085/conversations/:id/messages/search?q=<query>"
    echo "  POST   http://localhost:8085/conversations/:id/read"
    echo "  PUT    http://localhost:8085/messages/:id"
    echo "  DELETE http://localhost:8085/messages/:id"
    echo "  GET    ws://localhost:8085/ws"
    exit 0
else
    echo -e "${YELLOW}⚠ Some services are not running${NC}"
    echo ""
    echo "To start services:"
    echo "  docker-compose up -d"
    echo ""
    echo "To check logs:"
    echo "  docker-compose logs messaging-service"
    echo "  docker-compose logs user-service"
    exit 1
fi
