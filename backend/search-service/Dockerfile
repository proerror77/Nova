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

# Copy backend workspace files (Cargo.toml, Cargo.lock, all services, libs, proto)
COPY backend ./backend

# Change to backend directory for workspace build
WORKDIR /app/backend

RUN cargo build --release -p search-service --bin search-service

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
COPY --from=builder /app/backend/target/release/search-service /app/search-service

# Adjust ownership and drop privileges
RUN chown -R appuser:appuser /app
USER appuser

ENV RUST_LOG=info
ENV PORT=8081
EXPOSE 8081
CMD ["/app/search-service"]
