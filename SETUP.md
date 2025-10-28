# Nova Project Setup Guide

## Git Hooks Configuration

### Overview
This project uses Git hooks to enforce the GitHub Flow development workflow. The pre-push hook prevents accidental direct pushes to the `main` branch.

### Setup Instructions

#### 1. Configure Git Hooks (One-time Setup)

Run this command in your local repository to enable the pre-push hook:

```bash
git config core.hooksPath .githooks
```

To verify the configuration:

```bash
git config core.hooksPath
# Should output: .githooks
```

#### 2. What the Hook Does

The pre-push hook:
- ✅ Blocks direct pushes to the `main` branch
- ✅ Blocks direct pushes to any protected branches
- ✅ Provides clear error messages with the correct workflow
- ✅ Allows pushes to feature branches

### GitHub Flow Workflow

#### Required Workflow

1. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   # or for fixes:
   git checkout -b fix/bug-description
   # or for documentation:
   git checkout -b docs/documentation-update
   ```

2. **Make your changes and commit**:
   ```bash
   git add .
   git commit -m "feat: implement your feature"
   # Use conventional commit format: feat:, fix:, chore:, docs:, etc.
   ```

3. **Push your feature branch**:
   ```bash
   git push -u origin feature/your-feature-name
   ```

4. **Create a Pull Request** on GitHub:
   - Go to the repository
   - Click "New Pull Request"
   - Select your feature branch as the source
   - Add a descriptive title and description
   - Request code review from team members

5. **Merge after approval**:
   - Wait for at least one approval (configured requirement)
   - Merge your PR
   - Delete the feature branch

### Branch Naming Conventions

| Prefix | Usage | Example |
|--------|-------|---------|
| `feature/` | New features | `feature/user-authentication` |
| `fix/` | Bug fixes | `fix/login-redirect-issue` |
| `docs/` | Documentation | `docs/api-specification` |
| `chore/` | Maintenance tasks | `chore/dependency-update` |
| `test/` | Test improvements | `test/add-integration-tests` |

### Commit Message Format

Follow the Conventional Commits format:

```
type(scope): short description

Optional detailed explanation...

Fixes #123
```

**Types**:
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation changes
- `chore`: Build, dependencies, or tooling
- `test`: Adding or updating tests
- `refactor`: Code refactoring without feature change
- `perf`: Performance improvements

### Troubleshooting

#### "Permission denied" error when pushing to main

This is the hook working correctly! Follow the workflow above:

```bash
# ❌ This will fail:
git push origin main

# ✅ Do this instead:
git checkout -b feature/my-changes
# ... make changes ...
git push -u origin feature/my-changes
# Then create a PR on GitHub
```

#### Hook not working?

1. Verify the hook is enabled:
   ```bash
   git config core.hooksPath
   # Should show: .githooks
   ```

2. Check hook permissions:
   ```bash
   ls -la .githooks/pre-push
   # Should have execute permission (x)
   ```

3. Re-enable hooks:
   ```bash
   git config core.hooksPath .githooks
   ```

#### Temporarily bypass the hook (not recommended)

If you need to bypass for emergency only:
```bash
git push --no-verify origin feature/branch-name
```

Note: This is only for emergencies. The hook exists to prevent mistakes and maintain code quality.

### GitHub Protection Rules

The `main` branch is protected with the following rules:
- ✅ Requires pull request reviews before merging
- ✅ Minimum 1 approval required
- ✅ Prevents force pushes
- ✅ Prevents deletion of the branch

### Team Setup Checklist

- [ ] Run `git config core.hooksPath .githooks` in your local repository
- [ ] Verify with `git config core.hooksPath` (should show `.githooks`)
- [ ] Try creating a feature branch and pushing to understand the workflow
- [ ] Review the branch naming conventions above
- [ ] Read through example commit messages

### Questions or Issues?

If you have questions about the workflow:
1. Check this document first
2. Review the error message from the hook (they're detailed!)
3. Ask in the team Slack channel
4. Create an issue if you think the hook needs adjustment

---

**Last Updated**: October 28, 2025
**Version**: 1.0
