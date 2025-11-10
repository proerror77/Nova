#!/bin/bash
# Claude Code Native Deployment Progress Monitor
# Monitors Phase 4 staging deployment via GitHub Actions
# This script is designed for Claude Code to call periodically to track progress

set -e

WORKFLOW_NAME="phase4-staging-deployment.yml"
REPO="proerror77/Nova"
BRANCH="main"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the latest workflow run
get_latest_run() {
    gh run list \
        --repo "$REPO" \
        --workflow "$WORKFLOW_NAME" \
        --branch "$BRANCH" \
        --limit 1 \
        --json status,conclusion,databaseId,name,updatedAt \
        --jq '.[0]'
}

# Get detailed job status
get_job_status() {
    local run_id=$1
    gh run view "$run_id" \
        --repo "$REPO" \
        --json jobs \
        --jq '.jobs[] | {name: .name, status: .status, conclusion: .conclusion, number: .number}'
}

# Get job logs
get_job_logs() {
    local run_id=$1
    local job_number=$2
    gh run view "$run_id" \
        --repo "$REPO" \
        --log \
        --job "$job_number" 2>/dev/null || echo "Logs not yet available"
}

# Format status for display
format_status() {
    local status=$1
    case "$status" in
        "completed")
            echo -e "${GREEN}✓ COMPLETED${NC}"
            ;;
        "in_progress")
            echo -e "${BLUE}⟳ IN PROGRESS${NC}"
            ;;
        "queued")
            echo -e "${YELLOW}◐ QUEUED${NC}"
            ;;
        "failed")
            echo -e "${RED}✗ FAILED${NC}"
            ;;
        *)
            echo "$status"
            ;;
    esac
}

# Format conclusion for display
format_conclusion() {
    local conclusion=$1
    case "$conclusion" in
        "success")
            echo -e "${GREEN}SUCCESS${NC}"
            ;;
        "failure")
            echo -e "${RED}FAILURE${NC}"
            ;;
        "cancelled")
            echo -e "${YELLOW}CANCELLED${NC}"
            ;;
        "skipped")
            echo -e "${YELLOW}SKIPPED${NC}"
            ;;
        "")
            echo -e "${YELLOW}IN PROGRESS${NC}"
            ;;
        *)
            echo "$conclusion"
            ;;
    esac
}

# Main monitoring function
monitor_deployment() {
    echo -e "${BLUE}=== Phase 4 Staging Deployment Monitor ===${NC}\n"

    # Get latest run
    run=$(get_latest_run)

    if [ -z "$run" ]; then
        echo -e "${YELLOW}No deployment runs found${NC}"
        return 1
    fi

    run_id=$(echo "$run" | jq -r '.databaseId')
    status=$(echo "$run" | jq -r '.status')
    conclusion=$(echo "$run" | jq -r '.conclusion // "in_progress"')
    updated_at=$(echo "$run" | jq -r '.updatedAt')

    echo -e "Run ID: ${BLUE}$run_id${NC}"
    echo -e "Status: $(format_status $status)"
    echo -e "Conclusion: $(format_conclusion $conclusion)"
    echo -e "Last Updated: $updated_at\n"

    # Get job status
    echo -e "${BLUE}Job Status:${NC}"
    get_job_status "$run_id" | while IFS= read -r line; do
        name=$(echo "$line" | jq -r '.name')
        job_status=$(echo "$line" | jq -r '.status')
        job_conclusion=$(echo "$line" | jq -r '.conclusion // "in_progress"')

        # Format job status display
        if [ "$job_conclusion" != "null" ] && [ -n "$job_conclusion" ]; then
            conclusion_display=$(format_conclusion "$job_conclusion")
            echo -e "  • $name: $conclusion_display"
        else
            status_display=$(format_status "$job_status")
            echo -e "  • $name: $status_display"
        fi
    done

    echo ""

    # Return overall status for scripting
    if [ "$status" = "completed" ]; then
        if [ "$conclusion" = "success" ]; then
            return 0
        else
            return 2
        fi
    else
        return 1
    fi
}

# If --watch flag provided, monitor continuously
if [ "$1" = "--watch" ]; then
    interval=${2:-30}  # Default 30 seconds
    echo "Monitoring deployment every ${interval}s (Ctrl+C to stop)"
    while true; do
        clear
        monitor_deployment
        status=$?

        if [ $status -eq 0 ]; then
            echo -e "\n${GREEN}✓ Deployment completed successfully!${NC}"
            exit 0
        elif [ $status -eq 2 ]; then
            echo -e "\n${RED}✗ Deployment failed. Check logs above.${NC}"
            exit 2
        fi

        sleep "$interval"
    done
else
    # Single check mode
    monitor_deployment
    exit $?
fi
