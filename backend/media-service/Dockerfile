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

# Copy backend workspace from repo root (build context is repo root)
COPY backend ./backend

# Change to backend directory for workspace build
WORKDIR /app/backend

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
COPY --from=builder /app/backend/target/release/media-service /app/media-service
COPY --from=builder /app/backend/target/release/thumb-migrate /app/thumb-migrate
COPY --from=builder /app/backend/target/release/thumb-worker /app/thumb-worker

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
