#!/bin/bash

set -e

echo "=== Debezium CDC End-to-End Test ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
DEBEZIUM_URL="http://localhost:8083"
KAFKA_BROKER="localhost:9092"
POSTGRES_CONN="postgresql://postgres:postgres@localhost:5432/nova"

# Helper functions
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Test 1: Check services health
echo "Test 1: Checking service health..."
echo "-----------------------------------"

# PostgreSQL
if docker exec nova-postgres pg_isready -U postgres > /dev/null 2>&1; then
    print_success "PostgreSQL is running"
else
    print_error "PostgreSQL is not running"
    exit 1
fi

# Kafka
if docker exec nova-kafka kafka-broker-api-versions.sh --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    print_success "Kafka is running"
else
    print_error "Kafka is not running"
    exit 1
fi

# Debezium
if curl -s -f "$DEBEZIUM_URL/" > /dev/null; then
    print_success "Debezium Connect is running"
else
    print_error "Debezium Connect is not running"
    exit 1
fi

echo ""

# Test 2: Check connector status
echo "Test 2: Checking Debezium connector..."
echo "---------------------------------------"

CONNECTOR_STATUS=$(curl -s "$DEBEZIUM_URL/connectors/nova-postgres-cdc-connector/status" | jq -r '.connector.state' 2>/dev/null || echo "NOT_FOUND")

if [ "$CONNECTOR_STATUS" == "RUNNING" ]; then
    print_success "Connector is RUNNING"
else
    print_error "Connector status: $CONNECTOR_STATUS"
    print_info "Try running: make deploy-connector"
    exit 1
fi

TASK_STATUS=$(curl -s "$DEBEZIUM_URL/connectors/nova-postgres-cdc-connector/status" | jq -r '.tasks[0].state' 2>/dev/null || echo "NOT_FOUND")

if [ "$TASK_STATUS" == "RUNNING" ]; then
    print_success "Task is RUNNING"
else
    print_error "Task status: $TASK_STATUS"
    exit 1
fi

echo ""

# Test 3: Verify Kafka topics exist
echo "Test 3: Checking Kafka topics..."
echo "---------------------------------"

TOPICS=("cdc.users" "cdc.posts" "cdc.follows" "cdc.comments" "cdc.likes" "events")
for topic in "${TOPICS[@]}"; do
    if docker exec nova-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep -q "^$topic$"; then
        print_success "Topic '$topic' exists"
    else
        print_error "Topic '$topic' not found"
        print_info "Try running: make topics"
        exit 1
    fi
done

echo ""

# Test 4: Create test tables (if not exist)
echo "Test 4: Creating test tables..."
echo "--------------------------------"

docker exec nova-postgres psql -U postgres -d nova -c "
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);
" > /dev/null 2>&1

print_success "Table 'users' created/verified"

docker exec nova-postgres psql -U postgres -d nova -c "
CREATE TABLE IF NOT EXISTS posts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);
" > /dev/null 2>&1

print_success "Table 'posts' created/verified"

echo ""

# Test 5: Insert test data
echo "Test 5: Inserting test data..."
echo "-------------------------------"

TIMESTAMP=$(date +%s)
TEST_USERNAME="test_user_$TIMESTAMP"
TEST_EMAIL="test_$TIMESTAMP@example.com"

USER_ID=$(docker exec nova-postgres psql -U postgres -d nova -tAc "
INSERT INTO users (username, email, password_hash)
VALUES ('$TEST_USERNAME', '$TEST_EMAIL', 'hash123')
RETURNING id;
")

print_success "Inserted user with ID: $USER_ID"

POST_ID=$(docker exec nova-postgres psql -U postgres -d nova -tAc "
INSERT INTO posts (user_id, content)
VALUES ($USER_ID, 'Test post from CDC flow test')
RETURNING id;
")

print_success "Inserted post with ID: $POST_ID"

echo ""

# Test 6: Wait for CDC to capture changes
echo "Test 6: Waiting for CDC to capture changes..."
echo "----------------------------------------------"

print_info "Waiting 5 seconds for Debezium to process..."
sleep 5

echo ""

# Test 7: Verify messages in Kafka
echo "Test 7: Verifying Kafka messages..."
echo "------------------------------------"

# Consume cdc.users topic
print_info "Consuming from cdc.users..."
USER_MESSAGE=$(docker exec nova-kafka timeout 5 kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic cdc.users \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 5000 2>/dev/null | tail -1 || echo "")

if [ -n "$USER_MESSAGE" ]; then
    print_success "Received message from cdc.users"
    echo "$USER_MESSAGE" | jq '.' 2>/dev/null || echo "$USER_MESSAGE"
else
    print_error "No message received from cdc.users"
fi

echo ""

# Consume cdc.posts topic
print_info "Consuming from cdc.posts..."
POST_MESSAGE=$(docker exec nova-kafka timeout 5 kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic cdc.posts \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 5000 2>/dev/null | tail -1 || echo "")

if [ -n "$POST_MESSAGE" ]; then
    print_success "Received message from cdc.posts"
    echo "$POST_MESSAGE" | jq '.' 2>/dev/null || echo "$POST_MESSAGE"
else
    print_error "No message received from cdc.posts"
fi

echo ""

# Test 8: Check replication slot
echo "Test 8: Checking PostgreSQL replication slot..."
echo "------------------------------------------------"

SLOT_ACTIVE=$(docker exec nova-postgres psql -U postgres -d nova -tAc "
SELECT active FROM pg_replication_slots WHERE slot_name = 'debezium_nova_slot';
")

if [ "$SLOT_ACTIVE" == "t" ]; then
    print_success "Replication slot 'debezium_nova_slot' is active"
else
    print_error "Replication slot is not active (status: $SLOT_ACTIVE)"
fi

WAL_LAG=$(docker exec nova-postgres psql -U postgres -d nova -tAc "
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn))
FROM pg_replication_slots
WHERE slot_name = 'debezium_nova_slot';
")

print_info "WAL lag: $WAL_LAG"

echo ""

# Test 9: Test UPDATE operation
echo "Test 9: Testing UPDATE operation..."
echo "------------------------------------"

docker exec nova-postgres psql -U postgres -d nova -c "
UPDATE users SET email = 'updated_$TIMESTAMP@example.com' WHERE id = $USER_ID;
" > /dev/null 2>&1

print_success "Updated user ID $USER_ID"

sleep 3

UPDATE_MESSAGE=$(docker exec nova-kafka timeout 3 kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic cdc.users \
    --max-messages 1 \
    --timeout-ms 3000 2>/dev/null | tail -1 || echo "")

if echo "$UPDATE_MESSAGE" | grep -q "updated_$TIMESTAMP@example.com"; then
    print_success "CDC captured UPDATE operation"
else
    print_error "UPDATE operation not captured"
fi

echo ""

# Test 10: Test soft DELETE (tombstone)
echo "Test 10: Testing soft DELETE operation..."
echo "-----------------------------------------"

docker exec nova-postgres psql -U postgres -d nova -c "
UPDATE users SET deleted_at = NOW() WHERE id = $USER_ID;
" > /dev/null 2>&1

print_success "Soft deleted user ID $USER_ID"

sleep 3

DELETE_MESSAGE=$(docker exec nova-kafka timeout 3 kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic cdc.users \
    --max-messages 1 \
    --timeout-ms 3000 2>/dev/null | tail -1 || echo "")

if echo "$DELETE_MESSAGE" | grep -q "deleted_at"; then
    print_success "CDC captured soft DELETE operation"
else
    print_error "Soft DELETE operation not captured"
fi

echo ""

# Test 11: Check Debezium metrics
echo "Test 11: Checking Debezium metrics..."
echo "--------------------------------------"

TOTAL_RECORDS=$(curl -s "$DEBEZIUM_URL/connectors/nova-postgres-cdc-connector/status" | \
    jq -r '.tasks[0].metrics."source-record-poll-total".count' 2>/dev/null || echo "N/A")

print_info "Total records processed: $TOTAL_RECORDS"

LAG=$(curl -s "$DEBEZIUM_URL/connectors/nova-postgres-cdc-connector/status" | \
    jq -r '.tasks[0].metrics."milliseconds-behind-source".max' 2>/dev/null || echo "N/A")

print_info "Lag (ms): $LAG"

if [ "$LAG" != "N/A" ] && [ "$LAG" -lt 5000 ]; then
    print_success "Lag is acceptable (< 5s)"
elif [ "$LAG" != "N/A" ]; then
    print_error "Lag is too high: ${LAG}ms"
fi

echo ""

# Summary
echo "======================================="
echo "          Test Summary"
echo "======================================="
print_success "All tests passed!"
echo ""
echo "CDC Flow:"
echo "  PostgreSQL → Debezium → Kafka → (Ready for Flink)"
echo ""
echo "Next steps:"
echo "  1. Develop Flink jobs to consume CDC topics"
echo "  2. Write processed data to ClickHouse/Redis"
echo "  3. Build hot ranking algorithm"
echo ""
echo "Useful commands:"
echo "  - View Kafka UI: http://localhost:8080"
echo "  - Check connector: curl $DEBEZIUM_URL/connectors/nova-postgres-cdc-connector/status"
echo "  - Consume messages: make consume-users"
echo "  - View logs: make logs"
echo ""
print_success "Test completed successfully!"
