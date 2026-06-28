require "test_helper"

class RuntimeAdapters::OpencodeProcessScannerTest < ActiveSupport::TestCase
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

  test "discovers live opencode cli sessions with their cwd" do
    ps_output = <<~PS
       101 Sat Jun 27 16:36:49 2026 opencode
       202 Sat Jun 27 16:37:36 2026 /opt/homebrew/bin/opencode run language-server
       303 Sat Jun 27 16:38:02 2026 opencode install
    PS
    runner = FakeRunner.new(
      {
        [ "ps", "-axo", "pid=,lstart=,command=" ] => ps_output,
        [ "lsof", "-a", "-p", "101", "-d", "cwd", "-Fn" ] => "p101\nfcwd\nn#{Rails.root}\n"
      }
    )

    scanner = RuntimeAdapters::OpencodeProcessScanner.new(command_runner: runner, timeout_seconds: 0.1)
    session = scanner.sessions.sole
    event = session.to_runtime_event

    assert_equal "opencode", session.runtime_name
    assert_equal 101, session.pid
    assert_equal Rails.root.to_s, session.cwd
    assert_equal "session.started", event.fetch(:type)
    assert_equal "opencode-process-101-#{Time.zone.parse("Sat Jun 27 16:36:49 2026").to_i}", event.fetch(:session_id)
    assert_equal "OpenCode", event.fetch(:title)
    assert_equal 101, event.fetch(:pid)
  end
end
