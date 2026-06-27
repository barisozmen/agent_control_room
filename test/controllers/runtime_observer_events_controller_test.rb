require "test_helper"

class RuntimeObserverEventsControllerTest < ActionDispatch::IntegrationTest
  test "rejects observer events without machine token" do
    assert_no_difference -> { Run.count } do
      post runtime_observer_events_path(runtime_name: "codex"),
        params: { runtime_event: { type: "session.started", session_id: "missing-token" } },
        as: :json
    end

    assert_response :unauthorized
    assert_equal false, response_json.fetch("ok")
    assert_equal "Invalid machine token", response_json.fetch("error")
  end

  test "rejects observer events with invalid machine token" do
    assert_no_difference -> { Run.count } do
      post runtime_observer_events_path(runtime_name: "codex"),
        params: { runtime_event: { type: "session.started", session_id: "invalid-token" } },
        headers: { MachineBridge::HEADER => "invalid-machine-token" },
        as: :json
    end

    assert_response :unauthorized
    assert_equal false, response_json.fetch("ok")
    assert_equal "Invalid machine token", response_json.fetch("error")
  end

  test "rejects non-json observer events" do
    assert_no_difference -> { Run.count } do
      post runtime_observer_events_path(runtime_name: "codex"),
        params: { runtime_event: { type: "session.started", session_id: "non-json" } },
        headers: machine_bridge_headers
    end

    assert_response :unsupported_media_type
    assert_equal false, response_json.fetch("ok")
    assert_equal "Runtime observer events must be posted as JSON", response_json.fetch("error")
  end

  test "rejects observer events for unknown runtimes" do
    assert_no_difference -> { Run.count } do
      post_observer_event(
        "future_runtime",
        type: "session.started",
        session_id: "unknown-runtime"
      )
    end

    assert_response :unprocessable_entity
    assert_equal false, response_json.fetch("ok")
    assert_equal "Unsupported runtime: future_runtime", response_json.fetch("error")
  end

  test "rejects malformed observer events" do
    post_observer_event(
      "codex",
      type: "tool.requested",
      event_id: "malformed-tool-request",
      session_id: "malformed-observed-session"
    )

    assert_response :unprocessable_entity
    assert_equal false, response_json.fetch("ok")
    assert_match(/key not found/, response_json.fetch("error"))
  end

  test "creates an observed Claude Code session and runtime-specific base passports" do
    assert_difference -> { Run.count }, 1 do
      post_observer_event(
        "claude_code",
        type: "session.started",
        event_id: "claude-observed-session-started",
        session_id: "claude-observed-session-1",
        title: "Claude observed repo",
        project_path: Rails.root.to_s,
        pid: 12345
      )
    end

    assert_response :created
    body = JSON.parse(response.body)
    run = Run.find(body.fetch("run_id"))

    assert_equal "claude_code", run.runtime_name
    assert_equal "observed", run.mode
    assert_equal "claude-observed-session-1", run.runtime_session_id
    assert_equal "Claude observed repo", run.title
    assert_equal 12345, run.observed_pid
    assert_equal "running", run.status
    assert_equal [ "local-owner", "main-agent" ], run.passports.order(:id).pluck(:actor_ref)
    assert_equal "claude-code/main-agent", run.passports.find_by!(actor_ref: "main-agent").actor_name
    assert_equal "claude_code", run.passports.find_by!(actor_ref: "main-agent").provider
  end

  test "creates an observed Codex tool request through the generic observer endpoint" do
    post_observer_event(
      "codex",
      type: "tool.requested",
      event_id: "codex-observed-tool-1",
      session_id: "codex-observed-session-2",
      title: "Codex observed tools",
      project_path: Rails.root.to_s,
      actor_ref: "main-agent",
      capability: "bash",
      action_kind: "bash",
      action_summary: "bash: bin/rails test",
      command: "bin/rails test",
      risk_level: "medium",
      risk_summary: "Runs tests",
      suggested_capability: "bash",
      suggested_pattern: "bin/rails test"
    )

    assert_response :created
    body = JSON.parse(response.body)
    run = Run.find(body.fetch("run_id"))
    action = run.tool_actions.find_by!(source_event_id: "codex-observed-tool-1")

    assert_equal "codex", run.runtime_name
    assert_equal "asking", action.status
    assert_equal run.permission_requests.last.id, body.fetch("permission_request_id")
  end

  private

  def post_observer_event(runtime_name, event)
    post runtime_observer_events_path(runtime_name: runtime_name),
      params: { runtime_event: event },
      headers: machine_bridge_headers,
      as: :json
  end

  def response_json
    JSON.parse(response.body)
  end
end
