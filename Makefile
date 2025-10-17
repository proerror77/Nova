.PHONY: help setup dev down clean build test lint docker-build docker-run migrate

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
	@echo "Services started. User service: http://localhost:8080"
	@echo "MailHog UI: http://localhost:8025"

down: ## Stop all Docker Compose services
	docker-compose down

clean: ## Stop services and remove volumes
	docker-compose down -v
	@echo "All services stopped and volumes removed."

build: ## Build Rust project
	cd backend && cargo build

build-release: ## Build optimized release binary
	cd backend && cargo build --release

test: ## Run tests
	cd backend && cargo test

test-verbose: ## Run tests with output
	cd backend && cargo test -- --nocapture

lint: ## Run linter (clippy)
	cd backend && cargo clippy --all-targets --all-features -- -D warnings

fmt: ## Format code
	cd backend && cargo fmt --all

fmt-check: ## Check code formatting
	cd backend && cargo fmt --all -- --check

docker-build: ## Build Docker image
	docker build -t nova-user-service:latest ./backend

docker-run: ## Run Docker container
	docker run -p 8080:8080 --env-file .env nova-user-service:latest

migrate: ## Run database migrations
	cd backend && sqlx migrate run --database-url $${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/nova_auth}

migrate-revert: ## Revert last migration
	cd backend && sqlx migrate revert --database-url $${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/nova_auth}

logs: ## Show user-service logs
	docker-compose logs -f user-service

logs-db: ## Show PostgreSQL logs
	docker-compose logs -f postgres

logs-redis: ## Show Redis logs
	docker-compose logs -f redis

health: ## Check service health
	@curl -s http://localhost:8080/api/v1/health | jq .

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
