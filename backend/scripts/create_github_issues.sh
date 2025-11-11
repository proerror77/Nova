#!/bin/bash

# Script to create GitHub issues for all TODOs and unwraps in the codebase
# Usage: ./scripts/create_github_issues.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# GitHub repository (update this with your repo)
REPO="owner/nova"  # UPDATE THIS WITH YOUR REPO

echo -e "${GREEN}=== Backend TODO and Code Quality Issue Tracker ===${NC}"
echo ""

# Function to create GitHub issue
create_issue() {
    local title="$1"
    local body="$2"
    local labels="$3"

    echo -e "${YELLOW}Creating issue: $title${NC}"

    # Using GitHub CLI (gh)
    # Uncomment the line below to actually create issues
    # gh issue create --title "$title" --body "$body" --label "$labels" --repo "$REPO"

    # For now, just output to a file
    echo "---" >> github_issues.md
    echo "Title: $title" >> github_issues.md
    echo "Labels: $labels" >> github_issues.md
    echo "Body:" >> github_issues.md
    echo "$body" >> github_issues.md
    echo "" >> github_issues.md
}

# Initialize output file
echo "# GitHub Issues to Create" > github_issues.md
echo "Generated: $(date)" >> github_issues.md
echo "" >> github_issues.md

# 1. Find all TODO comments
echo -e "${GREEN}Scanning for TODO comments...${NC}"
todos=$(grep -rn "TODO\|todo!()" --include="*.rs" . 2>/dev/null | grep -v target | grep -v ".git" || true)

if [ -n "$todos" ]; then
    echo -e "${YELLOW}Found $(echo "$todos" | wc -l) TODOs${NC}"

    # Group TODOs by file
    echo "$todos" | awk -F: '{print $1}' | sort -u | while read -r file; do
        file_todos=$(echo "$todos" | grep "^$file:")
        todo_count=$(echo "$file_todos" | wc -l)

        title="Fix TODOs in $(basename "$file")"
        body="## File: \`$file\`

### TODOs Found ($todo_count):

\`\`\`
$file_todos
\`\`\`

### Tasks:
- [ ] Review each TODO
- [ ] Implement or convert to GitHub issue
- [ ] Remove completed TODOs
"

        create_issue "$title" "$body" "technical-debt,todo"
    done
fi

# 2. Find all unwrap() calls in non-test code
echo -e "${GREEN}Scanning for unwrap() calls...${NC}"
unwraps=$(grep -rn "\.unwrap()" --include="*.rs" . 2>/dev/null | grep -v "test" | grep -v "#\[cfg(test)\]" | grep -v target | grep -v ".git" || true)

if [ -n "$unwraps" ]; then
    echo -e "${RED}Found $(echo "$unwraps" | wc -l) unwrap() calls in production code${NC}"

    # Group unwraps by severity
    critical_unwraps=$(echo "$unwraps" | grep -E "main\.rs|lib\.rs|mod\.rs" || true)
    other_unwraps=$(echo "$unwraps" | grep -vE "main\.rs|lib\.rs|mod\.rs" || true)

    if [ -n "$critical_unwraps" ]; then
        title="[P0] Fix critical unwrap() calls in main/lib files"
        body="## Critical unwrap() calls that could crash the service

\`\`\`
$critical_unwraps
\`\`\`

### Impact:
These unwrap() calls are in critical paths and could cause service crashes.

### Recommended Fix:
- Use \`.context()\` with anyhow
- Return proper errors
- Use \`.unwrap_or_default()\` where appropriate
"
        create_issue "$title" "$body" "bug,priority-high,security"
    fi

    if [ -n "$other_unwraps" ]; then
        title="[P1] Replace unwrap() calls with proper error handling"
        body="## unwrap() calls in production code

Total: $(echo "$other_unwraps" | wc -l) occurrences

### Sample (first 20):
\`\`\`
$(echo "$other_unwraps" | head -20)
\`\`\`

### Recommended Fix:
- Use \`?\` operator for error propagation
- Use \`.context()\` for better error messages
- Handle errors explicitly where needed
"
        create_issue "$title" "$body" "bug,technical-debt"
    fi
fi

# 3. Find all expect() calls
echo -e "${GREEN}Scanning for expect() calls...${NC}"
expects=$(grep -rn "\.expect(" --include="*.rs" . 2>/dev/null | grep -v "test" | grep -v "#\[cfg(test)\]" | grep -v target | grep -v ".git" || true)

if [ -n "$expects" ]; then
    echo -e "${YELLOW}Found $(echo "$expects" | wc -l) expect() calls${NC}"

    title="[P2] Review expect() calls for better error messages"
    body="## expect() calls in production code

Total: $(echo "$expects" | wc -l) occurrences

### Sample (first 20):
\`\`\`
$(echo "$expects" | head -20)
\`\`\`

### Tasks:
- [ ] Review each expect() message for clarity
- [ ] Consider replacing with proper error handling
- [ ] Ensure messages are helpful for debugging
"
    create_issue "$title" "$body" "enhancement,technical-debt"
fi

# 4. Find hardcoded values
echo -e "${GREEN}Scanning for hardcoded values...${NC}"
hardcoded=$(grep -rn "127\.0\.0\.1\|localhost\|8080\|3000\|5432\|6379" --include="*.rs" . 2>/dev/null | grep -v "test" | grep -v "example" | grep -v target | grep -v ".git" || true)

if [ -n "$hardcoded" ]; then
    echo -e "${YELLOW}Found potential hardcoded values${NC}"

    title="[P2] Replace hardcoded values with configuration"
    body="## Potential hardcoded values found

\`\`\`
$(echo "$hardcoded" | head -20)
\`\`\`

### Recommended Fix:
- Move to environment variables
- Use configuration files
- Implement proper config management
"
    create_issue "$title" "$body" "enhancement,configuration"
fi

# 5. Security scan for sensitive patterns
echo -e "${GREEN}Scanning for security issues...${NC}"
security=$(grep -rn "password\|secret\|key\|token" --include="*.rs" . 2>/dev/null | grep -v "test" | grep -v "// " | grep -v target | grep -v ".git" | grep "=" || true)

if [ -n "$security" ]; then
    echo -e "${RED}Found potential security issues${NC}"

    title="[P0] Security: Review potential hardcoded secrets"
    body="## Potential security issues found

**⚠️ Manual review required - may be false positives**

\`\`\`
$(echo "$security" | head -10)
\`\`\`

### Actions Required:
- [ ] Review each match
- [ ] Move secrets to environment variables
- [ ] Use secret management service
- [ ] Rotate any exposed secrets
"
    create_issue "$title" "$body" "security,priority-critical"
fi

# Summary
echo ""
echo -e "${GREEN}=== Summary ===${NC}"
echo "Issues have been written to: github_issues.md"
echo ""
echo "To create these issues on GitHub:"
echo "1. Install GitHub CLI: https://cli.github.com/"
echo "2. Update the REPO variable in this script"
echo "3. Uncomment the 'gh issue create' line in the create_issue function"
echo "4. Run: ./scripts/create_github_issues.sh"
echo ""
echo -e "${YELLOW}Review github_issues.md before creating issues to avoid duplicates${NC}"