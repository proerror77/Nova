# Multi-stage build for user-service
FROM rust:1.88-slim-bookworm AS builder

# Install dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    cmake \
    build-essential \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy workspace files from repo root
COPY Cargo.toml ./
COPY backend/user-service ./backend/user-service
COPY backend/libs ./backend/libs

# Build user-service
RUN cargo build --release --package user-service

# Runtime stage
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1001 -s /bin/bash appuser

WORKDIR /app

# Copy binary and migrations
COPY --from=builder /app/target/release/user-service /app/user-service
COPY --chown=appuser:appuser backend/user-service/migrations /app/migrations

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

CMD ["/app/user-service"]
