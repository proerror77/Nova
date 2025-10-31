FROM rust:1.88-slim-bookworm AS builder

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    cmake \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Build with workspace context
COPY Cargo.toml ./
COPY backend/search-service ./backend/search-service
COPY backend/libs ./backend/libs

RUN cargo build --release --package search-service

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*

# Create non-root user and group
RUN useradd -m -u 1001 -s /bin/bash appuser

WORKDIR /app
COPY --from=builder /app/target/release/search-service /app/search-service

# Adjust ownership and drop privileges
RUN chown -R appuser:appuser /app
USER appuser

ENV RUST_LOG=info
ENV PORT=8081
EXPOSE 8081
CMD ["/app/search-service"]
