# GitHub Branch Protection Configuration

**Objective**: Enable strict CI/CD gates with AI-powered security blocking
**Target Branch**: `main` (production)
**Status**: Ready to configure via GitHub UI or gh CLI

---

## Manual Setup (GitHub UI)

### Step 1: Enable Branch Protection

Navigate to: **Settings → Branches → Add Rule**

Rule applies to: `main`

### Step 2: Configure Status Checks (REQUIRED)

Enable:
- ✅ **Require status checks to pass before merging**
- ✅ **Require branches to be up to date before merging**

### Step 3: Add Required Status Checks

These MUST pass before merge is allowed:

**BLOCKING Checks**:
1. `ai-code-review / claude-security-review` ← **SECURITY GATE**
2. `ci-validate / validate` (existing CI)
3. `build` or `cargo-test` (if you have build checks)

**Optional Status Checks** (informational only):
- `ai-code-review / claude-code-review`
- `ai-code-review / codex-gate`
- Coverage reports

### Step 4: Require PR Reviews

Enable:
- ✅ **Require pull request reviews before merging**
- Required approving reviews: **1**
- ✅ **Dismiss stale pull request approvals when new commits are pushed**
- ✅ **Require review from code owners** (if CODEOWNERS exists)

### Step 5: Merge Settings

- ✅ **Allow merge commits** (recommended for audit trail)
- ✅ **Require commit signature** (optional but recommended)
- ✅ **Require conversation resolution before merging**

### Step 6: Restrictions

- ✅ **Restrict who can push to matching branches** (optional)
  - Allow admins to bypass (for emergency hotfixes)

---

## Automated Setup (GitHub CLI)

```bash
# Login if not already authenticated
gh auth login

# Set repository
export REPO="proerror77/Nova"

# Create branch protection rule via API
cat > /tmp/branch-protect.json << 'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "ai-code-review / claude-security-review",
      "ci-validate / validate"
    ]
  },
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "enforce_admins": false,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF

# Apply to main branch
gh api repos/$REPO/branches/main/protection \
  --input /tmp/branch-protect.json \
  -X PUT
```

---

## Merge Queue Configuration (Advanced)

For additional safety, enable Merge Queue:

**Settings → Branches → Add Rule → Merge Queue**

- ✅ **Enable merge queue**
- Merge method: Squash and merge (or as preferred)
- Queue entry timeout: 24 hours
- Auto-merge on approval: true

When enabled:
- PRs approved are queued (not immediately merged)
- Queued PRs are tested against latest main
- Merge happens only if all checks pass

---

## Required Actions Mapping

Your `.github/workflows/ai-code-review.yml` defines these status checks:

| Job Name | Status Check Name | Type | Block? |
|----------|-------------------|------|--------|
| claude-security-review | ai-code-review / claude-security-review | BLOCKING | ✅ YES |
| claude-code-review | ai-code-review / claude-code-review | INFO | ⭕ NO |
| codex-gate | ai-code-review / codex-gate | INFO | ⭕ NO |
| ai-review-summary | ai-code-review / ai-review-summary | INFO | ⭕ NO |

Add to branch protection: Only the **BLOCKING** check (first one)

---

## Workflow for Contributors

### Before Pushing

```bash
# 1. Format & lint locally
cargo fmt --all
cargo clippy --all -- -D warnings

# 2. Run tests
cargo test --all

# 3. Check for secrets
git diff HEAD~1..HEAD | grep -iE "(password|secret|key|token)"
```

### After Pushing PR

1. **Claude Security Review** (auto-triggered)
   - If **BLOCKER found** → PR is blocked ❌
   - If **pass** → Continue to next check ✅

2. **Manual Review** (GitHub PR review)
   - Request 1 approval from team member
   - Address feedback

3. **Codex Suggestions** (optional, informational)
   - Review but won't block merge

4. **Final Merge**
   - All required checks pass ✅
   - At least 1 approval ✅
   - Ready to merge! 🚀

---

## Secrets Management

### GitHub Secrets (for CI/CD)

Set these in **Settings → Secrets and variables → Actions**:

| Secret | Value | Source |
|--------|-------|--------|
| ANTHROPIC_API_KEY | `sk-ant-...` | Anthropic Console |
| OPENAI_API_KEY | `sk-...` | OpenAI Console |
| GITHUB_TOKEN | Auto-provided | GitHub (built-in) |

### Credential Handling in Code

❌ **NEVER**:
```python
api_key = "sk-ant-abc123"  # ❌ Hardcoded!
```

✅ **ALWAYS**:
```python
api_key = os.environ.get("ANTHROPIC_API_KEY")
# Or in Rust:
let api_key = std::env::var("ANTHROPIC_API_KEY")?;
```

---

## Testing the Configuration

### 1. Verify Status Check Registration

```bash
gh api repos/proerror77/Nova/branches/main/protection \
  --jq '.required_status_checks.contexts[]'
```

Expected output:
```
ai-code-review / claude-security-review
ci-validate / validate
...
```

### 2. Test with a Dummy PR

Create a test PR with harmless change:
```bash
git checkout -b test/branch-protection
echo "# Test" >> README.md
git add README.md
git commit -m "test: branch protection"
git push origin test/branch-protection
```

Then open PR and verify:
- ✅ Workflows trigger
- ✅ Security review runs
- ✅ Status checks appear
- ✅ Cannot merge without approvals

### 3. Test Blocking Scenario

Create PR with intentional issue:
```bash
echo 'password = "hardcoded123"' >> backend/src/main.rs
git add backend/src/main.rs
git commit -m "test: hardcoded secret"
git push origin test/secret-exposure
```

Expected:
- ❌ Claude security check FAILS
- ❌ Cannot merge (status check failed)
- ✅ PR is blocked as intended

---

## Emergency Bypass (Admin Override)

For critical hotfixes, admins can:

1. In PR, click **Merge anyway** (only if `enforce_admins: false`)
2. Add comment explaining emergency
3. Create follow-up PR to address root cause

---

## Monitoring & Alerts

### Check Status Check Health

```bash
# Get all recent workflow runs
gh run list -R proerror77/Nova \
  --workflow=ai-code-review.yml \
  -L 20 \
  --json name,status,conclusion
```

### Alert on Failure Pattern

If security review failures spike:
1. Check for new vulnerability patterns
2. Review recent PRs for common issues
3. Update AGENTS.md / CLAUDE.md if new patterns discovered

---

## References

- [GitHub Branch Protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)
- [Required Status Checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#about-branch-protection-rules)
- [Merge Queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-merge-queue)
- [AGENTS.md](../AGENTS.md) - Code review standards for Codex
- [CLAUDE.md](../CLAUDE.md) - Code review standards for Claude Code

