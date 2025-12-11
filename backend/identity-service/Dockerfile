# Multi-stage build for identity-service
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

# Copy backend workspace Cargo files first for layer caching
COPY backend/Cargo.toml backend/Cargo.lock ./

# Copy all services and libs for workspace resolution
COPY backend/identity-service ./identity-service
COPY backend/libs ./libs
COPY backend/graphql-gateway ./graphql-gateway
COPY backend/content-service ./content-service
COPY backend/social-service ./social-service
COPY backend/media-service ./media-service
COPY backend/feed-service ./feed-service
COPY backend/graph-service ./graph-service
COPY backend/analytics-service ./analytics-service
COPY backend/notification-service ./notification-service
COPY backend/search-service ./search-service
COPY backend/ranking-service ./ranking-service
COPY backend/trust-safety-service ./trust-safety-service
COPY backend/feature-store ./feature-store
COPY backend/streaming-service ./streaming-service

# Build identity-service
RUN cargo build --release -p identity-service --bin identity-service

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

# Copy binary
COPY --from=builder /app/target/release/identity-service /app/identity-service

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

CMD ["/app/identity-service"]
