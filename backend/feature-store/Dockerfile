# Multi-stage build for feature-store
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

# Copy backend workspace files (build context is ./backend in GitHub Actions)
COPY . ./

# Build feature-store
RUN cargo build --release -p feature-store --bin feature-store

# Runtime stage
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1001 -s /bin/bash appuser

WORKDIR /app

# Copy binary
COPY --from=builder /app/target/release/feature-store /app/feature-store

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

CMD ["/app/feature-store"]
