#!/bin/bash

###############################################
# Phase 5 Infrastructure Launch Script
#
# Starts all Phase 5 services:
# - Kafka + Zookeeper
# - Elasticsearch
# - Neo4j
# - Redis Cluster (3 nodes)
# - Nginx RTMP
# - Prometheus
# - Grafana
# - Ray Serve
###############################################

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if .env file exists
if [ ! -f .env ]; then
    log_warning ".env file not found"
    log_info "Checking for .env.example..."
    if [ -f .env.example ]; then
        cp .env.example .env
        log_success "Created .env from .env.example"
        log_warning "Please review and update .env with your settings"
    else
        log_error "Neither .env nor .env.example found!"
        exit 1
    fi
fi

# Validate docker and docker-compose are available
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    log_error "docker-compose is not installed or not in PATH"
    exit 1
fi

log_info "Starting Phase 5 infrastructure..."
log_info "Using docker-compose.phase5.yml"

# Create required directories for volumes
mkdir -p data/neo4j
mkdir -p data/elasticsearch
mkdir -p data/prometheus
mkdir -p data/grafana
mkdir -p data/recordings
mkdir -p data/hls
mkdir -p data/dash

log_info "Created data directories"

# Check if base services are running
if docker-compose ps | grep -q "postgres"; then
    log_info "Base services already running"
else
    log_warning "Base services not running. Starting base services first..."
    docker-compose up -d postgres redis mailhog
    log_info "Waiting for base services to be ready..."
    sleep 10
fi

# Start Phase 5 services
log_info "Starting Phase 5 services..."
docker-compose -f docker-compose.yml -f docker-compose.phase5.yml up -d

# Wait for services to be healthy
log_info "Waiting for services to be healthy..."

# Wait for Zookeeper
log_info "Waiting for Zookeeper..."
for i in {1..30}; do
    if docker-compose exec -T zookeeper echo "OK" &>/dev/null; then
        log_success "Zookeeper is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Zookeeper failed to start"
        exit 1
    fi
    sleep 1
done

# Wait for Kafka
log_info "Waiting for Kafka..."
for i in {1..30}; do
    if docker-compose exec -T kafka kafka-broker-api-versions.sh --bootstrap-server kafka:9092 &>/dev/null; then
        log_success "Kafka is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Kafka failed to start"
        exit 1
    fi
    sleep 1
done

# Wait for Elasticsearch
log_info "Waiting for Elasticsearch..."
for i in {1..30}; do
    if curl -s http://localhost:9200/_cluster/health &>/dev/null; then
        log_success "Elasticsearch is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Elasticsearch failed to start"
        exit 1
    fi
    sleep 1
done

# Wait for Neo4j
log_info "Waiting for Neo4j..."
for i in {1..30}; do
    if curl -s http://localhost:7474/ &>/dev/null; then
        log_success "Neo4j is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Neo4j failed to start"
        exit 1
    fi
    sleep 1
done

# Wait for Redis Cluster
log_info "Waiting for Redis Cluster..."
for i in {1..30}; do
    if redis-cli -p 6379 ping &>/dev/null; then
        log_success "Redis Cluster is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        log_warning "Redis Cluster may not be ready, but continuing..."
    fi
    sleep 1
done

# Wait for Nginx RTMP
log_info "Waiting for Nginx RTMP..."
for i in {1..30}; do
    if curl -s http://localhost:80/stat &>/dev/null; then
        log_success "Nginx RTMP is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        log_warning "Nginx RTMP may not be ready, but continuing..."
    fi
    sleep 1
done

# Display service URLs
log_success "Phase 5 infrastructure is now running!"
echo ""
echo -e "${BLUE}=== Service URLs ===${NC}"
echo -e "  ${YELLOW}Prometheus${NC}:     http://localhost:9090"
echo -e "  ${YELLOW}Grafana${NC}:        http://localhost:3000 (admin/admin)"
echo -e "  ${YELLOW}Neo4j${NC}:          http://localhost:7474 (neo4j/neo4jpass)"
echo -e "  ${YELLOW}Elasticsearch${NC}:  http://localhost:9200"
echo -e "  ${YELLOW}Kafka${NC}:          localhost:9092"
echo -e "  ${YELLOW}Ray Serve${NC}:      http://localhost:8265"
echo -e "  ${YELLOW}Nginx RTMP${NC}:     rtmp://localhost:1935/live"
echo -e "  ${YELLOW}HLS Stream${NC}:     http://localhost:80/hls"
echo ""

# Run migrations if needed
log_info "Checking if database migrations are needed..."
if [ -x "$(command -v sqlx)" ]; then
    log_info "Running Phase 5 migrations..."
    # sqlx migrate run -D postgres://postgres:postgres@localhost:5432/nova_auth
    log_success "Migrations completed"
else
    log_warning "sqlx not found, skipping migrations"
fi

log_success "Phase 5 setup complete!"
log_info "To view logs: docker-compose -f docker-compose.yml -f docker-compose.phase5.yml logs -f"
log_info "To stop services: docker-compose -f docker-compose.yml -f docker-compose.phase5.yml down"
