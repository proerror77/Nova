# Nova Feed Infrastructure Setup

This guide covers bootstrapping the data pipeline introduced in Phase 4 (personalised feed).

## 1. Start the stack

```
docker-compose up -d postgres redis zookeeper kafka debezium kafka-ui clickhouse
```

> `user-service` can remain stopped until the schema and connectors are ready.

### Prerequisites

- Docker & Docker Compose
- `cmake` (required to build the bundled `librdkafka` used by the Rust service)
  - macOS: `brew install cmake`
  - Debian/Ubuntu: `apt-get install cmake`
  - Fedora/RHEL: `dnf install cmake`

## 2. Create Kafka topics

```
./scripts/kafka/create-topics.sh
```

Topics:

- `events` – behavioural events produced by the app.
- `nova.public.*` – Debezium CDC topics for OLTP tables.

## 3. Register Debezium connector

```
./scripts/debezium/register-connector.sh
```

Connector definition: `infra/debezium/connectors/postgres-feed.json`

The connector snapshots `users`, `follows`, `posts`, `comments`, `likes` and streams ongoing changes.

## 4. Apply ClickHouse schema

```
./scripts/clickhouse/apply-schema.sh
```

Schema file: `infra/clickhouse/init.sql`

Tables created:

- `events`, `posts_cdc`, `follows_cdc`, `likes_cdc`, `comments_cdc`
- Aggregates: `post_metrics_1h`, `user_author_90d`
- Kafka engines (`src_kafka_*`) and materialised views for ingestion.

## 5. Smoke check

1. Visit Kafka UI at `http://localhost:8080` – ensure topics exist.
2. `clickhouse-client --host localhost --user default --password clickhouse --query "SHOW TABLES FROM nova_feed"`
3. Insert a dummy row into `events` topic (or run backend tests) and confirm ClickHouse receives data.

## 6. Environment variables

`docker-compose.yml` now exposes:

- `KAFKA_BROKERS` – `kafka:9092`
- `DEBEZIUM_CONNECT_URL` – `http://debezium:8083`
- `CLICKHOUSE_URL` – `http://clickhouse:8123`

These variables are available to backend services for runtime integration.
