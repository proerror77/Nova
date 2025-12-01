# Contributing to Nova

Thanks for your interest in contributing!

## Development Setup

- Backend: Rust toolchain stable; see `backend/README.md`.
- iOS: Xcode 15; see `.github/workflows/ios-tests.yml` for simulator versions.
- Infra: Docker and Docker Compose; see `backend/docker-compose.yml`.

## Branch Naming Convention

We use team-prefixed branches to organize work:

### iOS Team
```
ios/feature/<description>   # New features
ios/fix/<description>       # Bug fixes
ios/refactor/<description>  # Code refactoring
```

### Backend Team
```
backend/feature/<description>   # New features
backend/fix/<description>       # Bug fixes
backend/refactor/<description>  # Code refactoring
```

### Shared / DevOps
```
infra/<description>         # Infrastructure changes
docs/<description>          # Documentation only
hotfix/<description>        # Urgent production fixes (any team)
```

### Examples
```bash
# iOS team adding new feed UI
git checkout -b ios/feature/new-feed-layout

# Backend team fixing auth bug
git checkout -b backend/fix/jwt-refresh-token

# Urgent production fix
git checkout -b hotfix/login-crash
```

## Workflow

1. **Create branch** from `main` with team prefix
2. **Develop** and commit with clear messages
3. **Push** and create PR to `main`
4. **Review** - CODEOWNERS will auto-assign reviewers
5. **Merge** - Branch auto-deletes after merge

## Pull Requests

- Ensure CI is green (lint, tests, security checks).
- Update docs when behavior changes.
- Fill out the PR template and include testing steps.
- Cross-team changes (e.g., API contracts in `/proto/`) require both teams' approval.

## Code Quality

- Rust: `cargo fmt`, `cargo clippy -- -D warnings`.
- iOS: SwiftLint, SwiftFormat (if configured).

## Security

Please report security issues via the [Security Policy](./SECURITY.md) and do not open public issues for vulnerabilities.

