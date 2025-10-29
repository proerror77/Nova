# Multi-stage build for notification-service
# Stage 1: Build
FROM rust:1.75 as builder

WORKDIR /app

# Copy workspace files
COPY Cargo.toml Cargo.lock ./
COPY backend/notification-service ./notification-service
COPY backend/libs ./libs

# Install system dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Build the application
RUN cargo build --release -p notification-service

# Stage 2: Runtime
FROM debian:bookworm-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /app/target/release/notification-service /usr/local/bin/

# Set environment variables
ENV RUST_LOG=info
ENV PORT=8000
ENV DATABASE_URL=postgres://user:password@postgres/nova

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Expose port
EXPOSE 8000

# Run the application
CMD ["notification-service"]
