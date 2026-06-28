require "test_helper"

class RuntimeAdapters::CodexProcessScannerTest < ActiveSupport::TestCase
  SuccessStatus = Struct.new(:success?) do
    def success?
      self[:success?]
    end
  end

  FakeRunner = Struct.new(:outputs) do
    def call(*command)
      [ outputs.fetch(command), SuccessStatus.new(true) ]
    end
  end

  test "discovers live codex cli sessions with their cwd" do
    ps_output = <<~PS
       101 Sat Jun 27 13:14:38 2026 codex --yolo
       202 Sat Jun 27 13:15:01 2026 /Applications/Codex.app/Contents/Resources/codex app-server --listen stdio://
       303 Sat Jun 27 13:16:02 2026 codex debug models
    PS
    runner = FakeRunner.new(
      {
        [ "ps", "-axo", "pid=,lstart=,command=" ] => ps_output,
        [ "lsof", "-a", "-p", "101", "-d", "cwd", "-Fn" ] => "p101\nfcwd\nn#{Rails.root}\n"
      }
    )

    scanner = RuntimeAdapters::CodexProcessScanner.new(command_runner: runner, timeout_seconds: 0.1)
    session = scanner.sessions.sole
    event = session.to_runtime_event

    assert_equal 101, session.pid
    assert_equal Rails.root.to_s, session.cwd
    assert_equal "session.started", event.fetch(:type)
    assert_equal "codex-process-101-#{Time.zone.parse("Sat Jun 27 13:14:38 2026").to_i}", event.fetch(:session_id)
    assert_equal "Codex", event.fetch(:title)
    assert_equal 101, event.fetch(:pid)
  end
end
