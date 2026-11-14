# GitHub Contributors Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the README's static contributor names with a GitHub Actions-maintained avatar grid.

**Architecture:** A dependency-free Node.js script fetches all pages of GitHub repository contributors and raster avatar bytes from GitHub's avatar host, then embeds the images into a tracked SVG. A workflow runs on default-branch pushes and manual dispatch, committing only when the generated SVG changes; the README embeds the SVG and retains explicit Copilot credit.

**Tech Stack:** GitHub Actions, Node.js 20 built-ins, GitHub REST API, Node's built-in test runner, SVG.

**Spec:** `docs/superpowers/specs/2026-11-14-contributors-image-design.md`

## Global Constraints

- Use a repository-owned GitHub Actions workflow and script; do not rely on an external image-hosting service.
- Limit the workflow token to `contents: write` and never log the token.
- Keep Copilot attribution as text alongside the dynamic contributor image.

## Review Focus

- API pagination with exactly 100 contributors on a page: fetch subsequent pages rather than silently truncating the image.
- Empty contributor response: generate a valid accessible SVG instead of a zero-sized image.
- API/network/non-JSON or avatar fetch failure: fail the workflow and leave the existing SVG unchanged.
- Malicious or malformed login/profile/avatar data and avatar retrieval: escape XML, allow only GitHub hosts and raster content types `image/jpeg`, `image/png`, `image/webp` up to 256 KiB, send no API token to the avatar host, and embed bytes in the SVG.
- Workflow permissions or unchanged SVG: grant only `contents: write` and skip empty commits; deterministic SVG output must remain byte-for-byte identical.

---

### Task 1: Create the contributor SVG generator

**Files:**
- Create: `scripts/update-contributors.mjs`
- Create: `tests/update-contributors.test.mjs`
- Create: `docs/contributors.svg`

**Interfaces:**
- Produces `fetchContributors(repository: string, token: string, fetchImpl?: typeof fetch): Promise<Contributor[]>`, `renderContributorsSvg(contributors: Contributor[]): string`, and a CLI entry point using `GITHUB_REPOSITORY` and `GITHUB_TOKEN`.
- Produces `updateContributorsSvg(outputPath: string, repository: string, token: string, fetchImpl?: typeof fetch): Promise<void>`; it fetches and renders successfully before writing the output file.
- `Contributor` uses GitHub API `login`, `html_url`, `avatar_url`, and `contributions` fields; rendered contributors also carry an embedded `avatar_data_url`.

- [x] **Step 1: Write a failing test** named `fetches contributors across pages` with a mocked fetch returning 100 entries then one; assert two page requests and 101 returned users.
- [x] **Step 2: Run the test and verify it fails** because the generator module does not exist.

  Run: `node --test tests/update-contributors.test.mjs`
  Expected: FAIL because the generator module is missing.

- [x] **Step 3: Implement paginated `fetchContributors`** in `scripts/update-contributors.mjs`, failing on non-2xx responses or invalid payloads.
- [x] **Step 4: Add failing SVG tests** named `renders a valid empty-state SVG`, `escapes contributor labels and rejects unsafe profile/avatar URLs`, and `renders identical output for identical contributor data`; assert valid nonzero dimensions, accessible empty text, escaped XML, no unsafe URL in output, and byte-for-byte determinism.
- [x] **Step 5: Run the SVG tests and verify they fail** before the renderer exists.
- [x] **Step 6: Implement `renderContributorsSvg`** with a stable eight-column avatar layout, accessible labels, safe XML escaping, and GitHub-only profile/avatar URL validation.
- [x] **Step 7: Add failing tests** named `does not overwrite SVG when contributor fetch fails` and `embeds avatar bytes in SVG instead of relying on external images`; assert existing contents remain unchanged on API failure, embedded raster data is used, no avatar URL is emitted, and no token is sent to the avatar host.
- [x] **Step 8: Implement `updateContributorsSvg` and the CLI entry point** to fetch GitHub-hosted raster avatars without sending the API token, reject unsupported types or images over 256 KiB, and write `docs/contributors.svg` only after every fetch and render succeeds.
- [x] **Step 9: Generate the initial tracked image** by running the CLI against `emperhub/callshelf` with `GITHUB_TOKEN` supplied from `gh auth token`; verify `docs/contributors.svg` exists and is nonempty.
- [x] **Step 10: Run the generator tests and syntax check.**

  Run: `node --test tests/update-contributors.test.mjs && node --check scripts/update-contributors.mjs`
  Expected: all tests pass and Node syntax check exits 0.

### Task 2: Automate updates and replace the README name list

**Files:**
- Create: `.github/workflows/update-contributors.yml`
- Modify: `README.md`
- Consumes: Task 1 generator CLI and committed `docs/contributors.svg`.

- [x] **Step 1: Add failing integration tests** named `workflow updates contributors on main pushes and manual dispatch`, `workflow commits only changed SVG`, and `README embeds the generated image and retains Copilot credit`; assert the specified triggers, only `contents: write` permission, change guard, image path, and credit.
- [x] **Step 2: Run the integration tests and verify they fail** because the workflow and image embed do not exist yet.
- [x] **Step 3: Replace the static contributor list** in `README.md` with an accessible image link to `docs/contributors.svg`; keep a separate explicit GitHub Copilot credit.
- [x] **Step 4: Add a workflow** triggered on pushes to `main` and `workflow_dispatch`, using Node.js 20, `GITHUB_TOKEN`, and `contents: write`; run generator and tests, then commit/push only when the SVG differs.
- [x] **Step 5: Validate workflow YAML, README image path, and complete tests.**

  Run: `node --test tests/update-contributors.test.mjs && node --check scripts/update-contributors.mjs && ruby -e 'require "yaml"; YAML.load_file(".github/workflows/update-contributors.yml")' && git diff --check`
  Expected: all tests pass, JavaScript and YAML syntax checks exit 0, and no whitespace errors.

- [x] **Step 6: Commit the contributor image automation** with message `feat: add contributor avatar automation`.
