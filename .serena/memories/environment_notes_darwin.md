# Environment Notes (Darwin/macOS)

Shell and Utilities
- `open <path>` opens files/apps; `open -a Simulator` launches iOS Simulator.
- Clipboard: `pbcopy` / `pbpaste`.
- Homebrew: `brew install <pkg>` for CLI tools (e.g., `brew install rustup jq ripgrep sqlx`).
- Sed in-place flag: `sed -i '' -e 's/foo/bar/' file` (note the empty backup extension on macOS BSD sed).
- Prefer `rg` (ripgrep) over `grep` for performance; `fd` over `find` when available.

iOS Tooling
- Xcode 15+ recommended; open workspace `ios/NovaSocial/NovaSocial.xcworkspace`.
- CLI builds: `xcodebuild -scheme NovaSocial -destination 'platform=iOS Simulator,name=iPhone 15' build`.

Containers and DB
- Docker Desktop for macOS; ensure virtualization enabled.
- Common DB ports: Postgres 5432, Redis 6379; use `docker-compose` services from repo.
