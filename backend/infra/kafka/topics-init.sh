#!/bin/bash

set -e

KAFKA_BROKER="${KAFKA_BROKER:-localhost:9092}"
REPLICATION_FACTOR="${REPLICATION_FACTOR:-1}"
ENV="${ENV:-dev}"

echo "=== Initializing Kafka Topics for Nova CDC & Events ==="
echo "Broker: $KAFKA_BROKER"
echo "Replication Factor: $REPLICATION_FACTOR"
echo "Environment: $ENV"
echo ""

create_topic() {
  TOPIC_NAME=$1
  PARTITIONS=$2
  RETENTION_MS=$3
  CLEANUP_POLICY=$4
  COMPRESSION=$5

  echo "Creating topic: $TOPIC_NAME (partitions: $PARTITIONS, retention: ${RETENTION_MS}ms)"

  kafka-topics.sh --bootstrap-server "$KAFKA_BROKER" \
    --create \
    --if-not-exists \
    --topic "$TOPIC_NAME" \
    --partitions "$PARTITIONS" \
    --replication-factor "$REPLICATION_FACTOR" \
    --config retention.ms="$RETENTION_MS" \
    --config cleanup.policy="$CLEANUP_POLICY" \
    --config compression.type="$COMPRESSION" \
    --config min.insync.replicas=1 \
    --config segment.ms=86400000
}

echo "[1/7] Creating CDC Topic: cdc.users"
create_topic "cdc.users" 3 604800000 "compact" "snappy"

echo "[2/7] Creating CDC Topic: cdc.posts"
create_topic "cdc.posts" 10 2592000000 "compact" "snappy"

echo "[3/7] Creating CDC Topic: cdc.follows"
create_topic "cdc.follows" 5 604800000 "compact" "snappy"

echo "[4/7] Creating CDC Topic: cdc.comments"
create_topic "cdc.comments" 5 1209600000 "compact" "snappy"

echo "[5/7] Creating CDC Topic: cdc.likes"
create_topic "cdc.likes" 8 1209600000 "compact" "snappy"

echo "[6/7] Creating Events Topic: events"
if [ "$ENV" = "prod" ]; then
  EVENTS_PARTITIONS=300
else
  EVENTS_PARTITIONS=10
fi

kafka-topics.sh --bootstrap-server "$KAFKA_BROKER" \
  --create \
  --if-not-exists \
  --topic "events" \
  --partitions "$EVENTS_PARTITIONS" \
  --replication-factor "$REPLICATION_FACTOR" \
  --config retention.ms=259200000 \
  --config cleanup.policy="delete" \
  --config compression.type="lz4" \
  --config min.insync.replicas=1 \
  --config segment.ms=3600000

echo "[7/7] Creating Debezium Heartbeat Topic"
create_topic "nova-cdc" 1 86400000 "delete" "snappy"

echo ""
echo "=== Topic Creation Complete ==="
kafka-topics.sh --bootstrap-server "$KAFKA_BROKER" --list | grep -E "^(cdc\.|events|nova-cdc)"

echo ""
echo "=== Topic Configurations ==="
for topic in cdc.users cdc.posts cdc.follows cdc.comments cdc.likes events; do
  echo "--- $topic ---"
  kafka-topics.sh --bootstrap-server "$KAFKA_BROKER" --describe --topic "$topic" | grep -E "PartitionCount|ReplicationFactor"
done

echo ""
echo "Topics initialization completed successfully!"
