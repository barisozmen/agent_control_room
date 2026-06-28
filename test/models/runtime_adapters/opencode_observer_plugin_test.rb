require "test_helper"
require "open3"

class RuntimeAdapters::OpencodeObserverPluginTest < ActiveSupport::TestCase
  test "global observer plugin source is importable and posts machine events" do
    require_node_for_bridge_tests!

    stdout, stderr, status = Open3.capture3(node_test_env, "node", "--input-type=module", "-", stdin_data: node_observer_test, chdir: Rails.root.to_s)

    assert status.success?, "node observer test failed\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
  end

  private

  def node_test_env
    {
      "AGENT_PASSPORTS_SERVER_URL" => "http://rails.test",
      "AGENT_PASSPORTS_MACHINE_TOKEN" => "machine-test-token",
      "AGENT_PASSPORTS_PERMISSION_POLL_INTERVAL_MS" => "0",
      "AGENT_PASSPORTS_PERMISSION_TIMEOUT_MS" => "25"
    }
  end

  def node_observer_test
    <<~JAVASCRIPT
      import assert from "node:assert/strict"

      const pluginUrl = new URL("./lib/opencode/agent-passports-observer.js", `file://${process.cwd()}/`).href
      const { AgentPassportsObserver } = await import(pluginUrl)
      const plugin = await AgentPassportsObserver({ directory: "/tmp/project", worktree: "/tmp/project", project: { name: "project" } })

      const calls = []
      const queuedResponses = []

      function response(body, status = 200) {
        return {
          ok: status >= 200 && status < 300,
          status,
          async json() { return body },
          async text() { return JSON.stringify(body) },
        }
      }

      function enqueueResponses(...responses) {
        queuedResponses.push(...responses)
      }

      globalThis.fetch = async (url, options = {}) => {
        calls.push({
          url: String(url),
          method: options.method || "GET",
          headers: options.headers || {},
          body: options.body ? JSON.parse(options.body) : undefined,
        })

        const next = queuedResponses.shift()
        if (next instanceof Error) throw next
        assert.ok(next, `unexpected fetch call to ${url}`)
        return next
      }

      function assertOpencodePost(call, type) {
        assert.equal(call.url, "http://rails.test/opencode/events")
        assert.equal(call.method, "POST")
        assert.equal(call.headers["content-type"], "application/json")
        assert.equal(call.headers["x-agent-passports-machine-token"], "machine-test-token")
        assert.equal(call.body.opencode_event.type, type)
        assert.equal(call.body.opencode_event.runtime_name, "opencode")
        assert.equal(call.body.opencode_event.session_id, "session-observer")
        assert.ok(call.body.opencode_event.occurred_at)
      }

      enqueueResponses(response({ status: "running", run_id: 9 }))
      await plugin.event({
        event: {
          sessionID: "session-observer",
          type: "session.updated",
          apiToken: "secret-token",
        },
      })

      assert.equal(calls.length, 1)
      assertOpencodePost(calls[0], "session.started")
      assert.equal(calls[0].body.opencode_event.event_id, "opencode-observed-session-observer-session-started")
      assert.equal(calls[0].body.opencode_event.title, "project")
      assert.equal(calls[0].body.opencode_event.project_path, "/tmp/project")
      assert.equal(calls[0].body.opencode_event.canonical_payload.hook, "session")
      assert.equal(calls[0].body.opencode_event.canonical_payload.event.apiToken, "[redacted]")

      await plugin.event({ event: { sessionID: "session-observer", type: "session.updated" } })
      assert.equal(calls.length, 1)

      enqueueResponses(
        response({ status: "asking", permission_request_id: 11, permission_request_url: "http://rails.test/permission_requests/11" }),
        response({ status: "resolved", decision: "allow_once" })
      )

      const output = {}
      await plugin["permission.ask"]({
        sessionID: "session-observer",
        callID: "call-observer",
        agent: "main-agent",
        type: "bash",
        title: "Run tests",
        pattern: "bin/rails test",
      }, output)

      assert.equal(output.status, "allow")
      assertOpencodePost(calls[1], "tool.requested")
      assert.equal(calls[1].body.opencode_event.session_id, "session-observer")
      assert.equal(calls[1].body.opencode_event.event_id, "opencode-observed-session-observer-call-observer-requested")
      assert.equal(calls[1].body.opencode_event.command, "bin/rails test")
      assert.equal(calls[1].body.opencode_event.canonical_payload.hook, "permission.ask")
      assert.equal(calls[2].url, "http://rails.test/permission_requests/11")
      assert.equal(calls[2].method, "GET")
      assert.equal(calls[2].headers["accept"], "application/json")
      assert.equal(calls[2].headers["x-agent-passports-machine-token"], "machine-test-token")

      enqueueResponses(response({ status: "denied" }))
      await assert.rejects(
        () => plugin["tool.execute.before"]({
          sessionID: "session-observer",
          callID: "call-before",
          agent: "main-agent",
          tool: "bash",
          args: { command: "bin/rails db:migrate" },
        }, {}),
        /Agent Identity Control Room denied this tool call/
      )

      assertOpencodePost(calls[3], "tool.requested")
      assert.equal(calls[3].body.opencode_event.event_id, "opencode-observed-session-observer-call-before-requested")
      assert.equal(calls[3].body.opencode_event.capability, "bash")
      assert.equal(calls[3].body.opencode_event.command, "bin/rails db:migrate")
      assert.equal(calls[3].body.opencode_event.canonical_payload.hook, "tool.execute.before")

      enqueueResponses(response({ status: "finished" }))
      await plugin["tool.execute.after"]({
        sessionID: "session-observer",
        callID: "call-after",
        agent: "main-agent",
        tool: "edit",
        args: { filePath: "app/models/run.rb" },
      }, {
        title: "Edit finished",
        exitCode: 0,
      })

      assertOpencodePost(calls[4], "tool.finished")
      assert.equal(calls[4].body.opencode_event.event_id, "opencode-observed-session-observer-call-after-finished")
      assert.equal(calls[4].body.opencode_event.source_event_id, "opencode-observed-session-observer-call-after-requested")
      assert.equal(calls[4].body.opencode_event.capability, "edit")
      assert.equal(calls[4].body.opencode_event.path, "app/models/run.rb")
      assert.equal(calls[4].body.opencode_event.exit_status, 0)
      assert.equal(calls[4].body.opencode_event.action_summary, "Edit finished")
      assert.equal(calls[4].body.opencode_event.canonical_payload.hook, "tool.execute.after")

      enqueueResponses(response({ status: "completed" }))
      await plugin.dispose()

      assertOpencodePost(calls[5], "session.finished")
      assert.equal(calls[5].body.opencode_event.event_id, "opencode-observed-session-observer-session-finished")
      assert.equal(calls[5].body.opencode_event.status, "completed")
      assert.equal(calls[5].body.opencode_event.title, "project")
      assert.equal(calls[5].body.opencode_event.project_path, "/tmp/project")

      assert.equal(calls.length, 6)
      assert.equal(queuedResponses.length, 0)
    JAVASCRIPT
  end
end
