# Task Completion Checklist

Before opening a PR
- Run formatters: `make fmt` (Rust), ensure iOS sources conform to Swift API guidelines (and SwiftLint if/when configured).
- Run linters: `make lint`.
- Run tests: `make test` (and service-specific tests as needed); ensure `make test-nextest` passes if used.
- Security: `make audit` (cargo audit) has no critical findings.
- Migrations: if changed, run `make migrate` locally; update migration docs.
- Update docs: service README, API spec, ADRs, and CHANGELOG if applicable.
- Validate health and logs when relevant: `make health`, `make logs`.

Pull Request requirements
- Link to issue/spec; include test plan and screenshots for UI.
- Ensure code adheres to Constitution principles (TDD, security, observability).
- Keep PRs scoped: structural vs behavioral changes separated when possible.
- Ensure main remains deployable; use feature flags for incomplete features.

Post-merge
- Monitor CI/CD pipelines; watch metrics/logs in staging.
- Prepare rollbacks for any risky deployment; verify alerts.
