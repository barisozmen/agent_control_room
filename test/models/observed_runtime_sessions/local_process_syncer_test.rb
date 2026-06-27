require "test_helper"

class ObservedRuntimeSessions::LocalProcessSyncerTest < ActiveSupport::TestCase
  FakeScanner = Struct.new(:sessions)

  class CountingScanner
    attr_reader :calls

    def initialize(sessions)
      @sessions = sessions
      @calls = 0
    end

    def sessions
      @calls += 1
      @sessions
    end
  end

  class NestedSyncScanner
    attr_reader :nested_result

    def initialize(now:, nested_scanner:)
      @now = now
      @nested_scanner = nested_scanner
    end

    def sessions
      @nested_result = ObservedRuntimeSessions::LocalProcessSyncer.sync_if_stale!(
        scanners: [ @nested_scanner ],
        now: @now + 1.second,
        ttl: 10.seconds
      )
      []
    end
  end

  setup do
    ObservedRuntimeSessions::LocalProcessSyncer.reset_scan_debounce!
  end

  teardown do
    ObservedRuntimeSessions::LocalProcessSyncer.reset_scan_debounce!
  end

  test "imports scanner sessions through the generic observed runtime ingestor" do
    event = runtime_event(pid: 4242)

    assert_difference -> { Run.where(runtime_name: "codex").count }, 1 do
      ObservedRuntimeSessions::LocalProcessSyncer.sync!(scanners: [ FakeScanner.new([ event ]) ])
    end

    run = Run.find_by!(runtime_name: "codex", runtime_session_id: "codex-process-4242")

    assert_equal "observed", run.mode
    assert_equal "running", run.status
    assert_equal 4242, run.observed_pid
    assert_equal "codex/main-agent", run.passports.find_by!(actor_ref: "main-agent").actor_name

    assert_no_difference -> { Run.where(runtime_name: "codex").count } do
      ObservedRuntimeSessions::LocalProcessSyncer.sync!(scanners: [ FakeScanner.new([ event ]) ])
    end
  end

  test "sync_if_stale skips scanner work inside the ttl" do
    now = Time.current
    event = runtime_event(pid: 5151, occurred_at: now)
    scanner = CountingScanner.new([ event ])

    assert_difference -> { Run.where(runtime_name: "codex").count }, 1 do
      ObservedRuntimeSessions::LocalProcessSyncer.sync_if_stale!(scanners: [ scanner ], now: now, ttl: 10.seconds)
    end

    assert_equal 1, scanner.calls

    assert_no_difference -> { Run.where(runtime_name: "codex").count } do
      result = ObservedRuntimeSessions::LocalProcessSyncer.sync_if_stale!(scanners: [ scanner ], now: now + 5.seconds, ttl: 10.seconds)
      assert_equal [], result
    end

    assert_equal 1, scanner.calls
  end

  test "sync_if_stale skips scanner work while another scan is running" do
    now = Time.current
    nested_scanner = CountingScanner.new([ runtime_event(pid: 5252, occurred_at: now) ])
    scanner = NestedSyncScanner.new(now: now, nested_scanner: nested_scanner)

    result = ObservedRuntimeSessions::LocalProcessSyncer.sync_if_stale!(scanners: [ scanner ], now: now, ttl: 10.seconds)

    assert_equal [], result
    assert_equal [], scanner.nested_result
    assert_equal 0, nested_scanner.calls
  end

  test "sync_if_stale scans again after the ttl expires" do
    now = Time.current
    first_scanner = CountingScanner.new([ runtime_event(pid: 6161, occurred_at: now) ])
    second_scanner = CountingScanner.new([ runtime_event(pid: 6262, occurred_at: now + 2.seconds) ])

    ObservedRuntimeSessions::LocalProcessSyncer.sync_if_stale!(scanners: [ first_scanner ], now: now, ttl: 1.second)

    assert_difference -> { Run.where(runtime_name: "codex").count }, 1 do
      ObservedRuntimeSessions::LocalProcessSyncer.sync_if_stale!(scanners: [ second_scanner ], now: now + 2.seconds, ttl: 1.second)
    end

    assert_equal 1, first_scanner.calls
    assert_equal 1, second_scanner.calls
  end

  private

  def runtime_event(pid:, occurred_at: Time.current)
    {
      type: "session.started",
      event_id: "codex-process-#{pid}-started",
      session_id: "codex-process-#{pid}",
      title: "Codex: agent_control_room",
      project_path: Rails.root.to_s,
      pid: pid,
      occurred_at: occurred_at.iso8601
    }
  end
end
