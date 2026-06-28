require "test_helper"

class RunBroadcastTest < ActiveSupport::TestCase
  test "control room broadcast replaces the mounted run panes" do
    run = demo_run
    passport = run.passports.find_by!(actor_ref: "auth-reviewer")

    streams = capture_turbo_stream_broadcasts(run) do
      run.broadcast_control_room!(selected_passport: passport)
    end

    assert_equal 7, streams.size
    assert_equal %w[session_sidebar run_header passport_tree permission_inbox audit_timeline tool_action_list passport_detail], streams.map { |stream| stream["target"] }
    assert streams.all? { |stream| stream["action"] == "replace" }
  end

  test "runtime tool action broadcast streams the affected row and count" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "owner", actor_name: "Owner", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)
    action = create_tool_action(run: run, passport: passport)
    audit_event = run.audit_events.create!(
      passport: passport,
      tool_action: action,
      event_kind: "tool.allowed",
      result: "allowed",
      capability: action.capability,
      action_summary: action.action_summary,
      occurred_at: Time.current
    )

    streams = capture_turbo_stream_broadcasts(run) do
      run.broadcast_runtime_event!(audit_event: audit_event, ui_changes: [:tool_action_list])
    end

    assert_equal [
      [ "append", "audit_event_list" ],
      [ "update", "audit_timeline_count" ],
      [ "remove", "audit_timeline_empty_state" ],
      [ "prepend", "session_action_list" ],
      [ "update", "tool_action_count" ],
      [ "remove", "session_action_empty_state" ]
    ].sort, stream_actions(streams).sort
    refute_includes streams.map { |stream| stream["target"] }, "tool_action_list"
    assert_includes streams.find { |stream| stream["target"] == "session_action_list" }.to_s, ActionView::RecordIdentifier.dom_id(action)
  end

  test "audit event broadcast count uses the run counter cache" do
    run = create_run
    audit_event = run.audit_events.create!(
      event_kind: "runtime.event",
      result: "observed",
      occurred_at: Time.current
    )

    streams = nil
    queries = capture_sql do
      streams = capture_turbo_stream_broadcasts(run) do
        run.broadcast_runtime_event!(audit_event: audit_event, ui_changes: [])
      end
    end

    count_stream = streams.find { |stream| stream["target"] == "audit_timeline_count" }

    assert_includes count_stream.to_s, "1 event"
    assert_empty audit_event_count_queries(queries), queries.join("\n")
  end

  test "runtime tool action broadcast falls back to replacing list without a row target" do
    run = create_run
    audit_event = run.audit_events.create!(
      event_kind: "runtime.event",
      result: "observed",
      occurred_at: Time.current
    )

    streams = capture_turbo_stream_broadcasts(run) do
      run.broadcast_runtime_event!(audit_event: audit_event, ui_changes: [:tool_action_list])
    end

    assert_includes stream_actions(streams), [ "replace", "tool_action_list" ]
  end

  test "runtime tool action broadcast replaces the bounded list after the first full page" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "owner", actor_name: "Owner", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)
    base_time = Time.current

    actions = 101.times.map do |index|
      run.tool_actions.create!(
        passport: passport,
        capability: "bash",
        action_kind: "command",
        action_summary: "action #{index}",
        status: "finished",
        requested_at: base_time + index.seconds
      )
    end
    audit_event = run.audit_events.create!(
      passport: passport,
      tool_action: actions.last,
      event_kind: "tool.finished",
      result: "finished",
      occurred_at: Time.current
    )

    streams = capture_turbo_stream_broadcasts(run) do
      run.broadcast_runtime_event!(audit_event: audit_event, ui_changes: [ :tool_action_list ])
    end

    assert_includes stream_actions(streams), [ "replace", "tool_action_list" ]
    refute_includes stream_actions(streams), [ "prepend", "session_action_list" ]
  end

  test "runtime tool action broadcast replaces a non-latest action row" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "owner", actor_name: "Owner", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)
    older_action = create_tool_action(run: run, passport: passport)
    create_tool_action(run: run, passport: passport)
    audit_event = run.audit_events.create!(
      passport: passport,
      tool_action: older_action,
      event_kind: "tool.finished",
      result: "finished",
      occurred_at: Time.current
    )

    streams = capture_turbo_stream_broadcasts(run) do
      run.broadcast_runtime_event!(audit_event: audit_event, ui_changes: [ :tool_action_list ])
    end

    assert_includes stream_actions(streams), [ "replace", ActionView::RecordIdentifier.dom_id(older_action) ]
    refute_includes stream_actions(streams), [ "replace", "tool_action_list" ]
  end

  private

  def stream_actions(streams)
    streams.map { |stream| [ stream["action"], stream["target"] ] }
  end

  def create_tool_action(run:, passport:)
    run.tool_actions.create!(
      passport: passport,
      capability: "bash",
      action_kind: "bash",
      action_summary: "bash: ruby -v",
      command: "ruby -v",
      status: "allowed",
      requested_at: Time.current
    )
  end

  def capture_sql(&block)
    queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s
      next if payload[:cached]
      next if payload[:name] == "SCHEMA"
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
      next if sql.match?(/(?:sqlite_master|ar_internal_metadata)/i)

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &block)
    queries
  end

  def audit_event_count_queries(queries)
    queries.select do |sql|
      sql.match?(/COUNT\(/i) && sql.match?(/FROM "?audit_events"?/i)
    end
  end
end
