# ============================================
# Builder Stage - Compile Rust application
# ============================================
FROM rust:1.76-slim-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create app user for non-root execution
RUN useradd -m -u 1001 -s /bin/bash appuser

# Set working directory
WORKDIR /app

# Copy workspace configuration
COPY Cargo.toml Cargo.lock ./

# Copy service configuration
COPY user-service/Cargo.toml ./user-service/

# Create dummy source files to cache dependencies
RUN mkdir -p user-service/src && \
    echo "fn main() {}" > user-service/src/main.rs && \
    echo "" > user-service/src/lib.rs

# Build dependencies only (layer caching optimization)
RUN cargo build --release --manifest-path user-service/Cargo.toml && \
    rm -rf user-service/src

# Copy actual source code
COPY user-service/src ./user-service/src

# Touch main.rs to trigger rebuild (invalidate cache)
RUN touch user-service/src/main.rs

# Build actual application
RUN cargo build --release --manifest-path user-service/Cargo.toml

# ============================================
# Runtime Stage - Minimal production image
# ============================================
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create app user (same UID as builder)
RUN useradd -m -u 1001 -s /bin/bash appuser

# Create app directory
WORKDIR /app

# Copy compiled binary from builder
COPY --from=builder /app/target/release/user-service /app/user-service

# Copy migrations (for runtime execution)
COPY migrations /app/migrations

# Change ownership to app user
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/app/user-service", "healthcheck"] || exit 1

# Set environment variables
ENV RUST_LOG=info
ENV APP_ENV=production

# Run application
CMD ["/app/user-service"]
