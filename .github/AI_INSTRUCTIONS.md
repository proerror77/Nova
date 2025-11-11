# AI Assistant Instructions for Nova Project

## 🚨 CRITICAL: Documentation Generation Policy

### ❌ NEVER Create Markdown Files in Root Directory

**ABSOLUTE RULE**: Do NOT create ANY markdown files in the project root directory (`/`) except for these GitHub-standard files:

- `README.md`
- `LICENSE.md`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `SECURITY.md`
- `CHANGELOG.md`

### ✅ ALWAYS Use docs/ Directory

When generating documentation:

1. **Check current directory first**
   ```bash
   pwd  # Ensure you're not in root
   ```

2. **Place files in appropriate subdirectories**:
   - Deployment docs → `docs/deployment/`
   - Development docs → `docs/development/`
   - Architecture docs → `docs/architecture/`
   - Guides → `docs/guides/`
   - Temporary reports → `docs/reports/YYYY-MM/`

3. **Never use these patterns in root**:
   - `*_REPORT.md`
   - `*_SUMMARY.md`
   - `EXECUTION_*.md`
   - `IMPLEMENTATION_*.md`
   - `PHASE_*.md`
   - `P0_*.md`, `P1_*.md`
   - `*_AUDIT_*.md`
   - `OPTIMIZATION_*.md`
   - `DEPLOYMENT_*.md`
   - `QUICKSTART.md`
   - `SETUP.md`

### 📋 Before Creating Any Document

Ask yourself:
1. Is this a GitHub-standard file? → Root directory OK
2. Is this project documentation? → Use `docs/` subdirectory
3. Is this a temporary report? → Use `docs/reports/YYYY-MM/`
4. Not sure? → **ALWAYS choose `docs/` directory**

---

## 📁 Project Documentation Structure

```
Nova/
├── README.md                    ✅ ONLY GitHub standard files in root
├── LICENSE.md
├── CONTRIBUTING.md
│
└── docs/                        ✅ ALL other docs go here
    ├── START_HERE.md
    ├── deployment/
    ├── development/
    ├── architecture/
    ├── guides/
    └── reports/
        └── 2025-11/
```

---

## 🔍 Verification Checklist

Before committing any work with documentation:

- [ ] No markdown files in root except GitHub standards
- [ ] All docs are in appropriate `docs/` subdirectories
- [ ] Temporary reports include date in filename
- [ ] Updated relevant index/README files

---

## 📚 Reference

See full policy: [`docs/DOCUMENTATION_POLICY.md`](../docs/DOCUMENTATION_POLICY.md)

---

**Last Updated**: 2025-11-11
**Version**: 1.0.0
