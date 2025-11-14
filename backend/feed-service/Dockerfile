FROM rust:1.88-slim-bookworm AS builder

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

# Copy workspace files from repo root
COPY Cargo.toml Cargo.lock ./
# Copy full backend workspace to satisfy workspace members
COPY backend ./backend

# Build feed-service
RUN cargo build --release -p feed-service --bin feed-service

FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    librdkafka1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user and group
RUN useradd -m -u 1001 -s /bin/bash appuser

WORKDIR /app

COPY --from=builder /app/target/release/feed-service /app/feed-service

# Adjust ownership and drop privileges
RUN chown -R appuser:appuser /app
USER appuser

ENV RUST_LOG=info
ENV APP_PORT=8080
ENV DATABASE_URL=postgresql://localhost/nova
ENV KAFKA_BOOTSTRAP_SERVERS=kafka:9092

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/app/feed-service"]
