#!/bin/bash

# Interactive helper to fix unwraps
# Usage: ./scripts/fix-unwrap-helper.sh [file]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ $# -eq 0 ]; then
    echo "Usage: $0 <file.rs>"
    echo ""
    echo "This script helps you fix unwrap() calls interactively"
    echo ""
    echo "Example: $0 src/main.rs"
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo -e "${RED}Error: File not found: $FILE${NC}"
    exit 1
fi

# Find all unwraps in the file
UNWRAPS=$(grep -n "\.unwrap()" "$FILE" || true)

if [ -z "$UNWRAPS" ]; then
    echo -e "${GREEN}✅ No unwraps found in $FILE${NC}"
    exit 0
fi

COUNT=$(echo "$UNWRAPS" | wc -l)
echo -e "${YELLOW}Found $COUNT unwrap() calls in $FILE${NC}"
echo ""

echo "$UNWRAPS" | while IFS=: read -r line_num line_content; do
    echo -e "${BLUE}=== Line $line_num ===${NC}"
    echo -e "${RED}$line_content${NC}"
    echo ""

    # Show context (2 lines before and after)
    echo "Context:"
    sed -n "$((line_num - 2)),$((line_num + 2))p" "$FILE" | cat -n
    echo ""

    # Suggest fixes based on pattern
    echo -e "${GREEN}Suggested fixes:${NC}"

    if echo "$line_content" | grep -q "env::var"; then
        echo "1. Environment variable pattern:"
        echo '   .context("ENV_VAR_NAME environment variable not set")?'
        echo ""
    fi

    if echo "$line_content" | grep -q "serde_json"; then
        echo "1. JSON parsing pattern:"
        echo '   .context("Failed to parse JSON")?'
        echo ""
    fi

    if echo "$line_content" | grep -q "lock\(\)"; then
        echo "1. Mutex lock pattern:"
        echo '   .expect("Mutex poisoned - should never happen")'
        echo '   OR'
        echo '   .map_err(|e| anyhow!("Mutex poisoned: {}", e))?'
        echo ""
    fi

    if echo "$line_content" | grep -q "\.get\("; then
        echo "1. Option pattern:"
        echo '   .ok_or_else(|| anyhow!("Key not found"))?'
        echo '   OR'
        echo '   .unwrap_or_default()'
        echo ""
    fi

    if echo "$line_content" | grep -q "parse\|from_str"; then
        echo "1. String parsing pattern:"
        echo '   .context("Failed to parse value")?'
        echo '   OR'
        echo '   .map_err(|e| anyhow!("Parse error: {}", e))?'
        echo ""
    fi

    # Generic suggestions
    echo "Generic options:"
    echo "  a) Add .context('helpful message')?"
    echo "  b) Use .map_err(|e| anyhow!('error: {}', e))?"
    echo "  c) Use .unwrap_or_default() if default makes sense"
    echo "  d) Use .expect('message') if panic is truly acceptable"
    echo "  e) Skip this one for now"
    echo ""

    echo -e "${YELLOW}Press Enter to continue to next unwrap...${NC}"
    read -r
    echo ""
done

echo -e "${GREEN}=== Summary ===${NC}"
echo "Total unwraps reviewed: $COUNT"
echo ""
echo "Next steps:"
echo "1. Edit the file: $FILE"
echo "2. Apply the suggested fixes"
echo "3. Run tests: cargo test"
echo "4. Check with clippy: cargo clippy"
echo "5. Commit: git add $FILE && git commit -m 'fix: remove unwrap() calls'"