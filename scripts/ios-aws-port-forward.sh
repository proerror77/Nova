#!/bin/bash
# iOS AWS Backend Port-Forward Setup
# This script sets up kubectl port-forwards to access AWS backend services from iOS simulator

set -e

NAMESPACE="nova"
CONTENT_SERVICE_PORT=8081
USER_SERVICE_PORT=8083
MEDIA_SERVICE_PORT=8082
MESSAGING_SERVICE_PORT=8084

echo "🚀 Setting up port-forwards for iOS AWS backend access..."
echo ""
echo "Services to forward:"
echo "  - content-service:$CONTENT_SERVICE_PORT (Posts endpoint)"
echo "  - user-service:$USER_SERVICE_PORT (Feed, Users endpoints)"
echo "  - media-service:$MEDIA_SERVICE_PORT (Media upload)"
echo "  - messaging-service:$MESSAGING_SERVICE_PORT (Messaging)"
echo ""

# Function to start port-forward in background
start_port_forward() {
    local service=$1
    local port=$2
    echo "▶️  Forwarding $service on port $port..."
    kubectl port-forward -n $NAMESPACE svc/$service $port:$port >/dev/null 2>&1 &
    echo "   PID: $!"
}

# Start all port-forwards
start_port_forward "content-service" $CONTENT_SERVICE_PORT
start_port_forward "user-service" $USER_SERVICE_PORT
start_port_forward "media-service" $MEDIA_SERVICE_PORT
start_port_forward "messaging-service" $MESSAGING_SERVICE_PORT

echo ""
echo "✅ Port-forwards started successfully!"
echo ""
echo "📱 iOS Configuration:"
echo "  - Environment: stagingAWS"
echo "  - Base URL: http://host.docker.internal:8081 (simulator)"
echo "  - Or: http://localhost:8081 (device)"
echo ""
echo "🧪 Quick test:"
echo "  curl -H 'Authorization: Bearer test-token' http://localhost:8081/health"
echo ""
echo "⚠️  NOTE: These port-forwards will run until you close this terminal"
echo "Press Ctrl+C to stop all port-forwards"
echo ""

# Keep the script running
trap 'echo ""; echo "🛑 Stopping port-forwards..."; pkill -P $$; exit 0' INT

wait
