<!--
Sync Impact Report:
Version: 0.0.0 → 1.0.0 (Initial Constitution)
- Added 7 core principles aligned with Instagram-like social platform requirements
- Added Architecture Standards section
- Added Development Workflow section
- Templates requiring updates: ⚠ All templates need initial review for alignment
- Date: 2025-10-17
-->

# Nova Social Platform Constitution

## Core Principles

### I. Microservices Architecture (NON-NEGOTIABLE)
**Rust-first microservices architecture for backend systems**

- All backend services MUST be implemented as independent Rust microservices
- Each service owns its data and exposes well-defined APIs (REST/gRPC)
- Services MUST be stateless to enable horizontal scaling
- No direct database access across service boundaries
- Service communication through message queues (Kafka/RabbitMQ) for event-driven patterns

**Rationale**: Microservices architecture ensures scalability to millions of users, allows independent service deployment, and provides fault isolation. Rust ensures memory safety and high performance.

### II. Cross-Platform Core Sharing
**Rust core libraries compiled for iOS and Android native integration**

- Business logic (algorithms, encryption, validation) MUST be written in Rust
- Core libraries compiled as C-compatible FFI for iOS (static library) and Android (JNI)
- Platform-specific code only for UI and platform APIs
- Recommendation algorithms and security modules are cross-platform by default
- UniFFI or similar tools for automatic binding generation

**Rationale**: Ensures consistency across platforms, reduces duplication, and leverages Rust's compile-to-native capabilities for optimal performance.

### III. Test-Driven Development (NON-NEGOTIABLE)
**Strict TDD with Red-Green-Refactor cycle**

- Tests MUST be written before implementation code
- All PRs require: failing tests → implementation → passing tests
- Unit test coverage minimum: 80% for business logic
- Integration tests required for: service boundaries, API contracts, shared schemas
- No code commits without corresponding tests

**Rationale**: TDD ensures code quality from the start, provides living documentation, and prevents regression. Critical for a social platform handling user data and interactions.

### IV. Security & Privacy First
**GDPR, App Store compliance, and zero-trust security model**

- All user data encrypted at rest and in transit (TLS/HTTPS mandatory)
- Password hashing with bcrypt/Argon2, no plaintext storage
- JWT/OAuth2 for authentication with short-lived tokens
- Privacy policy and GDPR/CCPA compliance built-in
- Account deletion functionality as per App Store requirements (5.1.1(v))
- UGC moderation: content filtering, user reporting, 24-hour response SLA
- Sensitive configs in secure secret management (not in code)

**Rationale**: User trust is paramount. Compliance is mandatory for App Store approval. Security breaches can destroy the platform.

### V. User Experience Excellence
**SwiftUI-first for iOS, Material Design principles for Android (future)**

- UI must be simple, intuitive, Instagram-like aesthetics
- Performance targets: 60fps scrolling, <200ms API response p95
- Accessibility compliance (WCAG 2.1 AA)
- Offline-first where possible (cached feed, draft posts)
- Dark mode and localization support from day one

**Rationale**: Social platforms live or die by UX. Smooth, delightful experiences drive user retention and growth.

### VI. Observability & Monitoring
**Comprehensive metrics, logging, and tracing for all services**

- Prometheus metrics for all microservices (CPU, memory, request latency, error rates)
- Centralized logging (ELK stack or CloudWatch)
- Distributed tracing (Jaeger/OpenTelemetry) for request flows
- Real-time alerting for critical failures (PagerDuty/Slack)
- APM integration for mobile apps (Crashlytics/Sentry)

**Rationale**: You cannot fix what you cannot see. Observability is critical for debugging production issues and optimizing performance.

### VII. Continuous Integration & Deployment
**Automated CI/CD pipelines with multi-environment strategy**

- Every commit triggers: build → test → lint (Rust: clippy/rustfmt, Swift: SwiftLint)
- Containerized deployments (Docker + Kubernetes)
- Environments: Dev → Staging → Production with automated promotion gates
- Rolling updates with zero downtime (health checks + gradual rollout)
- Rollback capability within 5 minutes
- TestFlight auto-publish for iOS, play store for Android (future)

**Rationale**: Fast, reliable deployments enable rapid iteration while maintaining stability. Automation reduces human error.

## Architecture Standards

### Backend Technology Stack
- **Language**: Rust (latest stable)
- **Web Framework**: Actix-web or Axum
- **Databases**: PostgreSQL (relational), Redis (cache), MongoDB/Cassandra (NoSQL for feed/chat)
- **Message Queue**: Kafka or RabbitMQ
- **Container Orchestration**: Kubernetes
- **API Gateway**: Custom Rust gateway or Nginx

### Frontend Technology Stack
- **iOS**: SwiftUI (iOS 15+), Combine for reactive programming
- **Android** (future): Kotlin + Jetpack Compose
- **State Management**: Clean architecture with repository pattern
- **Networking**: URLSession (iOS) with retry/caching logic

### Infrastructure
- **Cloud Provider**: AWS or GCP
- **CDN**: CloudFront or Cloudflare for media delivery
- **Media Storage**: S3 or Google Cloud Storage
- **Media Processing**: FFmpeg for video transcoding, CoreImage/GPUImage for filters

### Security Requirements
- All APIs behind HTTPS/TLS 1.3+
- API rate limiting (per user/IP)
- Input validation and sanitization at API gateway
- SQL injection prevention via ORM/parameterized queries
- XSS prevention via output encoding
- CSRF protection for web admin panel

## Development Workflow

### Code Review Process
- All changes via Pull Requests (no direct commits to main)
- Minimum 1 approval from senior engineer
- Automated checks MUST pass: tests, lint, build
- PR description MUST reference issue/spec and include test plan
- Structural changes separate from behavioral changes (different PRs)

### Version Control
- GitFlow branching model: feature → develop → main
- Semantic versioning (MAJOR.MINOR.PATCH) for all services
- Main branch always deployable
- Feature flags for gradual rollouts

### Quality Gates
- No merge without:
  - All tests passing (unit + integration)
  - Code coverage >= 80% for new code
  - No critical security vulnerabilities (automated scanning)
  - Performance regression checks (benchmarks)

### Documentation Requirements
- API documentation via OpenAPI/Swagger
- Architecture Decision Records (ADRs) for major decisions
- README with setup instructions for each service
- Inline code comments for complex logic

## Governance

**This Constitution is the supreme authority for all development practices.**

- All Pull Requests MUST be validated against these principles
- Deviations require explicit justification and architecture review
- Constitution amendments require:
  1. Documented rationale and impact analysis
  2. Team consensus (80% approval)
  3. Migration plan for existing code
  4. Version bump per semantic versioning

**Compliance Review**:
- Quarterly audits of codebase against Constitution principles
- Security audits before each major release
- Performance benchmarks tracked over time

**Conflict Resolution**:
- Technical disputes escalated to Architecture Review Board
- Constitution takes precedence over individual preferences
- "Simplicity wins" as tiebreaker

**Runtime Development Guidance**:
- Follow `.specify/templates/` for spec, plan, and task structures
- Use spec-kit workflows: constitution → specify → plan → tasks → implement
- All specs must map to Constitution principles

**Version**: 1.0.0 | **Ratified**: 2025-10-17 | **Last Amended**: 2025-10-17
