require "test_helper"
require "tempfile"

class RuntimeAdapters::CodexRunLogIngestorTest < ActiveSupport::TestCase
  test "imports codex jsonl log actions into an existing run without permission asks" do
    run = create_run(runtime_name: "codex")

    Tempfile.create("codex-run-log") do |file|
      file.puts({ type: "thread.started", thread_id: "codex-thread-4" }.to_json)
      file.puts({
        type: "item.started",
        item: {
          id: "item-1",
          type: "command_execution",
          command: "/bin/zsh -lc pwd",
          status: "in_progress"
        }
      }.to_json)
      file.puts({
        type: "item.completed",
        item: {
          id: "item-1",
          type: "command_execution",
          command: "/bin/zsh -lc pwd",
          exit_code: 0,
          status: "completed"
        }
      }.to_json)
      file.flush

      assert_difference -> { run.tool_actions.count }, 1 do
        assert_no_difference -> { run.permission_requests.count } do
          RuntimeAdapters::CodexRunLogIngestor.new(run: run, path: file.path).process
        end
      end
    end

    action = run.tool_actions.sole
    assert_equal "finished", action.status
    assert_equal 0, action.exit_status
    assert_equal "/bin/zsh -lc pwd", action.command
    assert_equal "posthoc", action.canonical_payload.fetch("observation_mode")
    assert run.audit_events.where(event_kind: "tool.observed").exists?
    assert run.audit_events.where(event_kind: "tool.finished").exists?
  end
end
