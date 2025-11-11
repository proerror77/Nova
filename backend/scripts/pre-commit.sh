#!/bin/bash

# Pre-commit hook to check code quality
# Install: ln -s ../../backend/scripts/pre-commit.sh .git/hooks/pre-commit

set -e

echo "🔍 Running pre-commit checks..."

# Get staged Rust files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep '\.rs$' || true)

if [ -z "$STAGED_FILES" ]; then
    echo "✅ No Rust files to check"
    exit 0
fi

echo "📝 Checking $(echo "$STAGED_FILES" | wc -l) Rust files..."

# Check for unwrap() in production code
echo ""
echo "1️⃣  Checking for unwrap() calls..."
UNWRAPS=$(echo "$STAGED_FILES" | xargs grep -n "\.unwrap()" | grep -v "test" | grep -v "#\[cfg(test)\]" || true)

if [ -n "$UNWRAPS" ]; then
    echo "❌ Found unwrap() in staged files:"
    echo "$UNWRAPS"
    echo ""
    echo "💡 Suggested fixes:"
    echo "  - Use .context('helpful message')?"
    echo "  - Use .unwrap_or_default()"
    echo "  - Handle the error properly with ?"
    echo ""
    echo "To bypass this check: git commit --no-verify"
    exit 1
fi
echo "✅ No unwrap() calls found"

# Check for println! debugging
echo ""
echo "2️⃣  Checking for println! debugging..."
PRINTLNS=$(echo "$STAGED_FILES" | xargs grep -n "println!" | grep -v "test" || true)

if [ -n "$PRINTLNS" ]; then
    echo "⚠️  Found println! in staged files:"
    echo "$PRINTLNS"
    echo ""
    echo "💡 Use tracing macros instead: info!, warn!, error!"
    echo ""
    echo "To bypass this check: git commit --no-verify"
    exit 1
fi
echo "✅ No println! calls found"

# Check for panic!
echo ""
echo "3️⃣  Checking for panic! calls..."
PANICS=$(echo "$STAGED_FILES" | xargs grep -n "panic!" | grep -v "test" | grep -v "unreachable!" || true)

if [ -n "$PANICS" ]; then
    echo "❌ Found panic! in staged files:"
    echo "$PANICS"
    echo ""
    echo "💡 Replace with proper error handling"
    exit 1
fi
echo "✅ No panic! calls found"

# Check for hardcoded secrets
echo ""
echo "4️⃣  Checking for hardcoded secrets..."
SECRETS=$(echo "$STAGED_FILES" | xargs grep -n -E '(password|secret|api_key)\s*=\s*"[^"]+"' | grep -v "//" | grep -v "test" || true)

if [ -n "$SECRETS" ]; then
    echo "❌ Found potential hardcoded secrets:"
    echo "$SECRETS"
    echo ""
    echo "⚠️  Security Issue: Use environment variables!"
    exit 1
fi
echo "✅ No hardcoded secrets found"

# Run rustfmt on staged files
echo ""
echo "5️⃣  Checking code formatting..."
for file in $STAGED_FILES; do
    if [ -f "$file" ]; then
        rustfmt --check "$file" 2>/dev/null || {
            echo "❌ Formatting issues in: $file"
            echo "💡 Run: rustfmt $file"
            exit 1
        }
    fi
done
echo "✅ All files properly formatted"

# Run clippy on staged files (if in backend directory)
if [ -f "Cargo.toml" ]; then
    echo ""
    echo "6️⃣  Running clippy checks..."
    cargo clippy --quiet -- \
        -W clippy::unwrap_used \
        -W clippy::expect_used \
        -W clippy::panic \
        -D warnings 2>&1 | head -20 || {
        echo "❌ Clippy found issues"
        echo "💡 Run: cargo clippy --fix"
        exit 1
    }
    echo "✅ Clippy checks passed"
fi

echo ""
echo "✅ All pre-commit checks passed!"
echo ""