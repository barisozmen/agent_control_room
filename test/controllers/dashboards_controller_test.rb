require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "shows the start panel when no run exists" do
    get root_path

    assert_response :success
    assert_select "h1", text: "Agent Control Room"
    assert_select "[data-testid='empty-start-panel']"
    assert_select "h2", text: "Runtime observer is waiting"
    assert_select "button", text: "OpenCode demo"
    assert_select "button", text: "Claude Code demo"
    assert_select "button", text: "Codex demo"
    assert_select "turbo-frame#session_sidebar"
  end

  test "shows the current run control room" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)

    get root_path

    assert_response :success
    assert_select "turbo-frame#run_header"
    assert_select "turbo-frame#session_sidebar"
    assert_select "turbo-frame#passport_tree"
    assert_select "turbo-frame#permission_inbox"
    assert_select "span", text: "Status: running"
    assert_select "span", text: "2 passports"
    assert_select "span", text: "opencode/main-agent"
    assert_select "h2", text: "No pending asks"
    assert_select "[data-testid='permission-inbox-idle']", text: /Waiting for the first permission ask/
    assert_select "a[href='#{run_path(run, panel: "audit")}']", text: "Receipts"
  end

  test "lists observed sessions in the left sidebar" do
    first = Run.create!(
      runtime_name: "opencode",
      runtime_session_id: "session-first",
      title: "First project",
      project_path: "/tmp/first-project",
      mode: "observed",
      status: "running",
      started_at: 5.minutes.ago,
      last_seen_at: 5.minutes.ago
    )
    second = Run.create!(
      runtime_name: "opencode",
      runtime_session_id: "session-second",
      title: "Second project",
      project_path: "/tmp/second-project",
      mode: "observed",
      status: "running",
      started_at: Time.current,
      last_seen_at: Time.current
    )

    get run_path(second)

    assert_response :success
    assert_select "turbo-frame#session_sidebar" do
      assert_select "a[href='#{run_path(first)}']", text: /First project/
      assert_select "a[href='#{run_path(second)}']", text: /Second project/
      assert_select "a[href='#{run_path(second)}']", text: /OpenCode/
      assert_select ".ap-session-row-selected", text: /Second project/
    end
  end
end
