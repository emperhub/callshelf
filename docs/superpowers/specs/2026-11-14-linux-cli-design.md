# Linux CLI support design

## Intent
Add a native Linux CLI for callshelf users who run Cloudflare WARP, with status and IP rotation behavior matching the existing Windows command-line tool.

## Goals and constraints
- Provide status, normal rotation, deep rotation, and JSON output from Linux.
- Use Bash with the system `warp-cli` and `curl`; do not change the existing Windows PowerShell or GUI behavior.
- Keep Linux GUI support, dependency installation, and packaging out of scope.
- Update the Thai README with Linux CLI prerequisites and examples, and identify Tatsuyato and Copilot as contributors.
- Create the requested pull request with a Thai title and description.

## Approaches
- **Bash Linux entry point (selected):** Small, native Linux implementation that preserves the Windows app; tradeoff is maintaining platform-specific implementations.
- **Python cross-platform implementation:** Consolidates rotation logic, but requires restructuring the existing PowerShell/GUI integration.
- Selection: Bash, to keep the change focused and make Linux use straightforward without adding a runtime dependency.

## Implementation decisions
Add an executable Linux script alongside the existing Windows scripts. It will default to status and expose rotate, deep rotation, and JSON flags, with WARP discovery and safety behavior consistent with the existing script. The builder will follow the repository's existing naming and output conventions where practical.

## Validation
Run shell syntax checks and focused tests with mocked `warp-cli`/`curl` so status, rotation, errors, and managed-registration refusal can be verified without changing a real WARP connection.
