require "test_helper"

class PassportsControllerTest < ActionDispatch::IntegrationTest
  test "full page passport requests redirect to the passport drawer" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "auth-reviewer", actor_name: "auth-reviewer", parent: owner)

    get run_passport_path(run, passport)

    assert_redirected_to run_path(run, passport_id: passport.id, panel: "passport")
  end

  test "turbo frame passport requests render passport authority and recent actions" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    passport = create_passport(
      run: run,
      actor_ref: "auth-reviewer",
      actor_name: "auth-reviewer",
      parent: owner,
      rules: { bash: "deny", web: "ask" }
    )
    run.tool_actions.create!(
      passport: passport,
      capability: "web",
      action_kind: "shell_command",
      action_summary: "Fetch external auth guidance",
      command: "curl https://example.com/security",
      status: "blocked",
      requested_at: Time.current
    )

    get run_passport_path(run, passport), headers: { "Turbo-Frame" => "passport_detail" }

    assert_response :success
    assert_select "turbo-frame#passport_detail"
    assert_select "h2", text: "auth-reviewer"
    assert_select "p", text: passport.lineage_label
    assert_select "h3", text: "effective authority"
    assert_select "span", text: "web"
    assert_select "span", text: "ask"
    assert_select "span", text: "bash"
    assert_select "span", text: "deny"
    assert_select "h3", text: "recent actions"
    assert_select "a[href='#{run_path(run, passport_id: passport.id, panel: "tools")}'][data-turbo-frame='_top']", text: /Fetch external auth guidance/
    assert_select "span", text: "blocked"
  end
end
