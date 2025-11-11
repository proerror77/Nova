# Quick Start: Backend Quality Assurance

**🚀 Get Started in 5 Minutes**

This is your quick reference guide for maintaining code quality in the Nova backend.

---

## 📋 What We Have

### Current Status
- **Total unwrap() calls**: 450
- **Priority breakdown**:
  - 🔴 P0 (Critical): 25 - Service entry points
  - 🟡 P1 (High): 98 - Network/I/O/Auth
  - 🟠 P2 (Medium): ~250 - Business logic
  - 🟢 P3 (Low): ~75 - Utilities

### Tools Installed ✅
- ✅ CI/CD quality checks (`.github/workflows/code-quality.yml`)
- ✅ Pre-commit git hooks (`scripts/pre-commit.sh`)
- ✅ Progress tracking scripts (6 scripts in `scripts/`)
- ✅ Complete documentation (3 guides)
- ✅ GitHub Issues (#67-#71)

---

## ⚡ Quick Commands

### Check Quality Status
```bash
# Weekly progress report (run every Monday)
./backend/scripts/unwrap-progress.sh

# Detailed analysis by priority
./backend/scripts/unwrap-report.sh
```

### Fix Unwraps
```bash
# Interactive assistant with context-aware suggestions
./backend/scripts/fix-unwrap-helper.sh path/to/file.rs

# Find all P0 critical unwraps
cd backend
grep -rn '\.unwrap()' --include='*.rs' . | grep -E 'main\.rs|lib\.rs' | grep -v test
```

### GitHub Issues
```bash
# View all unwrap removal issues
gh issue list --repo proerror77/Nova | grep -E "P0|P1|P2|P3|Epic"

# View specific issue
gh issue view 67  # P0 Critical

# Comment on progress
gh issue comment 67 --body "Fixed 5/25 unwraps in user-service"
```

### Install Pre-commit Hook
```bash
# One-time setup (prevents new unwraps from being committed)
ln -sf ../../backend/scripts/pre-commit.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Test it
./backend/scripts/pre-commit.sh
```

---

## 🎯 Your First Day

### Morning (30 min)
1. **Run progress check**
   ```bash
   cd /path/to/nova/backend
   ./scripts/unwrap-progress.sh
   ```

2. **View GitHub issues**
   ```bash
   gh issue view 71  # Epic issue with full plan
   gh issue view 67  # P0 Critical - start here
   ```

3. **Assign yourself**
   ```bash
   gh issue edit 67 --add-assignee @me
   ```

### Afternoon (2-3 hours)
1. **Pick a file from P0 list**
   ```bash
   # Find P0 files
   grep -rn '\.unwrap()' --include='*.rs' . | \
     grep -E 'main\.rs|lib\.rs' | \
     grep -v test | head -5
   ```

2. **Use interactive helper**
   ```bash
   ./scripts/fix-unwrap-helper.sh backend/user-service/src/main.rs
   ```

3. **Fix, test, commit**
   ```bash
   # Make fixes in your editor
   vim backend/user-service/src/main.rs

   # Run tests
   cd backend/user-service
   cargo test

   # Commit (pre-commit hook will check)
   git add src/main.rs
   git commit -m "fix(user-service): remove unwrap() from main.rs startup path"
   ```

### End of Day (10 min)
1. **Update issue**
   ```bash
   gh issue comment 67 --body "✅ Fixed 3/25 P0 unwraps in user-service/main.rs"
   ```

2. **Check progress**
   ```bash
   ./scripts/unwrap-progress.sh
   ```

---

## 📖 Documentation Quick Links

| Document | Purpose | When to Use |
|----------|---------|-------------|
| `QUICKSTART_QUALITY.md` (this file) | Quick reference | Starting out, daily checks |
| `UNWRAP_REMOVAL_PLAN.md` | Full 6-week plan | Planning, sprint reviews |
| `QUALITY_ASSURANCE.md` | Error handling guide | Learning patterns, code review |
| `scripts/README.md` | Script documentation | Using tools, troubleshooting |
| `GITHUB_ISSUES_CREATED.md` | Issue tracking guide | Team coordination |

---

## 🔧 Common Patterns

### Pattern 1: Environment Variables
```rust
// ❌ BAD
let api_key = env::var("API_KEY").unwrap();

// ✅ GOOD
let api_key = env::var("API_KEY")
    .context("API_KEY environment variable not set")?;
```

### Pattern 2: Database Queries
```rust
// ❌ BAD
let user = sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", id)
    .fetch_one(&pool)
    .await
    .unwrap();

// ✅ GOOD
let user = sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", id)
    .fetch_one(&pool)
    .await
    .with_context(|| format!("Failed to fetch user {}", id))?;
```

### Pattern 3: Option Unwrapping
```rust
// ❌ BAD
let value = map.get(&key).unwrap();

// ✅ GOOD
let value = map.get(&key)
    .ok_or_else(|| anyhow!("Key {} not found", key))?;
```

---

## 🚨 What Gets Blocked

The pre-commit hook and CI will **block** these:

- ❌ New `unwrap()` calls in production code
- ❌ `println!()` debug statements (use `tracing::info!`)
- ❌ `panic!()` calls (use proper error handling)
- ❌ Hardcoded secrets/API keys
- ❌ Unformatted code (`cargo fmt` required)
- ❌ Clippy warnings

---

## 💡 Tips

### Working in a Team
1. **Morning standup**: Share which P0/P1 file you're fixing
2. **Small PRs**: Fix 1-2 files at a time for easier review
3. **Update issues**: Comment progress daily
4. **Ask for help**: #backend-quality Slack channel

### Efficient Fixing
1. **Start with P0**: Highest impact, smallest count
2. **Use patterns**: Copy-paste from `QUALITY_ASSURANCE.md`
3. **Test thoroughly**: Add tests for error paths
4. **Commit often**: Small, focused commits

### Avoiding Burnout
1. **Time-box**: 2-3 hours per day maximum
2. **Take breaks**: This is marathon, not sprint
3. **Celebrate wins**: Fixed 10 unwraps? Great job! 🎉
4. **Help others**: Pair programming on tricky files

---

## 🎯 Weekly Checklist

### Monday Morning
- [ ] Run `./scripts/unwrap-progress.sh`
- [ ] Review GitHub issues (#67-#71)
- [ ] Pick priority files for the week
- [ ] Assign yourself to issues

### Daily
- [ ] Fix 2-5 unwraps
- [ ] Run tests
- [ ] Commit with pre-commit hook
- [ ] Update issue comments

### Friday Afternoon
- [ ] Run progress script again
- [ ] Comment final week stats on issues
- [ ] Close completed tasks
- [ ] Plan next week

---

## 🆘 Troubleshooting

### Pre-commit Hook Not Running
```bash
# Check if installed
ls -la .git/hooks/pre-commit

# Reinstall
ln -sf ../../backend/scripts/pre-commit.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### Script Errors
```bash
# Make sure you're in backend directory
cd backend
./scripts/unwrap-progress.sh

# Check permissions
chmod +x scripts/*.sh
```

### CI Failing
```bash
# Run locally first
cargo fmt --check
cargo clippy -- -D warnings
cargo test
```

---

## 📞 Support

- **Documentation**: All files in `backend/` directory
- **GitHub Issues**: https://github.com/proerror77/Nova/issues
- **Slack**: #backend-quality
- **Questions**: Comment on relevant issue

---

## 🎉 Milestones

Track your progress:
- ✅ Week 1: P0 complete (0 critical unwraps)
- ⏳ Week 3: P1 under control (< 10 high priority)
- ⏳ Week 5: P2 mostly done (< 50 medium priority)
- ⏳ Week 6: Zero unwraps! 🚀

---

**Current Phase**: Week 1 - P0 Critical Fixes
**Next Milestone**: 25 → 0 P0 unwraps by end of Week 1
**Your Impact**: Every unwrap fixed = More reliable production services ⚡

---

*Last Updated: 2025-11-11*
*Quick Questions? See `QUALITY_ASSURANCE.md` for full guide*
