# Build stage
FROM rust:latest AS builder

WORKDIR /app

# Copy standalone Cargo.toml for Docker build
COPY admin-api/Cargo.docker.toml ./Cargo.toml

# Copy source code
COPY admin-api/src ./src
COPY admin-api/migrations ./migrations

# Build the admin-api binary
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/target/release/admin-api /app/admin-api

# Copy migrations
COPY --from=builder /app/migrations /app/migrations

ENV RUST_LOG=info
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["./admin-api"]
