require "test_helper"

class PermissionDecisionsControllerTest < ActionDispatch::IntegrationTest
  test "passport grant decision streams updated panes" do
    run = demo_run
    request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "security-auditor" })

    assert_turbo_stream_broadcasts run, count: 6 do
      assert_difference -> { Grant.count }, 1 do
        post permission_request_decisions_path(request),
          params: { decision: { scope: "passport" } },
          headers: { "Accept" => Mime[:turbo_stream].to_s }
      end
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "permission_inbox"
    assert_includes response.body, "passport_detail"
    assert_includes response.body, "audit_timeline"
  end

  test "final decision completes run" do
    run = demo_run
    run.permission_requests.pending.limit(2).each { |request| request.resolve!("allow_once") }
    final_request = run.permission_requests.pending.first

    post permission_request_decisions_path(final_request), params: { decision: { scope: "deny" } }

    assert_redirected_to run_path(run, passport_id: final_request.passport_id)
    assert_equal "completed", run.reload.status
    assert run.audit_events.where(event_kind: "session.finished", result: "completed").exists?
  end

  test "json decision response returns resolved request state" do
    run = demo_run
    request = run.permission_requests.pending.first

    post permission_request_decisions_path(request),
      params: { decision: { scope: "deny" } },
      as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body.fetch("ok")
    assert_equal request.id, body.fetch("id")
    assert_equal "resolved", body.fetch("status")
    assert_equal "deny", body.fetch("decision")
    assert_equal "denied", body.fetch("tool_action_status")
  end

  test "json decision response rejects duplicate decisions" do
    run = demo_run
    request = run.permission_requests.pending.first
    request.resolve!("allow_once")

    assert_no_difference -> { AuditEvent.where(permission_request: request, event_kind: "permission.decided").count } do
      post permission_request_decisions_path(request),
        params: { decision: { scope: "deny" } },
        as: :json
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body.fetch("ok")
    assert_includes body.fetch("error"), "already resolved"
    assert_equal "allow_once", request.reload.decision
    assert_equal "allowed", request.tool_action.reload.status
  end

  test "html duplicate decision shows alert after redirect" do
    run = demo_run
    request = run.permission_requests.pending.first
    request.resolve!("allow_once")

    post permission_request_decisions_path(request),
      params: { decision: { scope: "deny" } }

    assert_redirected_to run_path(run)

    follow_redirect!

    assert_response :success
    assert_select "turbo-frame#flash_messages" do
      assert_select "[role='alert']", text: /Permission request already resolved/
    end
  end

  test "turbo stream duplicate decision replaces flash messages" do
    run = demo_run
    request = run.permission_requests.pending.first
    request.resolve!("allow_once")

    post permission_request_decisions_path(request),
      params: { decision: { scope: "deny" } },
      headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_response :unprocessable_entity
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, %(target="flash_messages")
    assert_select "turbo-stream[action='replace'][target='flash_messages']" do
      assert_select "turbo-frame#flash_messages" do
        assert_select "[role='alert']", text: /Permission request already resolved/
      end
    end
  end
end
