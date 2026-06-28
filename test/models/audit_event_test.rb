require "test_helper"

class AuditEventTest < ActiveSupport::TestCase
  test "chronological orders by occurred time then id" do
    run = create_run
    later = run.audit_events.create!(event_kind: "later", result: "ok", occurred_at: 1.minute.from_now)
    earlier = run.audit_events.create!(event_kind: "earlier", result: "ok", occurred_at: Time.current)

    assert_equal [ earlier, later ], run.audit_events.chronological.to_a
  end

  test "timeline page returns bounded recent receipts in chronological order" do
    run = create_run
    base_time = Time.current

    events = 105.times.map do |index|
      run.audit_events.create!(event_kind: "event-#{index}", result: "ok", occurred_at: base_time + index.seconds)
    end

    page = run.audit_timeline_page

    assert_equal AuditEvent::TIMELINE_PAGE_SIZE, page.events.size
    assert_equal 105, page.total_count
    assert_equal 5, page.older_count
    assert_equal events[5], page.events.first
    assert_equal events[104], page.events.last
    assert_equal events[5].id, page.oldest_event_id
    assert page.more_events?
  end

  test "timeline page total count uses the run counter cache" do
    run = create_run
    base_time = Time.current

    105.times do |index|
      run.audit_events.create!(event_kind: "event-#{index}", result: "ok", occurred_at: base_time + index.seconds)
    end

    page = nil
    queries = capture_sql do
      page = run.audit_timeline_page
    end

    assert_equal 105, page.total_count
    assert_empty audit_event_count_queries(queries), queries.join("\n")
  end

  test "timeline page can load older receipts before the current tail" do
    run = create_run
    base_time = Time.current

    events = 105.times.map do |index|
      run.audit_events.create!(event_kind: "event-#{index}", result: "ok", occurred_at: base_time + index.seconds)
    end

    latest_page = run.audit_timeline_page
    older_page = run.audit_timeline_page(before_id: latest_page.oldest_event_id)

    assert_equal events.first(5), older_page.events
    assert_equal 105, older_page.total_count
    assert_equal 0, older_page.older_count
    assert_equal latest_page.oldest_event_id, older_page.before_id
    assert_not older_page.more_events?
    assert older_page.paginated?
  end

  test "source event id is unique within a run when present" do
    run = create_run
    run.audit_events.create!(source_event_id: "event-1", event_kind: "first", result: "ok", occurred_at: Time.current)

    duplicate = run.audit_events.build(source_event_id: "event-1", event_kind: "second", result: "ok", occurred_at: Time.current)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_event_id], "has already been taken"
  end

  test "audit events without source ids append as distinct receipts" do
    run = create_run

    assert_difference -> { run.audit_events.count }, 2 do
      run.audit_events.create!(event_kind: "first", result: "ok", occurred_at: Time.current)
      run.audit_events.create!(event_kind: "second", result: "ok", occurred_at: Time.current)
    end
  end

  test "audit event counter cache tracks creates and destroys" do
    run = create_run
    event = run.audit_events.create!(event_kind: "first", result: "ok", occurred_at: Time.current)

    assert_equal 1, run.audit_events_count
    assert_equal 1, run.reload.audit_events_count

    event.destroy!

    assert_equal 0, run.audit_events_count
    assert_equal 0, run.reload.audit_events_count
  end

  private

  def capture_sql(&block)
    queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s
      next if payload[:cached]
      next if payload[:name] == "SCHEMA"
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
      next if sql.match?(/(?:sqlite_master|ar_internal_metadata)/i)

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &block)
    queries
  end

  def audit_event_count_queries(queries)
    queries.select do |sql|
      sql.match?(/COUNT\(/i) && sql.match?(/FROM "?audit_events"?/i)
    end
  end
end
