# AI-Powered Code Review Implementation Guide

**Status**: Ready to Deploy
**Last Updated**: 2025-11-06
**Components**: 3 files + 1 workflow

---

## 📋 What You're Getting

### Files Created

1. **`.github/workflows/ai-code-review.yml`**
   - 4-phase review pipeline
   - Claude Security Review (BLOCKING)
   - Claude Code Review (suggestions)
   - Codex trigger + gate (optional)

2. **`AGENTS.md`**
   - Review standards for Codex
   - Security checklist (P0/P1/P2)
   - gRPC, database, Rust-specific rules
   - Testing expectations

3. **`CLAUDE.md`** (updated)
   - Deep security principles
   - Minimal fix recommendations
   - gRPC microservices specifics
   - Review output templates

4. **`.github/BRANCH_PROTECTION_CONFIG.md`**
   - Manual setup instructions
   - CLI automation commands
   - Testing procedures
   - Emergency bypass documentation

---

## 🚀 Implementation Roadmap

### Phase 1: Deploy (Today - 5 minutes)

**Step 1.1**: Push all files to feature branch
```bash
cd /Users/proerror/Documents/nova
git add .github/workflows/ai-code-review.yml \
        AGENTS.md \
        CLAUDE.md \
        .github/BRANCH_PROTECTION_CONFIG.md
git commit -m "feat: implement Claude + Codex AI review pipeline"
git push origin feature/ai-review-system
```

**Step 1.2**: Create PR & let it run
- AI review workflows will trigger automatically
- Review Claude's security findings
- Address any flagged items

**Step 1.3**: Merge to main
```bash
gh pr merge <PR_NUMBER> --squash
```

### Phase 2: Configure (After merge - 10 minutes)

**Step 2.1**: Set GitHub Secrets
```bash
# Export secrets to GitHub
export REPO="proerror77/Nova"

# Add Anthropic API key (optional if using Bedrock)
gh secret set ANTHROPIC_API_KEY \
  --body "$(cat ~/.anthropic/api_key)" \
  -R $REPO

# GitHub token is auto-provided, no action needed
```

**Step 2.2**: Enable Branch Protection
Option A (UI - easiest):
1. Go to Settings → Branches
2. Add rule for `main`
3. Follow: `.github/BRANCH_PROTECTION_CONFIG.md`

Option B (CLI):
```bash
# Use the CLI commands in BRANCH_PROTECTION_CONFIG.md
gh api repos/proerror77/Nova/branches/main/protection \
  --input /tmp/branch-protect.json -X PUT
```

### Phase 3: Validate (5 minutes)

**Step 3.1**: Create test PR
```bash
git checkout -b test/ai-review-validation
echo "# Test PR" >> TEST.md
git add TEST.md
git commit -m "test: validate AI review system"
git push origin test/ai-review-validation
```

**Step 3.2**: Verify in GitHub UI
- [ ] PR created
- [ ] `ai-code-review` workflow triggered
- [ ] Status checks appear on PR
- [ ] Claude security review comment posted
- [ ] Cannot merge without approval (if protection enabled)

**Step 3.3**: Clean up
```bash
git push origin --delete test/ai-review-validation
```

### Phase 4: Operate (Ongoing)

**For Each PR**:
1. Write clear commit messages (helps AI understand intent)
2. Wait for Claude security review (5-10 seconds)
3. Address any [BLOCKER] findings
4. Request manual review from team member
5. Merge when all checks pass ✅

---

## 🔐 Security Review Behavior

### What Claude Checks

**P0 Blockers** (PR cannot merge):
- Credentials in code (API keys, passwords, tokens)
- Missing authentication on endpoints
- SQL injection vulnerabilities
- RCE risks (eval, exec)
- Breaking database changes
- Unsafe crypto

**P1 High Priority** (warnings):
- `.unwrap()` in I/O paths
- Missing timeouts on network ops
- Unhandled errors
- Missing input validation
- Connection pool issues

**P2 Suggestions** (informational):
- Missing tests
- Code style improvements
- Performance suggestions

### What Happens

```
User pushes PR
    ↓
Claude Security Review triggered automatically
    ├─ Scans for P0 blockers
    ├─ Posts findings as PR comment
    └─ Sets status check:
       ├─ FAIL if P0 found → PR blocked ❌
       └─ PASS if clean → PR can proceed ✅
    ↓
Claude Code Review (if security passed)
    ├─ Non-blocking suggestions
    └─ Posts as informational comment
    ↓
Codex Review (optional trigger)
    ├─ Lightweight automated checks
    └─ Also informational
    ↓
Manual Team Review
    └─ At least 1 human approval required
    ↓
All checks pass?
    └─ Can merge! 🚀
```

---

## 📖 How to Use AGENTS.md & CLAUDE.md

### For Codex (Automated Agent)

Codex reads **AGENTS.md** for:
- What to look for during code review
- Security/database/Rust rules
- Test expectations
- Checklist format for its responses

Example trigger in PR:
```
@codex review
Please review against AGENTS.md standards.
```

### For Claude Code (Deep Review)

Claude reads **CLAUDE.md** for:
- Principles: security first, minimalist fixes, backward compatibility
- Checklists: P0/P1/P2 priorities
- gRPC/database/async patterns
- Output format (use [BLOCKER] for high-risk items)
- Communication style

The workflow automatically points Claude to CLAUDE.md standards.

---

## 🛠️ Customization

### Adjust Security Sensitivity

In `.github/workflows/ai-code-review.yml`, find:
```yaml
- name: Block merge if P0 findings
  if: steps.parse.outputs.status == 'FAIL'
```

To **disable** blocking:
```yaml
  if: false  # Changes to informational only
```

### Add More Status Checks

To require additional checks beyond Claude security:

In `.github/BRANCH_PROTECTION_CONFIG.md`, add to `required_status_checks.contexts`:
```json
"contexts": [
  "ai-code-review / claude-security-review",  # Blocking
  "ci-validate / validate",                   # Existing CI
  "cargo-test / test",                        # If you add
  "integration-tests / test"                  # Coverage
]
```

### Scale to Multiple Branches

Copy branch protection rule:
```bash
# Apply to develop branch too
gh api repos/proerror77/Nova/branches/develop/protection \
  --input /tmp/branch-protect.json -X PUT
```

---

## 🧪 Testing & Troubleshooting

### Test: Does Claude detect hardcoded secrets?

Create test PR:
```bash
echo 'password = "hardcoded123"' >> backend/src/main.rs
git add .
git commit -m "test: secret exposure"
git push
```

Expected: Claude security check FAILS ✅

### Test: Does Claude allow safe code?

Create test PR:
```bash
# Add safe code
echo 'pub fn hello() { println!("safe"); }' >> backend/src/lib.rs
git add .
git commit -m "test: safe code"
git push
```

Expected: Claude security check PASSES ✅

### Troubleshoot: Workflow not triggering

Check:
1. **File exists**: `.github/workflows/ai-code-review.yml` ✓
2. **On pull_request**: Workflow `on: pull_request` ✓
3. **Branch**: Pushed to non-main branch ✓
4. **Status**: Check "Actions" tab in GitHub

### Troubleshoot: No PR comment from Claude

Check:
1. **API key**: `ANTHROPIC_API_KEY` in GitHub Secrets ✓
2. **Permissions**: Workflow has `pull-requests: write` ✓
3. **Logs**: View workflow run logs for errors

---

## 📊 Expected Workflow Timing

| Phase | Duration | Notes |
|-------|----------|-------|
| Security Review | 5-10s | Pattern matching + placeholder API |
| Code Review | 15-30s | Claude analysis (if security passed) |
| Codex Gate | 30-60s | Wait time for review |
| **Total** | **~1 min** | User can address issues immediately |

---

## 🎯 Best Practices for PR Authors

### Before Pushing

```bash
# 1. Local checks
cargo fmt --all
cargo clippy --all -- -D warnings
cargo test --all

# 2. Commit message (helps Claude understand)
git commit -m "feat(user-service): add JWT authentication

- Add AuthInterceptor to all gRPC endpoints
- Validate JWT tokens via JWKS endpoint
- Return Unauthenticated status for invalid tokens

Fixes: #123"

# 3. Manual secret scan
git diff HEAD~1 | grep -iE "password|secret|key|token"
```

### When Claude Flags an Issue

If Claude posts `[BLOCKER]`:
1. Read the finding carefully
2. Understand the risk
3. Apply the recommended fix
4. Test locally
5. Push fix: `git commit --amend && git push --force-with-lease`
6. Workflow re-runs automatically ✅

---

## 🔄 Continuous Improvement

### Monthly Review

1. **Check for patterns**: Are we blocking the same issue repeatedly?
2. **Update rules**: Add new patterns to AGENTS.md / CLAUDE.md
3. **Team feedback**: "Too strict?" vs "Missed something?"
4. **Refine threshold**: P0 vs P1 classification

### Metrics to Track

- Avg. PRs blocked by security: ___ per week
- Avg. time to fix blockers: ___ minutes
- False positives (real safe code flagged): ___
- Team satisfaction: 😀 / 😐 / 😤

---

## 📚 Reference

### Files & Locations

```
/Users/proerror/Documents/nova/
├─ .github/
│  ├─ workflows/
│  │  └─ ai-code-review.yml          ← Main workflow
│  └─ BRANCH_PROTECTION_CONFIG.md    ← GitHub setup guide
├─ AGENTS.md                          ← Codex standards
├─ CLAUDE.md                          ← Claude standards
└─ AI_REVIEW_IMPLEMENTATION.md        ← This file
```

### Documentation Links

- **Security Rules**: `AGENTS.md` (Codex) + `CLAUDE.md` (Claude)
- **Branch Protection**: `.github/BRANCH_PROTECTION_CONFIG.md`
- **Workflow Details**: `.github/workflows/ai-code-review.yml`

---

## ⚠️ Important Notes

### Cost Implications

- Claude API calls: ~$0.01-0.05 per PR (depending on diff size)
- Codex API calls: Depends on pricing (check OpenAI dashboard)
- GitHub Actions minutes: ~1 min per PR (free tier: 2000 min/month)

**Recommendation**: Start with main branch only, scale after 1 month.

### Security Considerations

- **API Keys**: Never hardcode; use GitHub Secrets
- **Diff Exposure**: Only PR diff sent to Claude, not secrets
- **Audit Trail**: All reviews logged in PR comments (retained in Git)
- **User Privacy**: Claude may retain PR diffs (review OpenAI/Anthropic policies)

---

## 🎬 Next Steps

1. **Deploy**: Push branch with 3 files + workflow
2. **Configure**: Enable GitHub Secrets + branch protection
3. **Test**: Create test PR to validate
4. **Operate**: Use in normal PR workflow
5. **Refine**: Adjust rules after 1-2 weeks of usage

---

**Ready? Start with Phase 1 above!** 🚀

