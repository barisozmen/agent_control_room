require "test_helper"

class ControlRoomFlowsTest < ActionDispatch::IntegrationTest
  test "community demo flow starts, decides asks, and leaves an audit story" do
    get root_path
    assert_response :success
    assert_select "button", text: "OpenCode demo"

    assert_difference -> { Run.count }, 1 do
      post runs_path
    end

    run = Run.latest_first.first
    assert_redirected_to run_path(run)
    follow_redirect!

    assert_response :success
    assert_select "span", text: "opencode/main-agent"
    assert_select "span", text: "code-writer"
    assert_select "span", text: "security-auditor"
    assert_select "span", text: "dependency-scanner"
    assert_select "span", text: "auth-reviewer"
    assert_select "span", text: "docs-writer"
    assert_select "button", text: "Allow once"
    assert_select "button", text: "Add to passport"
    assert_select "button", text: "Deny"
    assert_equal 3, run.permission_requests.pending.count

    allow_once_request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "code-writer" })
    post permission_request_decisions_path(allow_once_request), params: { decision: { scope: "allow_once" } }
    assert_redirected_to run_path(run, passport_id: allow_once_request.passport_id)
    assert_equal "allow_once", allow_once_request.reload.decision
    assert_not Grant.exists?(permission_request: allow_once_request)

    grant_request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "security-auditor" })
    assert_difference -> { Grant.count }, 1 do
      post permission_request_decisions_path(grant_request),
        params: { decision: { scope: "passport" } },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
    end
    assert_response :success
    assert_equal "passport_grant", grant_request.reload.decision
    assert_includes response.body, "passport_detail"

    deny_request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "auth-reviewer" })
    post permission_request_decisions_path(deny_request), params: { decision: { scope: "deny" } }
    assert_redirected_to run_path(run, passport_id: deny_request.passport_id)

    assert_equal "completed", run.reload.status
    assert_equal "deny", deny_request.reload.decision
    assert run.audit_events.where(event_kind: "session.finished", result: "completed").exists?
    assert run.audit_events.where(event_kind: "permission.decided", decision: "deny", result: "denied").exists?
  end

  test "developer can inspect an agent passport frame" do
    run = demo_run
    passport = run.passports.find_by!(actor_ref: "auth-reviewer")

    get run_passport_path(run, passport)
    assert_redirected_to run_path(run, passport_id: passport.id, panel: "passport")

    get run_passport_path(run, passport), headers: { "Turbo-Frame" => "passport_detail" }

    assert_response :success
    assert_select "turbo-frame#passport_detail"
    assert_select "h2", text: "auth-reviewer"
    assert_select "p", text: passport.lineage_label
    assert_select "span", text: "web"
    assert_select "a[href='#{run_path(run, passport_id: passport.id, panel: "audit")}'][data-turbo-frame='_top']", text: /Fetch external auth/
  end

  test "run page keeps inspection panes behind drawer URLs" do
    run = demo_run
    passport = run.passports.find_by!(actor_ref: "auth-reviewer")

    get run_path(run)
    assert_response :success
    assert_select ".ap-drawer", count: 0
    assert_select "turbo-frame#audit_timeline", count: 0
    assert_select "turbo-frame#passport_detail", count: 0
    assert_select "a.ap-passport-node[data-turbo-frame='_top']", minimum: 1
    assert_select "a[href='#{run_path(run, passport_id: passport.id, panel: "passport")}'][data-turbo-frame='_top']", text: "auth-reviewer"

    get run_path(run, passport_id: passport.id, panel: "passport")
    assert_response :success
    assert_select "main[data-controller='drawer'][data-drawer-close-url-value='#{run_path(run, passport_id: passport.id)}']"
    assert_select "[data-drawer-target='background'][inert]"
    assert_select ".ap-drawer[role='dialog'][aria-modal='true'][aria-labelledby='passport-drawer-title'][data-drawer-target='dialog']"
    assert_select ".ap-drawer-panel[tabindex='-1'][data-drawer-target='panel']"
    assert_select "a.ap-quiet-link", text: "Passport"
    assert_select "a.ap-quiet-link", text: "Receipts"
    assert_select "a.ap-quiet-link", text: "Close"
    assert_select "turbo-frame#passport_detail"
    assert_select "h2#passport-drawer-title", text: "auth-reviewer"

    get run_path(run, panel: "audit")
    assert_response :success
    assert_select ".ap-drawer[role='dialog'][aria-modal='true'][aria-labelledby='audit-drawer-title']"
    assert_select "turbo-frame#audit_timeline"
    assert_select "h2#audit-drawer-title", text: "Receipt drawer"
    assert_select "span", text: "actor.delegated"
  end

  test "developer can review the run audit frame" do
    run = demo_run
    request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "auth-reviewer" })
    request.resolve!("deny")

    get run_audit_events_path(run)
    assert_redirected_to run_path(run, panel: "audit")

    get run_audit_events_path(run), headers: { "Turbo-Frame" => "audit_timeline" }

    assert_response :success
    assert_select "turbo-frame#audit_timeline"
    assert_select "span", text: "actor.delegated"
    assert_select "span", text: "permission.requested"
    assert_select "div", text: "deny"
    assert_select "a[href='#{run_path(run, passport_id: request.passport_id, panel: "passport")}'][data-turbo-frame='_top']", text: /auth-reviewer/
    assert_includes response.body, "Baris / opencode/main-agent / security-auditor / auth-reviewer"
  end
end
