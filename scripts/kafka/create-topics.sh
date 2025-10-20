#!/usr/bin/env bash
set -euo pipefail

KAFKA_BROKER=${KAFKA_BROKER:-localhost:29092}
REPLICATION=${REPLICATION:-1}
PARTITIONS=${PARTITIONS:-3}

topics=(
  "events"
  "nova.public.posts"
  "nova.public.follows"
  "nova.public.likes"
  "nova.public.comments"
)

for topic in "${topics[@]}"; do
  echo "Creating topic ${topic} (if not exists)"
  docker exec -i nova-kafka kafka-topics \
    --bootstrap-server "${KAFKA_BROKER}" \
    --create \
    --if-not-exists \
    --topic "${topic}" \
    --partitions "${PARTITIONS}" \
    --replication-factor "${REPLICATION}"
done

echo "Topic list after creation:"
docker exec -i nova-kafka kafka-topics \
  --bootstrap-server "${KAFKA_BROKER}" \
  --list
