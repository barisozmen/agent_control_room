require "test_helper"
require "fileutils"

class RuntimeAdapters::CodexSessionLogScannerTest < ActiveSupport::TestCase
  setup do
    @codex_home = Pathname.new(Dir.mktmpdir("codex-home"))
    @state_path = @codex_home.join("scanner-state.json")
    @log_path = @codex_home.join("sessions", "2026", "06", "27", "rollout-session.jsonl")
  end

  teardown do
    FileUtils.remove_entry(@codex_home)
  end

  test "discovers events from recent logs on first scan" do
    append_record(type: "session_meta", payload: { id: "session-1", cwd: Rails.root.to_s })
    append_record(type: "response_item", payload: {
      type: "function_call",
      name: "exec_command",
      call_id: "call-1",
      arguments: { cmd: "bin/rails test" }.to_json
    })

    events = scanner.sessions

    assert_equal [ "session.started", "tool.observed" ], events.map { |event| event.fetch(:type) }
    assert_equal "session-1", events.last.fetch(:session_id)
    assert_equal Rails.root.to_s, events.last.fetch(:project_path)
    assert state_entry.fetch("offset").positive?
  end

  test "subsequent scans read only appended lines and keep codex session context" do
    append_record(type: "session_meta", payload: { id: "session-2", cwd: Rails.root.to_s })
    scanner.sessions

    append_record(type: "response_item", payload: {
      type: "function_call",
      name: "exec_command",
      call_id: "call-2",
      arguments: { cmd: "bin/rails test test/models/runtime_adapters/codex_session_log_scanner_test.rb" }.to_json
    })

    events = scanner.sessions

    assert_equal [ "tool.observed" ], events.map { |event| event.fetch(:type) }
    assert_equal "session-2", events.sole.fetch(:session_id)
    assert_equal Rails.root.to_s, events.sole.fetch(:project_path)
    assert_equal "codex-jsonl-session-2-call-2-requested", events.sole.fetch(:event_id)
    assert_equal [], scanner.sessions
  end

  test "truncated logs are read again from the beginning" do
    append_record(type: "session_meta", payload: { id: "old-session", cwd: Rails.root.to_s, title: "Old Codex session with enough bytes to force a larger cursor" })
    scanner.sessions

    write_records({ type: "session_meta", payload: { id: "new-session", cwd: Rails.root.to_s } })

    event = scanner.sessions.sole

    assert_equal "session.started", event.fetch(:type)
    assert_equal "new-session", event.fetch(:session_id)
  end

  test "replaced log paths are read again from the beginning" do
    append_record(type: "session_meta", payload: { id: "old-session", cwd: Rails.root.to_s })
    scanner.sessions

    FileUtils.mv(@log_path, @log_path.sub_ext(".jsonl.old"))
    write_records(
      { type: "session_meta", payload: { id: "replacement-session", cwd: Rails.root.to_s } },
      { type: "response_item", payload: {
        type: "function_call",
        name: "exec_command",
        call_id: "replacement-call",
        arguments: { cmd: "pwd" }.to_json
      } }
    )

    events = scanner.sessions

    assert_equal [ "session.started", "tool.observed" ], events.map { |event| event.fetch(:type) }
    assert_equal "replacement-session", events.last.fetch(:session_id)
  end

  private

  def scanner
    RuntimeAdapters::CodexSessionLogScanner.new(codex_home: @codex_home, state_path: @state_path)
  end

  def append_record(record)
    FileUtils.mkdir_p(@log_path.dirname)
    File.open(@log_path, "a") { |file| file.puts(JSON.generate(record)) }
  end

  def write_records(*records)
    FileUtils.mkdir_p(@log_path.dirname)
    File.write(@log_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")
  end

  def state_entry
    JSON.parse(File.read(@state_path)).fetch("paths").fetch(@log_path.to_s)
  end
end
