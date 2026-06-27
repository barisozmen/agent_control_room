require "test_helper"

class AuditEventsControllerTest < ActionDispatch::IntegrationTest
  test "full page audit requests redirect to the run audit drawer" do
    run = create_run

    get run_audit_events_path(run)

    assert_redirected_to run_path(run, panel: "audit")
  end

  test "turbo frame audit requests render the receipt timeline" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "auth-reviewer", actor_name: "auth-reviewer", parent: owner)
    event = run.audit_events.create!(
      passport: passport,
      event_kind: "tool.allowed",
      actor_lineage: passport.lineage_label,
      capability: "web",
      action_summary: "Fetch external auth guidance",
      result: "allowed",
      occurred_at: Time.current
    )

    get run_audit_events_path(run), headers: { "Turbo-Frame" => "audit_timeline" }

    assert_response :success
    assert_select "turbo-frame#audit_timeline"
    assert_select "h2", text: "Receipt drawer"
    assert_select "span", text: "tool.allowed"
    assert_select "span", text: "web"
    assert_select "p", text: "Fetch external auth guidance"
    assert_select "li##{dom_id(event)}"
    assert_select "a[href='#{run_path(run, passport_id: passport.id, panel: "passport")}'][data-turbo-frame='_top']", text: passport.lineage_label
    assert_select "div", text: "allowed"
  end

  test "turbo frame audit requests render only the recent timeline tail" do
    run = create_run
    base_time = Time.current

    events = 105.times.map do |index|
      run.audit_events.create!(event_kind: "event-#{index}", result: "ok", occurred_at: base_time + index.seconds)
    end

    get run_audit_events_path(run), headers: { "Turbo-Frame" => "audit_timeline" }

    assert_response :success
    assert_select "turbo-frame#audit_timeline"
    assert_select "li", count: AuditEvent::TIMELINE_PAGE_SIZE
    assert_select "p", text: "100 of 105 events"
    assert_select "li##{dom_id(events[0])}", count: 0
    assert_select "li##{dom_id(events[5])}"
    assert_select "li##{dom_id(events[104])}"
    assert_select "a[href='#{run_audit_events_path(run, before_id: events[5].id)}']", text: "Load older receipts"
  end

  test "turbo frame audit requests can page to older receipts" do
    run = create_run
    base_time = Time.current

    events = 105.times.map do |index|
      run.audit_events.create!(event_kind: "event-#{index}", result: "ok", occurred_at: base_time + index.seconds)
    end

    get run_audit_events_path(run, before_id: events[5].id), headers: { "Turbo-Frame" => "audit_timeline" }

    assert_response :success
    assert_select "li", count: 5
    assert_select "li##{dom_id(events[0])}"
    assert_select "li##{dom_id(events[4])}"
    assert_select "li##{dom_id(events[5])}", count: 0
    assert_select "a[href='#{run_audit_events_path(run)}']", text: "Latest receipts"
    assert_select "a", text: "Load older receipts", count: 0
  end
end
