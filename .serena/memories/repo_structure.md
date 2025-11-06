# Repository Structure (Top Level)

- backend — Rust workspace of microservices (auth, user, content, messaging, feed, search, streaming, notification, video, etc.), migrations, Dockerfiles, proto, scripts.
- ios — Xcode workspace-based iOS app (NovaSocial) with SPM package `NovaSocialPackage` for most feature code; additional iOS demos and modules.
- streaming — Streaming/RTMP-related assets or services (see also backend/streaming-service).
- docs — Product, architecture, API, and design documentation.
- scripts — Helper scripts (Neo4j schema, graph backfill, etc.).
- infra, k8s, aws — Infrastructure, deployment, and cloud configuration.
- openspec, specs — Specifications and API definitions (OpenAPI and internal spec kit files).
- tests — Integration/utility tests at the repo root; backend also has tests.
- vendor — Third-party assets or vendored code.
- .github, .githooks — CI/CD and git hooks.

iOS Layout (ios/NovaSocial)
- NovaSocial.xcworkspace — Open this in Xcode.
- NovaSocial.xcodeproj — App shell.
- NovaSocialPackage — Primary Swift package with Sources/ and Tests/.
- App/, Views/, ViewModels (if present), Services/, Network/, LocalData/, DesignSystem/, Accessibility/, Config/, Localization/.

Backend Layout (backend)
- Cargo.toml (workspace), Dockerfiles, prometheus configs.
- services directories: auth-service, user-service, content-service, messaging-service, feed-service, search-service, notification-service, video-service, streaming-service.
- libs, proto, scripts, migrations, docs.
