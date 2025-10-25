FROM rust:1.88-slim-bookworm AS builder

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    cmake \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Cargo.toml ./
COPY src ./src
COPY migrations ./migrations

RUN cargo build --release

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/search-service /app/search-service
COPY migrations /app/migrations
ENV RUST_LOG=info
ENV PORT=8081
EXPOSE 8081
CMD ["/app/search-service"]

