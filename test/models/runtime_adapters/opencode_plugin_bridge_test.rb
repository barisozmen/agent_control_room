require "test_helper"
require "open3"

class RuntimeAdapters::OpencodePluginBridgeTest < ActiveSupport::TestCase
  test "project plugin bridge is installed where opencode auto-loads local plugins" do
    plugin_path = Rails.root.join(".opencode/plugins/agent-passports.js")
    package_path = Rails.root.join(".opencode/package.json")

    assert_path_exists plugin_path
    assert_path_exists package_path

    plugin = plugin_path.read
    assert_includes plugin, '"permission.ask"'
    assert_includes plugin, "event: async"
    assert_includes plugin, '"tool.execute.before"'
    assert_includes plugin, '"tool.execute.after"'
    assert_includes plugin, "actor.delegated"
    assert_includes plugin, "parent_actor_ref"
    assert_includes plugin, "actor_name"
    assert_includes plugin, "AGENT_PASSPORTS_RUN_ID"
    assert_includes plugin, "AGENT_PASSPORTS_BRIDGE_TOKEN"
    assert_includes plugin, "AGENT_PASSPORTS_RUNTIME_EVENTS_URL"
    assert_includes plugin, "waitForPermissionDecision"
    assert_includes plugin, "permissionRequestUrl"
    assert_includes plugin, "AGENT_PASSPORTS_PERMISSION_TIMEOUT_MS"
    assert_includes plugin, 'output.status = "deny"'
    assert_includes plugin, "Agent Identity Control Room permission bridge denied by default"
  end

  test "permission ask waits for rails decisions and denies on polling trouble" do
    require_node_for_bridge_tests!

    stdout, stderr, status = Open3.capture3(node_test_env, "node", "--input-type=module", "-", stdin_data: node_permission_bridge_test, chdir: Rails.root.to_s)

    assert status.success?, "node bridge test failed\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
  end

  private

  def node_test_env
    {
      "AGENT_PASSPORTS_RUN_ID" => "test-run",
      "AGENT_PASSPORTS_BRIDGE_TOKEN" => "test-token",
      "AGENT_PASSPORTS_RUNTIME_EVENTS_URL" => "http://rails.test/runtime_events",
      "AGENT_PASSPORTS_PERMISSION_POLL_INTERVAL_MS" => "0",
      "AGENT_PASSPORTS_PERMISSION_TIMEOUT_MS" => "25"
    }
  end

  def node_permission_bridge_test
    <<~JAVASCRIPT
      import assert from "node:assert/strict"

      console.error = () => {}

      const pluginUrl = new URL("./.opencode/plugins/agent-passports.js", `file://${process.cwd()}/`).href
      const { AgentPassportsPlugin } = await import(pluginUrl)
      const plugin = await AgentPassportsPlugin()
      assert.equal(typeof plugin["permission.ask"], "function")

      function response(body, status = 200) {
        return {
          ok: status >= 200 && status < 300,
          status,
          async json() { return body },
          async text() { return JSON.stringify(body) },
        }
      }

      function fetchFrom(responses, calls = []) {
        return async (url, options = {}) => {
          calls.push({
            url: String(url),
            method: options.method || "GET",
            headers: options.headers || {},
            body: options.body ? JSON.parse(options.body) : undefined,
          })

          const next = responses.shift()
          if (next instanceof Error) throw next
          assert.ok(next, `unexpected fetch call to ${url}`)
          return next
        }
      }

      async function askWith(fetchImplementation, input = {}) {
        globalThis.fetch = fetchImplementation

        const output = {}
        await plugin["permission.ask"]({
          sessionID: "session-1",
          callID: "call-1",
          agent: "main-agent",
          type: "bash",
          title: "Run tests",
          pattern: "bin/rails test",
          ...input,
        }, output)

        return output.status
      }

      const childCalls = []
      globalThis.fetch = fetchFrom([ response({ status: "minted" }) ], childCalls)
      await plugin.event({
        event: {
          type: "session.updated",
          properties: {
            info: {
              id: "child-session",
              parentID: "session-1",
              title: "Explore sidebar session rendering (@explore subagent)",
            },
          },
        },
      })

      assert.equal(childCalls.length, 1)
      assert.equal(childCalls[0].method, "POST")
      assert.equal(childCalls[0].body.runtime_event.type, "actor.delegated")
      assert.equal(childCalls[0].body.runtime_event.session_id, "session-1")
      assert.equal(childCalls[0].body.runtime_event.event_id, "opencode-test-run-session-1-child-session-delegated")
      assert.equal(childCalls[0].body.runtime_event.actor_ref, "opencode-session-child-session")
      assert.equal(childCalls[0].body.runtime_event.parent_actor_ref, "main-agent")
      assert.equal(childCalls[0].body.runtime_event.actor_name, "opencode/explore")

      const childToolCalls = []
      assert.equal(await askWith(fetchFrom([ response({ status: "allowed" }) ], childToolCalls), {
        sessionID: "child-session",
        agent: undefined,
      }), "allow")
      assert.equal(childToolCalls[0].body.runtime_event.session_id, "session-1")
      assert.equal(childToolCalls[0].body.runtime_event.actor_ref, "opencode-session-child-session")
      assert.equal(childToolCalls[0].body.runtime_event.actor_name, "opencode/explore")
      assert.equal(childToolCalls[0].body.runtime_event.parent_actor_ref, "main-agent")

      assert.equal(await askWith(fetchFrom([ response({ status: "allowed" }) ])), "allow")
      assert.equal(await askWith(fetchFrom([ response({ status: "finished" }) ])), "allow")
      assert.equal(await askWith(fetchFrom([ response({ status: "blocked" }) ])), "deny")
      assert.equal(await askWith(fetchFrom([ response({ status: "denied" }) ])), "deny")

      for (const decision of ["allow_once", "passport_grant"]) {
        const calls = []
        const status = await askWith(fetchFrom([
          response({ status: "asking", permission_request_id: 42, permission_request_url: "http://rails.test/permission_requests/42" }),
          response({ status: "resolved", decision }),
        ], calls))

        assert.equal(status, "allow")
        assert.equal(calls.length, 2)
        assert.equal(calls[0].method, "POST")
        assert.equal(calls[0].url, "http://rails.test/runtime_events")
        assert.equal(calls[0].headers["x-agent-passports-bridge-token"], "test-token")
        assert.equal(calls[0].body.runtime_event.type, "tool.requested")
        assert.equal(calls[0].body.runtime_event.canonical_payload.hook, "permission.ask")
        assert.equal(calls[1].method, "GET")
        assert.equal(calls[1].url, "http://rails.test/permission_requests/42")
        assert.equal(calls[1].headers["x-agent-passports-bridge-token"], "test-token")
      }

      assert.equal(await askWith(fetchFrom([
        response({ status: "asking", permission_request_id: 43, permission_request_url: "http://rails.test/permission_requests/43" }),
        response({ status: "resolved", decision: "deny" }),
      ])), "deny")

      assert.equal(await askWith(fetchFrom([
        response({ status: "asking", permission_request_id: 44, permission_request_url: "http://rails.test/permission_requests/44" }),
        response({ ok: false }, 500),
      ])), "deny")

      let timeoutPolls = 0
      assert.equal(await askWith(async (url, options = {}) => {
        if ((options.method || "GET") === "POST") {
          return response({ status: "asking", permission_request_id: 45, permission_request_url: "http://rails.test/permission_requests/45" })
        }

        timeoutPolls += 1
        return response({ status: "pending" })
      }), "deny")
      assert.ok(timeoutPolls > 0)

      const afterCalls = []
      globalThis.fetch = fetchFrom([ response({ status: "finished" }) ], afterCalls)
      await plugin["tool.execute.after"]({
        sessionID: "session-2",
        callID: "call-2",
        agent: "main-agent",
        tool: "bash",
        args: { command: "bin/rails test" },
      }, {
        title: "Tests finished",
        exitCode: 0,
      })

      assert.equal(afterCalls.length, 1)
      assert.equal(afterCalls[0].method, "POST")
      assert.equal(afterCalls[0].headers["x-agent-passports-bridge-token"], "test-token")
      assert.equal(afterCalls[0].body.runtime_event.type, "tool.finished")
      assert.equal(afterCalls[0].body.runtime_event.event_id, "opencode-test-run-session-2-call-2-finished")
      assert.equal(afterCalls[0].body.runtime_event.source_event_id, "opencode-test-run-session-2-call-2-requested")
      assert.equal(afterCalls[0].body.runtime_event.capability, "bash")
      assert.equal(afterCalls[0].body.runtime_event.command, "bin/rails test")
      assert.equal(afterCalls[0].body.runtime_event.canonical_payload.hook, "tool.execute.after")
    JAVASCRIPT
  end
end
