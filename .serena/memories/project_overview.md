# Nova Social Platform — Project Overview

Purpose
- Instagram-like social media platform with Rust microservices backend and SwiftUI iOS frontend.

Core Components
- Backend (Rust): Actix-web/Axum services; PostgreSQL, Redis, MongoDB/Cassandra; Kafka/RabbitMQ; custom Rust API gateway.
  - gRPC: All services expose gRPC on HTTP_PORT + 1000 with tonic_health
  - Microservice Independence: Application-level FK validation via gRPC (Spec 007 complete)
  - Shared Libraries: grpc-clients (unified AuthClient with connection pooling), db-pool, error-types, crypto-core
- iOS (Swift): SwiftUI + UIKit; Clean Architecture + Repository; URLSession; optional Rust FFI for algorithms.
- Infra: Docker + Kubernetes (EKS on AWS); Prometheus + Grafana; GitHub Actions CI/CD; AWS ECR + CloudFront/Cloudflare.

Principles (from constitution)
- Microservices architecture (Rust-first), cross-platform Rust core libraries via FFI.
- Strict TDD (80%+ coverage), Security & Privacy first (GDPR/App Store), Observability everywhere.
- CI/CD with automated gates; UX performance targets (60fps UI, <200ms API p95).

Getting Started (high level)
- Backend: `docker-compose up -d` or `cd backend && cargo run`; DB via Docker; migrations via `sqlx migrate run`.
- iOS: open `ios/NovaSocial/NovaSocial.xcworkspace` in Xcode; or `xcodebuild` with iOS Simulator.
