# Agent Passports

Agent Passports is a local Rails control room for coding-agent runs, passport hierarchy, permission requests, scoped grants, and audit receipts. OpenCode is the first full bridge; Claude Code and Codex use the shared runtime adapter boundary.

## Source Of Truth

- `docs/requirements.md` - launch constraints and goals.
- `docs/manifesto.md` - why this exists and what v1 refuses.
- `docs/destination_plan.md` - long-term destination.
- `docs/path_plan.md` - staged release path.
- `docs/spec.md` - v1 features, routes, and runtime adapter boundary.
- `docs/user_flows/` - Rails user flows and the community demo.
- `docs/DESIGN.md` - UI design system. Read before changing views or CSS.
- `docs/domain_model.md` - Rails models, tables, relationships, and invariants.
- `docs/tech_stack.md` - stack choices, setup commands, and verification.

## Working Rules

- Keep the core runtime-neutral. Opencode is the first adapter, not the internal shape of the authorizer.
- Do not add dark mode in v1. The design is opencode-like light mode only.
- The first useful screen is the Rails control room, not a marketing landing page.
- Use generator-first Rails development, but do not install broad kit features that violate `docs/manifesto.md`.
- Keep facts in one owning doc and link rather than duplicating.

## Local Commands

```bash
bin/setup --skip-server
bin/dev
bin/rails test
```

If this shell has `BUNDLE_GEMFILE` set to another repo, prefix commands with:

```bash
env -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH bin/rails test
```

## Dev Server Port (deterministic, hashed)

A single shared dev server is usually already running — **reuse it, don't start
your own.** A second `bin/dev`/`bin/rails server` fails on `tmp/pids/server.pid`
("A server is already running") and SIGTERMs the whole foreman group.

**Do not assume port 3000.** This project's dev port is **deterministic**: a hash
of the folder name into the band `3000..3999`. `bin/dev` boots on it automatically.
Never guess the port — resolve it:

```bash
PORT=$(bin/find_server_port)                 # bare port, e.g. 3712
URL=$(bin/find_server_port --url)            # http://localhost:3712
curl -s "$(bin/find_server_port --url)/up"   # confirm it's actually up
```

`bin/find_server_port` (the single source of truth for port assignment) hashes
the folder name to a stable port; if our server is already running it reports the
exact live port (recorded in `tmp/pids/dev_server.port`), otherwise it returns the
hashed slot, walking forward only if another project already holds it. It always
prints a port — so before relying on the server, confirm it answers (`curl .../up`).
This repo intentionally ignores inherited shell-level `PORT` values in `bin/dev`;
use `AGENT_PASSPORTS_PORT=xxxx bin/dev` for a deliberate override.
If nothing is listening, **do not start your own server** — verify changes with
`bin/rails test` (system tests boot their own random-port server, conflict-free),
or ask the user to run `bin/dev`.
