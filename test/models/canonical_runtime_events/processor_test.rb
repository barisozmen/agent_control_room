require "test_helper"
require "minitest/mock"

class CanonicalRuntimeEvents::ProcessorTest < ActiveSupport::TestCase
  test "invalid permission request risk rolls back the tool action transition" do
    run, agent = run_with_agent(rules: { bash: "ask" })
    event = tool_requested_event(actor_ref: agent.actor_ref, event_id: "invalid-risk-tool", risk_level: "severe")

    assert_no_difference -> { run.tool_actions.count } do
      assert_no_difference -> { run.permission_requests.count } do
        assert_no_difference -> { run.audit_events.count } do
          assert_raises(ActiveRecord::RecordInvalid) { process(run, event) }
        end
      end
    end

    assert_nil run.tool_actions.find_by(source_event_id: "invalid-risk-tool")
  end

  test "conflicting duplicate event id rolls back the state change" do
    run = create_run
    run.audit_events.create!(
      source_event_id: "conflicting-event-id",
      event_kind: "session.started",
      result: "started",
      occurred_at: 1.minute.ago
    )

    assert_no_difference -> { run.audit_events.count } do
      assert_raises(ArgumentError) do
        process(run, {
          event_id: "conflicting-event-id",
          type: "session.finished",
          status: "completed"
        })
      end
    end

    assert_equal "running", run.reload.status
    assert_nil run.finished_at
  end

  test "audit creation failure rolls back the tool action transition" do
    run, agent = run_with_agent(rules: { bash: "allow" })
    event = tool_requested_event(actor_ref: agent.actor_ref, event_id: nil)
    failure = ActiveRecord::RecordInvalid.new(AuditEvent.new)

    AuditEvent.stub(:create!, ->(*_args, &_block) { raise failure }) do
      assert_no_difference -> { run.tool_actions.count } do
        assert_no_difference -> { run.audit_events.count } do
          assert_raises(ActiveRecord::RecordInvalid) { process(run, event) }
        end
      end
    end
  end

  private

  def process(run, event)
    CanonicalRuntimeEvents::Processor.new(run: run, event: event).process
  end

  def run_with_agent(rules:)
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: rules)

    [ run, agent ]
  end

  def tool_requested_event(actor_ref:, event_id:, risk_level: "medium")
    {
      event_id: event_id,
      type: "tool.requested",
      actor_ref: actor_ref,
      capability: "bash",
      action_kind: "bash",
      action_summary: "bash: bundle exec rails test",
      command: "bundle exec rails test",
      risk_level: risk_level,
      risk_summary: "Runs the test suite"
    }.compact
  end
end
