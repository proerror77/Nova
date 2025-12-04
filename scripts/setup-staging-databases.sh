#!/bin/bash
# Nova Staging Database Setup Script
# This script initializes and configures all databases for the staging environment
#
# Prerequisites:
#   - kubectl configured with access to nova-staging namespace
#   - K8s services running: postgres, neo4j, kafka, elasticsearch, redis

set -euo pipefail

NAMESPACE="${NAMESPACE:-nova-staging}"
KAFKA_POD=""
NEO4J_POD="neo4j-0"
POSTGRES_POD="postgres-0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Find Kafka pod dynamically
find_kafka_pod() {
    KAFKA_POD=$(kubectl get pods -n "$NAMESPACE" -l app=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "$KAFKA_POD" ]]; then
        log_error "Kafka pod not found in $NAMESPACE"
        return 1
    fi
    log_info "Found Kafka pod: $KAFKA_POD"
}

# ============================================================================
# 1. Apply K8s Configurations
# ============================================================================
apply_k8s_configs() {
    log_info "Applying K8s configurations..."

    kubectl apply -f k8s/microservices/graph-service-configmap.yaml -n "$NAMESPACE"
    kubectl apply -f k8s/microservices/graph-service-secret.yaml -n "$NAMESPACE"
    kubectl apply -f k8s/microservices/search-service-configmap.yaml -n "$NAMESPACE"

    log_success "K8s configurations applied"
}

# ============================================================================
# 2. Initialize PostgreSQL Graph Schema
# ============================================================================
init_postgres_graph() {
    log_info "Initializing PostgreSQL graph schema..."

    # Check if tables exist
    local table_count
    table_count=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- \
        psql -U nova -d nova_graph -t -c \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')

    if [[ "$table_count" -gt 0 ]]; then
        log_warn "PostgreSQL graph schema already exists ($table_count tables)"
        return 0
    fi

    # Apply migrations
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U nova -d nova_graph -c "
        -- Users table
        CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY,
            username VARCHAR(50) NOT NULL UNIQUE,
            created_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

        -- Follows table
        CREATE TABLE IF NOT EXISTS follows (
            follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            PRIMARY KEY (follower_id, following_id),
            CONSTRAINT no_self_follow CHECK (follower_id <> following_id)
        );
        CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id);
        CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);
        CREATE INDEX IF NOT EXISTS idx_follows_created_at ON follows(created_at);

        -- Mutes table
        CREATE TABLE IF NOT EXISTS mutes (
            muter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            muted_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            PRIMARY KEY (muter_id, muted_id),
            CONSTRAINT no_self_mute CHECK (muter_id <> muted_id)
        );

        -- Blocks table
        CREATE TABLE IF NOT EXISTS blocks (
            blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            PRIMARY KEY (blocker_id, blocked_id),
            CONSTRAINT no_self_block CHECK (blocker_id <> blocked_id)
        );
    "

    log_success "PostgreSQL graph schema initialized"
}

# ============================================================================
# 3. Create Kafka Topics
# ============================================================================
create_kafka_topics() {
    log_info "Creating Kafka topics..."

    find_kafka_pod || return 1

    local topics=(
        "message_persisted"
        "message_deleted"
        "post_created"
        "post_deleted"
        "user_created"
        "user_updated"
    )

    for topic in "${topics[@]}"; do
        log_info "Creating topic: $topic"
        kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -c kafka -- \
            /usr/bin/kafka-topics --bootstrap-server localhost:9092 \
            --create --if-not-exists \
            --topic "$topic" \
            --partitions 3 \
            --replication-factor 1 2>/dev/null || true
    done

    log_success "Kafka topics created"

    # List all topics
    log_info "Current Kafka topics:"
    kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -c kafka -- \
        /usr/bin/kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | \
        grep -E "message_|post_|user_" || true
}

# ============================================================================
# 4. Initialize Neo4j with Test Data
# ============================================================================
init_neo4j() {
    log_info "Checking Neo4j..."

    local node_count
    node_count=$(kubectl exec -n "$NAMESPACE" "$NEO4J_POD" -- \
        cypher-shell -u neo4j -p nova "MATCH (n) RETURN count(n) as count;" 2>/dev/null | \
        tail -1 | tr -d ' ')

    if [[ "$node_count" -gt 0 ]]; then
        log_warn "Neo4j already has $node_count nodes"
        return 0
    fi

    log_info "Initializing Neo4j with test data..."

    # Create User nodes
    kubectl exec -n "$NAMESPACE" "$NEO4J_POD" -- cypher-shell -u neo4j -p nova "
        CREATE (u1:User {id: '00000000-0000-0000-0000-000000000001', username: 'alice', created_at: 1704106800})
        CREATE (u2:User {id: '00000000-0000-0000-0000-000000000002', username: 'bob', created_at: 1704106801})
        CREATE (u3:User {id: '00000000-0000-0000-0000-000000000003', username: 'charlie', created_at: 1704106802})
        CREATE (u4:User {id: '00000000-0000-0000-0000-000000000004', username: 'diana', created_at: 1704106803})
        CREATE (u5:User {id: '00000000-0000-0000-0000-000000000005', username: 'evan', created_at: 1704106804})
        CREATE (u6:User {id: '00000000-0000-0000-0000-000000000006', username: 'fiona', created_at: 1704106805})
        CREATE (u7:User {id: '00000000-0000-0000-0000-000000000007', username: 'george', created_at: 1704106806})
        CREATE (u8:User {id: '00000000-0000-0000-0000-000000000008', username: 'hannah', created_at: 1704106807})
        CREATE (u9:User {id: '00000000-0000-0000-0000-000000000009', username: 'ian', created_at: 1704106808})
        CREATE (u10:User {id: '00000000-0000-0000-0000-000000000010', username: 'julia', created_at: 1704106809})
        RETURN count(*) as users_created;
    "

    log_success "Neo4j initialized with test data"
}

# ============================================================================
# 5. Sync PostgreSQL to Neo4j (Backfill)
# ============================================================================
sync_pg_to_neo4j() {
    log_info "Syncing PostgreSQL follows to Neo4j..."

    # Get follows from PostgreSQL and create in Neo4j
    local follows
    follows=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- \
        psql -U nova -d nova_graph -t -A -F',' -c \
        "SELECT u1.username, u2.username FROM follows f
         JOIN users u1 ON f.follower_id = u1.id
         JOIN users u2 ON f.following_id = u2.id;" 2>/dev/null)

    if [[ -z "$follows" ]]; then
        log_warn "No follows to sync"
        return 0
    fi

    echo "$follows" | while IFS=',' read -r follower following; do
        [[ -z "$follower" || -z "$following" ]] && continue
        kubectl exec -n "$NAMESPACE" "$NEO4J_POD" -- cypher-shell -u neo4j -p nova "
            MATCH (a:User {username: '$follower'}), (b:User {username: '$following'})
            MERGE (a)-[:FOLLOWS {since: datetime()}]->(b);
        " 2>/dev/null || true
    done

    log_success "PostgreSQL to Neo4j sync completed"
}

# ============================================================================
# 6. Restart Services
# ============================================================================
restart_services() {
    log_info "Restarting services to pick up new configs..."

    kubectl rollout restart deployment/graph-service -n "$NAMESPACE" 2>/dev/null || true
    kubectl rollout restart deployment/search-service -n "$NAMESPACE" 2>/dev/null || true

    log_info "Waiting for rollout..."
    kubectl rollout status deployment/graph-service -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
    kubectl rollout status deployment/search-service -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

    log_success "Services restarted"
}

# ============================================================================
# 7. Verify Setup
# ============================================================================
verify_setup() {
    log_info "Verifying setup..."

    echo ""
    echo "=== PostgreSQL (nova_graph) ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- \
        psql -U nova -d nova_graph -c "SELECT 'users' as table_name, COUNT(*) FROM users UNION ALL SELECT 'follows', COUNT(*) FROM follows;" 2>/dev/null

    echo ""
    echo "=== Neo4j ==="
    kubectl exec -n "$NAMESPACE" "$NEO4J_POD" -- cypher-shell -u neo4j -p nova "
        MATCH (u:User) RETURN 'User nodes' as type, count(u) as count
        UNION ALL
        MATCH ()-[r:FOLLOWS]->() RETURN 'FOLLOWS relations', count(r);
    " 2>/dev/null

    echo ""
    echo "=== Kafka Topics ==="
    find_kafka_pod && kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -c kafka -- \
        /usr/bin/kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | \
        grep -E "message_|post_|user_" || true

    echo ""
    log_success "Setup verification complete"
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         Nova Staging Database Setup Script                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    case "${1:-all}" in
        config)
            apply_k8s_configs
            ;;
        postgres)
            init_postgres_graph
            ;;
        kafka)
            create_kafka_topics
            ;;
        neo4j)
            init_neo4j
            ;;
        sync)
            sync_pg_to_neo4j
            ;;
        restart)
            restart_services
            ;;
        verify)
            verify_setup
            ;;
        all)
            apply_k8s_configs
            init_postgres_graph
            create_kafka_topics
            init_neo4j
            sync_pg_to_neo4j
            restart_services
            verify_setup
            ;;
        *)
            echo "Usage: $0 {config|postgres|kafka|neo4j|sync|restart|verify|all}"
            echo ""
            echo "Commands:"
            echo "  config   - Apply K8s configurations"
            echo "  postgres - Initialize PostgreSQL graph schema"
            echo "  kafka    - Create Kafka topics"
            echo "  neo4j    - Initialize Neo4j with test data"
            echo "  sync     - Sync PostgreSQL data to Neo4j"
            echo "  restart  - Restart graph and search services"
            echo "  verify   - Verify setup"
            echo "  all      - Run all steps (default)"
            exit 1
            ;;
    esac
}

main "$@"
