#!/bin/bash

#################################################################################
# Phase 4 Deployment Progress Monitor
#
# Usage:
#   ./scripts/phase4-deployment-progress.sh              # Watch mode (auto-refresh)
#   ./scripts/phase4-deployment-progress.sh --once       # Single check
#   ./scripts/phase4-deployment-progress.sh --json       # JSON output
#   ./scripts/phase4-deployment-progress.sh --follow-logs # Follow pod logs
#
#################################################################################

set -euo pipefail

# Configuration
GITHUB_OWNER="proerror77"
GITHUB_REPO="Nova"
WORKFLOW_NAME="phase4-staging-deployment.yml"
K8S_NAMESPACE="nova-staging"
REFRESH_INTERVAL=5  # seconds
WATCH_MODE=true
OUTPUT_FORMAT="human"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#################################################################################
# Functions
#################################################################################

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[⚠]${NC} $*"
}

print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     Phase 4 GraphQL Gateway Staging Deployment       ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Get latest workflow run for Phase 4 deployment
get_latest_workflow_run() {
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) not installed. Install from https://cli.github.com"
        return 1
    fi

    local status_filter="$1"
    gh run list \
        --repo "$GITHUB_OWNER/$GITHUB_REPO" \
        --workflow "$WORKFLOW_NAME" \
        --status "$status_filter" \
        --limit 1 \
        --json id,status,conclusion,createdAt,url \
        --jq '.[0]'
}

# Get all jobs for a workflow run
get_workflow_jobs() {
    local run_id="$1"
    gh run view "$run_id" \
        --repo "$GITHUB_OWNER/$GITHUB_REPO" \
        --json jobs \
        --jq '.jobs[] | {name: .name, status: .status, conclusion: .conclusion}'
}

# Calculate progress percentage
calculate_progress() {
    local completed=0
    local total=0

    while IFS= read -r job; do
        total=$((total + 1))
        local status=$(echo "$job" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        if [ "$status" = "completed" ]; then
            completed=$((completed + 1))
        fi
    done <<< "$1"

    if [ $total -eq 0 ]; then
        echo "0"
    else
        echo $((completed * 100 / total))
    fi
}

# Display progress bar
show_progress_bar() {
    local percentage="$1"
    local width=40
    local filled=$((percentage * width / 100))

    printf "Progress: ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%$((width - filled))s" | tr ' ' '░'
    printf "] %3d%%\n" "$percentage"
}

# Get Kubernetes pod status
get_k8s_pod_status() {
    if ! command -v kubectl &> /dev/null; then
        warning "kubectl not installed, skipping K8s status"
        return 1
    fi

    echo ""
    log "Kubernetes Pod Status:"
    kubectl get pods -n "$K8S_NAMESPACE" -l app=graphql-gateway \
        -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[?(@.type==\"Ready\")].status,AGE:.metadata.creationTimestamp \
        2>/dev/null || warning "Cannot access K8s cluster"
}

# Display workflow status
display_workflow_status() {
    print_header

    log "Fetching latest deployment status..."
    echo ""

    # Get in-progress deployment first
    local run=$(get_latest_workflow_run "in_progress" || echo "")

    if [ -z "$run" ] || [ "$run" = "null" ]; then
        # Try to get completed deployment
        run=$(get_latest_workflow_run "completed")
    fi

    if [ -z "$run" ] || [ "$run" = "null" ]; then
        warning "No Phase 4 deployment found"
        return 1
    fi

    # Parse run information
    local run_id=$(echo "$run" | grep -o '"id":[0-9]*' | cut -d':' -f2)
    local status=$(echo "$run" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    local conclusion=$(echo "$run" | grep -o '"conclusion":"[^"]*"' | cut -d'"' -f4)
    local created_at=$(echo "$run" | grep -o '"createdAt":"[^"]*"' | cut -d'"' -f4)
    local url=$(echo "$run" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)

    # Display run information
    echo -e "${CYAN}📦 Deployment Information${NC}"
    echo "  Run ID: ${BLUE}${run_id}${NC}"
    echo "  Status: $(get_status_emoji "$status" "$conclusion") ${status^^}"
    if [ -n "$conclusion" ] && [ "$conclusion" != "null" ]; then
        echo "  Result: $(get_conclusion_emoji "$conclusion") ${conclusion^^}"
    fi
    echo "  Started: ${YELLOW}${created_at}${NC}"
    echo "  URL: ${BLUE}${url}${NC}"
    echo ""

    # Get and display job status
    log "Fetching job status..."
    local jobs=$(get_workflow_jobs "$run_id")

    echo -e "${CYAN}📋 Job Status${NC}"
    local completed=0
    local failed=0
    local in_progress=0
    local total=0

    while IFS= read -r -u 3 job; do
        local job_name=$(echo "$job" | jq -r '.name // "Unknown"' 2>/dev/null)
        local job_status=$(echo "$job" | jq -r '.status // "unknown"' 2>/dev/null)
        local job_conclusion=$(echo "$job" | jq -r '.conclusion // ""' 2>/dev/null)

        total=$((total + 1))

        case "$job_status" in
            completed)
                completed=$((completed + 1))
                if [ "$job_conclusion" = "success" ]; then
                    echo "  $(success) $job_name"
                else
                    echo "  $(error) $job_name (${job_conclusion})"
                    failed=$((failed + 1))
                fi
                ;;
            in_progress)
                in_progress=$((in_progress + 1))
                echo "  🔄 $job_name"
                ;;
            queued)
                echo "  ⏳ $job_name"
                ;;
            *)
                echo "  ❓ $job_name ($job_status)"
                ;;
        esac
    done 3<<< "$jobs"

    echo ""

    # Show progress
    local percentage=$((completed * 100 / total))
    show_progress_bar "$percentage"
    echo "  $completed / $total jobs completed"
    if [ $failed -gt 0 ]; then
        echo -e "  ${RED}$failed failed${NC}"
    fi
    echo ""

    # Show next steps
    case "$status:$conclusion" in
        in_progress:*)
            echo -e "${CYAN}⏳ Status: Deployment In Progress${NC}"
            echo "  • Waiting for $in_progress job(s) to complete"
            echo "  • Check back in ${REFRESH_INTERVAL}s for updates"
            ;;
        completed:success)
            echo -e "${GREEN}✅ Status: Deployment Successful${NC}"
            echo "  • All jobs completed successfully"
            echo ""
            echo -e "${CYAN}🎯 Next Steps:${NC}"
            echo "  1. Verify pod status: kubectl get pods -n $K8S_NAMESPACE"
            echo "  2. Port-forward: kubectl port-forward -n $K8S_NAMESPACE svc/graphql-gateway 8080:80"
            echo "  3. Test health: curl http://localhost:8080/health"
            echo "  4. Review logs: kubectl logs -n $K8S_NAMESPACE -l app=graphql-gateway"
            get_k8s_pod_status
            ;;
        completed:failure)
            echo -e "${RED}❌ Status: Deployment Failed${NC}"
            echo "  • $failed job(s) failed"
            echo ""
            echo -e "${CYAN}🔍 Troubleshooting:${NC}"
            echo "  1. View workflow logs: gh run view $run_id --log"
            echo "  2. Check specific job: gh run view $run_id --log --job <job_id>"
            echo "  3. Review error details: $url"
            ;;
    esac

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ "$WATCH_MODE" = "true" ] && [ "$status" = "in_progress" ]; then
        echo "Refreshing in ${REFRESH_INTERVAL}s... (Press Ctrl+C to exit)"
    fi
}

# Get status emoji
get_status_emoji() {
    local status="$1"
    local conclusion="$2"

    case "$status" in
        in_progress) echo "🔄" ;;
        completed)
            case "$conclusion" in
                success) echo "✅" ;;
                failure) echo "❌" ;;
                *) echo "⚠️" ;;
            esac
            ;;
        queued) echo "⏳" ;;
        *) echo "❓" ;;
    esac
}

# Get conclusion emoji
get_conclusion_emoji() {
    local conclusion="$1"
    case "$conclusion" in
        success) echo "✅" ;;
        failure) echo "❌" ;;
        cancelled) echo "🚫" ;;
        skipped) echo "⏭️" ;;
        *) echo "❓" ;;
    esac
}

# Follow pod logs
follow_pod_logs() {
    if ! command -v kubectl &> /dev/null; then
        error "kubectl not installed"
        return 1
    fi

    log "Following GraphQL Gateway pod logs..."
    kubectl logs -n "$K8S_NAMESPACE" -l app=graphql-gateway -f --tail=50
}

# Main watch loop
watch_deployment() {
    while true; do
        display_workflow_status

        if [ "$WATCH_MODE" = "false" ]; then
            break
        fi

        sleep "$REFRESH_INTERVAL"
    done
}

# JSON output
json_output() {
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) not installed"
        return 1
    fi

    gh run list \
        --repo "$GITHUB_OWNER/$GITHUB_REPO" \
        --workflow "$WORKFLOW_NAME" \
        --limit 1 \
        --json id,status,conclusion,createdAt,updatedAt,url,headBranch,headSha
}

#################################################################################
# Main
#################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --once)
                WATCH_MODE=false
                shift
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            --follow-logs)
                follow_pod_logs
                exit $?
                ;;
            --help)
                cat <<EOF
Usage: $0 [options]

Options:
  --once            Show status once and exit
  --json            Output JSON format
  --follow-logs     Follow pod logs in real-time
  --help            Show this help message

Default behavior: Watch mode with auto-refresh every ${REFRESH_INTERVAL}s

Examples:
  # Watch deployment progress (auto-refresh)
  $0

  # Single status check
  $0 --once

  # Follow logs
  $0 --follow-logs

  # Get JSON data for programmatic access
  $0 --json
EOF
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Execute based on format
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        json_output
    else
        watch_deployment
    fi
}

main "$@"
