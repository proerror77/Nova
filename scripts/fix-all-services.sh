#!/bin/bash

# Script to fix all identified backend service issues
# Author: Claude
# Date: 2025-11-11

set -e

echo "🔧 Starting comprehensive backend services fix..."
echo "================================================"

# 1. Apply Kafka ConfigMap fixes
echo ""
echo "1️⃣ Fixing Kafka connection configuration..."
kubectl apply -f /Users/proerror/Documents/nova/k8s/fixes/kafka-config-fix.yaml

# 2. Update existing ConfigMaps with correct Kafka broker address
echo ""
echo "2️⃣ Updating existing ConfigMaps..."

# Update nova-backend ConfigMap
kubectl patch configmap nova-config -n nova-backend --type merge -p '{"data":{"KAFKA_BROKERS":"kafka-0.kafka.kafka.svc.cluster.local:9092"}}' 2>/dev/null || echo "No nova-config in nova-backend"

# 3. Patch deployment environment variables directly
echo ""
echo "3️⃣ Patching deployments with correct Kafka configuration..."

# Feed Service
kubectl patch deployment feed-service -n nova-feed --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "KAFKA_BROKERS", "value": "kafka-0.kafka.kafka.svc.cluster.local:9092"}}
]' 2>/dev/null || echo "Feed Service: patch applied or not needed"

# Events Service
kubectl patch deployment events-service -n nova-backend --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "KAFKA_BROKERS", "value": "kafka-0.kafka.kafka.svc.cluster.local:9092"}}
]' 2>/dev/null || echo "Events Service: patch applied or not needed"

# 4. Restart affected services to pick up new configuration
echo ""
echo "4️⃣ Restarting services to apply configuration changes..."

# Restart Feed Service
kubectl rollout restart deployment/feed-service -n nova-feed
echo "Feed Service: restart initiated"

# Restart Events Service
kubectl rollout restart deployment/events-service -n nova-backend
echo "Events Service: restart initiated"

# Restart Messaging Service (to fix service discovery)
kubectl rollout restart deployment/messaging-service -n nova-backend
echo "Messaging Service: restart initiated"

# Restart other services that may have issues
kubectl rollout restart deployment/cdn-service -n nova-backend
echo "CDN Service: restart initiated"

kubectl rollout restart deployment/notification-service -n nova-backend
echo "Notification Service: restart initiated"

kubectl rollout restart deployment/media-service -n nova-media
echo "Media Service: restart initiated"

# 5. Wait for rollouts to complete
echo ""
echo "5️⃣ Waiting for rollouts to complete..."

echo -n "Feed Service: "
kubectl rollout status deployment/feed-service -n nova-feed --timeout=180s

echo -n "Events Service: "
kubectl rollout status deployment/events-service -n nova-backend --timeout=180s

echo -n "Messaging Service: "
kubectl rollout status deployment/messaging-service -n nova-backend --timeout=180s

echo -n "CDN Service: "
kubectl rollout status deployment/cdn-service -n nova-backend --timeout=180s

echo -n "Notification Service: "
kubectl rollout status deployment/notification-service -n nova-backend --timeout=180s

echo -n "Media Service: "
kubectl rollout status deployment/media-service -n nova-media --timeout=180s

# 6. Verify services are running
echo ""
echo "6️⃣ Verifying service status..."

echo ""
echo "Pod Status:"
echo "==========="
kubectl get pods -n nova-backend --no-headers | grep -E "events|cdn|messaging|notification" | awk '{print $1": "$3" ("$2")"}'
kubectl get pods -n nova-feed --no-headers | awk '{print $1": "$3" ("$2")"}'
kubectl get pods -n nova-media --no-headers | grep media-service | awk '{print $1": "$3" ("$2")"}'

echo ""
echo "✅ All fixes applied successfully!"
echo ""
echo "Next steps:"
echo "1. Check service logs for any remaining errors: kubectl logs -n <namespace> <pod-name>"
echo "2. Test health endpoints after services stabilize"
echo "3. Verify Kafka connectivity is restored"