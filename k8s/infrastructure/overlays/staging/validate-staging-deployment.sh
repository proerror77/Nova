#!/bin/bash

# Nova Staging Environment Validation Script
# Comprehensive checks for production-ready staging deployment
# Usage: ./validate-staging-deployment.sh

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="nova-staging"
REQUIRED_SERVICES=(
  "user-service"
  "content-service"
  "feed-service"
  "search-service"
  "messaging-service"
  "notification-service"
  "media-service"
  "analytics-service"
  "graph-service"
  "ranking-service"
  "identity-service"
  "trust-safety-service"
  "realtime-chat-service"
)

DATABASES=(
  "nova_auth"
  "nova_user"
  "nova_content"
  "nova_feed"
  "nova_messaging"
  "nova_search"
  "nova_notification"
  "nova_media"
  "nova_analytics"
  "nova_graph"
  "nova_ranking"
  "nova_feature_store"
  "nova_identity"
  "nova_trust_safety"
  "nova_realtime_chat"
)

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
print_header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_check() {
  echo -e "${YELLOW}→${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
  ((PASSED++))
}

print_error() {
  echo -e "${RED}✗${NC} $1"
  ((FAILED++))
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((WARNINGS++))
}

# Main validation functions

validate_namespace() {
  print_header "Namespace Validation"

  print_check "Checking if namespace exists"
  if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    print_success "Namespace '$NAMESPACE' exists"
  else
    print_error "Namespace '$NAMESPACE' not found"
    return 1
  fi

  print_check "Checking namespace status"
  STATUS=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.status.phase}')
  if [ "$STATUS" == "Active" ]; then
    print_success "Namespace is active"
  else
    print_error "Namespace status: $STATUS (expected: Active)"
  fi
}

validate_storage() {
  print_header "Storage Class Validation"

  print_check "Checking gp3 storage class"
  if kubectl get storageclass gp3 &>/dev/null; then
    print_success "gp3 storage class exists"
  else
    print_warning "gp3 storage class not found (using default)"
  fi

  print_check "Checking PersistentVolumeClaims"
  PVC_COUNT=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
  if [ "$PVC_COUNT" -gt 0 ]; then
    print_success "Found $PVC_COUNT PersistentVolumeClaims"
    kubectl get pvc -n "$NAMESPACE" -o wide
  else
    print_warning "No PersistentVolumeClaims found"
  fi
}

validate_secrets() {
  print_header "Secrets & Credentials Validation"

  print_check "Checking External Secrets Operator"
  if kubectl get deployment external-secrets -n external-secrets-system &>/dev/null; then
    print_success "External Secrets Operator is installed"
  else
    print_warning "External Secrets Operator not found (may not be needed)"
  fi

  print_check "Checking nova-db-credentials secret"
  if kubectl get secret nova-db-credentials -n "$NAMESPACE" &>/dev/null; then
    print_success "nova-db-credentials secret exists"
  else
    print_error "nova-db-credentials secret not found"
  fi

  print_check "Checking for hardcoded passwords"
  if kubectl get all -n "$NAMESPACE" -o yaml | grep -i "password" | grep -v "valueFrom\|secretKeyRef" &>/dev/null; then
    print_warning "Found potential hardcoded passwords in manifests"
  else
    print_success "No hardcoded passwords detected"
  fi
}

validate_initialization_jobs() {
  print_header "Initialization Jobs Validation"

  JOBS=("seed-data-job" "sqlx-migrate" "redis-cluster-init" "kafka-init-topics" "clickhouse-init" "proto-validate")

  for job in "${JOBS[@]}"; do
    print_check "Checking $job"

    if kubectl get job "$job" -n "$NAMESPACE" &>/dev/null; then
      STATUS=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
      SUCCEEDED=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")

      if [ "$SUCCEEDED" == "1" ]; then
        print_success "$job completed successfully"
      else
        print_warning "$job status: $STATUS (may still be running)"
      fi
    else
      print_warning "$job not found (optional job)"
    fi
  done
}

validate_postgres() {
  print_header "PostgreSQL Validation"

  print_check "Checking PostgreSQL StatefulSet"
  if kubectl get statefulset postgres -n "$NAMESPACE" &>/dev/null; then
    REPLICAS=$(kubectl get statefulset postgres -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    if [ "$REPLICAS" == "1" ]; then
      print_success "PostgreSQL is ready (1 replica)"
    else
      print_error "PostgreSQL ready replicas: $REPLICAS (expected: 1)"
    fi
  else
    print_error "PostgreSQL StatefulSet not found"
    return 1
  fi

  print_check "Checking PostgreSQL connectivity"
  POD=$(kubectl get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD" ]; then
    if kubectl exec -n "$NAMESPACE" "$POD" -- pg_isready &>/dev/null; then
      print_success "PostgreSQL is accepting connections"
    else
      print_error "PostgreSQL not accepting connections"
    fi
  else
    print_warning "PostgreSQL pod not found"
  fi

  print_check "Checking databases"
  if [ -n "$POD" ]; then
    DB_COUNT=$(kubectl exec -n "$NAMESPACE" "$POD" -- psql -U postgres -c "SELECT count(*) FROM pg_database WHERE datname LIKE 'nova_%';" 2>/dev/null | tail -1 | tr -d ' ')
    EXPECTED_COUNT=${#DATABASES[@]}
    if [ "$DB_COUNT" == "$EXPECTED_COUNT" ]; then
      print_success "All $DB_COUNT databases created"
    else
      print_error "Database count mismatch: $DB_COUNT (expected: $EXPECTED_COUNT)"
    fi
  fi
}

validate_redis() {
  print_header "Redis Cluster Validation"

  print_check "Checking Redis StatefulSet"
  if kubectl get statefulset redis-cluster -n "$NAMESPACE" &>/dev/null; then
    REPLICAS=$(kubectl get statefulset redis-cluster -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    if [ "$REPLICAS" == "3" ]; then
      print_success "Redis cluster ready (3 nodes)"
    else
      print_error "Redis ready replicas: $REPLICAS (expected: 3)"
    fi
  else
    print_warning "Redis StatefulSet not found"
  fi

  print_check "Checking Redis cluster status"
  REDIS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=redis-cluster -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$REDIS_POD" ]; then
    CLUSTER_NODES=$(kubectl exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli cluster nodes 2>/dev/null | wc -l)
    if [ "$CLUSTER_NODES" -ge 3 ]; then
      print_success "Redis cluster topology established ($CLUSTER_NODES nodes)"
    else
      print_error "Redis cluster nodes: $CLUSTER_NODES (expected: >=3)"
    fi
  else
    print_warning "Redis pod not found"
  fi
}

validate_kafka() {
  print_header "Kafka Validation"

  print_check "Checking Kafka Deployment"
  if kubectl get deployment kafka -n "$NAMESPACE" &>/dev/null; then
    REPLICAS=$(kubectl get deployment kafka -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    if [ "$REPLICAS" == "1" ]; then
      print_success "Kafka is ready (1 replica)"
    else
      print_error "Kafka ready replicas: $REPLICAS (expected: 1)"
    fi
  else
    print_warning "Kafka Deployment not found"
  fi

  print_check "Checking Zookeeper Deployment"
  if kubectl get deployment zookeeper -n "$NAMESPACE" &>/dev/null; then
    REPLICAS=$(kubectl get deployment zookeeper -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    if [ "$REPLICAS" == "1" ]; then
      print_success "Zookeeper is ready (1 replica)"
    else
      print_error "Zookeeper ready replicas: $REPLICAS (expected: 1)"
    fi
  else
    print_warning "Zookeeper Deployment not found"
  fi

  print_check "Checking Kafka topics"
  KAFKA_POD=$(kubectl get pod -n "$NAMESPACE" -l app=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$KAFKA_POD" ]; then
    TOPICS=$(kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -- kafka-topics.sh --bootstrap-server kafka:9092 --list 2>/dev/null | wc -l)
    if [ "$TOPICS" -ge 5 ]; then
      print_success "Kafka topics created ($TOPICS topics)"
    else
      print_warning "Kafka topics: $TOPICS (expected: >=5)"
    fi
  fi
}

validate_clickhouse() {
  print_header "ClickHouse Validation"

  print_check "Checking ClickHouse pods"
  CH_POD=$(kubectl get pod -n "$NAMESPACE" -l app=clickhouse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$CH_POD" ]; then
    print_success "ClickHouse pod found"
  else
    print_warning "ClickHouse pod not found (optional component)"
  fi
}

validate_services() {
  print_header "Microservices Validation"

  print_check "Checking gRPC services"
  GRPC_SERVICES=$(kubectl get svc -n "$NAMESPACE" --sort-by=.metadata.name | grep ":50051" | wc -l)
  if [ "$GRPC_SERVICES" -gt 0 ]; then
    print_success "Found $GRPC_SERVICES gRPC services (port 50051)"
  else
    print_warning "No gRPC services found"
  fi

  print_check "Checking microservice pods"
  for service in "${REQUIRED_SERVICES[@]}"; do
    if kubectl get pod -n "$NAMESPACE" -l "app=$service" &>/dev/null; then
      READY=$(kubectl get pod -n "$NAMESPACE" -l "app=$service" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
      if [ "$READY" == "True" ]; then
        print_success "$service is ready"
      else
        print_warning "$service not ready (may still be starting)"
      fi
    else
      print_warning "$service pod not found"
    fi
  done
}

validate_service_discovery() {
  print_header "Service Discovery Validation"

  print_check "Checking DNS headless service"
  if kubectl get svc nova-grpc-services -n "$NAMESPACE" &>/dev/null; then
    CLUSTER_IP=$(kubectl get svc nova-grpc-services -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
    if [ "$CLUSTER_IP" == "None" ]; then
      print_success "Headless service configured for DNS discovery"
    else
      print_error "Service is not headless (clusterIP: $CLUSTER_IP)"
    fi
  else
    print_error "nova-grpc-services not found"
  fi

  print_check "Checking Service Endpoints"
  ENDPOINTS=$(kubectl get endpoints -n "$NAMESPACE" | grep -E "user-service|feed-service" | wc -l)
  if [ "$ENDPOINTS" -gt 0 ]; then
    print_success "Service endpoints established ($ENDPOINTS services)"
  else
    print_warning "No service endpoints found"
  fi
}

validate_proto_management() {
  print_header "Protocol Buffer Management Validation"

  print_check "Checking proto definitions ConfigMap"
  if kubectl get configmap nova-proto-definitions-v1 -n "$NAMESPACE" &>/dev/null; then
    PROTO_FILES=$(kubectl get configmap nova-proto-definitions-v1 -n "$NAMESPACE" -o jsonpath='{.data}' | grep -c "\.proto")
    print_success "Proto ConfigMap exists with $PROTO_FILES proto files"
  else
    print_warning "Proto definitions ConfigMap not found"
  fi

  print_check "Checking service registry"
  if kubectl get configmap nova-service-registry -n "$NAMESPACE" &>/dev/null; then
    print_success "Service registry ConfigMap exists"
  else
    print_warning "Service registry ConfigMap not found"
  fi
}

validate_resource_limits() {
  print_header "Resource Limits Validation"

  print_check "Checking pod resource requests/limits"
  PODS_WITHOUT_LIMITS=$(kubectl get pods -n "$NAMESPACE" -o json | grep -c '"limits"' || true)
  TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

  if [ "$PODS_WITHOUT_LIMITS" -eq "$TOTAL_PODS" ]; then
    print_success "All pods have resource limits defined"
  else
    print_warning "Some pods missing resource limits ($PODS_WITHOUT_LIMITS/$TOTAL_PODS)"
  fi
}

validate_logs() {
  print_header "Log Validation"

  print_check "Checking for error logs"
  ERROR_LOGS=$(kubectl logs -n "$NAMESPACE" --all-containers=true -l "app" --tail=100 2>/dev/null | grep -ic "error" || echo "0")
  if [ "$ERROR_LOGS" -lt 10 ]; then
    print_success "No significant errors in recent logs"
  else
    print_warning "Found $ERROR_LOGS error messages in logs (may be expected)"
  fi
}

print_summary() {
  print_header "Validation Summary"
  echo ""
  echo -e "${GREEN}✓ Passed: $PASSED${NC}"
  echo -e "${RED}✗ Failed: $FAILED${NC}"
  echo -e "${YELLOW}⚠ Warnings: $WARNINGS${NC}"
  echo ""

  if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All critical validations passed!${NC}"
    echo ""
    echo "Staging environment is ready for testing."
    echo ""
    echo "Next steps:"
    echo "  1. Configure ingress for GraphQL gateway"
    echo "  2. Run smoke tests against services"
    echo "  3. Verify data layer connectivity"
    echo "  4. Configure monitoring and logging"
    echo ""
    return 0
  else
    echo -e "${RED}Some critical validations failed!${NC}"
    echo ""
    echo "Please check the errors above and resolve before proceeding."
    echo ""
    return 1
  fi
}

# Main execution
main() {
  echo ""
  echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║ Nova Staging Deployment Validator v2.0 ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
  echo ""

  # Run all validations
  validate_namespace || true
  validate_storage
  validate_secrets
  validate_initialization_jobs
  validate_postgres
  validate_redis
  validate_kafka
  validate_clickhouse
  validate_services
  validate_service_discovery
  validate_proto_management
  validate_resource_limits
  validate_logs

  # Print summary
  print_summary
}

# Run main function
main "$@"
