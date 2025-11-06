#!/bin/bash
# ==============================================
# Nova Backend - Deployment Setup Verification
# ==============================================
# Verifies all deployment configuration files are in place

set -euo pipefail

echo "🔍 Nova Backend - Deployment Setup Verification"
echo "=============================================="
echo ""

ERRORS=0

# Check core files
echo "📦 Checking Core Files..."
files=(
  "Dockerfile.template"
  ".env.example"
  "docker-compose.prod.yml"
  "DEPLOYMENT_GUIDE.md"
  "DEPLOYMENT_CHECKLIST.md"
  "DEPLOYMENT_FILES_SUMMARY.md"
)

for file in "${files[@]}"; do
  if [[ -f "$file" ]]; then
    echo "  ✅ $file"
  else
    echo "  ❌ MISSING: $file"
    ((ERRORS++))
  fi
done

echo ""

# Check Kubernetes structure
echo "☸️  Checking Kubernetes Files..."
k8s_files=(
  "k8s/README.md"
  "k8s/generate-manifests.sh"
  "k8s/base/namespace.yaml"
  "k8s/base/configmap.yaml"
  "k8s/base/auth-service.yaml"
  "k8s/base/kustomization.yaml"
  "k8s/overlays/prod/kustomization.yaml"
)

for file in "${k8s_files[@]}"; do
  if [[ -f "$file" ]]; then
    echo "  ✅ $file"
  else
    echo "  ❌ MISSING: $file"
    ((ERRORS++))
  fi
done

echo ""

# Check monitoring files
echo "📊 Checking Monitoring Files..."
monitoring_files=(
  "monitoring/prometheus/prometheus.yml"
  "monitoring/prometheus/rules/alerts.yml"
  "monitoring/grafana/dashboards/nova-overview.json"
)

for file in "${monitoring_files[@]}"; do
  if [[ -f "$file" ]]; then
    echo "  ✅ $file"
  else
    echo "  ❌ MISSING: $file"
    ((ERRORS++))
  fi
done

echo ""

# Check executable permissions
echo "🔐 Checking Execute Permissions..."
scripts=(
  "k8s/generate-manifests.sh"
)

for script in "${scripts[@]}"; do
  if [[ -x "$script" ]]; then
    echo "  ✅ $script (executable)"
  else
    echo "  ⚠️  $script (not executable, fixing...)"
    chmod +x "$script"
    echo "     ✅ Fixed"
  fi
done

echo ""

# Validate YAML files
echo "📝 Validating YAML Syntax..."
if command -v yamllint &> /dev/null; then
  for yaml in k8s/base/*.yaml k8s/overlays/prod/*.yaml monitoring/prometheus/*.yml; do
    if [[ -f "$yaml" ]]; then
      if yamllint -d relaxed "$yaml" &> /dev/null; then
        echo "  ✅ $yaml"
      else
        echo "  ❌ INVALID YAML: $yaml"
        ((ERRORS++))
      fi
    fi
  done
else
  echo "  ⚠️  yamllint not installed, skipping YAML validation"
  echo "     Install with: pip install yamllint"
fi

echo ""

# Check .env.example completeness
echo "⚙️  Checking .env.example Configuration..."
required_vars=(
  "DATABASE_URL"
  "REDIS_URL"
  "KAFKA_BROKERS"
  "JWT_PRIVATE_KEY_PEM"
  "JWT_PUBLIC_KEY_PEM"
  "AWS_S3_BUCKET"
  "GRPC_AUTH_SERVICE_URL"
  "GRPC_USER_SERVICE_URL"
)

for var in "${required_vars[@]}"; do
  if grep -q "^${var}=" .env.example; then
    echo "  ✅ $var"
  else
    echo "  ❌ MISSING: $var in .env.example"
    ((ERRORS++))
  fi
done

echo ""

# Summary
echo "=============================================="
if [[ $ERRORS -eq 0 ]]; then
  echo "✅ All deployment configuration files are in place!"
  echo ""
  echo "Next steps:"
  echo "  1. Review DEPLOYMENT_GUIDE.md"
  echo "  2. Copy .env.example to .env and configure"
  echo "  3. Test Docker Compose: docker-compose -f docker-compose.prod.yml up -d"
  echo "  4. Generate K8s manifests: cd k8s && ./generate-manifests.sh"
  echo "  5. Follow DEPLOYMENT_CHECKLIST.md for production deployment"
  exit 0
else
  echo "❌ Found $ERRORS error(s). Please fix the issues above."
  exit 1
fi
