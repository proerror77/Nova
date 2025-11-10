# Multi-stage build for GraphQL Gateway
FROM rust:latest as builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y \
    pkg-config \
    libssl-dev \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy workspace Cargo files
COPY Cargo.toml Cargo.lock ./

# Copy all backend services (for workspace dependencies)
COPY backend/ ./backend/

# Build GraphQL Gateway
WORKDIR /app
RUN cargo build --release -p graphql-gateway

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder (binary is in workspace target dir)
COPY --from=builder /app/target/release/graphql-gateway /app/graphql-gateway

# Create non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the binary
CMD ["/app/graphql-gateway"]
