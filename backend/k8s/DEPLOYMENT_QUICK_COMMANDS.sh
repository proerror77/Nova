#!/bin/bash
# DEPLOYMENT_QUICK_COMMANDS.sh
#
# Quick reference commands for deploying optional enhancements
# Copy and paste individual commands as needed
#
# Usage: source this file or copy individual commands

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        NOVA K8s Optional Enhancements - Quick Deployment Commands${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# PHASE 1: INGRESS + TLS
# ============================================================================

echo -e "${YELLOW}PHASE 1: Ingress + TLS Deployment${NC}"
echo ""

echo -e "${GREEN}1.1 Install Nginx Ingress Controller (one-time)${NC}"
cat << 'EOF'
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && \
helm repo update && \
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
EOF
echo ""

echo -e "${GREEN}1.2 Generate Self-Signed Certificate${NC}"
cat << 'EOF'
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=api.nova.local"
EOF
echo ""

echo -e "${GREEN}1.3 Create TLS Secret${NC}"
cat << 'EOF'
kubectl create secret tls nova-tls-cert \
  --cert=/tmp/tls.crt \
  --key=/tmp/tls.key \
  -n nova-messaging
EOF
echo ""

echo -e "${GREEN}1.4 Deploy Ingress${NC}"
cat << 'EOF'
kubectl apply -f ingress-tls-setup.yaml
EOF
echo ""

echo -e "${GREEN}1.5 Verify Ingress Deployment${NC}"
cat << 'EOF'
# Get Ingress IP
INGRESS_IP=$(kubectl get ingress messaging-service-ingress \
  -n nova-messaging -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# Test HTTPS
curl -k https://api.nova.local/health

# Check Ingress status
kubectl get ingress -n nova-messaging
kubectl describe ingress messaging-service-ingress -n nova-messaging
EOF
echo ""
echo ""

# ============================================================================
# PHASE 2: TURN SERVER
# ============================================================================

echo -e "${YELLOW}PHASE 2: TURN Server Deployment${NC}"
echo ""

echo -e "${GREEN}2.1 Deploy TURN Server${NC}"
cat << 'EOF'
kubectl apply -f turn-server-deployment.yaml
EOF
echo ""

echo -e "${GREEN}2.2 Get TURN Server External IP${NC}"
cat << 'EOF'
kubectl get svc turn-server -n nova-turn -w

# Store IP in variable
TURN_IP=$(kubectl get svc turn-server -n nova-turn \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "TURN Server IP: $TURN_IP"
EOF
echo ""

echo -e "${GREEN}2.3 Update TURN Secret with External IP${NC}"
cat << 'EOF'
# Edit manually
kubectl edit secret turn-server-secret -n nova-turn

# Or patch directly (replace YOUR_IP)
kubectl patch secret turn-server-secret \
  -n nova-turn \
  -p '{"data":{"EXTERNAL_IP":"'$(echo -n YOUR_IP | base64)'"}}'
EOF
echo ""

echo -e "${GREEN}2.4 Verify TURN Server Deployment${NC}"
cat << 'EOF'
# Check pods
kubectl get pods -n nova-turn -w

# Check service
kubectl get svc -n nova-turn

# View logs
kubectl logs -f -l component=turn-server -n nova-turn

# Test STUN (install stun-client first: apt-get install stun-client)
TURN_IP=$(kubectl get svc turn-server -n nova-turn \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
stunclient $TURN_IP 3478
EOF
echo ""
echo ""

# ============================================================================
# PHASE 3: PROMETHEUS MONITORING
# ============================================================================

echo -e "${YELLOW}PHASE 3: Prometheus Monitoring Deployment${NC}"
echo ""

echo -e "${GREEN}3.1 Deploy Prometheus Stack${NC}"
cat << 'EOF'
kubectl apply -f prometheus-monitoring-setup.yaml
EOF
echo ""

echo -e "${GREEN}3.2 Wait for Prometheus Pods${NC}"
cat << 'EOF'
kubectl get pods -n nova-monitoring -w
EOF
echo ""

echo -e "${GREEN}3.3 Access Prometheus UI${NC}"
cat << 'EOF'
# Port forward
kubectl port-forward svc/prometheus 9090:9090 -n nova-monitoring

# Open in browser
# http://localhost:9090
EOF
echo ""

echo -e "${GREEN}3.4 Verify Metrics Collection${NC}"
cat << 'EOF'
# In Prometheus UI, run these queries:
# 1. rate(http_requests_total[5m])
# 2. container_memory_usage_bytes{pod=~"messaging-service-.*"}
# 3. kube_pod_status_phase{namespace="nova-messaging", phase="Running"}
EOF
echo ""

echo -e "${GREEN}3.5 Access AlertManager UI${NC}"
cat << 'EOF'
# Port forward
kubectl port-forward svc/alertmanager 9093:9093 -n nova-monitoring

# Open in browser
# http://localhost:9093
EOF
echo ""

echo -e "${GREEN}3.6 Configure Slack Notifications (Optional)${NC}"
cat << 'EOF'
# Edit AlertManager config
kubectl edit configmap alertmanager-config -n nova-monitoring

# Find the global section and add:
# slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
EOF
echo ""

echo -e "${GREEN}3.7 Install Grafana (Optional)${NC}"
cat << 'EOF'
helm repo add grafana https://grafana.github.io/helm-charts && \
helm repo update && \
helm install grafana grafana/grafana \
  -n nova-monitoring \
  --set adminPassword=admin \
  --set persistence.enabled=true \
  --set persistence.size=10Gi

# Access Grafana
kubectl port-forward svc/grafana 3000:80 -n nova-monitoring
# http://localhost:3000 (admin/admin)

# Add Prometheus data source:
# URL: http://prometheus:9090
EOF
echo ""
echo ""

# ============================================================================
# PHASE 4: GITOPS (ARGOCD)
# ============================================================================

echo -e "${YELLOW}PHASE 4: GitOps (ArgoCD) Deployment${NC}"
echo ""

echo -e "${GREEN}4.1 Install ArgoCD${NC}"
cat << 'EOF'
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=300s
EOF
echo ""

echo -e "${GREEN}4.2 Create GitHub Repository Secret${NC}"
cat << 'EOF'
# First, get your GitHub token from: https://github.com/settings/tokens

# Then create the secret (replace YOUR_TOKEN)
kubectl create secret generic nova-repo-credentials \
  --from-literal=username=git \
  --from-literal=password=YOUR_TOKEN \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -
EOF
echo ""

echo -e "${GREEN}4.3 Deploy GitOps Configuration${NC}"
cat << 'EOF'
# Edit gitops-argocd-setup.yaml first:
# 1. Replace "your-org/nova.git" with your GitHub repo
# 2. Replace "your-github-token" with GitHub Personal Access Token

# Then apply
kubectl apply -f gitops-argocd-setup.yaml

# Verify applications created
kubectl get applications -n argocd
EOF
echo ""

echo -e "${GREEN}4.4 Access ArgoCD UI${NC}"
cat << 'EOF'
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD URL: https://localhost:8080"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"

# Login
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD
EOF
echo ""

echo -e "${GREEN}4.5 Configure GitHub Webhook (Optional)${NC}"
cat << 'EOF'
# Get ArgoCD server IP
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
WEBHOOK_URL="https://$ARGOCD_IP/api/webhook"

# 1. Go to GitHub repo Settings → Webhooks
# 2. Add webhook with:
#    - Payload URL: $WEBHOOK_URL
#    - Content type: application/json
#    - Events: Push events
EOF
echo ""

echo -e "${GREEN}4.6 Verify GitOps Deployment${NC}"
cat << 'EOF'
# List applications
argocd app list

# Check sync status
argocd app get messaging-service
argocd app get turn-server
argocd app get monitoring-stack

# Manual sync (if needed)
argocd app sync messaging-service

# Watch sync progress
argocd app logs messaging-service
EOF
echo ""
echo ""

# ============================================================================
# VERIFICATION & TROUBLESHOOTING
# ============================================================================

echo -e "${YELLOW}VERIFICATION & TROUBLESHOOTING${NC}"
echo ""

echo -e "${GREEN}Complete Deployment Verification${NC}"
cat << 'EOF'
# Check all namespaces
kubectl get ns | grep nova

# Check all pods
kubectl get pods -A | grep -E "nova-|argocd|ingress"

# Check all services
kubectl get svc -A | grep -E "nova-|argocd|ingress"

# Check all ingresses
kubectl get ingress -A

# Resource usage
kubectl top nodes
kubectl top pods -A | grep -E "nova-|argocd|ingress"
EOF
echo ""

echo -e "${GREEN}Troubleshooting Commands${NC}"
cat << 'EOF'
# View pod logs
kubectl logs -f <pod_name> -n <namespace>

# Describe pod (shows events and errors)
kubectl describe pod <pod_name> -n <namespace>

# Get recent events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Debug pod (create temporary debug container)
kubectl debug -it <pod_name> -n <namespace>

# Execute command in pod
kubectl exec -it <pod_name> -n <namespace> -- /bin/sh
EOF
echo ""

echo -e "${GREEN}Clean Up Enhancements (if needed)${NC}"
cat << 'EOF'
# Delete specific namespace
kubectl delete namespace nova-turn
kubectl delete namespace nova-monitoring
kubectl delete namespace argocd

# Delete Ingress only
kubectl delete ingress messaging-service-ingress -n nova-messaging

# Delete GitOps only
kubectl delete -f gitops-argocd-setup.yaml
EOF
echo ""
echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Quick Deployment Summary:${NC}"
echo ""
echo "1. PHASE 1 (Recommended Week 1):"
echo "   - Ingress + TLS: 15-30 min"
echo "   - TURN Server: 10-20 min"
echo ""
echo "2. PHASE 2 (Recommended Week 2-3):"
echo "   - Prometheus Monitoring: 10-15 min"
echo ""
echo "3. PHASE 3 (Recommended Week 3-4):"
echo "   - GitOps (ArgoCD): 30-45 min"
echo ""
echo -e "${YELLOW}Total Time: ~2 hours for complete setup${NC}"
echo ""
echo -e "${GREEN}Cost Estimate: ~$66-96 per month (AWS)${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}✅ Ready to deploy! Copy commands from above and execute in order.${NC}"
echo ""
