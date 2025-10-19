#!/bin/bash
# OAuth Integration Tests Runner
# Automatically sets up test database and runs OAuth tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== OAuth Integration Tests Runner ===${NC}\n"

# Configuration
DB_CONTAINER_NAME="nova-test-db"
DB_PORT=5432
DB_USER="postgres"
DB_PASSWORD="postgres"
DB_NAME="nova_test"
DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}"

# Step 1: Check if Docker is running
echo -e "${YELLOW}[1/5]${NC} Checking Docker..."
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    echo "Please start Docker Desktop and try again"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker is running\n"

# Step 2: Start PostgreSQL container if not running
echo -e "${YELLOW}[2/5]${NC} Setting up test database..."
if docker ps -a --format '{{.Names}}' | grep -q "^${DB_CONTAINER_NAME}$"; then
    echo "Container ${DB_CONTAINER_NAME} exists"
    if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER_NAME}$"; then
        echo "Starting existing container..."
        docker start ${DB_CONTAINER_NAME}
    else
        echo "Container already running"
    fi
else
    echo "Creating new test database container..."
    docker run --name ${DB_CONTAINER_NAME} \
        -e POSTGRES_PASSWORD=${DB_PASSWORD} \
        -e POSTGRES_DB=${DB_NAME} \
        -p ${DB_PORT}:5432 \
        -d postgres:14
fi

# Wait for database to be ready
echo "Waiting for database to be ready..."
for i in {1..30}; do
    if docker exec ${DB_CONTAINER_NAME} pg_isready -U ${DB_USER} > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Database is ready\n"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}Error: Database failed to start${NC}"
        exit 1
    fi
    sleep 1
done

# Step 3: Run migrations
echo -e "${YELLOW}[3/5]${NC} Running database migrations..."
export DATABASE_URL="${DATABASE_URL}"

if command -v sqlx &> /dev/null; then
    cd "$(dirname "$0")/.."
    sqlx migrate run --database-url "${DATABASE_URL}"
    echo -e "${GREEN}✓${NC} Migrations completed\n"
else
    echo -e "${YELLOW}Warning: sqlx-cli not found, skipping migrations${NC}"
    echo "Install with: cargo install sqlx-cli --no-default-features --features postgres"
    echo -e "\n"
fi

# Step 4: Set environment variables
echo -e "${YELLOW}[4/5]${NC} Setting environment variables..."
export DATABASE_URL="${DATABASE_URL}"
export RUST_LOG=debug
export RUST_BACKTRACE=1
echo -e "${GREEN}✓${NC} Environment configured\n"

# Step 5: Run tests
echo -e "${YELLOW}[5/5]${NC} Running OAuth integration tests..."
echo -e "Command: ${GREEN}cargo test --test oauth_test${NC}\n"

cd "$(dirname "$0")/.."
cargo test --test oauth_test -- --test-threads=1 --nocapture

# Test result
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}=== All OAuth tests passed! ===${NC}\n"
else
    echo -e "\n${RED}=== Some tests failed ===${NC}\n"
    exit 1
fi

# Optional: Show test coverage
echo -e "${YELLOW}Tip:${NC} Generate coverage report with:"
echo -e "  ${GREEN}cargo tarpaulin --test oauth_test --out Html${NC}\n"
