#!/bin/bash
# Script to generate Kubernetes manifests for V2 services (social-service, communication-service)
# Usage: ./generate-v2-services.sh

set -euo pipefail

K8S_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MICROSERVICES_DIR="$K8S_DIR/microservices"

echo "Generating V2 service Kubernetes manifests..."

# Function to create deployment manifest
create_deployment() {
  local service_name=$1
  local grpc_port=$2
  local http_port=$3
  local min_replicas=$4
  local max_replicas=$5

  cat > "$MICROSERVICES_DIR/${service_name}-deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $service_name
  namespace: nova
  labels:
    app: $service_name
    version: v2
    tier: backend
  annotations:
    fluxcd.io/automated: "true"
    fluxcd.io/tag.$service_name: semver:~2.0
spec:
  replicas: $min_replicas
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: $service_name
  template:
    metadata:
      labels:
        app: $service_name
        version: v2
        tier: backend
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "$http_port"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: $service_name
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000

      containers:
      - name: $service_name
        image: nova/$service_name:2.0.0
        imagePullPolicy: IfNotPresent

        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL

        ports:
        - name: http
          containerPort: $http_port
          protocol: TCP
        - name: grpc
          containerPort: $grpc_port
          protocol: TCP

        env:
        - name: RUST_LOG
          value: "info,${service_name//-/_}=debug"
        - name: SERVICE_NAME
          value: "$service_name"
        - name: SERVER_HOST
          value: "0.0.0.0"
        - name: SERVER_PORT
          value: "$http_port"
        - name: GRPC_PORT
          value: "$grpc_port"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: ${service_name}-secret
              key: database-url
        - name: REDIS_URL
          valueFrom:
            configMapKeyRef:
              name: ${service_name}-configmap
              key: redis-url
        - name: KAFKA_BROKERS
          valueFrom:
            configMapKeyRef:
              name: ${service_name}-configmap
              key: kafka-brokers

        livenessProbe:
          httpGet:
            path: /health/live
            port: $http_port
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /health/ready
            port: $http_port
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3

        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"

        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /var/cache

      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}

      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - $service_name
              topologyKey: kubernetes.io/hostname
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 50
            preference:
              matchExpressions:
              - key: tier
                operator: In
                values:
                - backend

      terminationGracePeriodSeconds: 30
EOF

  echo "✓ Created $service_name deployment"
}

# Function to create service manifest
create_service() {
  local service_name=$1
  local grpc_port=$2
  local http_port=$3

  cat > "$MICROSERVICES_DIR/${service_name}-service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $service_name
  namespace: nova
  labels:
    app: $service_name
    version: v2
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "$http_port"
    prometheus.io/path: "/metrics"
spec:
  type: ClusterIP
  selector:
    app: $service_name
  ports:
    - name: http
      port: $http_port
      targetPort: $http_port
      protocol: TCP
    - name: grpc
      port: $grpc_port
      targetPort: $grpc_port
      protocol: TCP
  sessionAffinity: None
---
apiVersion: v1
kind: Service
metadata:
  name: ${service_name}-headless
  namespace: nova
  labels:
    app: $service_name
    version: v2
spec:
  type: ClusterIP
  clusterIP: None
  selector:
    app: $service_name
  ports:
    - name: grpc
      port: $grpc_port
      targetPort: $grpc_port
      protocol: TCP
EOF

  echo "✓ Created $service_name service"
}

# Function to create HPA
create_hpa() {
  local service_name=$1
  local min_replicas=$2
  local max_replicas=$3

  cat > "$MICROSERVICES_DIR/${service_name}-hpa.yaml" <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${service_name}-hpa
  namespace: nova
  labels:
    app: $service_name
    version: v2
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $service_name
  minReplicas: $min_replicas
  maxReplicas: $max_replicas
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
      - type: Pods
        value: 2
        periodSeconds: 15
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
      selectPolicy: Min
EOF

  echo "✓ Created $service_name HPA"
}

# Function to create PDB
create_pdb() {
  local service_name=$1

  cat > "$MICROSERVICES_DIR/${service_name}-pdb.yaml" <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${service_name}-pdb
  namespace: nova
  labels:
    app: $service_name
    version: v2
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: $service_name
  maxUnavailable: 1
EOF

  echo "✓ Created $service_name PDB"
}

# Function to create ServiceAccount
create_serviceaccount() {
  local service_name=$1

  cat > "$MICROSERVICES_DIR/${service_name}-serviceaccount.yaml" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $service_name
  namespace: nova
  labels:
    app: $service_name
    version: v2
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${service_name}-role
  namespace: nova
  labels:
    app: $service_name
    version: v2
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${service_name}-rolebinding
  namespace: nova
  labels:
    app: $service_name
    version: v2
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${service_name}-role
subjects:
- kind: ServiceAccount
  name: $service_name
  namespace: nova
EOF

  echo "✓ Created $service_name ServiceAccount"
}

# Generate social-service manifests
echo ""
echo "Creating social-service manifests..."
create_deployment "social-service" "50052" "8081" "2" "10"
create_service "social-service" "50052" "8081"
create_hpa "social-service" "2" "10"
create_pdb "social-service"
create_serviceaccount "social-service"

# Generate communication-service manifests
echo ""
echo "Creating communication-service manifests..."
create_deployment "communication-service" "50053" "8082" "2" "8"
create_service "communication-service" "50053" "8082"
create_hpa "communication-service" "2" "8"
create_pdb "communication-service"
create_serviceaccount "communication-service"

echo ""
echo "✅ All V2 service manifests generated successfully!"
echo ""
echo "Generated files:"
echo "  - social-service: deployment, service, hpa, pdb, serviceaccount"
echo "  - communication-service: deployment, service, hpa, pdb, serviceaccount"
echo ""
echo "Note: You still need to create ConfigMaps and Secrets manually with actual values."