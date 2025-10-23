.PHONY: help build test clean fmt lint docker-up docker-down db-migrate db-reset dev watch logs
 .PHONY: spec-validate

# Variables
RUST_LOG ?= info
SERVICES := streaming-core streaming-ingest streaming-transcode streaming-delivery streaming-api user-service
DOCKER_COMPOSE_FILE ?= ../docker-compose.yml

# Help
help:
	@echo "Nova Streaming Infrastructure - Makefile Commands"
	@echo "=================================================="
	@echo ""
	@echo "Build Commands:"
	@echo "  make build              - Build all services (debug)"
	@echo "  make build-release      - Build all services (release/optimized)"
	@echo "  make build-{service}    - Build specific service"
	@echo ""
	@echo "Testing:"
	@echo "  make test               - Run all tests"
	@echo "  make test-{service}     - Test specific service"
	@echo "  make fmt                - Format code"
	@echo "  make lint               - Clippy checks"
	@echo ""
	@echo "Docker & Infrastructure:"
	@echo "  make docker-up          - Start all services (docker-compose)"
	@echo "  make docker-down        - Stop all services"
	@echo "  make docker-logs        - View Docker logs"
	@echo "  make docker-clean       - Remove containers and volumes"
	@echo ""
	@echo "Database:"
	@echo "  make db-migrate         - Run migrations"
	@echo "  make db-reset           - Reset database"
	@echo "  make db-shell           - Connect to PostgreSQL"
	@echo ""
	@echo "Development:"
	@echo "  make dev                - Run all services locally (non-Docker)"
	@echo "  make spec-validate      - Validate specs vs implementation (Phase 7B)"
	@echo ""

# Build targets
build:
	@echo "🔨 Building all services (debug)..."
	cargo build --all

build-release:
	@echo "🔨 Building all services (release)..."
	cargo build --release --all

build-%:
	@echo "🔨 Building service: $*"
	cargo build -p $*

# Testing targets
test:
	@echo "✅ Running all tests..."
	cargo test --all -- --test-threads=1

test-%:
	@echo "✅ Testing service: $*"
	cargo test -p $* -- --test-threads=1

fmt:
	@echo "📝 Formatting code..."
	cargo fmt --all

lint:
	@echo "🔍 Running Clippy..."
	cargo clippy --all -- -D warnings

# Docker targets
docker-up:
	@echo "🐳 Starting Docker services..."
	docker-compose -f $(DOCKER_COMPOSE_FILE) up -d
	@echo "✅ Services started"

docker-down:
	@echo "🐳 Stopping Docker services..."
	docker-compose -f $(DOCKER_COMPOSE_FILE) down

docker-logs:
	@echo "📋 Tailing Docker logs..."
	docker-compose -f $(DOCKER_COMPOSE_FILE) logs -f --tail=100

docker-clean:
	@echo "🧹 Cleaning Docker resources..."
	docker-compose -f $(DOCKER_COMPOSE_FILE) down -v

# Database targets
db-migrate:
	@echo "🗄️  Running database migrations..."
	sqlx migrate run --database-url "postgresql://postgres:postgres@localhost:55432/nova_auth"

db-reset:
	@echo "🔄 Resetting database..."
	docker exec nova-postgres psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS nova_auth;"
	docker exec nova-postgres psql -U postgres -d postgres -c "CREATE DATABASE nova_auth;"
	@sleep 1
	@make db-migrate

db-shell:
	@docker exec -it nova-postgres psql -U postgres -d nova_auth

# Utility targets
clean:
	@echo "🧹 Cleaning build artifacts..."
	cargo clean

check:
	@echo "✔️  Checking code..."
	cargo check --all

status:
	@echo "📊 Infrastructure Status:"
	@docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "Docker not running"

setup: docker-up db-migrate
	@echo "✅ Setup complete!"

spec-validate:
	@echo "🔎 Validating specs vs implementation..."
	bash ../scripts/spec-validate.sh

.DEFAULT_GOAL := help
