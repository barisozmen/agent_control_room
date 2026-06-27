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
      function response(body, status = 200) {
        return {
          ok: status >= 200 && status < 300,
          status,
          async json() { return body },
          async text() { return JSON.stringify(body) },
        }
      }

      globalThis.fetch = async (url, options = {}) => {
        calls.push({
          url: String(url),
          method: options.method || "GET",
          headers: options.headers || {},
          body: options.body ? JSON.parse(options.body) : undefined,
        })

        if ((options.method || "GET") === "GET") return response({ status: "resolved", decision: "allow_once" })
        if (calls.length === 1) return response({ status: "running", run_id: 9 })
        return response({ status: "asking", permission_request_id: 11, permission_request_url: "http://rails.test/permission_requests/11" })
      }

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
      assert.equal(calls[0].url, "http://rails.test/opencode/events")
      assert.equal(calls[0].headers["x-agent-passports-machine-token"], "machine-test-token")
      assert.equal(calls[0].body.opencode_event.type, "session.started")
      assert.equal(calls[1].body.opencode_event.type, "tool.requested")
      assert.equal(calls[1].body.opencode_event.session_id, "session-observer")
      assert.equal(calls[2].url, "http://rails.test/permission_requests/11")
      assert.equal(calls[2].headers["x-agent-passports-machine-token"], "machine-test-token")
    JAVASCRIPT
  end
end
