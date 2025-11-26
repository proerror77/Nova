#!/bin/bash
# Generate proto descriptor file for Envoy gRPC-JSON transcoder
# This script requires buf CLI: https://buf.build/docs/installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTO_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROTO_DIR/gen/descriptor"

echo "=== Generating Proto Descriptor for Envoy Transcoder ==="
echo "Proto directory: $PROTO_DIR"
echo "Output directory: $OUTPUT_DIR"

# Create output directory
mkdir -p "$OUTPUT_DIR"

cd "$PROTO_DIR"

# Check if buf is installed
if ! command -v buf &> /dev/null; then
    echo "Error: buf CLI not found. Install it first:"
    echo "  brew install bufbuild/buf/buf"
    echo "  or"
    echo "  curl -sSL https://github.com/bufbuild/buf/releases/latest/download/buf-$(uname -s)-$(uname -m) -o /usr/local/bin/buf && chmod +x /usr/local/bin/buf"
    exit 1
fi

# Update buf dependencies
echo ""
echo "=== Updating buf dependencies ==="
buf dep update

# Generate all outputs (including descriptor)
echo ""
echo "=== Generating code and descriptor ==="
buf generate

# Also generate a standalone descriptor set for Envoy
echo ""
echo "=== Generating Envoy descriptor set ==="
buf build -o "$OUTPUT_DIR/nova-api.pb"

echo ""
echo "=== Done! ==="
echo "Descriptor file: $OUTPUT_DIR/nova-api.pb"
echo ""
echo "To use with Envoy, mount this file at:"
echo "  /etc/envoy/proto/nova-api.pb"
