require "application_system_test_case"

class SessionSidebarFilterSystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1280, 900] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--force-prefers-reduced-motion")
  end

  test "developer filters the session sidebar by runtime" do
    codex = Run.create!(
      runtime_name: "codex",
      runtime_session_id: "session-codex",
      title: "Codex: shared-project",
      project_path: "/tmp/shared-project",
      mode: "observed",
      status: "running",
      started_at: 3.minutes.ago,
      last_seen_at: 3.minutes.ago
    )
    opencode = Run.create!(
      runtime_name: "opencode",
      runtime_session_id: "session-opencode",
      title: "Review permissions",
      project_path: "/tmp/shared-project",
      mode: "observed",
      status: "running",
      started_at: 2.minutes.ago,
      last_seen_at: 2.minutes.ago
    )
    Run.create!(
      runtime_name: "claude_code",
      runtime_session_id: "session-claude",
      title: "Claude investigation",
      project_path: "/tmp/claude-project",
      mode: "observed",
      status: "running",
      started_at: 1.minute.ago,
      last_seen_at: 1.minute.ago
    )

    visit run_path(opencode)

    within "turbo-frame#session_sidebar" do
      assert_selector "button[aria-pressed='true']", text: "All"
      assert_selector "a.ap-session-row[href='#{run_path(codex)}']", text: "Codex"
      assert_selector "a.ap-session-row[href='#{run_path(opencode)}']", text: "Review permissions"
      assert_selector ".ap-session-row", text: "Claude investigation"

      click_button "Codex"

      assert_selector "button[aria-pressed='true']", text: "Codex"
      assert_selector "a.ap-session-row[href='#{run_path(codex)}']", text: "Codex"
      assert_no_selector "a.ap-session-row[href='#{run_path(opencode)}']", text: "Review permissions"
      assert_no_selector ".ap-session-row", text: "Claude investigation"

      click_button "Opencode"

      assert_selector "button[aria-pressed='true']", text: "Opencode"
      assert_no_selector "a.ap-session-row[href='#{run_path(codex)}']", text: "Codex"
      assert_selector "a.ap-session-row[href='#{run_path(opencode)}']", text: "Review permissions"
      assert_no_selector ".ap-session-row", text: "Claude investigation"

      click_button "All"

      assert_selector "button[aria-pressed='true']", text: "All"
      assert_selector "a.ap-session-row[href='#{run_path(codex)}']", text: "Codex"
      assert_selector "a.ap-session-row[href='#{run_path(opencode)}']", text: "Review permissions"
      assert_selector ".ap-session-row", text: "Claude investigation"
    end
  end
end
