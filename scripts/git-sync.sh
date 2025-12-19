#!/bin/bash
#
# git-sync.sh - Git Workflow Automation Script
#
# Automates the git commit → update → push workflow with support for:
# - Automatic or manual commit messages
# - Rebase or merge update strategies
# - Optional PR creation via GitHub CLI
#
# Usage: ./scripts/git-sync.sh [options]
#
# Options:
#   -m, --message <msg>     Commit message (required for commit)
#   -a, --all               Stage all changes before commit
#   -r, --rebase            Use rebase instead of merge for update
#   -b, --branch <branch>   Target branch for update (default: main)
#   -p, --pr                Create a pull request after push
#   --pr-title <title>      PR title (defaults to last commit message)
#   --pr-body <body>        PR body/description
#   --draft                 Create PR as draft
#   -n, --no-push           Skip push step
#   -f, --force             Force push (use with caution)
#   -v, --verbose           Enable verbose output
#   -h, --help              Show this help message
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
COMMIT_MESSAGE=""
STAGE_ALL=false
USE_REBASE=false
TARGET_BRANCH="main"
CREATE_PR=false
PR_TITLE=""
PR_BODY=""
DRAFT_PR=false
SKIP_PUSH=false
FORCE_PUSH=false
VERBOSE=false
NO_COMMIT=false

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_step() { echo -e "${CYAN}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✖ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${CYAN}  → $1${NC}"
    fi
}

show_help() {
    head -30 "$0" | grep -E '^#' | sed 's/^# //' | sed 's/^#//'
    exit 0
}

check_git_repo() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        print_error "Not inside a git repository"
        exit 1
    fi
}

has_staged_changes() {
    ! git diff --cached --quiet 2>/dev/null
}

get_current_branch() {
    git branch --show-current
}

branch_exists_on_remote() {
    git ls-remote --heads origin "$1" | grep -q "$1"
}

do_commit() {
    print_header "STEP 1: Commit Changes"

    if [[ "$STAGE_ALL" == true ]]; then
        print_step "Staging all changes..."
        git add -A
        print_success "All changes staged"
    fi

    if ! has_staged_changes; then
        print_warning "No staged changes to commit"
        return 0
    fi

    print_step "Changes to be committed:"
    git diff --cached --stat
    echo ""

    print_step "Creating commit..."
    local full_message="${COMMIT_MESSAGE}

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

    git commit -m "$full_message"
    print_success "Changes committed successfully"
}

do_update() {
    print_header "STEP 2: Update from Remote"

    print_step "Fetching latest changes from origin..."
    git fetch origin
    print_success "Fetched latest changes"

    if ! branch_exists_on_remote "$TARGET_BRANCH"; then
        print_warning "Branch '$TARGET_BRANCH' does not exist on remote"
        return 0
    fi

    local current_branch
    current_branch=$(get_current_branch)

    if [[ "$current_branch" == "$TARGET_BRANCH" ]]; then
        print_step "Updating $TARGET_BRANCH..."
        if [[ "$USE_REBASE" == true ]]; then
            git pull --rebase origin "$TARGET_BRANCH"
        else
            git pull origin "$TARGET_BRANCH"
        fi
    else
        print_step "Updating current branch from $TARGET_BRANCH..."
        if [[ "$USE_REBASE" == true ]]; then
            git rebase "origin/$TARGET_BRANCH"
        else
            git merge "origin/$TARGET_BRANCH" --no-edit
        fi
    fi

    print_success "Branch updated successfully"
}

do_push() {
    print_header "STEP 3: Push to Remote"

    local current_branch
    current_branch=$(get_current_branch)

    print_step "Pushing to origin/$current_branch..."

    local push_args=("-u" "origin" "$current_branch")

    if [[ "$FORCE_PUSH" == true ]]; then
        print_warning "Force pushing (--force-with-lease)..."
        push_args=("--force-with-lease" "${push_args[@]}")
    fi

    git push "${push_args[@]}"
    print_success "Pushed to origin/$current_branch"
}

do_create_pr() {
    print_header "STEP 4: Create Pull Request"

    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        exit 1
    fi

    if ! gh auth status &> /dev/null; then
        print_error "Not authenticated with GitHub CLI"
        exit 1
    fi

    local current_branch
    current_branch=$(get_current_branch)

    if [[ "$current_branch" == "$TARGET_BRANCH" ]]; then
        print_error "Cannot create PR from $TARGET_BRANCH to itself"
        exit 1
    fi

    if [[ -z "$PR_TITLE" ]]; then
        PR_TITLE=$(git log -1 --format=%s)
    fi

    if [[ -z "$PR_BODY" ]]; then
        local commits
        commits=$(git log "origin/$TARGET_BRANCH..HEAD" --format="- %s" 2>/dev/null || git log -5 --format="- %s")
        PR_BODY="## Summary
$commits

## Test plan
- [ ] Tested locally

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
    fi

    print_step "Creating pull request..."

    local pr_args=("--title" "$PR_TITLE" "--body" "$PR_BODY" "--base" "$TARGET_BRANCH")

    if [[ "$DRAFT_PR" == true ]]; then
        pr_args+=("--draft")
    fi

    local pr_url
    pr_url=$(gh pr create "${pr_args[@]}")

    print_success "Pull request created!"
    echo ""
    print_info "PR URL: $pr_url"
}

show_summary() {
    print_header "Summary"

    local current_branch
    current_branch=$(get_current_branch)

    echo -e "  Branch:  ${GREEN}$current_branch${NC}"
    echo -e "  Remote:  ${GREEN}origin/$current_branch${NC}"

    if [[ -n "$COMMIT_MESSAGE" ]]; then
        echo -e "  Commit:  ${GREEN}$COMMIT_MESSAGE${NC}"
    fi

    if [[ "$CREATE_PR" == true ]]; then
        echo -e "  PR:      ${GREEN}Created${NC}"
    fi

    echo ""
    print_success "Git sync completed successfully!"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--message) COMMIT_MESSAGE="$2"; shift 2 ;;
            -a|--all) STAGE_ALL=true; shift ;;
            -r|--rebase) USE_REBASE=true; shift ;;
            -b|--branch) TARGET_BRANCH="$2"; shift 2 ;;
            -p|--pr) CREATE_PR=true; shift ;;
            --pr-title) PR_TITLE="$2"; shift 2 ;;
            --pr-body) PR_BODY="$2"; shift 2 ;;
            --draft) DRAFT_PR=true; shift ;;
            -n|--no-push) SKIP_PUSH=true; shift ;;
            --no-commit) NO_COMMIT=true; shift ;;
            -f|--force) FORCE_PUSH=true; shift ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help) show_help ;;
            *) print_error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

main() {
    parse_args "$@"

    print_header "Git Sync - Commit → Update → Push"

    check_git_repo

    local current_branch
    current_branch=$(get_current_branch)
    print_info "Current branch: $current_branch"
    print_info "Target branch: $TARGET_BRANCH"
    echo ""

    if [[ "$NO_COMMIT" != true ]] && [[ -n "$COMMIT_MESSAGE" || "$STAGE_ALL" == true ]]; then
        if [[ -z "$COMMIT_MESSAGE" ]]; then
            print_error "Please provide a commit message with -m/--message"
            exit 1
        fi
        do_commit
    fi

    do_update

    if [[ "$SKIP_PUSH" != true ]]; then
        do_push
    fi

    if [[ "$CREATE_PR" == true ]]; then
        do_create_pr
    fi

    show_summary
}

main "$@"
