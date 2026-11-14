# GitHub contributors image design

## Intent
Replace the static names in the Thai README contributor section with an automatically refreshed image showing repository contributors.

## Goals and constraints
- Generate an SVG avatar grid from GitHub's repository contributor data and display it in `README.md`.
- Use a repository-owned GitHub Actions workflow and script; do not rely on an external image-hosting service.
- Keep contributor data limited to GitHub-recognized repository contributors; retain explicit Copilot credit because co-author attribution may not map to the contributors endpoint.
- Grant the workflow only the permissions needed to read contributors and update the generated SVG.

## Approaches
- **Repository-owned workflow and SVG generator (selected):** Fetch contributor data and commit an updated SVG from GitHub Actions. This matches the request and avoids an image service, at the cost of a small script and workflow to maintain.
- **External contributor image service:** Simpler embed, but depends on a third-party service and does not provide the requested GitHub Action.
- **Manually maintained/static image:** No workflow or service dependency, but it does not refresh automatically.

## Implementation decisions
Add a small Node.js generator using built-in APIs, a GitHub Actions workflow triggered by pushes to the default branch and manual dispatch, and a tracked SVG referenced by the README. Fetch raster avatar bytes only from GitHub's avatar host and embed them in the SVG so it renders without external image requests. Keep Copilot attribution as text alongside the dynamic contributor image.

## Validation
Test the generator against mocked GitHub API and raster avatar responses, verify stable SVG output, safe escaping, and no-overwrite behavior, check workflow YAML and Node syntax, and confirm the README references the generated image.
