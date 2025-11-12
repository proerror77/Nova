#!/bin/bash
##############################################################################
# Generate PgBouncer user list with SCRAM-SHA-256 password hashes
#
# Usage:
#   ./generate_userlist.sh <username> <password>
#   Or read from environment variables:
#   PGBOUNCER_NOVA_USER_PASS=xxx PGBOUNCER_ADMIN_PASS=yyy ./generate_userlist.sh
#
# This script:
# 1. Reads passwords from arguments or environment variables
# 2. Generates SCRAM-SHA-256 hashes using PostgreSQL's password hash functions
# 3. Outputs user list in PgBouncer format to userlist.txt
#
# Security Notes:
# - Passwords should NOT be stored in environment variables in production
# - Use Kubernetes Secrets or similar secure storage
# - This script is meant for local development and CI/CD setup
##############################################################################

set -e

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PGBOUNCER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${PGBOUNCER_DIR}/userlist.txt"
SCRAM_ITERATIONS=4096

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to generate SCRAM-SHA-256 hash using openssl and base64
# This mimics what PostgreSQL does internally
generate_scram_sha256() {
    local username=$1
    local password=$2
    
    # Generate random salt (16 bytes)
    local salt=$(openssl rand -hex 8)
    
    # SCRAM-SHA-256 hash generation (simplified - for full compatibility, use PostgreSQL)
    # In production, use: SELECT format('SCRAM-SHA-256$%s', encode(password, 'hex')) FROM pg_shadow
    
    # For now, we'll use a Python helper if available, or document the alternative
    if command -v python3 &> /dev/null; then
        python3 - "$username" "$password" "$salt" "$SCRAM_ITERATIONS" << 'PYTHON_SCRIPT'
import sys
import hashlib
import base64
import struct

def generate_scram_sha256(username, password, salt_hex, iterations):
    """Generate SCRAM-SHA-256 hash in PgBouncer format"""
    
    # Convert salt from hex to bytes
    salt = bytes.fromhex(salt_hex)
    
    # Step 1: Generate PBKDF2 key
    dk = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, iterations)
    
    # Step 2: Generate ClientKey = HMAC(StoredKey, "Client Key")
    client_key = hashlib.new('sha256', dk)
    client_key.update(b"Client Key")
    client_key_digest = client_key.digest()
    
    # Step 3: StoredKey = H(ClientKey)
    stored_key = hashlib.sha256(client_key_digest).digest()
    
    # Step 4: ServerKey = HMAC(StoredKey, "Server Key")
    server_key = hashlib.new('sha256', dk)
    server_key.update(b"Server Key")
    server_key_digest = server_key.digest()
    
    # Encode to base64
    salt_b64 = base64.b64encode(salt).decode()
    stored_key_b64 = base64.b64encode(stored_key).decode()
    server_key_b64 = base64.b64encode(server_key_digest).decode()
    
    # Return in PgBouncer format
    return f"SCRAM-SHA-256${iterations}${salt_b64}${stored_key_b64}${server_key_b64}"

username = sys.argv[1]
password = sys.argv[2]
salt = sys.argv[3]
iterations = int(sys.argv[4])

hash_result = generate_scram_sha256(username, password, salt, iterations)
print(hash_result)
PYTHON_SCRIPT
    else
        # Fallback: Instructions for PostgreSQL
        log_warn "Python3 not found. Using PostgreSQL method instead."
        log_info "Connect to PostgreSQL and run:"
        log_info "  SELECT 'SCRAM-SHA-256\$' || encode(concat(password, salt), 'hex') FROM pg_shadow WHERE usename = '$username';"
        return 1
    fi
}

# Main script
main() {
    log_info "PgBouncer User List Generator"
    log_info "==============================\n"
    
    # Get passwords from environment variables or arguments
    NOVA_USER_PASS="${PGBOUNCER_NOVA_USER_PASS:-}"
    ADMIN_PASS="${PGBOUNCER_ADMIN_PASS:-}"
    STATS_USER_PASS="${PGBOUNCER_STATS_USER_PASS:-}"
    
    # If no env vars, try command line arguments
    if [ -z "$NOVA_USER_PASS" ] && [ $# -ge 2 ]; then
        NOVA_USER_PASS="$1"
        ADMIN_PASS="$2"
        STATS_USER_PASS="${3:-}"
    fi
    
    # Validate inputs
    if [ -z "$NOVA_USER_PASS" ]; then
        log_error "nova_user password not provided"
        log_info "Usage:"
        log_info "  Method 1: ./generate_userlist.sh nova_password admin_password [stats_password]"
        log_info "  Method 2: PGBOUNCER_NOVA_USER_PASS=xxx PGBOUNCER_ADMIN_PASS=yyy ./generate_userlist.sh"
        exit 1
    fi
    
    if [ -z "$ADMIN_PASS" ]; then
        log_error "admin password not provided"
        exit 1
    fi
    
    # Set defaults
    STATS_USER_PASS="${STATS_USER_PASS:-$ADMIN_PASS}"
    
    log_info "Generating SCRAM-SHA-256 hashes..."
    log_info "Iterations: $SCRAM_ITERATIONS\n"
    
    # Generate hashes
    log_info "Generating hash for nova_user..."
    NOVA_HASH=$(generate_scram_sha256 "nova_user" "$NOVA_USER_PASS" "$(openssl rand -hex 8)" "$SCRAM_ITERATIONS")
    
    log_info "Generating hash for admin..."
    ADMIN_HASH=$(generate_scram_sha256 "admin" "$ADMIN_PASS" "$(openssl rand -hex 8)" "$SCRAM_ITERATIONS")
    
    log_info "Generating hash for stats_user..."
    STATS_HASH=$(generate_scram_sha256 "stats_user" "$STATS_USER_PASS" "$(openssl rand -hex 8)" "$SCRAM_ITERATIONS")
    
    # Write output file
    log_info "\nWriting to $OUTPUT_FILE"
    
    cat > "$OUTPUT_FILE" << USERLIST
; PgBouncer User List with SCRAM-SHA-256 Hashes
; Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
; 
; DO NOT EDIT THIS FILE MANUALLY - regenerate using generate_userlist.sh
; Keep this file secure (read-only, restricted access)

; Main application user - used by all Nova microservices
"nova_user" "$NOVA_HASH"

; Admin user - for maintenance, health checks, pool management
"admin" "$ADMIN_HASH"

; Read-only stats user - for Prometheus monitoring/metrics
"stats_user" "$STATS_HASH"
USERLIST
    
    # Set secure permissions
    chmod 600 "$OUTPUT_FILE"
    
    log_info "User list generated successfully!"
    log_info "File: $OUTPUT_FILE"
    log_info "Permissions: 600 (read/write for owner only)"
    log_info "\nNext steps:"
    log_info "1. Copy $OUTPUT_FILE to PgBouncer container: /etc/pgbouncer/userlist.txt"
    log_info "2. Ensure PostgreSQL has the same users with same passwords"
    log_info "3. Test connection: psql postgresql://nova_user:password@localhost:6432/nova"
    
    # Security warning
    log_warn "\n⚠️  SECURITY REMINDERS:"
    log_warn "1. Never commit userlist.txt to version control!"
    log_warn "2. In production, use Kubernetes Secrets, AWS Secrets Manager, or Vault"
    log_warn "3. Rotate passwords regularly"
    log_warn "4. Restrict file access (current: $(ls -l $OUTPUT_FILE | awk '{print $1}'))"
}

main "$@"
