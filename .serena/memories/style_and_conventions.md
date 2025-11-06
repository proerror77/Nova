# Style and Conventions

Global
- Follow Constitution (.specify/memory/constitution.md): microservices-first, TDD, security, observability, CI/CD.
- PRs: tests before code (red→green→refactor), link spec/issue, include test plan; 1+ senior approval; main always deployable.
- Branching: GitFlow; semantic versioning; feature flags for progressive delivery.

Rust Backend
- Formatting: `rustfmt` (enforced via `make fmt` / `fmt-check`).
- Linting: `clippy` with `-D warnings` (`make lint`).
- Testing: unit + integration; aim 80%+ for business logic; use nextest optionally.
- Security: `cargo audit`; secure secrets; TLS; JWT/OAuth2; input validation.
- Observability: Prometheus metrics, structured logs, tracing (OTel/Jaeger).
- API Contracts: OpenAPI where applicable; integration tests for boundaries.

iOS (Swift)
- SwiftUI-first; modern Swift concurrency (async/await) over legacy patterns.
- Prefer @Observable over @Published where applicable; performance-focused.
- No heavy ViewModel layer; use SwiftUI state patterns and clean architecture.
- Testing: Swift Testing for unit tests; XCUITest for UI; managed by `NovaSocial.xctestplan`.
- Public API from SPM package as needed (use `public`).
- Consider SwiftLint if added later; follow Apple naming and Swift API Design Guidelines.

Documentation and ADRs
- Maintain ADRs for major decisions; keep service READMEs updated.
- Architecture docs live in `docs/` and service-level READMEs in each component.
