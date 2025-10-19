# ============================================
# ClickHouse Infrastructure Makefile
# Version: 1.0.0
# Date: 2025-10-18
# ============================================

.PHONY: help up down logs init test verify clean

# Default target
.DEFAULT_GOAL := help

# ============================================
# Help
# ============================================
help: ## Show this help message
	@echo "ClickHouse Analytics Infrastructure"
	@echo "===================================="
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ============================================
# Docker Compose Commands
# ============================================
up: ## Start all services (ClickHouse + Kafka + Zookeeper)
	@echo "🚀 Starting ClickHouse analytics stack..."
	docker-compose up -d
	@echo "✅ Services started!"
	@echo ""
	@echo "ClickHouse HTTP: http://localhost:8123"
	@echo "ClickHouse Native: localhost:9000"
	@echo "Kafka: localhost:9092"
	@echo "Kafka UI: http://localhost:8081"
	@echo ""
	@echo "Run 'make init' to initialize database schema"

down: ## Stop all services
	@echo "🛑 Stopping ClickHouse analytics stack..."
	docker-compose down
	@echo "✅ Services stopped!"

restart: down up ## Restart all services

logs: ## Show logs (use SERVICE=clickhouse for specific service)
	@if [ -z "$(SERVICE)" ]; then \
		docker-compose logs -f; \
	else \
		docker-compose logs -f $(SERVICE); \
	fi

ps: ## Show running services
	docker-compose ps

# ============================================
# Database Initialization
# ============================================
init: ## Initialize ClickHouse database (idempotent)
	@echo "📦 Initializing ClickHouse database..."
	@./init.sh
	@echo "✅ Database initialized!"

init-force: ## Force re-initialize (drop all tables)
	@echo "⚠️  WARNING: This will drop all tables!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker exec -it nova-clickhouse clickhouse-client --query "DROP DATABASE IF EXISTS nova_analytics"; \
		$(MAKE) init; \
	else \
		echo "Cancelled."; \
	fi

# ============================================
# Testing
# ============================================
test: ## Load test data and verify
	@echo "🧪 Loading test data..."
	docker exec -it nova-clickhouse clickhouse-client --multiquery < queries/test-data.sql
	@echo "✅ Test data loaded!"

verify: ## Verify database setup
	@echo "🔍 Verifying ClickHouse setup..."
	@echo ""
	@echo "Tables:"
	@docker exec -it nova-clickhouse clickhouse-client --query "SHOW TABLES FROM nova_analytics"
	@echo ""
	@echo "Materialized Views:"
	@docker exec -it nova-clickhouse clickhouse-client --query "SELECT name FROM system.tables WHERE database = 'nova_analytics' AND name LIKE 'mv_%'"
	@echo ""
	@echo "Kafka Consumers:"
	@docker exec -it nova-clickhouse clickhouse-client --query "SELECT table, consumer_number, assignments.topic_name FROM system.kafka_consumers WHERE database = 'nova_analytics' FORMAT PrettyCompact"

query: ## Run a ClickHouse query (use SQL='...' to specify)
	@if [ -z "$(SQL)" ]; then \
		echo "Usage: make query SQL='SELECT 1'"; \
	else \
		docker exec -it nova-clickhouse clickhouse-client --query "$(SQL)"; \
	fi

client: ## Connect to ClickHouse client
	docker exec -it nova-clickhouse clickhouse-client

# ============================================
# Monitoring
# ============================================
stats: ## Show table statistics
	@echo "📊 Table Statistics"
	@echo "===================="
	@docker exec -it nova-clickhouse clickhouse-client --query " \
		SELECT \
			table, \
			formatReadableSize(sum(bytes)) AS size, \
			sum(rows) AS rows, \
			count() AS parts \
		FROM system.parts \
		WHERE database = 'nova_analytics' AND active \
		GROUP BY table \
		ORDER BY sum(bytes) DESC \
		FORMAT PrettyCompact"

partitions: ## Show partition information
	@echo "📅 Partition Information"
	@echo "========================="
	@docker exec -it nova-clickhouse clickhouse-client --query " \
		SELECT \
			table, \
			count(DISTINCT partition) AS partition_count, \
			min(partition) AS oldest, \
			max(partition) AS newest \
		FROM system.parts \
		WHERE database = 'nova_analytics' AND active \
		GROUP BY table \
		FORMAT PrettyCompact"

slow-queries: ## Show slow queries (> 1s)
	@echo "🐌 Slow Queries (last 24h)"
	@echo "==========================="
	@docker exec -it nova-clickhouse clickhouse-client --query " \
		SELECT \
			query_duration_ms, \
			substring(query, 1, 100) AS query_preview, \
			read_rows, \
			formatReadableSize(read_bytes) AS read_size \
		FROM system.query_log \
		WHERE event_date >= today() - 1 \
			AND type = 'QueryFinish' \
			AND query_duration_ms > 1000 \
			AND query NOT LIKE '%system.%' \
		ORDER BY query_duration_ms DESC \
		LIMIT 10 \
		FORMAT PrettyCompact"

# ============================================
# Kafka Operations
# ============================================
kafka-topics: ## List Kafka topics
	@docker exec -it nova-kafka kafka-topics.sh --list --bootstrap-server localhost:9092

kafka-create-topics: ## Create required Kafka topics
	@echo "📝 Creating Kafka topics..."
	docker exec -it nova-kafka kafka-topics.sh --create --topic events --partitions 2 --replication-factor 1 --bootstrap-server localhost:9092 --if-not-exists
	docker exec -it nova-kafka kafka-topics.sh --create --topic postgres.public.posts --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 --if-not-exists
	docker exec -it nova-kafka kafka-topics.sh --create --topic postgres.public.follows --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 --if-not-exists
	docker exec -it nova-kafka kafka-topics.sh --create --topic postgres.public.likes --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 --if-not-exists
	docker exec -it nova-kafka kafka-topics.sh --create --topic postgres.public.comments --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 --if-not-exists
	@echo "✅ Topics created!"

kafka-consumer-groups: ## Show Kafka consumer groups
	@docker exec -it nova-kafka kafka-consumer-groups.sh --list --bootstrap-server localhost:9092

kafka-lag: ## Show consumer lag for all groups
	@echo "📊 Consumer Lag"
	@echo "================"
	@docker exec -it nova-kafka kafka-consumer-groups.sh --describe --all-groups --bootstrap-server localhost:9092

kafka-produce-test: ## Send a test event to Kafka
	@echo '{"event_id":"'$$(uuidgen)'","user_id":"'$$(uuidgen)'","post_id":"'$$(uuidgen)'","event_type":"view","author_id":"'$$(uuidgen)'","dwell_ms":5000,"created_at":"'$$(date -u +"%Y-%m-%d %H:%M:%S")'"}' | \
		docker exec -i nova-kafka kafka-console-producer.sh --topic events --bootstrap-server localhost:9092
	@echo "✅ Test event sent to 'events' topic"

# ============================================
# Cleanup
# ============================================
clean: ## Remove all data (DANGEROUS)
	@echo "⚠️  WARNING: This will delete all data and volumes!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker-compose down -v; \
		echo "✅ All data removed!"; \
	else \
		echo "Cancelled."; \
	fi

clean-logs: ## Clean ClickHouse logs
	@echo "🧹 Cleaning ClickHouse logs..."
	docker exec -it nova-clickhouse sh -c "truncate -s 0 /var/log/clickhouse-server/*.log"
	@echo "✅ Logs cleaned!"

# ============================================
# Maintenance
# ============================================
optimize: ## Optimize all tables (force merge)
	@echo "🔧 Optimizing tables..."
	@docker exec -it nova-clickhouse clickhouse-client --query "OPTIMIZE TABLE nova_analytics.events FINAL"
	@docker exec -it nova-clickhouse clickhouse-client --query "OPTIMIZE TABLE nova_analytics.posts FINAL"
	@docker exec -it nova-clickhouse clickhouse-client --query "OPTIMIZE TABLE nova_analytics.follows FINAL"
	@docker exec -it nova-clickhouse clickhouse-client --query "OPTIMIZE TABLE nova_analytics.likes FINAL"
	@docker exec -it nova-clickhouse clickhouse-client --query "OPTIMIZE TABLE nova_analytics.comments FINAL"
	@echo "✅ Optimization complete!"

backup: ## Backup all tables to /tmp/clickhouse-backup
	@echo "💾 Backing up ClickHouse data..."
	@mkdir -p /tmp/clickhouse-backup
	@docker exec nova-clickhouse clickhouse-client --query "SELECT name FROM system.tables WHERE database = 'nova_analytics' AND engine NOT LIKE '%Kafka%'" | \
		while read table; do \
			echo "Backing up $$table..."; \
			docker exec nova-clickhouse clickhouse-client --query "SELECT * FROM nova_analytics.$$table FORMAT Native" > /tmp/clickhouse-backup/$$table.native; \
		done
	@echo "✅ Backup complete at /tmp/clickhouse-backup/"

# ============================================
# Development
# ============================================
dev: up init kafka-create-topics test ## Full development setup (start + init + test)
	@echo "🎉 Development environment ready!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Open Kafka UI: http://localhost:8081"
	@echo "  2. Connect to ClickHouse: make client"
	@echo "  3. Run feed query: make query SQL='SELECT * FROM nova_analytics.posts FINAL LIMIT 10'"

benchmark: ## Run query benchmark
	@echo "🏃 Running benchmark..."
	@echo "SELECT * FROM nova_analytics.posts FINAL WHERE status = 'published' LIMIT 50" | \
		docker exec -i nova-clickhouse clickhouse-benchmark \
			--host=localhost \
			--port=9000 \
			--concurrency=10 \
			--iterations=100
