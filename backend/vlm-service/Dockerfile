# Multi-stage build for vlm-service
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
    libsasl2-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend workspace files (build context is ./backend in GitHub Actions)
COPY . ./

# Build vlm-service
RUN cargo build --release -p vlm-service --bin vlm-service

# Runtime stage
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    librdkafka1 \
    libsasl2-2 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1001 -s /bin/bash appuser

WORKDIR /app

# Copy binary
COPY --from=builder /app/target/release/vlm-service /app/vlm-service

# Adjust ownership
RUN chown -R appuser:appuser /app
USER appuser

# Health check via gRPC
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:50060/health || exit 1

ENV RUST_LOG=info,vlm_service=debug,rdkafka=warn

# Expose gRPC port
EXPOSE 50060

CMD ["/app/vlm-service"]
