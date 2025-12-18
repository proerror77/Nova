# Multi-stage build for media-service
FROM rust:1.85-slim-bookworm AS builder

# Install dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    cmake \
    build-essential \
    protobuf-compiler \
    librdkafka-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy workspace files (context is backend directory)
COPY Cargo.toml Cargo.lock ./
COPY proto ./proto
COPY libs ./libs
COPY media-service ./media-service
# Copy service deps for workspace resolution
COPY identity-service/Cargo.toml ./identity-service/Cargo.toml
COPY content-service/Cargo.toml ./content-service/Cargo.toml
COPY social-service/Cargo.toml ./social-service/Cargo.toml
COPY streaming-service/Cargo.toml ./streaming-service/Cargo.toml
COPY notification-service/Cargo.toml ./notification-service/Cargo.toml
COPY search-service/Cargo.toml ./search-service/Cargo.toml
COPY analytics-service/Cargo.toml ./analytics-service/Cargo.toml
COPY graph-service/Cargo.toml ./graph-service/Cargo.toml
COPY feed-service/Cargo.toml ./feed-service/Cargo.toml
COPY feature-store/Cargo.toml ./feature-store/Cargo.toml
COPY ranking-service/Cargo.toml ./ranking-service/Cargo.toml
COPY trust-safety-service/Cargo.toml ./trust-safety-service/Cargo.toml
COPY graphql-gateway/Cargo.toml ./graphql-gateway/Cargo.toml

# Create stub lib.rs for workspace members we don't need to build
RUN for dir in identity-service content-service social-service streaming-service notification-service search-service analytics-service graph-service feed-service feature-store ranking-service trust-safety-service graphql-gateway; do \
    mkdir -p $dir/src && echo "" > $dir/src/lib.rs; \
    done && \
    mkdir -p content-service/benches && echo "fn main() {}" > content-service/benches/feed_ranking_bench.rs

# Downgrade home crate to version compatible with Rust 1.85
RUN cargo update -p home --precise 0.5.9

# Build media-service binaries (main server + thumbnail migrator + thumbnail worker)
RUN cargo build --release -p media-service --bin media-service --bin thumb-migrate --bin thumb-worker

# Runtime stage
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    librdkafka1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1001 -s /bin/bash appuser

WORKDIR /app

# Copy binaries
COPY --from=builder /app/target/release/media-service /app/media-service
COPY --from=builder /app/target/release/thumb-migrate /app/thumb-migrate
COPY --from=builder /app/target/release/thumb-worker /app/thumb-worker

# Adjust ownership
RUN chown -R appuser:appuser /app
USER appuser

# Health check - use HTTP_PORT from env (default 8085)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${HTTP_PORT:-8085}/health || exit 1

ENV RUST_LOG=info
ENV SERVER_HOST=0.0.0.0
ENV HTTP_PORT=8085
ENV GRPC_PORT=9085

# Expose REST API port
EXPOSE 8085
# Expose gRPC port
EXPOSE 9085

CMD ["/app/media-service"]
