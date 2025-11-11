#!/bin/bash

# Generate detailed report of unwrap() usage by severity
# Usage: ./scripts/unwrap-report.sh

set -euo pipefail

OUTPUT_FILE="unwrap-analysis.md"

echo "# Unwrap() Analysis Report" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Function to analyze unwraps by category
analyze_category() {
    local pattern="$1"
    local title="$2"
    local priority="$3"

    echo "## $priority: $title" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    results=$(grep -rn "\.unwrap()" --include="*.rs" . 2>/dev/null | \
              grep -v "test" | \
              grep -v "target" | \
              grep -v "build.rs" | \
              grep "$pattern" || true)

    if [ -n "$results" ]; then
        count=$(echo "$results" | wc -l)
        echo "**Count**: $count" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "### Files:" >> "$OUTPUT_FILE"
        echo '```' >> "$OUTPUT_FILE"
        echo "$results" | head -20 >> "$OUTPUT_FILE"
        if [ "$count" -gt 20 ]; then
            echo "... and $((count - 20)) more" >> "$OUTPUT_FILE"
        fi
        echo '```' >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        echo "**Count**: 0 ✅" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
}

# P0: Critical paths that could crash services
echo "Analyzing critical paths..."
analyze_category "main\.rs\|lib\.rs\|error\.rs" \
                 "Critical Service Entry Points" \
                 "P0 (Critical)"

# P1: Network/IO operations
echo "Analyzing I/O operations..."
analyze_category "redis\|postgres\|http\|grpc\|kafka" \
                 "Network and I/O Operations" \
                 "P1 (High)"

# P1: Authentication/Authorization
echo "Analyzing auth paths..."
analyze_category "auth\|jwt\|token\|permission" \
                 "Authentication and Authorization" \
                 "P1 (High)"

# P2: Business logic
echo "Analyzing business logic..."
analyze_category "service\|handler\|controller" \
                 "Business Logic Handlers" \
                 "P2 (Medium)"

# P3: Utilities and helpers
echo "Analyzing utilities..."
grep -rn "\.unwrap()" --include="*.rs" . 2>/dev/null | \
    grep -v "test" | \
    grep -v "target" | \
    grep -v "build.rs" | \
    grep -v "main\.rs" | \
    grep -v "lib\.rs" | \
    grep -v "redis" | \
    grep -v "postgres" | \
    grep -v "http" | \
    grep -v "grpc" | \
    grep -v "auth" | \
    grep -v "service" | \
    grep -v "handler" > /tmp/p3_unwraps.txt || true

if [ -s /tmp/p3_unwraps.txt ]; then
    count=$(wc -l < /tmp/p3_unwraps.txt)
    echo "## P3 (Low): Utility Functions and Helpers" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**Count**: $count" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

# Summary statistics
echo "## Summary" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

total=$(grep -rn "\.unwrap()" --include="*.rs" . 2>/dev/null | \
        grep -v "test" | \
        grep -v "target" | \
        grep -v "build.rs" | \
        wc -l)

echo "**Total unwrap() calls in production code**: $total" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# By file type
echo "### By Component" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| Component | Count |" >> "$OUTPUT_FILE"
echo "|-----------|-------|" >> "$OUTPUT_FILE"

for dir in $(find . -maxdepth 2 -type d -name "src" | grep -v target); do
    component=$(dirname "$dir" | sed 's/\.\///')
    if [ "$component" != "." ]; then
        count=$(grep -rn "\.unwrap()" "$dir" 2>/dev/null | \
                grep -v "test" | \
                wc -l || echo "0")
        if [ "$count" -gt 0 ]; then
            echo "| $component | $count |" >> "$OUTPUT_FILE"
        fi
    fi
done

echo "" >> "$OUTPUT_FILE"

# Recommended action plan
echo "## Recommended Action Plan" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "### Phase 1: Critical Fixes (Week 1)" >> "$OUTPUT_FILE"
echo "- [ ] Fix all P0 unwraps in main.rs and lib.rs" >> "$OUTPUT_FILE"
echo "- [ ] Add error handling to all service startup paths" >> "$OUTPUT_FILE"
echo "- [ ] Target: 0 P0 unwraps" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "### Phase 2: High Priority (Week 2-3)" >> "$OUTPUT_FILE"
echo "- [ ] Fix all network/IO unwraps" >> "$OUTPUT_FILE"
echo "- [ ] Fix all authentication unwraps" >> "$OUTPUT_FILE"
echo "- [ ] Target: <10 P1 unwraps" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "### Phase 3: Business Logic (Week 4-5)" >> "$OUTPUT_FILE"
echo "- [ ] Fix service handler unwraps" >> "$OUTPUT_FILE"
echo "- [ ] Add comprehensive error types" >> "$OUTPUT_FILE"
echo "- [ ] Target: <50 P2 unwraps" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "### Phase 4: Cleanup (Week 6+)" >> "$OUTPUT_FILE"
echo "- [ ] Fix remaining utility unwraps" >> "$OUTPUT_FILE"
echo "- [ ] Enable strict Clippy lints" >> "$OUTPUT_FILE"
echo "- [ ] Target: 0 production unwraps" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Common patterns and fixes
echo "## Common Patterns and Recommended Fixes" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "### Pattern 1: Environment Variables" >> "$OUTPUT_FILE"
echo '```rust' >> "$OUTPUT_FILE"
echo '// ❌ Bad' >> "$OUTPUT_FILE"
echo 'let key = env::var("API_KEY").unwrap();' >> "$OUTPUT_FILE"
echo '' >> "$OUTPUT_FILE"
echo '// ✅ Good' >> "$OUTPUT_FILE"
echo 'let key = env::var("API_KEY")' >> "$OUTPUT_FILE"
echo '    .context("API_KEY environment variable not set")?;' >> "$OUTPUT_FILE"
echo '```' >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "### Pattern 2: JSON Parsing" >> "$OUTPUT_FILE"
echo '```rust' >> "$OUTPUT_FILE"
echo '// ❌ Bad' >> "$OUTPUT_FILE"
echo 'let data: Config = serde_json::from_str(&json).unwrap();' >> "$OUTPUT_FILE"
echo '' >> "$OUTPUT_FILE"
echo '// ✅ Good' >> "$OUTPUT_FILE"
echo 'let data: Config = serde_json::from_str(&json)' >> "$OUTPUT_FILE"
echo '    .context("Failed to parse config JSON")?;' >> "$OUTPUT_FILE"
echo '```' >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "### Pattern 3: Lock Guards" >> "$OUTPUT_FILE"
echo '```rust' >> "$OUTPUT_FILE"
echo '// ❌ Bad' >> "$OUTPUT_FILE"
echo 'let data = mutex.lock().unwrap();' >> "$OUTPUT_FILE"
echo '' >> "$OUTPUT_FILE"
echo '// ✅ Good (if poisoning is truly impossible)' >> "$OUTPUT_FILE"
echo 'let data = mutex.lock()' >> "$OUTPUT_FILE"
echo '    .expect("Mutex poisoned - this should never happen");' >> "$OUTPUT_FILE"
echo '' >> "$OUTPUT_FILE"
echo '// ✅ Better (handle poisoning)' >> "$OUTPUT_FILE"
echo 'let data = mutex.lock()' >> "$OUTPUT_FILE"
echo '    .map_err(|e| anyhow!("Mutex poisoned: {}", e))?;' >> "$OUTPUT_FILE"
echo '```' >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "### Pattern 4: Option Unwrapping" >> "$OUTPUT_FILE"
echo '```rust' >> "$OUTPUT_FILE"
echo '// ❌ Bad' >> "$OUTPUT_FILE"
echo 'let user = users.get(&id).unwrap();' >> "$OUTPUT_FILE"
echo '' >> "$OUTPUT_FILE"
echo '// ✅ Good' >> "$OUTPUT_FILE"
echo 'let user = users.get(&id)' >> "$OUTPUT_FILE"
echo '    .ok_or_else(|| anyhow!("User {} not found", id))?;' >> "$OUTPUT_FILE"
echo '```' >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Report generated: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "1. Review the report: cat $OUTPUT_FILE"
echo "2. Create GitHub issues for each priority level"
echo "3. Start with P0 fixes in the next sprint"
echo "4. Track progress with: ./scripts/unwrap-progress.sh"