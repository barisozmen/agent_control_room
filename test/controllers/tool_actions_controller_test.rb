require "test_helper"

class ToolActionsControllerTest < ActionDispatch::IntegrationTest
  test "full page action requests redirect to the run tools drawer" do
    run = create_run

    get run_tool_actions_path(run)

    assert_redirected_to run_path(run, panel: "tools")
  end

  test "turbo frame action requests render only the recent action page" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "owner", actor_name: "Owner", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)
    base_time = Time.current

    actions = create_tool_actions(run: run, passport: passport, base_time: base_time, count: 105)

    get run_tool_actions_path(run), headers: { "Turbo-Frame" => "tool_action_list" }

    assert_response :success
    assert_select "turbo-frame#tool_action_list"
    assert_select "li[data-testid='session-action']", count: Run::TOOL_ACTION_PAGE_SIZE
    assert_select "p", text: "100 of 105 actions"
    assert_select "li##{dom_id(actions[0])}", count: 0
    assert_select "li##{dom_id(actions[5])}"
    assert_select "li##{dom_id(actions[104])}"
    assert_select "a[href='#{run_tool_actions_path(run, before_id: actions[5].id)}']", text: "Load older actions"
  end

  test "turbo frame action requests can page to older actions" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "owner", actor_name: "Owner", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)
    base_time = Time.current

    actions = create_tool_actions(run: run, passport: passport, base_time: base_time, count: 105)

    get run_tool_actions_path(run, before_id: actions[5].id), headers: { "Turbo-Frame" => "tool_action_list" }

    assert_response :success
    assert_select "li[data-testid='session-action']", count: 5
    assert_select "li##{dom_id(actions[0])}"
    assert_select "li##{dom_id(actions[4])}"
    assert_select "li##{dom_id(actions[5])}", count: 0
    assert_select "a[href='#{run_tool_actions_path(run)}']", text: "Latest actions"
    assert_select "a", text: "Load older actions", count: 0
  end

  private

  def create_tool_actions(run:, passport:, base_time:, count:)
    count.times.map do |index|
      run.tool_actions.create!(
        passport: passport,
        capability: "bash",
        action_kind: "command",
        action_summary: "action #{index}",
        command: "echo #{index}",
        status: "finished",
        requested_at: base_time + index.seconds
      )
    end
  end
end
