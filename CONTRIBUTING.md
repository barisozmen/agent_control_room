# Contributing to Agent Control Room

Agent Control Room is a local-first Rails prototype for observing agent runtimes, showing agent and subagent authority, gating risky actions, and recording audit receipts. Contributions should keep that trust boundary clear: runtime adapters translate events, while the Rails core owns passports, grants, permission requests, decisions, and receipts.

## Local Setup

Install dependencies:

```bash
bin/setup --skip-server
```

Start the app:

```bash
bin/dev
```

Find the local URL:

```bash
bin/find_server_port --url
```

Install the OpenCode observer if you want to test real local OpenCode sessions:

```bash
bin/install_opencode_observer
```

The control room is intended for loopback development. Do not expose it on a LAN or public host without adding real app authentication.

## Test Before Opening a PR

Run the full test suite:

```bash
bin/rails test:all
```

Node must be available for the JavaScript bridge tests. For an intentional local opt-out, run with `SKIP_NODE_BRIDGE_TESTS=1`.

If your shell points Bundler at another repository:

```bash
env -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH bin/rails test:all
```

For UI or runtime-adapter work, also run the app locally and exercise the relevant flow from the browser.

## Architecture Rules

- Keep the authorization core runtime-neutral.
- Put runtime-specific parsing, launch behavior, hooks, plugins, and approval mapping behind runtime adapters.
- Prefer canonical runtime events over runtime-specific fields in shared models.
- Keep permission scopes visible and understandable before a user grants them.
- Preserve the local-first, fail-safe posture for gated actions.
- Add tests for new behavior, especially around permission decisions, grants, audit events, and adapter event translation.

The main adapter contract is documented in `docs/runtime_adapters.md`.

## Good First Contributions

- Improve setup docs for macOS, Linux, and fresh clone workflows.
- Add small tests around existing permission request, grant, and audit receipt behavior.
- Polish UI states for empty sessions, missing runtimes, failed launches, and completed runs.
- Improve copy where the UI explains actor lineage, passport authority, and scoped grants.
- Tighten demo reliability without weakening the runtime-neutral adapter boundary.

## Larger Contributions We Want

- Full Claude Code and Codex per-tool permission bridges.
- New runtime adapters that emit the canonical event contract.
- Better OpenCode hook coverage and clearer failure handling.
- Richer passport scope previews, including safer command and file-pattern descriptions.
- Exportable or shareable audit receipts for post-run review.
- Security hardening for any mode beyond loopback-only local development.

## Pull Request Checklist

- The change has a focused purpose and avoids unrelated refactors.
- New behavior has tests, or the PR explains why it is documentation-only.
- Runtime-specific code stays inside the adapter layer.
- The README or docs are updated when setup, behavior, or architecture changes.
- The app still works as a local-first tool with no hosted service dependency.
