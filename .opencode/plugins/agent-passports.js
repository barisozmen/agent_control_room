const RUN_ID = process.env.AGENT_PASSPORTS_RUN_ID
const EVENTS_URL = process.env.AGENT_PASSPORTS_RUNTIME_EVENTS_URL
const BRIDGE_TOKEN = process.env.AGENT_PASSPORTS_BRIDGE_TOKEN
const PERMISSION_POLL_INTERVAL_MS = Number(process.env.AGENT_PASSPORTS_PERMISSION_POLL_INTERVAL_MS || 1000)
const PERMISSION_TIMEOUT_MS = Number(process.env.AGENT_PASSPORTS_PERMISSION_TIMEOUT_MS || 120000)

export const AgentPassportsPlugin = async () => {
  if (!RUN_ID || !EVENTS_URL || !BRIDGE_TOKEN) return {}

  return {
    "permission.ask": async (input, output) => {
      try {
        const response = await postToolRequested(permissionEvent(input))
        const immediateDecision = opencodeDecisionFor(response)

        if (immediateDecision) {
          output.status = immediateDecision
          return
        }

        if (response.status === "asking") {
          output.status = await waitForPermissionDecision(response)
          return
        }

        throw new Error(`Unexpected Agent Control Room permission status: ${response.status || "missing"}`)
      } catch (error) {
        console.error("Agent Control Room permission bridge denied by default:", error)
        output.status = "deny"
      }
    },

    "tool.execute.before": async (input, output) => {
    },

    "tool.execute.after": async (input, output) => {
      await postRuntimeEvent({
        ...toolEvent(input, output, "tool.execute.after"),
        type: "tool.finished",
        event_id: eventId(input.sessionID, input.callID, "finished"),
        source_event_id: eventId(input.sessionID, input.callID, "requested"),
        exit_status: exitStatusFor(output),
        action_summary: output?.title || `${input.tool} finished`,
      })
    },
  }
}

async function postToolRequested(payload) {
  return postRuntimeEvent({
    type: "tool.requested",
    runtime_name: "opencode",
    ...payload,
  })
}

async function postRuntimeEvent(payload) {
  const response = await fetch(EVENTS_URL, {
    method: "POST",
    headers: bridgeHeaders({ "content-type": "application/json" }),
    body: JSON.stringify({
      runtime_event: {
        run_id: RUN_ID,
        occurred_at: new Date().toISOString(),
        ...payload,
      },
    }),
  })

  if (!response.ok) {
    const body = await response.text()
    throw new Error(`Agent Control Room bridge failed: ${response.status} ${body}`)
  }

  return response.json()
}

async function waitForPermissionDecision(initialResponse) {
  const url = permissionRequestUrl(initialResponse)
  if (!url) throw new Error("Rails returned asking without a permission_request_id or permission_request_url")

  const deadline = Date.now() + PERMISSION_TIMEOUT_MS
  while (Date.now() < deadline) {
    const response = await fetchPermissionRequest(url)
    const decision = opencodeDecisionFor(response)
    if (decision) return decision

    await sleep(PERMISSION_POLL_INTERVAL_MS)
  }

  throw new Error(`Timed out waiting ${PERMISSION_TIMEOUT_MS}ms for permission request ${initialResponse.permission_request_id}`)
}

async function fetchPermissionRequest(url) {
  const response = await fetch(url, { headers: bridgeHeaders({ "accept": "application/json" }) })

  if (!response.ok) {
    const body = await response.text()
    throw new Error(`Agent Control Room permission poll failed: ${response.status} ${body}`)
  }

  return response.json()
}

function permissionRequestUrl(response) {
  if (response.permission_request_url) return response.permission_request_url
  if (response.permission_request_path) return new URL(response.permission_request_path, EVENTS_URL).toString()
  if (response.permission_request_id) return new URL(`/permission_requests/${response.permission_request_id}`, EVENTS_URL).toString()
}

function opencodeDecisionFor(response) {
  if (!response) return undefined
  if (["allowed", "finished"].includes(response.status)) return "allow"
  if (["blocked", "denied"].includes(response.status)) return "deny"
  if (response.status === "resolved" && ["allow_once", "passport_grant"].includes(response.decision)) return "allow"
  if (response.status === "resolved" && response.decision === "deny") return "deny"
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function bridgeHeaders(headers = {}) {
  return {
    ...headers,
    "x-agent-passports-bridge-token": BRIDGE_TOKEN,
  }
}

function toolEvent(input, output, hook = "tool.execute.before") {
  const args = output?.args || input.args
  const actionText = summarizeArgs(args)
  const capability = capabilityFor(input.tool)

  return {
    event_id: eventId(input.sessionID, input.callID, "requested"),
    actor_ref: actorRef(input),
    capability,
    action_kind: input.tool,
    action_summary: `${input.tool}: ${actionText}`,
    command: commandFor(input.tool, args),
    path: pathFor(args),
    canonical_payload: { hook, tool: input.tool, args },
    risk_level: riskLevelFor(capability),
    risk_summary: riskSummaryFor(capability, actionText),
    suggested_capability: capability,
    suggested_pattern: suggestedPatternFor(input.tool, args, actionText),
  }
}

function exitStatusFor(output) {
  if (typeof output?.exitCode === "number") return output.exitCode
  if (typeof output?.exit_status === "number") return output.exit_status
  if (typeof output?.code === "number") return output.code
  return 0
}

function permissionEvent(input) {
  const text = Array.isArray(input.pattern) ? input.pattern.join(" ") : input.pattern || input.title
  const capability = capabilityFor(input.type)
  const callID = input.callID || input.id

  return {
    event_id: eventId(input.sessionID, callID, "requested"),
    actor_ref: actorRef(input),
    capability,
    action_kind: input.type,
    action_summary: input.title || `${input.type}: ${text}`,
    command: input.type === "bash" ? text : undefined,
    path: pathFromPattern(text),
    canonical_payload: { hook: "permission.ask", permission: input },
    risk_level: riskLevelFor(capability),
    risk_summary: riskSummaryFor(capability, text),
    suggested_capability: capability,
    suggested_pattern: text,
  }
}

function eventId(sessionID, callID, suffix) {
  return `opencode-${RUN_ID}-${sessionID}-${callID}-${suffix}`
}

function actorRef(input) {
  return stringValue(input.agent)
    || stringValue(input.agentID)
    || stringValue(input.agentId)
    || stringValue(input.actor)
    || stringValue(input.actor_ref)
    || stringValue(input.actorRef)
    || stringValue(input.session?.agent)
    || "main-agent"
}

function stringValue(value) {
  if (!value) return undefined
  if (typeof value === "string") return value
  if (typeof value === "object") return value.id || value.name || value.ref
}

function capabilityFor(tool) {
  if (["bash", "shell"].includes(tool)) return "bash"
  if (["edit", "write", "patch"].includes(tool)) return "edit"
  if (["webfetch", "websearch", "fetch"].includes(tool)) return "web"
  if (["task", "subtask"].includes(tool)) return "delegate"
  return "read"
}

function summarizeArgs(args) {
  if (!args || typeof args !== "object") return String(args || "")
  return args.command || args.filePath || args.path || args.pattern || JSON.stringify(args)
}

function commandFor(tool, args) {
  return capabilityFor(tool) === "bash" ? summarizeArgs(args) : undefined
}

function pathFor(args) {
  if (!args || typeof args !== "object") return undefined
  return args.filePath || args.path || pathFromPattern(args.pattern)
}

function pathFromPattern(pattern) {
  if (!pattern || typeof pattern !== "string") return undefined
  return pattern.includes("/") || pattern.includes(".") ? pattern : undefined
}

function suggestedPatternFor(tool, args, fallback) {
  return commandFor(tool, args) || pathFor(args) || fallback
}

function riskLevelFor(capability) {
  if (capability === "web") return "high"
  if (["bash", "edit", "delegate"].includes(capability)) return "medium"
  return "low"
}

function riskSummaryFor(capability, text) {
  const subject = text || "runtime action"
  if (capability === "bash") return `Runs a local command: ${subject}`
  if (capability === "edit") return `May change local project files: ${subject}`
  if (capability === "web") return `May access the network: ${subject}`
  if (capability === "delegate") return `May delegate work to another agent: ${subject}`
  return `Reads local project context: ${subject}`
}
