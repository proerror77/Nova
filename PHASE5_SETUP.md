# Phase 5 Infrastructure Setup Guide

## Overview

Phase 5 introduces five major features to the Nova platform:
1. **Real-time Notifications** - Event-driven via Kafka, multi-channel delivery
2. **Private Messaging** - PostgreSQL + Elasticsearch for search and delivery
3. **Live Streaming** - RTMP ingest via Nginx, HLS output, quality streaming
4. **Social Graph Optimization** - Neo4j for relationship graph, friend discovery
5. **Recommendation Algorithm v2.0** - ML inference via Ray Serve with PyTorch/TensorFlow

## Architecture Components

### Message Queue & Streaming
- **Kafka** - High-throughput event streaming for real-time features
- **Zookeeper** - Kafka coordination and management

### Storage & Search
- **PostgreSQL** - Primary relational database (Phase 0-4 base)
- **Neo4j** - Graph database for social relationships
- **Elasticsearch** - Full-text search for messages, discovery
- **ClickHouse** - Analytics (Phase 0-4 base)

### Caching & Sessions
- **Redis Cluster** - 3-node cluster for distributed caching and sessions
  - Node 1: `redis-cluster-1:6379`
  - Node 2: `redis-cluster-2:6380`
  - Node 3: `redis-cluster-3:6381`

### Media & Streaming
- **Nginx RTMP** - RTMP protocol server for live stream ingest
  - Ingest port: `1935`
  - HTTP/HLS port: `80`
  - HLS output: `/hls/`
  - DASH output: `/dash/`

### Machine Learning & Inference
- **Ray Serve** - Distributed inference serving
  - Head node: `ray-head:8265`
  - Redis: `ray-head:6379` (internal)

### Monitoring & Observability
- **Prometheus** - Metrics collection (scrape interval: 15s)
- **Grafana** - Visualization dashboards (port `3000`)

## Prerequisites

1. **Docker & Docker Compose**
   ```bash
   docker --version  # 20.10+
   docker-compose --version  # 2.0+
   ```

2. **System Resources**
   - CPU: 4+ cores recommended
   - RAM: 16GB+ recommended
   - Disk: 50GB+ available

3. **Ports Available**
   - `1935` (RTMP)
   - `6379, 6380, 6381` (Redis Cluster)
   - `7474, 7687` (Neo4j)
   - `8123` (ClickHouse)
   - `9092` (Kafka)
   - `9200` (Elasticsearch)
   - `9090` (Prometheus)
   - `3000` (Grafana)
   - `8265` (Ray)

## Quick Start

### 1. Configure Environment

```bash
# Copy .env.example if needed
cp .env.example .env

# Review and update Phase 5 configuration in .env
# Key variables to check:
# - NEO4J_PASSWORD
# - ELASTICSEARCH_SHARDS
# - KAFKA_NOTIFICATIONS_TOPIC, etc.
# - ENABLE_* feature flags
```

### 2. Start Phase 5 Services

```bash
# Simple method - automated script
./scripts/phase5_up.sh

# OR manual method
docker-compose -f docker-compose.yml -f docker-compose.phase5.yml up -d
```

### 3. Verify Services

```bash
# Check all containers are running
docker-compose ps

# Expected services:
# ✓ zookeeper
# ✓ kafka
# ✓ elasticsearch
# ✓ neo4j
# ✓ nginx-rtmp
# ✓ prometheus
# ✓ grafana
# ✓ ray-head
# ✓ redis-cluster-1, redis-cluster-2, redis-cluster-3

# View health status
docker-compose logs -f
```

## Service URLs & Credentials

| Service | URL | User | Password |
|---------|-----|------|----------|
| **Grafana** | http://localhost:3000 | admin | admin |
| **Neo4j** | http://localhost:7474 | neo4j | neo4jpass |
| **Elasticsearch** | http://localhost:9200 | - | - |
| **Prometheus** | http://localhost:9090 | - | - |
| **Ray Serve** | http://localhost:8265 | - | - |
| **Kafka** | localhost:9092 | - | - |

## Database Migrations

Phase 5 introduces 3 new migration files:

### 020_notifications_schema.sql
Creates tables for:
- `notification_preferences` - User notification settings
- `notifications` - Notification records
- `device_push_tokens` - FCM/APNs device tokens
- `notification_delivery_logs` - Audit trail

### 021_messaging_schema.sql
Creates tables for:
- `conversations` - 1-to-1 chat sessions
- `messages` - Message content and metadata
- `message_reactions` - Emoji reactions
- `conversation_participants` - Participant management
- `message_search_index` - Full-text search vectors
- `blocked_users` - User blocking

### 022_live_streaming_schema.sql
Creates tables for:
- `live_streams` - Stream metadata and RTMP/HLS URLs
- `live_stream_viewers` - Viewer session tracking
- `live_chat_messages` - Real-time chat during streams
- `super_chats` - Paid donations/messages
- `stream_hosts` - Co-host management
- `stream_segments` - DVR segments for replay

Run migrations:
```bash
# Via sqlx (if installed)
sqlx migrate run -D postgres://postgres:postgres@localhost:5432/nova_auth

# OR via psql
psql -h localhost -U postgres -d nova_auth -f backend/migrations/020_notifications_schema.sql
psql -h localhost -U postgres -d nova_auth -f backend/migrations/021_messaging_schema.sql
psql -h localhost -U postgres -d nova_auth -f backend/migrations/022_live_streaming_schema.sql
```

## Kafka Topics

Phase 5 uses these Kafka topics for event streaming:

```
nova-notifications   # Real-time notification events
nova-messages        # Direct message events
nova-streaming       # Live streaming events
nova-social-graph    # Social relationship events
nova-recommendations # Recommendation engine events
```

Create topics manually if needed:
```bash
docker-compose exec kafka kafka-topics.sh \
  --create \
  --topic nova-notifications \
  --bootstrap-server kafka:9092 \
  --partitions 10 \
  --replication-factor 1
```

## Redis Cluster Setup

The Redis Cluster automatically initializes on first start:

```bash
# Verify cluster status
docker-compose exec redis-cluster-1 redis-cli cluster info

# Check connected nodes
docker-compose exec redis-cluster-1 redis-cli cluster nodes
```

## Monitoring & Dashboards

### Prometheus
- URL: http://localhost:9090
- Scrapes metrics from all services every 15 seconds
- Metrics paths:
  - User Service: `/metrics`
  - Nginx RTMP: `/metrics`
  - Ray: `/metrics`

### Grafana
- URL: http://localhost:3000
- Comes with Prometheus datasource pre-configured
- Default credentials: `admin` / `admin`
- Create dashboards for:
  - Kafka topic consumer lag
  - Elasticsearch cluster health
  - Neo4j query performance
  - Stream viewer counts
  - Redis cluster status

## Troubleshooting

### Service won't start
```bash
# View logs
docker-compose logs <service-name>

# Check port conflicts
lsof -i :<port>

# Restart service
docker-compose restart <service-name>
```

### Kafka not ready
```bash
# Check broker status
docker-compose exec kafka kafka-broker-api-versions.sh --bootstrap-server kafka:9092

# View broker logs
docker-compose logs kafka
```

### Elasticsearch cluster yellow/red
```bash
# Check cluster health
curl http://localhost:9200/_cluster/health

# View shard allocation
curl http://localhost:9200/_cat/shards
```

### Neo4j connection refused
```bash
# Verify Neo4j is running
curl http://localhost:7474/

# Check credentials
curl -u neo4j:neo4jpass http://localhost:7474/db/data/
```

### Redis cluster initialization fails
```bash
# Reset cluster
docker-compose down
rm -rf data/redis-*
docker-compose up -d

# Or initialize manually
docker-compose exec redis-cluster-1 redis-cli cluster init
```

## Performance Tuning

### Kafka Consumer Throughput
```env
NOTIFICATION_BATCH_SIZE=100           # Messages per batch
NOTIFICATION_BATCH_TIMEOUT_MS=1000    # Batch timeout
```

### Elasticsearch
```env
ELASTICSEARCH_SHARDS=2                # Number of shards
ELASTICSEARCH_REPLICAS=1              # Replicas per shard
```

### Redis Cluster
```env
REDIS_CLUSTER_ENABLED=true
REDIS_CLUSTER_NODES=redis-cluster-1:6379,redis-cluster-2:6380,redis-cluster-3:6381
```

### Ray Inference
- Batch size: Configured per model
- GPU support: Set `RAY_GPU=1` if available
- Worker nodes: Ray Head includes workers by default

## Cleanup & Shutdown

### Stop all services
```bash
# Keep data volumes
docker-compose -f docker-compose.yml -f docker-compose.phase5.yml down

# Remove volumes (WARNING: Data loss!)
docker-compose -f docker-compose.yml -f docker-compose.phase5.yml down -v
```

### Stop individual services
```bash
docker-compose stop <service-name>
```

### Remove Phase 5 services only
```bash
docker-compose -f docker-compose.phase5.yml down
```

## Development Workflow

### Adding a new Kafka topic
1. Update `docker-compose.phase5.yml` in kafka section
2. Update `.env` with new topic name
3. Restart Kafka: `docker-compose restart kafka`
4. Verify topic creation in test harness

### Monitoring a feature
1. Open Prometheus http://localhost:9090
2. Add query for service metrics
3. Create Grafana dashboard from Prometheus

### Testing streams locally
```bash
# Publish test event to Kafka
echo '{"event": "test", "timestamp": "'$(date -u +%s)'"}' | \
  docker-compose exec -T kafka kafka-console-producer.sh \
    --broker-list kafka:9092 \
    --topic nova-notifications

# Consume messages
docker-compose exec kafka kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic nova-notifications \
  --from-beginning
```

## Next Steps

1. **Implement Feature Services**
   - Create Rust service modules in `backend/user-service/src/services/`
   - Implement notification dispatcher
   - Implement message search
   - Implement stream manager
   - Implement social graph queries
   - Implement recommendation inference

2. **Create Integration Tests**
   - Test Kafka consumer workflows
   - Test Neo4j graph operations
   - Test Elasticsearch queries
   - Test stream delivery

3. **Setup Observability**
   - Configure Grafana dashboards
   - Setup alerting rules in Prometheus
   - Implement distributed tracing

4. **Performance Testing**
   - Load test Kafka consumers
   - Stream performance benchmarks
   - Graph query performance tuning

5. **Production Deployment**
   - Use docker-compose.prod.yml (create)
   - Setup Kubernetes manifests
   - Configure TLS/SSL
   - Setup disaster recovery

## References

- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [Neo4j Documentation](https://neo4j.com/docs/)
- [Elasticsearch Documentation](https://www.elastic.co/guide/index.html)
- [Ray Serve Documentation](https://docs.ray.io/en/latest/serve/index.html)
- [Redis Cluster Documentation](https://redis.io/topics/cluster-tutorial)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
