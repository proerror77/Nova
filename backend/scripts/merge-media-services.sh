#!/bin/bash

# Media Services Consolidation Script
# Merges media, video, streaming, cdn services into media-service and delivery-service
# Author: Linus Torvalds (AI)
# Date: 2025-11-11

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Media Services Consolidation"
echo "========================================="
echo ""
echo "This script will merge:"
echo "  - media-service + video-service + streaming-service → media-service"
echo "  - cdn-service → delivery-service"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if services exist
check_service_exists() {
    local service=$1
    if [ -d "$BACKEND_DIR/$service" ]; then
        return 0
    else
        return 1
    fi
}

# Backup existing services
backup_services() {
    log_info "Creating backups..."
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKEND_DIR/backups/media_consolidation_$timestamp"

    mkdir -p "$backup_dir"

    for service in media-service video-service streaming-service cdn-service; do
        if check_service_exists "$service"; then
            log_info "Backing up $service..."
            cp -r "$BACKEND_DIR/$service" "$backup_dir/"
        else
            log_warn "$service not found, skipping backup"
        fi
    done

    log_info "Backups created at: $backup_dir"
}

# Create consolidated media-service structure
create_media_service() {
    log_info "Creating consolidated media-service..."

    local media_dir="$BACKEND_DIR/media-service-new"
    mkdir -p "$media_dir"

    # Create Cargo.toml for consolidated service
    cat > "$media_dir/Cargo.toml" << 'EOF'
[package]
name = "media-service"
version = "0.2.0"
edition = "2021"

[dependencies]
# Core dependencies
tokio = { version = "1.40", features = ["full"] }
tonic = "0.12"
prost = "0.13"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

# Database
sqlx = { version = "0.8", features = ["runtime-tokio-native-tls", "postgres", "uuid", "chrono"] }
uuid = { version = "1.10", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }

# Media processing
image = "0.25"
ffmpeg-next = "7.0"
aws-sdk-s3 = "1.39"
mime = "0.3"

# Observability
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
opentelemetry = "0.24"
prometheus = { version = "0.13", features = ["process"] }

# Error handling
thiserror = "1.0"
anyhow = "1.0"

# Configuration
config = "0.14"
dotenv = "0.15"

[build-dependencies]
tonic-build = "0.12"

[[bin]]
name = "media-service"
path = "src/main.rs"
EOF

    # Create source directory structure
    mkdir -p "$media_dir/src/handlers"
    mkdir -p "$media_dir/src/processors"
    mkdir -p "$media_dir/src/storage"
    mkdir -p "$media_dir/src/models"
    mkdir -p "$media_dir/proto"

    # Create main.rs with consolidated logic
    cat > "$media_dir/src/main.rs" << 'EOF'
//! Consolidated Media Service
//! Handles all media operations: images, videos, audio
//! Owns: media_files, media_metadata, thumbnails, transcode_jobs

use anyhow::Result;
use tonic::transport::Server;
use tracing::{info, error};

mod handlers;
mod processors;
mod storage;
mod models;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    info!("Starting consolidated Media Service v0.2.0");

    // Load configuration
    dotenv::dotenv().ok();

    // Initialize database pool
    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set");

    let pool = sqlx::PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to database");

    info!("Database connected successfully");

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    info!("Database migrations completed");

    // Initialize S3 client
    let config = aws_config::load_from_env().await;
    let s3_client = aws_sdk_s3::Client::new(&config);

    // Initialize gRPC server
    let addr = "0.0.0.0:50054".parse()?;

    info!("Media Service listening on {}", addr);

    // TODO: Add actual service implementation
    // This is a placeholder for the consolidated service

    Ok(())
}
EOF

    log_info "Created consolidated media-service structure"
}

# Create delivery-service from cdn-service
create_delivery_service() {
    log_info "Creating delivery-service (enhanced CDN)..."

    local delivery_dir="$BACKEND_DIR/delivery-service"
    mkdir -p "$delivery_dir"

    # Create Cargo.toml for delivery service
    cat > "$delivery_dir/Cargo.toml" << 'EOF'
[package]
name = "delivery-service"
version = "0.1.0"
edition = "2021"

[dependencies]
# Core dependencies
tokio = { version = "1.40", features = ["full"] }
tonic = "0.12"
prost = "0.13"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

# CDN and streaming
hyper = { version = "1.4", features = ["full"] }
tower = "0.4"
bytes = "1.7"
futures = "0.3"

# Caching
redis = { version = "0.25", features = ["tokio-comp", "connection-manager"] }
moka = { version = "0.12", features = ["future"] }

# Database
sqlx = { version = "0.8", features = ["runtime-tokio-native-tls", "postgres", "uuid", "chrono"] }
uuid = { version = "1.10", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }

# Observability
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
prometheus = { version = "0.13", features = ["process"] }

# Error handling
thiserror = "1.0"
anyhow = "1.0"

# Configuration
config = "0.14"
dotenv = "0.15"

[build-dependencies]
tonic-build = "0.12"

[[bin]]
name = "delivery-service"
path = "src/main.rs"
EOF

    # Create source directory structure
    mkdir -p "$delivery_dir/src/cdn"
    mkdir -p "$delivery_dir/src/streaming"
    mkdir -p "$delivery_dir/src/cache"
    mkdir -p "$delivery_dir/src/models"
    mkdir -p "$delivery_dir/proto"

    # Create main.rs
    cat > "$delivery_dir/src/main.rs" << 'EOF'
//! Delivery Service
//! Handles CDN distribution, streaming, and caching
//! Owns: cdn_nodes, cache_rules, streaming_sessions, delivery_metrics

use anyhow::Result;
use tonic::transport::Server;
use tracing::{info, error};

mod cdn;
mod streaming;
mod cache;
mod models;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    info!("Starting Delivery Service v0.1.0");

    // Load configuration
    dotenv::dotenv().ok();

    // Initialize database pool
    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set");

    let pool = sqlx::PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to database");

    info!("Database connected successfully");

    // Initialize Redis for caching
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1/".to_string());

    let redis_client = redis::Client::open(redis_url)?;
    let redis_connection = redis_client
        .get_connection_manager()
        .await?;

    info!("Redis cache connected");

    // Initialize gRPC server
    let addr = "0.0.0.0:50055".parse()?;

    info!("Delivery Service listening on {}", addr);

    // TODO: Add actual service implementation

    Ok(())
}
EOF

    log_info "Created delivery-service structure"
}

# Create migration scripts
create_migrations() {
    log_info "Creating database migration scripts..."

    # Media service migrations
    mkdir -p "$BACKEND_DIR/media-service-new/migrations"

    cat > "$BACKEND_DIR/media-service-new/migrations/001_consolidate_media_tables.sql" << 'EOF'
-- Consolidate media tables from multiple services
-- This migration merges tables from media, video, and streaming services

BEGIN;

-- Create consolidated media_files table if not exists
CREATE TABLE IF NOT EXISTS media_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_type VARCHAR(50) NOT NULL, -- 'image', 'video', 'audio'
    file_name VARCHAR(255) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    storage_path TEXT NOT NULL,
    storage_bucket VARCHAR(100) NOT NULL,
    checksum VARCHAR(64),
    duration_seconds INTEGER, -- For video/audio
    width INTEGER, -- For images/video
    height INTEGER, -- For images/video
    bitrate INTEGER, -- For video/audio
    codec VARCHAR(50), -- For video/audio
    uploaded_by UUID NOT NULL,
    status VARCHAR(50) DEFAULT 'processing',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'media-service' NOT NULL,
    CONSTRAINT owned_by_media CHECK (service_owner = 'media-service')
);

-- Create metadata table
CREATE TABLE IF NOT EXISTS media_metadata (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    media_file_id UUID NOT NULL REFERENCES media_files(id) ON DELETE CASCADE,
    key VARCHAR(100) NOT NULL,
    value TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'media-service' NOT NULL,
    UNIQUE(media_file_id, key),
    CONSTRAINT owned_by_media_meta CHECK (service_owner = 'media-service')
);

-- Create thumbnails table
CREATE TABLE IF NOT EXISTS thumbnails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    media_file_id UUID NOT NULL REFERENCES media_files(id) ON DELETE CASCADE,
    size VARCHAR(20) NOT NULL, -- 'small', 'medium', 'large'
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    storage_path TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'media-service' NOT NULL,
    UNIQUE(media_file_id, size),
    CONSTRAINT owned_by_media_thumb CHECK (service_owner = 'media-service')
);

-- Create transcode jobs table
CREATE TABLE IF NOT EXISTS transcode_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    media_file_id UUID NOT NULL REFERENCES media_files(id) ON DELETE CASCADE,
    input_format VARCHAR(50) NOT NULL,
    output_format VARCHAR(50) NOT NULL,
    quality VARCHAR(20) NOT NULL, -- '360p', '720p', '1080p', '4k'
    status VARCHAR(50) DEFAULT 'pending',
    progress INTEGER DEFAULT 0,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'media-service' NOT NULL,
    CONSTRAINT owned_by_media_transcode CHECK (service_owner = 'media-service')
);

-- Create indexes
CREATE INDEX idx_media_files_type ON media_files(file_type);
CREATE INDEX idx_media_files_status ON media_files(status);
CREATE INDEX idx_media_files_uploaded_by ON media_files(uploaded_by);
CREATE INDEX idx_transcode_jobs_status ON transcode_jobs(status);

-- Migrate data from old tables (if they exist)
-- NOTE: Adjust these based on your actual table structures

-- From media-service
INSERT INTO media_files (id, file_type, file_name, file_size, mime_type, storage_path, storage_bucket, uploaded_by, status, created_at)
SELECT id, 'image', file_name, file_size, mime_type, storage_path, bucket_name, user_id, status, created_at
FROM media_uploads
WHERE NOT EXISTS (SELECT 1 FROM media_files WHERE media_files.id = media_uploads.id)
ON CONFLICT (id) DO NOTHING;

-- From video-service (if exists)
-- INSERT INTO media_files (...) SELECT ... FROM videos ...;

-- From streaming-service (if exists)
-- INSERT INTO media_files (...) SELECT ... FROM streams ...;

COMMIT;
EOF

    # Delivery service migrations
    mkdir -p "$BACKEND_DIR/delivery-service/migrations"

    cat > "$BACKEND_DIR/delivery-service/migrations/001_create_delivery_tables.sql" << 'EOF'
-- Create delivery service tables
-- Manages CDN nodes, caching rules, and streaming sessions

BEGIN;

-- CDN nodes table
CREATE TABLE IF NOT EXISTS cdn_nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_name VARCHAR(100) NOT NULL UNIQUE,
    region VARCHAR(50) NOT NULL,
    endpoint_url TEXT NOT NULL,
    capacity_gb INTEGER NOT NULL,
    used_gb INTEGER DEFAULT 0,
    status VARCHAR(50) DEFAULT 'active',
    health_check_url TEXT,
    last_health_check TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'delivery-service' NOT NULL,
    CONSTRAINT owned_by_delivery_cdn CHECK (service_owner = 'delivery-service')
);

-- Cache rules table
CREATE TABLE IF NOT EXISTS cache_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern TEXT NOT NULL,
    cache_control VARCHAR(255),
    ttl_seconds INTEGER NOT NULL DEFAULT 3600,
    priority INTEGER DEFAULT 0,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'delivery-service' NOT NULL,
    CONSTRAINT owned_by_delivery_cache CHECK (service_owner = 'delivery-service')
);

-- Streaming sessions table
CREATE TABLE IF NOT EXISTS streaming_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    media_file_id UUID NOT NULL,
    user_id UUID NOT NULL,
    cdn_node_id UUID REFERENCES cdn_nodes(id),
    session_token VARCHAR(255) NOT NULL UNIQUE,
    quality VARCHAR(20) NOT NULL,
    bandwidth_kbps INTEGER,
    buffer_health INTEGER,
    playback_position_seconds INTEGER DEFAULT 0,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_heartbeat TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE,
    service_owner VARCHAR(50) DEFAULT 'delivery-service' NOT NULL,
    CONSTRAINT owned_by_delivery_stream CHECK (service_owner = 'delivery-service')
);

-- Delivery metrics table
CREATE TABLE IF NOT EXISTS delivery_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cdn_node_id UUID REFERENCES cdn_nodes(id),
    metric_type VARCHAR(50) NOT NULL, -- 'bandwidth', 'requests', 'cache_hit_rate'
    value DECIMAL(10, 2) NOT NULL,
    unit VARCHAR(20) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'delivery-service' NOT NULL,
    CONSTRAINT owned_by_delivery_metrics CHECK (service_owner = 'delivery-service')
);

-- Create indexes
CREATE INDEX idx_cdn_nodes_region ON cdn_nodes(region);
CREATE INDEX idx_cdn_nodes_status ON cdn_nodes(status);
CREATE INDEX idx_cache_rules_pattern ON cache_rules(pattern);
CREATE INDEX idx_streaming_sessions_user ON streaming_sessions(user_id);
CREATE INDEX idx_streaming_sessions_media ON streaming_sessions(media_file_id);
CREATE INDEX idx_delivery_metrics_timestamp ON delivery_metrics(timestamp);

COMMIT;
EOF

    log_info "Migration scripts created"
}

# Update proto files
update_proto_files() {
    log_info "Updating proto definitions..."

    # Media service proto
    mkdir -p "$BACKEND_DIR/media-service-new/proto"
    cat > "$BACKEND_DIR/media-service-new/proto/media.proto" << 'EOF'
syntax = "proto3";

package media;

// Consolidated Media Service API
service MediaService {
  // Upload operations
  rpc UploadMedia(UploadMediaRequest) returns (MediaResponse);
  rpc CompleteMultipartUpload(CompleteUploadRequest) returns (MediaResponse);

  // Retrieval operations
  rpc GetMedia(GetMediaRequest) returns (MediaResponse);
  rpc ListMedia(ListMediaRequest) returns (ListMediaResponse);

  // Processing operations
  rpc ProcessMedia(ProcessMediaRequest) returns (ProcessResponse);
  rpc GenerateThumbnail(ThumbnailRequest) returns (ThumbnailResponse);
  rpc TranscodeVideo(TranscodeRequest) returns (TranscodeResponse);

  // Management operations
  rpc DeleteMedia(DeleteMediaRequest) returns (DeleteResponse);
  rpc UpdateMetadata(UpdateMetadataRequest) returns (MediaResponse);
}

message UploadMediaRequest {
  string file_name = 1;
  string mime_type = 2;
  int64 file_size = 3;
  bytes content = 4; // For small files
  bool multipart = 5; // For large files
  map<string, string> metadata = 6;
}

message MediaResponse {
  string id = 1;
  string file_name = 2;
  string mime_type = 3;
  int64 file_size = 4;
  string storage_url = 5;
  string cdn_url = 6;
  MediaMetadata metadata = 7;
  string status = 8;
  int64 created_at = 9;
}

message MediaMetadata {
  int32 width = 1;
  int32 height = 2;
  int32 duration_seconds = 3;
  int32 bitrate = 4;
  string codec = 5;
  map<string, string> custom = 6;
}

// Additional message definitions...
EOF

    # Delivery service proto
    mkdir -p "$BACKEND_DIR/delivery-service/proto"
    cat > "$BACKEND_DIR/delivery-service/proto/delivery.proto" << 'EOF'
syntax = "proto3";

package delivery;

// Delivery Service API (CDN + Streaming)
service DeliveryService {
  // CDN operations
  rpc GetOptimalCDNNode(CDNNodeRequest) returns (CDNNodeResponse);
  rpc InvalidateCache(InvalidateCacheRequest) returns (InvalidateResponse);
  rpc GetCDNStatus(StatusRequest) returns (CDNStatusResponse);

  // Streaming operations
  rpc StartStreaming(StartStreamRequest) returns (StreamResponse);
  rpc UpdateStreamHeartbeat(HeartbeatRequest) returns (HeartbeatResponse);
  rpc EndStreaming(EndStreamRequest) returns (EndResponse);
  rpc GetStreamingUrl(StreamUrlRequest) returns (StreamUrlResponse);

  // Metrics
  rpc GetDeliveryMetrics(MetricsRequest) returns (MetricsResponse);
}

message CDNNodeRequest {
  string region = 1;
  string content_type = 2;
}

message CDNNodeResponse {
  string node_id = 1;
  string endpoint_url = 2;
  string region = 3;
  int32 capacity_percent = 4;
}

message StartStreamRequest {
  string media_id = 1;
  string user_id = 2;
  string quality = 3; // "360p", "720p", "1080p", "4k"
  string preferred_cdn_region = 4;
}

message StreamResponse {
  string session_id = 1;
  string stream_url = 2;
  string cdn_node = 3;
  map<string, string> stream_config = 4;
}

// Additional message definitions...
EOF

    log_info "Proto files updated"
}

# Update Docker configurations
update_docker_configs() {
    log_info "Updating Docker configurations..."

    # Media service Dockerfile
    cat > "$BACKEND_DIR/media-service-new/Dockerfile" << 'EOF'
FROM rust:1.75 as builder

WORKDIR /usr/src/media-service
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY proto ./proto
COPY migrations ./migrations

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    libssl3 \
    ca-certificates \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/media-service/target/release/media-service /usr/local/bin/media-service
COPY --from=builder /usr/src/media-service/migrations /migrations

ENV RUST_LOG=info

EXPOSE 50054

CMD ["media-service"]
EOF

    # Delivery service Dockerfile
    cat > "$BACKEND_DIR/delivery-service/Dockerfile" << 'EOF'
FROM rust:1.75 as builder

WORKDIR /usr/src/delivery-service
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY proto ./proto
COPY migrations ./migrations

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    libssl3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/delivery-service/target/release/delivery-service /usr/local/bin/delivery-service
COPY --from=builder /usr/src/delivery-service/migrations /migrations

ENV RUST_LOG=info

EXPOSE 50055

CMD ["delivery-service"]
EOF

    log_info "Docker configurations updated"
}

# Update Kubernetes manifests
update_k8s_manifests() {
    log_info "Updating Kubernetes manifests..."

    local k8s_dir="$BACKEND_DIR/../k8s/backend"
    mkdir -p "$k8s_dir"

    # Media service K8s manifest
    cat > "$k8s_dir/media-service.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: media-service
  namespace: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: media-service
  template:
    metadata:
      labels:
        app: media-service
    spec:
      containers:
      - name: media-service
        image: media-service:latest
        ports:
        - containerPort: 50054
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: aws-secret
              key: access-key
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: aws-secret
              key: secret-key
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: media-service
  namespace: backend
spec:
  selector:
    app: media-service
  ports:
  - port: 50054
    targetPort: 50054
  type: ClusterIP
EOF

    # Delivery service K8s manifest
    cat > "$k8s_dir/delivery-service.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: delivery-service
  namespace: backend
spec:
  replicas: 5
  selector:
    matchLabels:
      app: delivery-service
  template:
    metadata:
      labels:
        app: delivery-service
    spec:
      containers:
      - name: delivery-service
        image: delivery-service:latest
        ports:
        - containerPort: 50055
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: url
        resources:
          requests:
            memory: "1Gi"
            cpu: "1000m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
---
apiVersion: v1
kind: Service
metadata:
  name: delivery-service
  namespace: backend
spec:
  selector:
    app: delivery-service
  ports:
  - port: 50055
    targetPort: 50055
  type: ClusterIP
EOF

    log_info "Kubernetes manifests updated"
}

# Main execution
main() {
    echo ""
    read -p "This will consolidate media services. Continue? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Operation cancelled"
        exit 0
    fi

    # Execute consolidation steps
    backup_services
    create_media_service
    create_delivery_service
    create_migrations
    update_proto_files
    update_docker_configs
    update_k8s_manifests

    echo ""
    log_info "========================================="
    log_info "Media services consolidation complete!"
    log_info "========================================="
    echo ""
    echo "Next steps:"
    echo "1. Review the new service structures in:"
    echo "   - $BACKEND_DIR/media-service-new"
    echo "   - $BACKEND_DIR/delivery-service"
    echo ""
    echo "2. Migrate application code from old services"
    echo "3. Update service references in other microservices"
    echo "4. Run database migrations"
    echo "5. Test the consolidated services"
    echo "6. Deploy to staging environment"
    echo ""
    echo "Old services backed up at: $BACKEND_DIR/backups/"
    echo ""
    log_info "Remember: 'Bad programmers worry about the code. Good programmers worry about data structures.'"
}

# Run main function
main "$@"