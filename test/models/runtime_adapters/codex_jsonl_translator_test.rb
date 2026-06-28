require "test_helper"

class RuntimeAdapters::CodexJsonlTranslatorTest < ActiveSupport::TestCase
  test "maps codex exec command items to observed and finished tool events" do
    translator = RuntimeAdapters::CodexJsonlTranslator.new(
      session_id: "codex-thread-1",
      project_path: Rails.root.to_s,
      title: "Codex: agent_control_room",
      occurred_at: Time.zone.parse("2026-06-27 15:00:00")
    )

    observed = translator.events_for({
      type: "item.started",
      item: {
        id: "item-1",
        type: "command_execution",
        command: "/bin/zsh -lc pwd",
        status: "in_progress"
      }
    }).sole

    assert_equal "tool.observed", observed.fetch(:type)
    assert_equal "codex-jsonl-codex-thread-1-item-1-requested", observed.fetch(:event_id)
    assert_equal "main-agent", observed.fetch(:actor_ref)
    assert_equal "bash", observed.fetch(:capability)
    assert_equal "shell_command", observed.fetch(:action_kind)
    assert_equal "/bin/zsh -lc pwd", observed.fetch(:command)
    assert_equal "running", observed.fetch(:status)
    assert_equal "posthoc", observed.fetch(:observation_mode)

    finished = translator.events_for({
      type: "item.completed",
      item: {
        id: "item-1",
        type: "command_execution",
        command: "/bin/zsh -lc pwd",
        aggregated_output: Rails.root.to_s,
        exit_code: 0,
        status: "completed"
      }
    }).sole

    assert_equal "tool.finished", finished.fetch(:type)
    assert_equal observed.fetch(:event_id), finished.fetch(:source_event_id)
    assert_equal "#{observed.fetch(:event_id)}-finished", finished.fetch(:event_id)
    assert_equal 0, finished.fetch(:exit_status)
  end

  test "maps persisted codex function calls to observed shell actions" do
    translator = RuntimeAdapters::CodexJsonlTranslator.new(
      session_id: "codex-thread-2",
      project_path: Rails.root.to_s,
      title: "Codex: agent_control_room",
      occurred_at: Time.current
    )

    event = translator.events_for({
      type: "response_item",
      payload: {
        type: "function_call",
        name: "exec_command",
        call_id: "call-1",
        arguments: { cmd: "bin/rails test", token: "secret-token" }.to_json
      }
    }).sole

    assert_equal "tool.observed", event.fetch(:type)
    assert_equal "bash", event.fetch(:capability)
    assert_equal "shell_command", event.fetch(:action_kind)
    assert_equal "bin/rails test", event.fetch(:command)
    assert_equal "running", event.fetch(:status)
  end

  test "maps persisted apply patch calls to edit actions" do
    translator = RuntimeAdapters::CodexJsonlTranslator.new(
      session_id: "codex-thread-3",
      project_path: Rails.root.to_s,
      title: "Codex: agent_control_room",
      occurred_at: Time.current
    )

    event = translator.events_for({
      type: "response_item",
      payload: {
        type: "custom_tool_call",
        name: "apply_patch",
        call_id: "patch-1",
        input: <<~PATCH
          *** Begin Patch
          *** Update File: app/models/run.rb
          @@
          -old
          +new
          *** End Patch
        PATCH
      }
    }).sole

    assert_equal "tool.observed", event.fetch(:type)
    assert_equal "edit", event.fetch(:capability)
    assert_equal "file_edit", event.fetch(:action_kind)
    assert_equal "app/models/run.rb", event.fetch(:path)
    assert_match(/Apply patch/, event.fetch(:action_summary))
  end

  test "redacts sensitive keys from raw codex payloads" do
    sanitized = RuntimeAdapters::CodexJsonlTranslator.sanitize(
      {
        "authorization" => "Bearer abc",
        "nested" => {
          "password" => "secret",
          "safe" => "visible"
        }
      }
    )

    assert_equal "[REDACTED]", sanitized.fetch("authorization")
    assert_equal "[REDACTED]", sanitized.fetch("nested").fetch("password")
    assert_equal "visible", sanitized.fetch("nested").fetch("safe")
  end
end
