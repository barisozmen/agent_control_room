require "application_system_test_case"

class OpencodeObservedLineageSystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1280, 900] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--force-prefers-reduced-motion")
  end

  test "observed opencode child sessions render as nested runtime lineage" do
    run = observed_opencode_run_with_nested_subagents

    visit run_path(run)

    within "turbo-frame#passport_tree" do
      assert_text "3 agents"
      assert_text "opencode/main-agent"
      assert_text "opencode/explore"
      assert_text "opencode/review"

      click_link "opencode/review"
    end

    within "turbo-frame#passport_detail" do
      assert_text "opencode/main-agent / opencode/explore / opencode/review"
      assert_text "Review nested behavior (@review subagent)"
    end
  end

  private

  def observed_opencode_run_with_nested_subagents
    session_id = "system-opencode-lineage-#{SecureRandom.hex(6)}"
    started_at = Time.current
    base_event = {
      runtime_name: "opencode",
      session_id: session_id,
      title: "System OpenCode lineage",
      project_path: Rails.root.to_s,
      started_at: started_at.iso8601,
      last_seen_at: started_at.iso8601,
      occurred_at: started_at.iso8601
    }

    [
      base_event.merge(
        type: "session.started",
        event_id: "#{session_id}-started"
      ),
      base_event.merge(
        type: "actor.delegated",
        event_id: "#{session_id}-explore-delegated",
        actor_ref: "opencode-session-system-explore",
        parent_actor_ref: "main-agent",
        actor_name: "opencode/explore",
        actor_kind: "agent",
        provider: "opencode",
        task: "Explore sidebar session rendering (@explore subagent)",
        rules: observed_agent_rules
      ),
      base_event.merge(
        type: "actor.delegated",
        event_id: "#{session_id}-review-delegated",
        actor_ref: "opencode-session-system-review",
        parent_actor_ref: "opencode-session-system-explore",
        actor_name: "opencode/review",
        actor_kind: "agent",
        provider: "opencode",
        task: "Review nested behavior (@review subagent)",
        rules: observed_agent_rules
      )
    ].each do |event|
      ObservedRuntimeSessions::Ingestor.new(runtime_name: "opencode", event: event).process
    end

    Run.find_by!(runtime_name: "opencode", runtime_session_id: session_id)
  end

  def observed_agent_rules
    { read: "allow", edit: "ask", bash: "ask", web: "ask", delegate: "ask" }
  end
end
