require "test_helper"

class RuntimeEventsControllerTest < ActionDispatch::IntegrationTest
  test "accepts canonical runtime actor delegation event" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")

    streams = capture_turbo_stream_broadcasts(run) do
      assert_difference -> { run.passports.count }, 1 do
        post_runtime_event(run, {
          event_id: "test-event-1",
          type: "actor.delegated",
          actor_ref: "main-agent",
          parent_actor_ref: root.actor_ref,
          actor_name: "opencode/main-agent",
          actor_kind: "agent",
          provider: "opencode",
          task: "Test delegation",
          rules: {
            read: "allow",
            edit: "ask",
            bash: "ask",
            web: "ask",
            delegate: "deny"
          }
        })
      end
    end

    assert_response :created
    assert_runtime_streams streams, [
      [ "append", "audit_event_list" ],
      [ "update", "audit_timeline_count" ],
      [ "remove", "audit_timeline_empty_state" ],
      [ "replace", "run_header" ],
      [ "replace", "passport_tree" ],
      [ "replace", "passport_detail" ]
    ]
    assert_equal "Passport", JSON.parse(response.body).fetch("type")
    assert_equal "opencode/main-agent", run.passports.find_by!(actor_ref: "main-agent").actor_name
  end

  test "returns tool action authorization status for adapter bridges" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "ask" })

    streams = capture_turbo_stream_broadcasts(run) do
      post_runtime_event(run, {
        event_id: "bridge-tool-1",
        type: "tool.requested",
        actor_ref: agent.actor_ref,
        capability: "bash",
        action_kind: "bash",
        action_summary: "bash: bundle exec rails test",
        command: "bundle exec rails test",
        risk_level: "medium",
        risk_summary: "Runs test suite"
      })
    end

    assert_response :created
    assert_runtime_streams streams, [
      [ "append", "audit_event_list" ],
      [ "update", "audit_timeline_count" ],
      [ "remove", "audit_timeline_empty_state" ],
      [ "replace", "session_sidebar" ],
      [ "replace", "run_header" ],
      [ "replace", "permission_inbox" ],
      [ "replace", "passport_detail" ]
    ]
    body = JSON.parse(response.body)
    assert_equal "ToolAction", body.fetch("type")
    assert_equal "asking", body.fetch("status")
    assert_equal run.permission_requests.last.id, body.fetch("permission_request_id")
    assert_match %r{/permission_requests/#{body.fetch("permission_request_id")}\z}, body.fetch("permission_request_url")
  end

  test "accepts json runtime event without csrf token when forgery protection is enabled" do
    previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "allow" })

    post_runtime_event(run, {
      event_id: "bridge-csrf-json",
      type: "tool.requested",
      actor_ref: agent.actor_ref,
      capability: "bash",
      action_kind: "bash",
      action_summary: "bash: ruby -v",
      command: "ruby -v"
    })

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal true, body.fetch("ok")
    assert_equal "allowed", body.fetch("status")
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
  end

  test "rejects runtime events without the bridge token" do
    run = create_run

    post runtime_events_path,
      params: {
        runtime_event: {
          run_id: run.id,
          type: "session.started"
        }
      },
      as: :json

    assert_response :unauthorized
    assert_equal false, JSON.parse(response.body).fetch("ok")
  end

  test "rejects non-json runtime bridge posts" do
    run = create_run

    post runtime_events_path,
      params: {
        runtime_event: {
          run_id: run.id,
          type: "session.started"
        }
      },
      headers: bridge_headers(run)

    assert_response :unsupported_media_type
    assert_equal false, JSON.parse(response.body).fetch("ok")
  end

  test "runtime events without adapter ids append distinct audit receipts" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")

    assert_difference -> { run.audit_events.count }, 2 do
      %w[first-agent second-agent].each do |actor_ref|
        post_runtime_event(run, {
          type: "actor.delegated",
          actor_ref: actor_ref,
          parent_actor_ref: root.actor_ref,
          actor_name: actor_ref,
          actor_kind: "agent",
          provider: "opencode",
          task: "Test delegation",
          rules: {
            read: "allow",
            edit: "ask",
            bash: "ask",
            web: "ask",
            delegate: "deny"
          }
        })

        assert_response :created
      end
    end

    assert_equal 2, run.audit_events.where(event_kind: "actor.delegated", source_event_id: nil).count
  end

  test "tool request events without adapter ids create distinct actions" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "allow" })

    assert_difference -> { run.tool_actions.count }, 2 do
      [ "ruby -v", "rails -v" ].each do |command|
        post_runtime_event(run, {
          type: "tool.requested",
          actor_ref: agent.actor_ref,
          capability: "bash",
          action_kind: "bash",
          action_summary: "bash: #{command}",
          command: command
        })

        assert_response :created
      end
    end

    assert_equal [ "rails -v", "ruby -v" ], run.tool_actions.where(source_event_id: nil).order(:command).pluck(:command)
    assert_equal 2, run.audit_events.where(event_kind: "tool.allowed", source_event_id: nil).count
  end

  test "allowed tool request only appends a receipt and refreshes passport detail" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "allow" })

    streams = capture_turbo_stream_broadcasts(run) do
      post_runtime_event(run, {
        event_id: "allowed-tool-request",
        type: "tool.requested",
        actor_ref: agent.actor_ref,
        capability: "bash",
        action_kind: "bash",
        action_summary: "bash: ruby -v",
        command: "ruby -v"
      })
    end

    assert_response :created
    assert_runtime_streams streams, [
      [ "append", "audit_event_list" ],
      [ "update", "audit_timeline_count" ],
      [ "remove", "audit_timeline_empty_state" ],
      [ "replace", "passport_detail" ]
    ]
  end

  test "duplicate tool request event does not reopen a resolved permission request" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "ask" })
    event = {
      run_id: run.id,
      event_id: "bridge-tool-duplicate",
      type: "tool.requested",
      actor_ref: agent.actor_ref,
      capability: "bash",
      action_kind: "bash",
      action_summary: "bash: bundle exec rails test",
      command: "bundle exec rails test",
      risk_level: "medium",
      risk_summary: "Runs test suite"
    }

    post_runtime_event(run, event)
    assert_response :created

    request = run.permission_requests.last
    request.resolve!("allow_once")
    assert_equal "allowed", request.tool_action.reload.status

    assert_no_difference -> { run.permission_requests.count } do
      post_runtime_event(run, event)
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal request.tool_action.id, body.fetch("id")
    assert_equal "allowed", body.fetch("status")
    assert_equal "resolved", request.reload.status
    assert_equal "allowed", request.tool_action.reload.status
  end

  test "duplicate tool request event does not reask after denial" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "ask" })
    event = {
      run_id: run.id,
      event_id: "bridge-tool-denied-duplicate",
      type: "tool.requested",
      actor_ref: agent.actor_ref,
      capability: "bash",
      action_kind: "bash",
      action_summary: "bash: rm -rf tmp/cache",
      command: "rm -rf tmp/cache",
      risk_level: "medium",
      risk_summary: "Removes local cache"
    }

    post_runtime_event(run, event)
    assert_response :created

    request = run.permission_requests.last
    request.resolve!("deny")
    assert_equal "denied", request.tool_action.reload.status

    assert_no_difference -> { run.permission_requests.count } do
      post_runtime_event(run, event)
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal request.tool_action.id, body.fetch("id")
    assert_equal "denied", body.fetch("status")
    assert_equal "resolved", request.reload.status
    assert_equal "denied", request.tool_action.reload.status
  end

  test "allow once does not grant future matching tool requests" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "ask" })

    post_tool_requested(run: run, actor_ref: agent.actor_ref, event_id: "allow-once-first", command: "bundle exec rails test")
    assert_response :created
    first_request = run.permission_requests.last
    first_request.resolve!("allow_once")

    assert_difference -> { run.permission_requests.count }, 1 do
      post_tool_requested(run: run, actor_ref: agent.actor_ref, event_id: "allow-once-second", command: "bundle exec rails test")
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "asking", body.fetch("status")
    assert_equal "pending", run.permission_requests.last.status
  end

  test "passport grant allows future matching tool requests for that passport" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "ask" })

    post_tool_requested(
      run: run,
      actor_ref: agent.actor_ref,
      event_id: "grant-first",
      command: "bundle exec brakeman",
      suggested_pattern: "bundle exec brakeman*"
    )
    assert_response :created
    run.permission_requests.last.resolve!("passport")

    assert_no_difference -> { run.permission_requests.count } do
      post_tool_requested(run: run, actor_ref: agent.actor_ref, event_id: "grant-second", command: "bundle exec brakeman --quiet")
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "allowed", body.fetch("status")
    assert run.audit_events.where(event_kind: "tool.allowed", result: "allowed").exists?
  end

  test "tool finished event closes an allowed action" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "allow" })

    post_tool_requested(run: run, actor_ref: agent.actor_ref, event_id: "finish-request", command: "ruby -v")
    assert_response :created
    action = run.tool_actions.find_by!(source_event_id: "finish-request")
    assert_equal "allowed", action.status

    streams = capture_turbo_stream_broadcasts(run) do
      post_runtime_event(run, {
        event_id: "finish-terminal",
        source_event_id: "finish-request",
        type: "tool.finished",
        actor_ref: agent.actor_ref,
        capability: "bash",
        action_kind: "bash",
        action_summary: "bash finished",
        command: "ruby -v",
        exit_status: 0
      })
    end

    assert_response :created
    assert_runtime_streams streams, [
      [ "append", "audit_event_list" ],
      [ "update", "audit_timeline_count" ],
      [ "replace", "passport_detail" ]
    ]
    assert_equal "finished", action.reload.status
    assert_equal 0, action.exit_status
    assert run.audit_events.where(event_kind: "tool.finished", result: "finished").exists?
  end

  test "tool finished event records observed actions that did not ask first" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { read: "allow" })

    assert_difference -> { run.tool_actions.count }, 1 do
      post_runtime_event(run, {
        event_id: "observed-finish-terminal",
        source_event_id: "observed-finish-request",
        type: "tool.finished",
        actor_ref: agent.actor_ref,
        capability: "read",
        action_kind: "file_read",
        action_summary: "Read README.md",
        path: "README.md",
        exit_status: 0
      })
    end

    assert_response :created
    action = run.tool_actions.find_by!(source_event_id: "observed-finish-request")
    assert_equal "finished", action.status
    assert_equal "README.md", action.path
  end

  test "tool blocked event closes an existing action" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { web: "ask" })

    post_runtime_event(run, {
      event_id: "blocked-request",
      type: "tool.requested",
      actor_ref: agent.actor_ref,
      capability: "web",
      action_kind: "webfetch",
      action_summary: "Fetch external URL",
      path: "https://example.com",
      risk_level: "high",
      risk_summary: "Network access"
    })
    assert_response :created
    action = run.tool_actions.find_by!(source_event_id: "blocked-request")

    post_runtime_event(run, {
      event_id: "blocked-terminal",
      source_event_id: "blocked-request",
      type: "tool.blocked",
      actor_ref: agent.actor_ref,
      capability: "web",
      action_kind: "webfetch",
      action_summary: "Fetch external URL",
      path: "https://example.com"
    })

    assert_response :created
    assert_equal "blocked", action.reload.status
    assert run.audit_events.where(event_kind: "tool.blocked", result: "blocked").exists?
  end

  test "session finished event updates status targets without replacing all panes" do
    run = create_run

    streams = capture_turbo_stream_broadcasts(run) do
      post_runtime_event(run, {
        event_id: "session-finished-minimal-broadcast",
        type: "session.finished",
        status: "completed"
      })
    end

    assert_response :created
    assert_runtime_streams streams, [
      [ "append", "audit_event_list" ],
      [ "update", "audit_timeline_count" ],
      [ "remove", "audit_timeline_empty_state" ],
      [ "replace", "session_sidebar" ],
      [ "replace", "run_header" ]
    ]
    assert_equal "completed", run.reload.status
  end

  private

  def post_tool_requested(run:, actor_ref:, event_id:, command:, suggested_pattern: nil)
    post_runtime_event(run, {
      event_id: event_id,
      type: "tool.requested",
      actor_ref: actor_ref,
      capability: "bash",
      action_kind: "bash",
      action_summary: "bash: #{command}",
      command: command,
      risk_level: "medium",
      risk_summary: "Runs a local command",
      suggested_pattern: suggested_pattern
    })
  end

  def post_runtime_event(run, event)
    post runtime_events_path,
      params: { runtime_event: event.merge(run_id: run.id) },
      headers: bridge_headers(run),
      as: :json
  end

  def assert_runtime_streams(streams, expected)
    actual = streams.map { |stream| [ stream["action"], stream["target"] ] }

    assert_equal expected.sort, actual.sort
    refute_includes actual.map(&:last), "audit_timeline"
    refute_includes actual.map(&:last), "permission_inbox", "permission inbox should only stream when pending asks change" unless expected.any? { |(_, target)| target == "permission_inbox" }
    refute_includes actual.map(&:last), "session_sidebar", "session sidebar should only stream when status or pending counts change" unless expected.any? { |(_, target)| target == "session_sidebar" }
  end
end
