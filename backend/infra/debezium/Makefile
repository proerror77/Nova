.PHONY: help start stop restart status logs clean deploy-connector delete-connector health topics

DEBEZIUM_URL := http://localhost:8083
CONNECTOR_NAME := nova-postgres-cdc-connector

help:
	@echo "Debezium CDC Management Commands:"
	@echo "  make start            - Start all services (Postgres + Kafka + Debezium)"
	@echo "  make stop             - Stop all services"
	@echo "  make restart          - Restart all services"
	@echo "  make status           - Show service status"
	@echo "  make logs             - Tail Debezium logs"
	@echo "  make clean            - Remove all containers and volumes"
	@echo ""
	@echo "  make topics           - Initialize Kafka topics"
	@echo "  make deploy-connector - Deploy Debezium connector"
	@echo "  make delete-connector - Delete Debezium connector"
	@echo "  make health           - Check connector health"
	@echo ""
	@echo "  make test-cdc         - Test CDC by inserting data"
	@echo "  make test-e2e         - Run end-to-end CDC flow test"
	@echo "  make consume-users    - Consume cdc.users topic"

start:
	@echo "Starting Debezium CDC infrastructure..."
	docker-compose up -d
	@echo "Waiting for services to be healthy..."
	@sleep 5
	@docker-compose ps

stop:
	@echo "Stopping all services..."
	docker-compose down

restart:
	@echo "Restarting all services..."
	docker-compose restart

status:
	@docker-compose ps

logs:
	@docker logs -f nova-debezium

clean:
	@echo "WARNING: This will delete all data. Press Ctrl+C to cancel..."
	@sleep 3
	docker-compose down -v
	@echo "All data cleaned."

topics:
	@echo "Initializing Kafka topics..."
	@sleep 10
	docker exec nova-kafka sh -c 'cd /tmp && cat > topics-init.sh' < ../kafka/topics-init.sh
	docker exec nova-kafka chmod +x /tmp/topics-init.sh
	docker exec nova-kafka sh -c 'KAFKA_BROKER=localhost:9092 /tmp/topics-init.sh'

deploy-connector:
	@echo "Waiting for Debezium Connect to be ready..."
	@until curl -f $(DEBEZIUM_URL)/ > /dev/null 2>&1; do sleep 2; done
	@echo "Deploying Postgres CDC Connector..."
	@curl -X POST $(DEBEZIUM_URL)/connectors \
		-H "Content-Type: application/json" \
		-d @postgres-connector.json \
		| jq || echo "Connector already exists or deployment failed"
	@sleep 2
	@make health

delete-connector:
	@echo "Deleting connector $(CONNECTOR_NAME)..."
	@curl -X DELETE $(DEBEZIUM_URL)/connectors/$(CONNECTOR_NAME)
	@echo "Connector deleted."

health:
	@echo "=== Debezium Connect Health ==="
	@curl -s $(DEBEZIUM_URL)/ | jq -r '.version'
	@echo ""
	@echo "=== Connector Status ==="
	@curl -s $(DEBEZIUM_URL)/connectors/$(CONNECTOR_NAME)/status | jq '.connector.state, .tasks[0].state'
	@echo ""
	@echo "=== Kafka Topics ==="
	@docker exec nova-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -E '^(cdc\.|events)'

test-cdc:
	@echo "Inserting test user into PostgreSQL..."
	@docker exec nova-postgres psql -U postgres -d nova -c \
		"INSERT INTO users (username, email, password_hash) VALUES ('test_user_$$(date +%s)', 'test@example.com', 'hash') RETURNING id, username, created_at;"
	@echo ""
	@echo "Wait 2 seconds for CDC to capture..."
	@sleep 2
	@echo "Consuming latest message from cdc.users..."
	@docker exec nova-kafka kafka-console-consumer.sh \
		--bootstrap-server localhost:9092 \
		--topic cdc.users \
		--max-messages 1 \
		--timeout-ms 5000 \
		--from-beginning | tail -1 | jq

consume-users:
	@echo "Consuming cdc.users topic (Ctrl+C to stop)..."
	@docker exec -it nova-kafka kafka-console-consumer.sh \
		--bootstrap-server localhost:9092 \
		--topic cdc.users \
		--from-beginning

consume-posts:
	@echo "Consuming cdc.posts topic (Ctrl+C to stop)..."
	@docker exec -it nova-kafka kafka-console-consumer.sh \
		--bootstrap-server localhost:9092 \
		--topic cdc.posts \
		--from-beginning

psql:
	@docker exec -it nova-postgres psql -U postgres -d nova

test-e2e:
	@echo "Running end-to-end CDC flow test..."
	@./test-cdc-flow.sh

kafka-ui:
	@echo "Opening Kafka UI..."
	@open http://localhost:8080 || xdg-open http://localhost:8080 || echo "Open http://localhost:8080 in your browser"
