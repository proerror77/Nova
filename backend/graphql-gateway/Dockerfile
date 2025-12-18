# Multi-stage build for graphql-gateway
# Build context: repo root (.)
# Use rust:slim-bookworm to match debian:bookworm-slim glibc version
FROM rust:slim-bookworm AS builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y \
    pkg-config \
    libssl-dev \
    protobuf-compiler \
    cmake \
    librdkafka-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Ensure we have a new enough Rust/Cargo toolchain with edition 2024 support
RUN rustup toolchain install nightly && \
    rustup default nightly

WORKDIR /app

# Copy backend workspace files (build context is repo root)
COPY backend ./backend

# Change to backend directory for workspace build
WORKDIR /app/backend

# Build GraphQL Gateway binary in release mode
RUN cargo +nightly build --release -p graphql-gateway

# Runtime stage
FROM debian:bookworm-slim

# Install minimal runtime dependencies
RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    curl \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/backend/target/release/graphql-gateway /app/graphql-gateway

# Create non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

# Expose HTTP port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the binary
CMD ["/app/graphql-gateway"]
