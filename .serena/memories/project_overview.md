# Nova Social Platform — Project Overview

Purpose
- Instagram-like social media platform with Rust microservices backend and SwiftUI iOS frontend.

Core Components
- Backend (Rust): Actix-web/Axum services; PostgreSQL, Redis, MongoDB/Cassandra; Kafka/RabbitMQ; custom Rust API gateway.
- iOS (Swift): SwiftUI + UIKit; Clean Architecture + Repository; URLSession; optional Rust FFI for algorithms.
- Infra: Docker + Kubernetes; Prometheus + Grafana; GitHub Actions CI/CD; AWS/GCP + CloudFront/Cloudflare.

Principles (from constitution)
- Microservices architecture (Rust-first), cross-platform Rust core libraries via FFI.
- Strict TDD (80%+ coverage), Security & Privacy first (GDPR/App Store), Observability everywhere.
- CI/CD with automated gates; UX performance targets (60fps UI, <200ms API p95).

Getting Started (high level)
- Backend: `docker-compose up -d` or `cd backend && cargo run`; DB via Docker; migrations via `sqlx migrate run`.
- iOS: open `ios/NovaSocial/NovaSocial.xcworkspace` in Xcode; or `xcodebuild` with iOS Simulator.
