# Idea Maze - Local coding-agent authority control room

*Date: 2026-06-27*
*Maze label: local coding-agent governance, observability, and delegated authority*

## The idea (one sentence)

A local-first Rails control room that observes coding-agent sessions across runtimes, shows delegation and passport lineage, gates risky tool actions with scoped grants, and writes audit receipts.

## Research snapshot

The category is active, not empty. The strongest adjacent tools found on GitHub and product docs:

- **Cordum** - Source-available agent control plane with policy enforcement, approval gates, audit trails, and a Claude Code "Compliance Firewall" path. GitHub API on 2026-06-27 showed 484 stars, created 2026-01-11. <https://github.com/cordum-io/cordum>
- **Microsoft Agent Governance Toolkit** - Public preview governance SDK/toolkit for policy enforcement, identity, sandboxing, and audit across autonomous agents. GitHub API showed 4,534 stars, created 2026-03-02. <https://github.com/microsoft/agent-governance-toolkit>
- **OpenHands / Agent Canvas** - Self-hosted developer control center for OpenHands, Claude Code, Codex, Gemini, and ACP-compatible agents; can run local, remote, cloud, or sandboxed agent backends. GitHub API showed OpenHands at 78,503 stars and Agent Canvas at 119 stars. <https://github.com/OpenHands/OpenHands> and <https://github.com/OpenHands/agent-canvas>
- **Cline and Roo Code** - Popular coding agents with approval and auto-approval modes; Cline API showed 63,952 stars, Roo Code showed 24,288 stars. <https://github.com/cline/cline> and <https://github.com/RooCodeInc/Roo-Code>
- **OpenCode, Claude Code, Codex, VS Code** - Runtime/editor-native permission systems. OpenCode has allow/ask/deny per tool and per agent; Claude Code has hierarchical permissions, hooks, subagent events, and managed settings; Codex has approval policies, sandbox modes, multi-agent features, and managed controls; VS Code has tool, URL, terminal, and sandbox approval controls.
- **Langfuse, LangSmith, Phoenix, AgentOps** - Agent/LLM observability and tracing platforms. These are powerful adjacent incumbents, but mostly post-execution trace/eval systems rather than local pre-execution authority control.
- **agentgateway, Arcade, Permit.io, Composio, MCP-Scan / Invariant** - Agent authorization, MCP gateway, OAuth, policy, monitoring, and security tooling. These validate that "agent authorization" is a real budget line, but they mostly govern app/API/MCP edges rather than local coding-runtime delegation, bash, file writes, and subagent identity.
- **HumanLayer / CodeLayer** - Started around human approval for agent function calls and moved toward an AI IDE / collaboration platform. The public GitHub README now says the code is mostly deprecated and points to the rebuild. <https://github.com/humanlayer/humanlayer>

## Graveyard

- **Generic LLM trace dashboard path, 2023-present** - Thesis: capture every LLM and tool call for debugging, evals, cost, and latency. Death for this idea: Langfuse, LangSmith, Phoenix, and AgentOps already own this surface. What's different now: Agent Control Room can win only if it is pre-execution authority and delegated identity, not another trace viewer.
- **Runtime-native approval prompt path, 2024-present** - Thesis: each coding agent asks before risky tools and lets users auto-approve safe actions. Cline, Roo, OpenCode, Claude Code, Codex, and VS Code all have versions of this. Death: approval fatigue turns into broad auto-approval, and each runtime sees only its own session. What's different now: a cross-runtime passport layer can explain "who is acting under whose authority" instead of showing anonymous prompts.
- **Broad enterprise agent governance path, 2026-present** - Thesis: provide policy engines, identity, sandboxing, approval, and audit for all autonomous agents. Cordum and Microsoft AGT are already in this lane. Death: a small product loses by scope, compliance claims, and enterprise sales motion. What's different now: the wedge can be local, developer-owned, coding-runtime-specific, and open source instead of general enterprise governance.
- **Agent IDE / orchestration canvas path, 2024-present** - Thesis: own the full place where developers start, schedule, and monitor coding agents. OpenHands Agent Canvas is directly pursuing this. Death: if Agent Control Room tries to become the IDE/canvas, it competes with the runtime surface. What's different now: it can be the authority layer under or beside multiple canvases.
- **MCP gateway / agent auth path, 2025-present** - Thesis: agents need governed access to external tools, OAuth, consent, and audit. agentgateway, Arcade, Permit.io, Composio, and MCP-Scan validate this. Death: only governing MCP misses local file, shell, git, and subagent actions. What's different now: combine MCP/tool authorization with local coding-agent process authority.
- **OS sandbox-only path, old security pattern applied to agents** - Thesis: restrict process filesystem/network access. Death: sandboxing tells you what a process can touch, not which subagent requested it, what scope was granted, or why. What's different now: runtime hooks expose semantic intent before execution, which can be paired with sandbox evidence later.
- **Human approval API path, 2024-present** - Thesis: route high-stakes agent tool calls to humans. HumanLayer proved demand for approval workflows, then shifted toward coding-agent collaboration. Death: generic human approval is not enough; approval must carry actor lineage, scoped authority, and local runtime context. What's different now: coding agents are spawning subagents and running local tools, so authority needs a visible tree.

## Analogies

- **Worked: Kubernetes admission controllers / OPA Gatekeeper** - Structural similarity: intercept a proposed action, evaluate policy before execution, and emit an audit trail. Where it holds: deterministic pre-action control outside the workload. Where it breaks: coding-agent actions are conversational, local, and lineage-bearing; the user needs an operator UI, not just policy YAML.
- **Worked: sudo and macOS TCC** - Structural similarity: local permission prompts for high-risk capability use. Where it holds: users understand scoped local authority. Where it breaks: process/user identity is too coarse for delegated agents and subagents.
- **Worked: GitHub branch protection and code review** - Structural similarity: a human approves a risky change before it lands. Where it holds: scoped review, auditability, and receipts. Where it breaks: PR review is too late for local secret reads, destructive shell commands, or exfiltration.
- **Failed: generic log viewer as safety layer** - Structural similarity: visibility after the fact. Why it failed for this maze: logs explain failures but do not prevent risky actions before they execute.
- **Failed: YOLO auto-approval as productivity layer** - Structural similarity: reduce prompt friction by allowing more actions. Why it failed for this maze: it destroys the control surface unless grants are narrow, visible, and revocable.

## Theory

- **Bottom-up developer adoption**: The first user is one developer running local agents. The product must install fast, stay loopback/local, improve daily control, and avoid a SaaS trust hurdle. If it asks for enterprise setup before proving solo utility, it dies.
- **Deterministic control plane vs prompt safety**: Cordum and Microsoft AGT are right that prompt-level safety is not a control surface. Agent Control Room's honest v1 is weaker than a true sandbox because it depends on runtime hooks, but stronger than a trace dashboard because it gates intent before execution.
- **Adapter contract / aggregation theory**: The durable asset is not the Rails UI by itself; it is a canonical event and authority model that can ingest OpenCode, Claude Code, Codex, and future runtimes. The risk is that each runtime ships its own good-enough control UI and leaves no room for an independent adapter layer.
- **Where frameworks disagree**: Bottom-up adoption says stay tiny and local. Control-plane theory says enterprise buyers will demand policy, sandboxing, managed config, and tamper evidence. The resolution is a staged path: local authority UI first, adapter conformance second, deeper sandbox/evidence third.

## Direct experience

- **Asymmetric insight**: The repo shows hands-on familiarity with the exact pain: OpenCode-first observer, canonical runtime events, passport tree, permission inbox, scoped grants, audit timeline, and demo adapters for Claude Code and Codex.
- **Founder-maze fit**: Strong for local developer tooling and agent workflow taste. Weaker if the path moves immediately into enterprise compliance sales.
- **Bizarre behavior observed or implied**: Developers already juggle runtime-specific approval prompts, YOLO/auto-approve modes, terminal logs, editor sidebars, and ad hoc trust in agent subthreads. The ugly workaround is "approve prompts without knowing which delegated actor is asking" or "turn on broad auto-approve because the prompts are too noisy."
- **Missing direct evidence**: No external user interviews are captured in this artifact. The map is strong on public market history and repo-informed intuition, but still weak on observed demand outside the builder.

## The maze

### Dead ends

- **Build a generic LLM observability product** - why it kills: Langfuse, LangSmith, Phoenix, and AgentOps are already mature and broader.
- **Build a broad enterprise governance platform first** - why it kills: Cordum, AGT, Arcade, Permit, and agentgateway will out-scope a small local prototype.
- **Stay OpenCode-specific** - why it kills: useful demo, but the runtime can absorb the feature and the product loses the "runtime-neutral authority" claim.
- **Lead with OS sandboxing** - why it kills: high engineering cost, cross-platform complexity, and delayed proof of the passport UI.
- **Make it a hidden daemon** - why it kills: the product promise is legibility; invisible governance becomes another trust black box.
- **Use broad "always allow" grants** - why it kills: it recreates the exact approval fatigue problem under a nicer label.

### Trap doors

- **Approval fatigue after the demo** - latent failure: users click through or disable the tool unless passport grants reduce prompts without hiding risk.
- **Fail-open hooks marketed as hard security** - latent failure: users assume enforcement that v1 cannot guarantee, damaging trust after one bypass.
- **Local-first without authentication boundaries** - latent failure: a loopback demo accidentally exposed on LAN becomes a serious security issue.
- **Runtime adapters with incompatible semantics** - latent failure: the canonical event model becomes a pile of runtime-specific exceptions.
- **Audit receipts that are not tamper-evident** - latent failure: they help debugging but cannot support the governance story.
- **Subagent lineage drift** - latent failure: if parent/child edges are wrong, the whole passport metaphor collapses.
- **Policy language too early** - latent failure: sophisticated configuration arrives before anyone has proved the simple permission inbox matters.

### Hidden paths (the founder's bet)

- **Passport as the user-legible primitive** - evidence it is real: runtime docs now expose agents, subagents, task tools, permission modes, and hooks; users need a noun that binds identity plus authority.
- **Canonical runtime event contract** - evidence it is real: this repo already defines `session.started`, `actor.delegated`, `tool.requested`, `tool.finished`, `tool.blocked`, and `session.finished`; OpenCode, Claude Code, and Codex all expose enough surface to test adapters.
- **Local coding-agent control instead of enterprise agent governance** - evidence it is real: Cline, OpenHands, Codex, Claude Code, and OpenCode adoption shows developers run local autonomous tools now; enterprise control planes are not optimized for the solo local loop.
- **MCP security plus local shell/file authority** - evidence it is real: MCP-Scan and agentgateway show the network/tool side is hot, but coding agents also need governance over bash, edits, git, external directories, and delegated subagents.
- **Beautiful live control room as trust builder** - evidence it is real: raw logs do not teach authority; the repo's UI thesis is that hierarchy, asks, scoped grants, and receipts should be visible in one place.

## Why now

- **The wall that moved**: coding-agent runtimes now expose enough hook, permission, subagent, and sandbox surfaces to build an external authority layer without building the agent runtime itself.
- **Specific events/dates**:
  - OpenCode permissions docs updated on 2026-06-26 describe allow/ask/deny rules, per-agent permissions, and approval outcomes.
  - Claude Code docs now describe hierarchical settings, managed permissions, hooks such as `PreToolUse`, `PermissionRequest`, `SubagentStart`, and `TaskCreated`.
  - Codex docs expose approval policies, sandbox modes, managed permission profiles, MCP allowlists, and multi-agent features; the openai/codex repository was created 2025-04-13 and showed 94,060 stars on 2026-06-27.
  - The market moved from "toy local assistants" to high-adoption agents: Cline repo created 2024-07-06 and showed 63,952 stars; OpenHands created 2024-03-13 and showed 78,503 stars.
  - Agent authorization became fundable infrastructure: Arcade announced a $60M Series A in June 2026 around AI agent authorization.

Weak "why now" answer to avoid: "AI agents are big." The stronger version is: "local coding agents now execute real shell/file/tool actions and expose interceptable lifecycle hooks, while users are already hitting approval fatigue and runtime fragmentation."

## Verdict

- **Map quality**: partial map. Strong on history, competitors, and why-now. Still weak on direct customer evidence outside the current builder.
- **Next deliverable**: do not add broad features yet. Interview or observe 5-7 developers who run Claude Code, Codex, OpenCode, Cline, Roo, Cursor, or OpenHands for real work. Install the local control room for at least 3 real tasks each. Measure whether they keep it on, whether they understand passport lineage, and whether scoped grants reduce prompt fatigue.
- **Second deliverable**: prove runtime neutrality by adding one non-OpenCode permission bridge behind the same canonical event contract, with a conformance test harness.
- **Kill criterion**: kill or radically narrow the idea if 5 serious local-agent users do not keep the control room running for real work after the demo, or if scoped grants do not reduce approval fatigue without becoming broad auto-approval.
- **Technical kill criterion**: kill the runtime-neutral thesis if a second full permission bridge cannot be integrated without changing the authorization core.

## Open questions to resolve before entering

- Which exact first persona cares most: solo power user, open-source maintainer, security-conscious startup engineer, or enterprise platform/security team?
- Is the first wedge "multi-runtime local control" or "OpenCode authority done beautifully"?
- What is the minimal tamper-evidence story for local receipts before enterprise claims begin?
- How does a passport grant expire, get revoked, or get explained after the session?
- What is the boundary between runtime-level intent gating and OS/process/network ground truth?
- Can the UI make approval faster than native prompts while showing more authority context?
- Should the product integrate with MCP-Scan/agentgateway later, or own MCP inspection itself?
- What has to be true for external runtime authors to adopt the canonical event contract?

## Source links

- Project docs read locally: `README.md`, `docs/manifesto.md`, `docs/spec.md`, `docs/destination_plan.md`, `docs/path_plan.md`.
- OpenCode permissions: <https://opencode.ai/docs/permissions>
- Claude Code settings and hooks: <https://code.claude.com/docs/en/settings> and <https://code.claude.com/docs/en/hooks>
- Codex security and config: <https://developers.openai.com/codex/security> and <https://developers.openai.com/codex/config-reference>
- VS Code approvals: <https://code.visualstudio.com/docs/agents/approvals>
- Cline auto-approve and permissions: <https://docs.cline.bot/features/auto-approve> and <https://docs.cline.bot/sdk/guides/permission-handling>
- Roo Code auto-approval: <https://roocodeinc.github.io/Roo-Code/features/auto-approving-actions/>
- Cordum: <https://github.com/cordum-io/cordum>
- Microsoft Agent Governance Toolkit: <https://github.com/microsoft/agent-governance-toolkit>
- OpenHands / Agent Canvas: <https://github.com/OpenHands/OpenHands> and <https://github.com/OpenHands/agent-canvas>
- HumanLayer: <https://github.com/humanlayer/humanlayer> and <https://www.humanlayer.dev/>
- Langfuse: <https://langfuse.com/docs/observability/overview>
- LangSmith: <https://docs.langchain.com/langsmith/observability>
- Phoenix: <https://github.com/Arize-ai/phoenix>
- AgentOps: <https://docs.agentops.ai/v1/introduction>
- agentgateway: <https://github.com/agentgateway/agentgateway> and <https://agentgateway.dev/>
- Arcade authorized tool calling: <https://docs.arcade.dev/en/guides/tool-calling/custom-apps/auth-tool-calling>
- Composio Connect: <https://docs.composio.dev/docs/composio-connect>
- Permit.io MCP Gateway: <https://docs.permit.io/>
- MCP-Scan / Invariant: <https://invariantlabs-ai.github.io/docs/mcp-scan/> and <https://invariantlabs-ai.github.io/docs/mcp-scan/proxying/>
