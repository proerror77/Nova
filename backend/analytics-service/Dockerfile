# Multi-stage build for analytics-service
FROM rust:1.88-slim-bookworm AS builder

# Install dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    cmake \
    build-essential \
    protobuf-compiler \
    librdkafka-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy workspace files from repo root
COPY Cargo.toml Cargo.lock ./
# Copy full backend workspace to satisfy workspace members
COPY backend ./backend

# Build analytics-service
RUN cargo build --release -p analytics-service --bin analytics-service

# Runtime stage
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    librdkafka1 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1001 -s /bin/bash appuser

WORKDIR /app

# Copy binary
COPY --from=builder /app/target/release/analytics-service /app/analytics-service

# Copy migrations if they exist
COPY --from=builder --chown=appuser:appuser /app/backend/analytics-service/migrations /app/migrations 2>/dev/null || true

# Adjust ownership
RUN chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENV RUST_LOG=info
ENV SERVER_HOST=0.0.0.0
ENV SERVER_PORT=8080

# Expose REST API port
EXPOSE 8080
# Expose gRPC port
EXPOSE 9080

CMD ["/app/analytics-service"]
