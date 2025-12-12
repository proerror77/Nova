# Multi-stage build for realtime-chat-service
# This is an INDEPENDENT WORKSPACE due to sqlite dependency conflict with matrix-sdk
# Build context must be set to backend/realtime-chat-service directory

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

# Copy the independent workspace files
# Docker build context is backend/realtime-chat-service/
COPY Cargo.toml Cargo.lock ./
COPY libs ./libs
COPY src ./src
COPY build.rs ./
COPY proto ./proto

# Build from the independent workspace
RUN cargo build --release --bin realtime-chat-service

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
COPY --from=builder /app/target/release/realtime-chat-service /app/realtime-chat-service

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

CMD ["/app/realtime-chat-service"]
