require "test_helper"

class RunsControllerTest < ActionDispatch::IntegrationTest
  test "start demo run redirects to control room with hierarchy and asks" do
    assert_difference -> { Run.count }, 1 do
      post runs_path
    end

    run = Run.latest_first.first
    assert_redirected_to run_path(run)

    follow_redirect!
    assert_response :success
    assert_select "span", text: "opencode/main-agent"
    assert_select "span", text: "dependency-scanner"
    assert_select "span", text: "auth-reviewer"
    assert_select "button", text: "Allow once"
    assert_select "button", text: "Add to passport"
    assert_select "button", text: "Deny"
  end

  test "start demo run reuses an active run instead of starting a second one" do
    run = create_run

    assert_no_difference -> { Run.count } do
      post runs_path
    end

    assert_redirected_to run_path(run)
  end

  test "starts a Claude Code demo run through the runtime registry" do
    assert_difference -> { Run.count }, 1 do
      post runs_path, params: { runtime_name: "claude_code" }
    end

    run = Run.latest_first.first

    assert_redirected_to run_path(run)
    assert_equal "claude_code", run.runtime_name
    assert_equal "claude-code/main-agent", run.passports.find_by!(actor_ref: "main-agent").actor_name
  end

  test "starts a Codex demo run through the runtime registry" do
    assert_difference -> { Run.count }, 1 do
      post runs_path, params: { runtime_name: "codex" }
    end

    run = Run.latest_first.first

    assert_redirected_to run_path(run)
    assert_equal "codex", run.runtime_name
    assert_equal "codex/main-agent", run.passports.find_by!(actor_ref: "main-agent").actor_name
  end

  test "failed run page shows setup guidance and retry action" do
    failed_run = Run.create!(
      runtime_name: "opencode",
      project_path: Rails.root.to_s,
      mode: "demo",
      status: "failed",
      started_at: Time.current,
      finished_at: Time.current,
      error_message: "opencode missing"
    )

    get run_path(failed_run)

    assert_response :success
    assert_select "span", text: "Status: failed"
    assert_select "p", text: "opencode missing"
    assert_select "p", text: /Install OpenCode/
    assert_select "button", text: "Retry OpenCode demo"
  end

  test "run page exposes current session, selected passport, and status labels" do
    other_run = Run.create!(
      runtime_name: "opencode",
      runtime_session_id: "session-other",
      title: "Other project",
      project_path: "/tmp/other-project",
      mode: "observed",
      status: "running",
      started_at: 5.minutes.ago,
      last_seen_at: 5.minutes.ago
    )
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)

    get run_path(run, passport_id: passport.id, panel: "passport")

    assert_response :success
    assert_select "a.ap-session-row[href='#{run_path(run)}'][aria-current='page']" do
      assert_select ".ap-status-dot[aria-hidden='true']"
      assert_select ".ap-status-text", text: "Status: running"
    end
    assert_select "a.ap-session-row[href='#{run_path(other_run)}'][aria-current]", count: 0

    assert_select "a.ap-passport-node[href='#{run_path(run, passport_id: passport.id, panel: "passport")}'][aria-current='page']" do
      assert_select ".ap-status-dot[aria-hidden='true']"
      assert_select ".ap-status-text", text: "Status: active"
    end
    assert_select "a.ap-passport-node[href='#{run_path(run, passport_id: owner.id, panel: "passport")}'][aria-current]", count: 0
    assert_select "turbo-frame#run_header .ap-status-text", text: "Status: running"
    assert_select "turbo-frame#passport_detail .ap-status-text", text: /Status: active/
  end
end
