.PHONY: help setup dev down clean build test lint docker-build docker-run migrate ios

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Initial setup (copy .env.example to .env)
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created .env file. Please update it with your configuration."; \
	else \
		echo ".env file already exists."; \
	fi

dev: ## Start development environment with Docker Compose
	docker-compose up -d
	@echo "Services started. Identity service: http://localhost:9080"
	@echo "MailHog UI: http://localhost:8025"

down: ## Stop all Docker Compose services
	docker-compose down

clean: ## Stop services and remove volumes
	docker-compose down -v
	@echo "All services stopped and volumes removed."

build: ## Build all services (workspace)
	cd backend && cargo build --workspace --all-targets

build-release: ## Build optimized release binary (all services)
	cd backend && cargo build --workspace --release

test: ## Run tests (all services)
	cd backend && cargo test --workspace

test-verbose: ## Run tests with output (all services)
	cd backend && cargo test --workspace -- --nocapture

test-nextest: ## Run tests with nextest (faster)
	cd backend && cargo nextest run --workspace

lint: ## Run linter (clippy) on all services
	cd backend && cargo clippy --workspace --all-targets --all-features -- -D warnings

fmt: ## Format code (all services)
	cd backend && cargo fmt --all

fmt-check: ## Check code formatting (all services)
	cd backend && cargo fmt --all -- --check

check: ## Quick compile check (all services)
	cd backend && cargo check --workspace --all-targets

docker-build: ## Build all service Docker images
	docker build -t nova-messaging-service:latest -f ./backend/Dockerfile.messaging ./backend
	docker build -t nova-search-service:latest -f ./backend/search-service/Dockerfile ./backend/search-service

docker-build-messaging: ## (deprecated) messaging-service 已淘汰，請改用 realtime-chat-service
	@echo "messaging-service 已淘汰，請使用 realtime-chat-service 對應 Dockerfile"

docker-build-search: ## Build search-service Docker image only
	docker build -t nova-search-service:latest -f ./backend/search-service/Dockerfile ./backend/search-service

migrate: ## Run database migrations
	cd backend && sqlx migrate run --database-url $${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/nova_auth}

migrate-revert: ## Revert last migration
	cd backend && sqlx migrate revert --database-url $${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/nova_auth}

logs: ## Show identity-service logs
	docker-compose logs -f identity-service

logs-db: ## Show PostgreSQL logs
	docker-compose logs -f postgres

logs-redis: ## Show Redis logs
	docker-compose logs -f redis

health: ## Check identity-service health
	@curl -s http://localhost:9080/api/v1/health | jq .

install-tools: ## Install development tools
	cargo install sqlx-cli --no-default-features --features postgres
	cargo install cargo-watch
	cargo install cargo-tarpaulin
	cargo install cargo-audit

watch: ## Run with hot reload
	cd backend && cargo watch -x run

audit: ## Run security audit
	cd backend && cargo audit

coverage: ## Generate test coverage report
	cd backend && cargo tarpaulin --out Html

.PHONY: graph-backfill
graph-backfill: ## Run follows -> Neo4j backfill (requires DB + Neo4j)
	./scripts/graph_backfill.sh

.PHONY: neo4j-init
neo4j-init: ## Apply Neo4j schema (constraints/indexes)
	./scripts/neo4j_init.sh || docker exec -i nova-neo4j cypher-shell -u $${NEO4J_USER:-neo4j} -p $${NEO4J_PASSWORD:-neo4j} < scripts/neo4j_schema.cypher

.PHONY: test-grpc-integration
test-grpc-integration: ## Run gRPC cross-service integration tests
	@echo "Running gRPC integration tests..."
	cargo test --test grpc_cross_service_integration_test -- --nocapture --ignored

.PHONY: test-grpc-integration-local
test-grpc-integration-local: ## Run gRPC integration tests against local services
	@echo "Running local gRPC integration tests..."
	@echo "Make sure services are running on:"
	@echo "  - Identity Service: http://127.0.0.1:9080"
	@echo "  - Messaging Service: http://127.0.0.1:9085"
	SERVICES_RUNNING=true cargo test --test grpc_cross_service_integration_test -- --nocapture --ignored

.PHONY: test-grpc-script
test-grpc-script: ## Run gRPC integration test script
	@chmod +x ./tests/grpc_integration_test.sh
	./tests/grpc_integration_test.sh local

.PHONY: test-grpc-script-staging
test-grpc-script-staging: ## Run gRPC integration test script against staging
	@chmod +x ./tests/grpc_integration_test.sh
	./tests/grpc_integration_test.sh staging

ios: ## Build and run iOS app in simulator
	@./run-ios.sh

ios-iphone15: ## Build and run iOS app on iPhone 15 Pro simulator
	@./run-ios.sh "iPhone 15 Pro"

ios-ipad: ## Build and run iOS app on iPad Pro simulator
	@./run-ios.sh "iPad Pro 13-inch (M5)"
