require "test_helper"

class ObservedRuntimeSessions::LocalProcessSyncerTest < ActiveSupport::TestCase
  FakeScanner = Struct.new(:sessions)
  FakeRuntimeSession = Struct.new(:runtime_name, :event) do
    def to_runtime_event
      event
    end
  end

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

  test "imports scanner sessions for their declared runtime" do
    started_at = Time.zone.parse("2026-06-27 19:03:41 UTC")
    last_seen_at = started_at + 5.minutes
    event = runtime_event(
      pid: nil,
      session_id: "opencode-log-session",
      title: "OpenCode: agent_control_room",
      started_at: started_at,
      occurred_at: started_at,
      last_seen_at: last_seen_at
    )
    session = FakeRuntimeSession.new("opencode", event)

    assert_difference -> { Run.where(runtime_name: "opencode").count }, 1 do
      ObservedRuntimeSessions::LocalProcessSyncer.sync!(scanners: [ FakeScanner.new([ session ]) ])
    end

    run = Run.find_by!(runtime_name: "opencode", runtime_session_id: "opencode-log-session")

    assert_equal "OpenCode: agent_control_room", run.title
    assert_equal started_at.to_i, run.started_at.to_i
    assert_equal last_seen_at.to_i, run.last_seen_at.to_i
    assert_equal last_seen_at.to_i, run.last_activity_at.to_i
    assert_equal "opencode/main-agent", run.passports.find_by!(actor_ref: "main-agent").actor_name
  end

  test "imports opencode child session delegations into the parent session lineage" do
    started_at = Time.zone.parse("2026-06-27 19:03:41 UTC")
    root_event = runtime_event(
      pid: nil,
      session_id: "opencode-root-session",
      title: "OpenCode root",
      started_at: started_at,
      occurred_at: started_at,
      last_seen_at: started_at
    ).merge(runtime_name: "opencode")
    child_event = {
      runtime_name: "opencode",
      type: "actor.delegated",
      event_id: "opencode-session-log-child-delegated",
      session_id: "opencode-root-session",
      title: "OpenCode root",
      project_path: Rails.root.to_s,
      actor_ref: "opencode-session-child",
      parent_actor_ref: "main-agent",
      actor_name: "opencode/explore",
      actor_kind: "agent",
      provider: "opencode",
      task: "Explore repo (@explore subagent)",
      rules: { read: "allow", edit: "ask", bash: "ask", web: "ask", delegate: "ask" },
      started_at: started_at.iso8601,
      last_seen_at: (started_at + 1.minute).iso8601,
      occurred_at: (started_at + 30.seconds).iso8601
    }
    nested_event = child_event.merge(
      event_id: "opencode-session-log-nested-delegated",
      actor_ref: "opencode-session-nested",
      parent_actor_ref: "opencode-session-child",
      actor_name: "opencode/review",
      task: "Review repo (@review subagent)"
    )

    ObservedRuntimeSessions::LocalProcessSyncer.sync!(
      scanners: [ FakeScanner.new([ root_event, child_event, nested_event ]) ]
    )

    run = Run.find_by!(runtime_name: "opencode", runtime_session_id: "opencode-root-session")
    main_agent = run.passports.find_by!(actor_ref: "main-agent")
    child = run.passports.find_by!(actor_ref: "opencode-session-child")
    nested = run.passports.find_by!(actor_ref: "opencode-session-nested")

    assert_equal main_agent, child.parent
    assert_equal child, nested.parent
    assert_equal [ "opencode/main-agent", "opencode/explore", "opencode/review" ], nested.lineage.drop(1).map(&:actor_name)
    assert_equal 1, Run.where(runtime_name: "opencode", runtime_session_id: "opencode-root-session").count

    assert_no_difference -> { run.passports.reload.count } do
      assert_no_difference -> { run.audit_events.reload.count } do
        ObservedRuntimeSessions::LocalProcessSyncer.sync!(
          scanners: [ FakeScanner.new([ root_event, child_event, nested_event ]) ]
        )
      end
    end
  end

  test "default scanners include opencode and pi session observers" do
    scanner_classes = ObservedRuntimeSessions::LocalProcessSyncer.new.send(:default_scanners).map(&:class)

    assert_includes scanner_classes, RuntimeAdapters::OpencodeSessionLogScanner
    assert_includes scanner_classes, RuntimeAdapters::PiProcessScanner
    assert_includes scanner_classes, RuntimeAdapters::PiSessionLogScanner
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

  def runtime_event(pid:, occurred_at: Time.current, session_id: nil, title: "Codex: agent_control_room", started_at: nil, last_seen_at: nil)
    session_id ||= "codex-process-#{pid}"
    {
      type: "session.started",
      event_id: "#{session_id}-started",
      session_id: session_id,
      title: title,
      project_path: Rails.root.to_s,
      pid: pid,
      started_at: started_at&.iso8601,
      last_seen_at: last_seen_at&.iso8601,
      occurred_at: occurred_at.iso8601
    }.compact
  end
end
