FROM rust:slim AS builder

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

# Ensure we have a new enough Rust/Cargo toolchain with edition 2024 support.
RUN rustup toolchain install nightly && \
    rustup default nightly

WORKDIR /app

# Copy workspace manifest files
COPY Cargo.toml Cargo.lock ./

# Copy backend workspace (needed for workspace dependencies)
COPY backend/ ./backend/

# Build GraphQL Gateway binary in release mode
RUN cargo +nightly build --release -p graphql-gateway

# Runtime stage
FROM rust:slim

# Install minimal runtime dependencies
RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder (binary is in workspace target dir)
COPY --from=builder /app/target/release/graphql-gateway /app/graphql-gateway

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
