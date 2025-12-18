#!/bin/bash
# Nova Social Platform - Development Environment Setup
# Usage: ./scripts/setup-dev-environment.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# Check Prerequisites
# ============================================================
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    # Required tools
    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v rustc >/dev/null 2>&1 || missing+=("rust (install via rustup)")
    command -v cargo >/dev/null 2>&1 || missing+=("cargo")
    command -v docker >/dev/null 2>&1 || missing+=("docker")
    command -v kubectl >/dev/null 2>&1 || missing+=("kubectl")

    # Optional but recommended
    command -v protoc >/dev/null 2>&1 || log_warn "protoc not found - needed for proto compilation"
    command -v gcloud >/dev/null 2>&1 || log_warn "gcloud not found - needed for GCP deployment"

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools:"
        for tool in "${missing[@]}"; do
            echo "  - $tool"
        done
        exit 1
    fi

    log_success "All required prerequisites installed"
}

# ============================================================
# Install Rust Tools
# ============================================================
install_rust_tools() {
    log_info "Installing Rust development tools..."

    # Rust components
    rustup component add clippy rustfmt 2>/dev/null || log_warn "Rust components may already be installed"

    # Cargo tools
    local tools=(
        "cargo-watch"
        "cargo-audit"
        "cargo-deny"
        "cargo-nextest"
    )

    for tool in "${tools[@]}"; do
        if ! command -v "${tool/cargo-/}" >/dev/null 2>&1; then
            log_info "Installing $tool..."
            cargo install "$tool" --quiet || log_warn "Failed to install $tool"
        else
            log_info "$tool already installed"
        fi
    done

    log_success "Rust tools installed"
}

# ============================================================
# Setup Pre-commit Hooks
# ============================================================
setup_precommit() {
    log_info "Setting up pre-commit hooks..."

    # Check if pre-commit is installed
    if ! command -v pre-commit >/dev/null 2>&1; then
        log_info "Installing pre-commit..."
        if command -v pip3 >/dev/null 2>&1; then
            pip3 install pre-commit --quiet
        elif command -v pip >/dev/null 2>&1; then
            pip install pre-commit --quiet
        elif command -v brew >/dev/null 2>&1; then
            brew install pre-commit
        else
            log_error "Cannot install pre-commit. Please install manually."
            return 1
        fi
    fi

    # Install hooks
    pre-commit install
    pre-commit install --hook-type commit-msg

    log_success "Pre-commit hooks installed"
}

# ============================================================
# Setup iOS Development (macOS only)
# ============================================================
setup_ios() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_info "Skipping iOS setup (not on macOS)"
        return 0
    fi

    log_info "Setting up iOS development environment..."

    # Check Xcode
    if ! xcode-select -p >/dev/null 2>&1; then
        log_warn "Xcode not found. Please install from App Store."
        return 1
    fi

    # Install SwiftLint
    if ! command -v swiftlint >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then
            log_info "Installing SwiftLint..."
            brew install swiftlint
        else
            log_warn "Homebrew not found. Please install SwiftLint manually."
        fi
    else
        log_info "SwiftLint already installed"
    fi

    # Install swift-format
    if ! command -v swift-format >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then
            log_info "Installing swift-format..."
            brew install swift-format
        fi
    fi

    log_success "iOS development environment ready"
}

# ============================================================
# Setup Environment Variables
# ============================================================
setup_environment() {
    log_info "Setting up environment variables..."

    # Create .env.local if it doesn't exist
    if [ ! -f ".env.local" ]; then
        cat > .env.local << 'EOF'
# Nova Social Platform - Local Development Environment
# Copy this file and update values as needed

# Application
APP_ENV=development
LOG_LEVEL=debug
RUST_LOG=info

# Database
DATABASE_URL=postgres://nova:nova@localhost:5432/nova_dev

# Redis
REDIS_URL=redis://localhost:6379

# GCP (for cloud development)
# GCP_PROJECT_ID=your-project-id
# GCP_REGION=asia-northeast1

# AWS (alternative cloud)
# AWS_REGION=ap-northeast-1
# AWS_ACCOUNT_ID=your-account-id

# Secrets (use local values for development)
# JWT_SECRET=dev-secret-key-change-in-production
EOF
        log_success "Created .env.local - please update with your values"
    else
        log_info ".env.local already exists"
    fi
}

# ============================================================
# Setup Local Services (Docker Compose)
# ============================================================
setup_local_services() {
    log_info "Setting up local development services..."

    # Check for docker-compose.dev.yml
    if [ -f "docker-compose.dev.yml" ]; then
        log_info "Starting local services..."
        docker compose -f docker-compose.dev.yml up -d || {
            log_warn "Failed to start some services"
        }
    else
        log_warn "docker-compose.dev.yml not found. Creating basic template..."
        cat > docker-compose.dev.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: nova
      POSTGRES_PASSWORD: nova
      POSTGRES_DB: nova_dev
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data

volumes:
  postgres_data:
  redis_data:
  minio_data:
EOF
        log_success "Created docker-compose.dev.yml"
    fi
}

# ============================================================
# Verify Setup
# ============================================================
verify_setup() {
    log_info "Verifying development environment..."

    local checks_passed=0
    local checks_total=0

    # Check Rust
    ((checks_total++))
    if cargo check --manifest-path backend/Cargo.toml >/dev/null 2>&1; then
        log_success "Rust project compiles"
        ((checks_passed++))
    else
        log_warn "Rust project has compilation issues"
    fi

    # Check pre-commit
    ((checks_total++))
    if [ -f ".git/hooks/pre-commit" ]; then
        log_success "Pre-commit hooks installed"
        ((checks_passed++))
    else
        log_warn "Pre-commit hooks not installed"
    fi

    # Check Docker
    ((checks_total++))
    if docker info >/dev/null 2>&1; then
        log_success "Docker is running"
        ((checks_passed++))
    else
        log_warn "Docker is not running"
    fi

    echo ""
    log_info "Verification: $checks_passed/$checks_total checks passed"
}

# ============================================================
# Print Next Steps
# ============================================================
print_next_steps() {
    echo ""
    echo "============================================================"
    echo -e "${GREEN}Development Environment Setup Complete!${NC}"
    echo "============================================================"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Update .env.local with your configuration"
    echo "   vi .env.local"
    echo ""
    echo "2. Start local services:"
    echo "   docker compose -f docker-compose.dev.yml up -d"
    echo ""
    echo "3. Run backend services:"
    echo "   cd backend && cargo run -p identity-service"
    echo ""
    echo "4. Run iOS app (macOS only):"
    echo "   open ios/NovaSocial/ICERED.xcodeproj"
    echo ""
    echo "5. Run tests:"
    echo "   cd backend && cargo nextest run"
    echo ""
    echo "============================================================"
    echo "Useful commands:"
    echo "  cargo watch -x check          # Auto-check on file changes"
    echo "  cargo clippy --all-targets    # Run linter"
    echo "  pre-commit run --all-files    # Run all pre-commit hooks"
    echo "============================================================"
}

# ============================================================
# Main
# ============================================================
main() {
    echo ""
    echo "============================================================"
    echo "Nova Social Platform - Development Environment Setup"
    echo "============================================================"
    echo ""

    check_prerequisites
    install_rust_tools
    setup_precommit
    setup_ios
    setup_environment
    setup_local_services
    verify_setup
    print_next_steps
}

main "$@"
