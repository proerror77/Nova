#!/bin/bash
# ==============================================
# Nova - Generate Kubernetes Manifests
# ==============================================
# This script generates Kubernetes manifests for all 11 services
# following the same pattern to avoid duplication

set -eo pipefail

# Service configuration: name:http_port pairs
services=(
  "auth-service:8083"
  "content-service:8081"
  "feed-service:8084"
  "media-service:8082"
  "messaging-service:8085"
  "search-service:8086"
  "streaming-service:8087"
  "notification-service:8088"
  "cdn-service:8089"
  "events-service:8090"
)

OUTPUT_DIR="base"
mkdir -p "$OUTPUT_DIR"

echo "Generating Kubernetes manifests for ${#services[@]} services..."

for entry in "${services[@]}"; do
  service=$(echo "$entry" | cut -d: -f1)
  http_port=$(echo "$entry" | cut -d: -f2)
  grpc_port=$((http_port + 1000))

  echo "  - $service (HTTP: $http_port, gRPC: $grpc_port)"

  cat > "$OUTPUT_DIR/${service}.yaml" <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $service
  namespace: nova-backend
  labels:
    app: $service
    component: backend
    version: v1
spec:
  replicas: 3
  selector:
    matchLabels:
      app: $service
  template:
    metadata:
      labels:
        app: $service
        version: v1
    spec:
      containers:
      - name: $service
        image: nova-$service:latest
        imagePullPolicy: Always
        ports:
        - name: http
          containerPort: $http_port
          protocol: TCP
        - name: grpc
          containerPort: $grpc_port
          protocol: TCP
        env:
        - name: HTTP_PORT
          value: "$http_port"
        - name: SERVER_HOST
          value: "0.0.0.0"
        - name: SERVER_PORT
          value: "$http_port"
        - name: GRPC_PORT
          value: "$grpc_port"
        - name: RUST_LOG
          value: "info"
        envFrom:
        - configMapRef:
            name: nova-backend-config
        - secretRef:
            name: nova-backend-secrets
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /api/v1/health/live
            port: $http_port
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /api/v1/health/ready
            port: $http_port
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 3
        startupProbe:
          httpGet:
            path: /api/v1/health
            port: $http_port
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 30
      restartPolicy: Always

---
apiVersion: v1
kind: Service
metadata:
  name: $service
  namespace: nova-backend
  labels:
    app: $service
spec:
  type: ClusterIP
  ports:
  - name: http
    port: $http_port
    targetPort: $http_port
    protocol: TCP
  - name: grpc
    port: $grpc_port
    targetPort: $grpc_port
    protocol: TCP
  selector:
    app: $service
EOF
done

echo "✅ Generated ${#services[@]} service manifests in $OUTPUT_DIR/"
echo ""
echo "Next steps:"
echo "  1. Review generated manifests: ls -lh $OUTPUT_DIR/"
echo "  2. Create secrets: kubectl create secret generic nova-backend-secrets -n nova-backend --from-env-file=.env"
echo "  3. Apply to cluster: kubectl apply -f $OUTPUT_DIR/"
