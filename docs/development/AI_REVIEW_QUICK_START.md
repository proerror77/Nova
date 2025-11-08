# AI Code Review - Quick Reference Card

**Version**: 1.0
**Duration to Setup**: 15 minutes
**Duration to Use**: 0 (automatic on every PR)

---

## ⚡ 3-Minute Overview

You now have **AI-powered code review** for every PR:

| Component | Role | Trigger | Blocks? |
|-----------|------|---------|---------|
| **Claude Security** | Find P0/P1 vulnerabilities | Auto on PR | ✅ YES |
| **Claude Code** | Design/style suggestions | After security passes | ❌ NO |
| **Codex** | Automated review checks | Manual `@codex review` | ❌ NO |
| **Human Review** | Final approval | Always required | ✅ YES |

---

## 🚀 What To Do Right Now (5 minutes)

### 1. Set API Keys

GitHub UI: **Settings → Secrets and variables → Actions**

Create these secrets:

**If using Anthropic Claude** (recommended):
```
Name: ANTHROPIC_API_KEY
Value: sk-ant-...abc123...
```

**If using OpenAI Codex** (optional):
```
Name: OPENAI_API_KEY
Value: sk-...xyz789...
```

### 2. Enable Branch Protection (5 minutes)

**Option A: GitHub UI (easier)**
1. Go to **Settings → Branches**
2. Click **Add rule**
3. Pattern: `main`
4. Check: ✅ Require status checks
5. Add required check: `ai-code-review / claude-security-review`
6. Save rules

**Option B: CLI (faster)**
```bash
# Copy this command from:
# .github/BRANCH_PROTECTION_CONFIG.md

gh api repos/proerror77/Nova/branches/main/protection \
  --input /tmp/branch-protect.json -X PUT
```

### 3. Test (2 minutes)

Create test PR:
```bash
git checkout -b test/ai-review
echo "# test" >> TEST.md
git add TEST.md
git commit -m "test: verify AI review"
git push origin test/ai-review
```

Expected:
- ✅ Workflow runs in ~10 seconds
- ✅ Claude posts security findings
- ✅ Cannot merge without approval

Then delete:
```bash
git push origin --delete test/ai-review
```

---

## 📋 For PR Authors (This is You)

### Before Each PR

```bash
# 1. Local quality check (5 min)
cargo fmt --all
cargo clippy --all -- -D warnings
cargo test --all

# 2. Write clear message (helps Claude understand)
git commit -m "feat: add JWT auth to user-service

- Add AuthInterceptor to gRPC server
- Validate JWT from JWKS endpoint
- Return Unauthenticated for invalid tokens"

# 3. Push
git push origin your-branch-name
```

### After Pushing (Automatic)

1. **Claude security check** starts (5 sec)
   - If `[BLOCKER]` found → Fix it → Push again
   - If `[PASS]` → Continue

2. **Claude code review** posts suggestions (10 sec)
   - Optional to address (doesn't block)
   - Usually: "add test", "consider enum", etc.

3. **Request team review**
   - Link to PR in Slack/Discord
   - Need ≥1 approval

4. **Merge when ready** ✅
   - All checks pass
   - ≥1 approval received
   - Click "Merge"

---

## 🔐 What Claude Checks (And Blocks)

### P0 BLOCKERS ❌ (PR cannot merge)

If found, Claude will say `[BLOCKER]` and block merge:

```
❌ Hardcoded API key detected
❌ Missing authentication on endpoint
❌ SQL injection risk (string concat)
❌ Breaking database change
❌ No timeout on network call
```

**Action**: Fix immediately, push again.

### P1 WARNINGS ⚠️ (Won't block, but important)

Claude will mention:

```
⚠️ unwrap() in I/O path - could panic
⚠️ Missing error handling
⚠️ Unvalidated user input
```

**Action**: Address if possible, explain if not.

### P2 SUGGESTIONS 💡 (Nice to have)

Claude will suggest:

```
💡 Add test for this case
💡 Consider using enum instead of bool
💡 Performance: batch these queries
```

**Action**: Optional, improve code quality over time.

---

## 📖 For Reviewers (Team Members)

### When You Get Review Request

1. **Read Claude's findings** (in PR comments)
   - Already identified security issues
   - Summarized code quality points

2. **Focus on**:
   - Architecture decisions
   - Business logic correctness
   - Team practices alignment
   - Things AI cannot check

3. **Approve** if:
   - No `[BLOCKER]` remains
   - All P1 issues addressed or documented
   - Code follows AGENTS.md / CLAUDE.md
   - Tests cover new functionality

4. **Request changes** if:
   - Security risk not caught by Claude
   - Design doesn't match architecture
   - Performance concern
   - Missing test coverage

---

## 🛠️ Common Scenarios

### Scenario 1: Claude blocks for "hardcoded secret"

```
❌ [BLOCKER] Hardcoded API key in code

Location: backend/src/main.rs:42
Password = "my-secret-abc"

Fix: Use environment variable
let secret = env::var("API_KEY")?;
```

**What to do**:
1. Replace hardcoded value with `env::var()`
2. Document in PR: "Now uses environment variable"
3. Push fix
4. Claude re-checks automatically ✅

### Scenario 2: Claude suggests "add test"

```
💡 Suggestion: Test Coverage

New public function should have test.

Example:
#[test]
fn test_valid_email() { ... }
```

**What to do**:
- Option A: Add test (improves code quality)
- Option B: Skip (Claude won't block)
- Add comment explaining decision

### Scenario 3: Your code is safe but Claude is unsure

```
⚠️ Pattern detected: unwrap() in code

Location: backend/src/db.rs:15
let conn = pool.get_connection().unwrap();

Note: If pool is guaranteed to be initialized,
document with expect() instead:
let conn = pool.get_connection()
  .expect("Pool initialized in main");
```

**What to do**:
```rust
// Add comment explaining safety
let conn = pool.get_connection()
  .expect("Pool guaranteed initialized in main");
```

---

## 📚 Reference Files

**Read if**... → **Then read**...

- Setting up? → `AI_REVIEW_IMPLEMENTATION.md`
- Team standards? → `AGENTS.md` (for Codex) + `CLAUDE.md` (for Claude)
- GitHub setup? → `.github/BRANCH_PROTECTION_CONFIG.md`
- This quick ref? → **You are here** ✓

---

## ⚙️ Configuration Reference

### GitHub Secrets Needed

```yaml
ANTHROPIC_API_KEY    # For Claude security/code reviews
GITHUB_TOKEN         # Auto-provided (no action needed)
```

### Branch Protection Rule

```
Rule applies to: main
Required status checks:
  ✅ ai-code-review / claude-security-review
Required approvals: 1
```

### Workflow Triggers

```yaml
Triggers on: PR opened, synchronized, reopened
Ignores: .md files, .gitignore, /docs
Runs: 4 jobs in parallel → Summary
```

---

## 🎯 Goals & Metrics

### What This System Achieves

✅ **Stop P0 vulnerabilities before production**
✅ **Consistent code standards across team**
✅ **Faster PR reviews (Claude does initial pass)**
✅ **Better knowledge sharing (team sees all findings)**
✅ **Audit trail of code quality (PR comments)**

### Success Indicators (check after 2 weeks)

- [ ] All team members understand [BLOCKER] vs suggestions
- [ ] Zero credentials slipped into main branch
- [ ] Average PR review time decreased
- [ ] Team confidence in code quality improved
- [ ] Claude suggestions are mostly relevant

---

## 🆘 Troubleshooting

### Workflow doesn't run

**Check**:
1. File exists: `.github/workflows/ai-code-review.yml` ✓
2. Pushed to non-main branch ✓
3. GitHub Actions tab shows runs ✓

### No comment from Claude

**Check**:
1. `ANTHROPIC_API_KEY` set in Secrets ✓
2. Workflow has `pull-requests: write` permission ✓
3. PR diff exists (not empty) ✓

### Too many false positives

**Action**:
1. Collect examples
2. Update `AGENTS.md` / `CLAUDE.md`
3. Re-run workflow tests

### Want stricter blocking

**Edit**: `.github/workflows/ai-code-review.yml`
```yaml
# Change from non-blocking to blocking
codex-gate:
  continue-on-error: true   # ← Change to: false
```

---

## 💬 Questions?

| Question | Answer |
|----------|--------|
| Does this slow down merges? | No, Claude runs in <10s |
| Can I bypass Claude? | Only admins, must add comment |
| What if Claude is wrong? | Document in PR, team approves anyway |
| Can I customize the rules? | Yes, edit AGENTS.md / CLAUDE.md |
| Cost implications? | ~$0.01-0.05 per PR (minimal) |

---

## ✅ Checklist: You're Ready When

- [ ] ANTHROPIC_API_KEY set in GitHub Secrets
- [ ] Branch protection enabled on `main`
- [ ] Test PR created and verified
- [ ] Team briefed on [BLOCKER] vs suggestions
- [ ] AGENTS.md / CLAUDE.md bookmarked
- [ ] This quick ref saved for later

**That's it! You're live.** 🚀

Every PR from now on gets AI security review automatically.
Enjoy faster, more consistent code quality! ✨

