# Suggested Commands

Environment Setup
- `make setup` — Copy `.env.example` to `.env`.
- `docker-compose up -d` / `make dev` — Start core services.
- `docker-compose down` / `make down` — Stop services.
- `docker-compose down -v` / `make clean` — Stop and remove volumes.

Backend: Build, Test, Lint
- `make build` — Build all services (debug).
- `make build-release` — Build optimized release.
- `make check` — Quick compile check.
- `make test` — Run all tests (workspace).
- `make test-verbose` — Tests with output; `make test-nextest` — faster runner.
- `make test-social` — Social graph tests; `make test-grpc-*` — gRPC integration tests.
- `make fmt` / `make fmt-check` — Format/check formatting.
- `make lint` — Run clippy with warnings as errors.
- `make coverage` — Test coverage report.
- `make audit` — Security audit.

Backend: Migrations and Utilities
- `make migrate` — Run DB migrations.
- `make migrate-revert` — Revert last migration.
- `make logs` / `make logs-db` / `make logs-redis` — Follow logs.
- `make health` — Check service health endpoint.
- `make install-tools` — Install sqlx-cli, watch, audit, tarpaulin.

Docker Images
- `make docker-build` — Build all images; or `make docker-build-{user,messaging,search}` for specific.
- `make docker-run` — Run user-service container.

iOS
- `open ios/NovaSocial/NovaSocial.xcworkspace` — Open workspace in Xcode.
- `open -a Simulator` — Launch iOS Simulator.
- `xcodebuild -scheme NovaSocial -destination 'platform=iOS Simulator,name=iPhone 15' build` — Build via CLI.

General (Darwin/macOS)
- `open <path>` — Open file/app; `pbcopy`/`pbpaste` — clipboard.
- Homebrew: `brew install <pkg>` (e.g., `brew install jq sqlx mysql-client`).
- GNU tools: Prefer `rg` (ripgrep) for fast search: `rg "pattern" -n`.
