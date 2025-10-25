# Contributing to Nova

Thanks for your interest in contributing!

## Development Setup

- Backend: Rust toolchain stable; see `backend/README.md`.
- iOS: Xcode 15; see `.github/workflows/ios-tests.yml` for simulator versions.
- Infra: Docker and Docker Compose; see `backend/docker-compose.yml`.

## Branching & Commits

- Use feature branches, e.g. `feature/<short-description>`.
- Write clear commit messages; reference issues where applicable.

## Pull Requests

- Ensure CI is green (lint, tests, security checks).
- Update docs when behavior changes.
- Fill out the PR template and include testing steps.

## Code Quality

- Rust: `cargo fmt`, `cargo clippy -- -D warnings`.
- JS/TS: `eslint`, `prettier` where applicable.
- iOS: Keep SwiftLint clean (if configured in the app).

## Security

Please report security issues via the [Security Policy](./SECURITY.md) and do not open public issues for vulnerabilities.

