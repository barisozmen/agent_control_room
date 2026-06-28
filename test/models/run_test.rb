require "test_helper"

class RunTest < ActiveSupport::TestCase
  test "current prefers active run over latest completed run" do
    active = create_run
    completed = Run.create!(
      runtime_name: "opencode",
      project_path: Rails.root.to_s,
      mode: "demo",
      status: "completed",
      started_at: Time.current,
      finished_at: Time.current,
      created_at: 1.minute.from_now
    )

    assert_equal active, Run.current

    active.update!(status: "completed", finished_at: Time.current)

    assert_equal completed, Run.current
  end

  test "status predicates expose active and failed states" do
    run = create_run

    assert run.active?
    assert_not run.failed?

    run.update!(status: "failed", finished_at: Time.current, error_message: "opencode missing")

    assert_not run.active?
    assert run.failed?
  end

  test "new runs get a bridge token" do
    run = create_run

    assert_predicate run.bridge_token, :present?
    assert_operator run.bridge_token.length, :>=, 32
  end

  test "last activity tracks last seen before started and created timestamps" do
    created_at = Time.zone.parse("2026-06-27 10:00:00 UTC")
    started_at = created_at + 5.minutes
    last_seen_at = created_at + 10.minutes
    run = Run.create!(
      runtime_name: "opencode",
      project_path: Rails.root.to_s,
      mode: "observed",
      status: "running",
      created_at: created_at,
      started_at: started_at,
      last_seen_at: last_seen_at
    )

    assert_equal last_seen_at.to_i, run.reload.last_activity_at.to_i

    run.update!(last_seen_at: nil)
    assert_equal started_at.to_i, run.reload.last_activity_at.to_i

    run.update!(started_at: nil)
    assert_equal created_at.to_i, run.reload.last_activity_at.to_i
  end

  test "header counts track passports pending permission requests and tool actions" do
    run = create_run
    passport = create_passport(
      run: run,
      actor_ref: "owner",
      actor_name: "Owner",
      actor_kind: "human",
      provider: "local"
    )
    tool_action = run.tool_actions.create!(
      passport: passport,
      capability: "bash",
      action_kind: "command",
      status: "asking",
      requested_at: Time.current,
      command: "bin/rails test"
    )
    permission_request = run.permission_requests.create!(
      passport: passport,
      tool_action: tool_action,
      status: "pending"
    )

    assert_header_counts run, passports: 1, pending_permission_requests: 1, tool_actions: 1
    assert_header_counts run.reload, passports: 1, pending_permission_requests: 1, tool_actions: 1

    permission_request.resolve!("deny")

    assert_header_counts run, passports: 1, pending_permission_requests: 0, tool_actions: 1
    assert_header_counts run.reload, passports: 1, pending_permission_requests: 0, tool_actions: 1

    tool_action.destroy!
    passport.destroy!

    assert_header_counts run, passports: 0, pending_permission_requests: 0, tool_actions: 0
    assert_header_counts run.reload, passports: 0, pending_permission_requests: 0, tool_actions: 0
  end

  test "run header partial renders persisted counts without table count queries" do
    run = create_run
    create_passport(
      run: run,
      actor_ref: "owner",
      actor_name: "Owner",
      actor_kind: "human",
      provider: "local"
    )
    create_permission_request_for(run)

    html = nil
    queries = capture_sql do
      html = ApplicationController.renderer.render(partial: "runs/run_header", locals: { run: run })
    end

    assert_includes html, "1 passport"
    assert_includes html, "1 pending ask"
    assert_includes html, "1 action"
    assert_empty header_count_queries(queries), queries.join("\n")
  end

  test "passport tree snapshot prevents recursive passport queries while rendering" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    main = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)
    security = create_passport(run: run, actor_ref: "security-auditor", actor_name: "security-auditor", parent: main)
    create_passport(run: run, actor_ref: "dependency-scanner", actor_name: "dependency-scanner", parent: security)
    create_passport(run: run, actor_ref: "auth-reviewer", actor_name: "auth-reviewer", parent: security)

    tree = nil
    snapshot_queries = capture_sql { tree = run.passport_tree }

    assert_equal 1, passport_queries(snapshot_queries).size
    assert_equal security, tree.selected_passport(security.id)
    assert_equal 2, tree.child_count_for(security)
    assert_equal 4, tree.agent_count

    html = nil
    render_queries = capture_sql do
      html = ApplicationController.renderer.render(
        partial: "runs/passport_tree",
        locals: { run: run, selected_passport: security, passport_tree: tree }
      )
    end

    assert_includes html, "4 agents"
    assert_includes html, "2 children"
    assert_includes html, "auth-reviewer"
    assert_empty passport_queries(render_queries)
  end

  test "session list is capped to the recent session window" do
    runs = 55.times.map do |index|
      Run.create!(
        runtime_name: "opencode",
        project_path: Rails.root.to_s,
        mode: "demo",
        status: "completed",
        started_at: index.minutes.ago,
        finished_at: index.minutes.ago,
        created_at: index.minutes.ago
      )
    end

    listed_runs = Run.session_list.to_a

    assert_equal Run::SESSION_LIST_LIMIT, listed_runs.size
    assert_includes listed_runs, runs.first
    assert_not_includes listed_runs, runs.last
  end

  test "session list orders by denormalized last activity" do
    base = Time.zone.parse("2026-06-27 12:00:00 UTC")
    stale_recently_created = Run.create!(
      runtime_name: "opencode",
      project_path: Rails.root.to_s,
      mode: "observed",
      status: "running",
      started_at: base - 30.minutes,
      created_at: base + 10.minutes
    )
    created_fallback = Run.create!(
      runtime_name: "opencode",
      project_path: Rails.root.to_s,
      mode: "manual",
      status: "starting",
      created_at: base
    )
    started = Run.create!(
      runtime_name: "opencode",
      project_path: Rails.root.to_s,
      mode: "demo",
      status: "running",
      started_at: base + 1.minute,
      created_at: base - 10.minutes
    )
    seen = Run.create!(
      runtime_name: "opencode",
      project_path: Rails.root.to_s,
      mode: "observed",
      status: "running",
      started_at: base - 1.hour,
      last_seen_at: base + 2.minutes,
      created_at: base - 1.hour
    )
    relation = Run.session_list.where(id: [ stale_recently_created, created_fallback, started, seen ])

    assert_no_match(/COALESCE/i, relation.to_sql)
    assert_match(/last_activity_at/i, relation.to_sql)
    assert_equal [ seen, started, created_fallback, stale_recently_created ], relation.to_a
  end

  test "session list query plan uses the last activity index" do
    plan_rows = ActiveRecord::Base.connection.execute("EXPLAIN QUERY PLAN #{Run.session_list.to_sql}")
    plan = plan_rows.map { |row| row.respond_to?(:values) ? row.values.join(" ") : row.join(" ") }.join("\n")

    assert_match(/index_runs_on_last_activity_at_created_at_id/i, plan)
    assert_no_match(/USE TEMP B-TREE/i, plan)
  end

  test "tool actions for display are capped to the recent action page" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "owner", actor_name: "Owner", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)
    base_time = Time.current

    actions = 105.times.map do |index|
      run.tool_actions.create!(
        passport: passport,
        capability: "bash",
        action_kind: "command",
        action_summary: "action #{index}",
        status: "finished",
        requested_at: base_time + index.seconds
      )
    end

    displayed_actions = run.tool_actions_for_display

    assert_equal Run::TOOL_ACTION_PAGE_SIZE, displayed_actions.size
    assert_equal actions[104], displayed_actions.first
    assert_equal actions[5], displayed_actions.last
    assert_not_includes displayed_actions, actions[4]
  end

  test "tool action page tracks total and older action counts" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "owner", actor_name: "Owner", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)
    base_time = Time.current

    actions = 105.times.map do |index|
      run.tool_actions.create!(
        passport: passport,
        capability: "bash",
        action_kind: "command",
        action_summary: "action #{index}",
        status: "finished",
        requested_at: base_time + index.seconds
      )
    end

    page = run.tool_action_page

    assert_equal Run::TOOL_ACTION_PAGE_SIZE, page.actions.size
    assert_equal 105, page.total_count
    assert_equal 5, page.older_count
    assert_equal actions[104], page.actions.first
    assert_equal actions[5], page.actions.last
    assert_equal actions[5].id, page.oldest_action_id
    assert page.more_actions?

    older_page = run.tool_action_page(before_id: page.oldest_action_id)

    assert_equal actions.first(5).reverse, older_page.actions
    assert_equal 105, older_page.total_count
    assert_equal 0, older_page.older_count
    assert_equal page.oldest_action_id, older_page.before_id
    assert_not older_page.more_actions?
    assert older_page.paginated?
  end

  test "pending permission counts are fetched in one grouped query" do
    first_run = create_run
    second_run = create_run
    resolved_only_run = create_run

    2.times { create_permission_request_for(first_run) }
    create_permission_request_for(second_run)
    create_permission_request_for(resolved_only_run, status: "resolved")

    counts = nil
    queries = permission_request_sql_queries do
      counts = Run.pending_permission_request_counts_for([ first_run, second_run, resolved_only_run ])
    end

    assert_equal({ first_run.id => 2, second_run.id => 1 }, counts)
    assert_equal 1, queries.size, queries.join("\n")
    assert_match(/GROUP BY/i, queries.first)
  end

  test "session sidebar partial renders pending counts without per-run permission queries" do
    runs = [ create_run, create_run, create_run ]
    2.times { create_permission_request_for(runs.first) }
    create_permission_request_for(runs.second)
    locals = Run.session_sidebar_locals(selected_run: runs.first)

    html = nil
    queries = permission_request_sql_queries do
      html = ApplicationController.renderer.render(partial: "runs/session_sidebar", locals: locals)
    end

    assert_match(/ap-count-pill[^>]*>2</, html)
    assert_match(/ap-count-pill[^>]*>1</, html)
    assert_empty queries
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

  def passport_queries(queries)
    queries.grep(/FROM "?passports"?/i)
  end

  def assert_header_counts(run, passports:, pending_permission_requests:, tool_actions:)
    counts = run.header_counts

    assert_equal passports, counts.passports
    assert_equal pending_permission_requests, counts.pending_permission_requests
    assert_equal tool_actions, counts.tool_actions
  end

  def header_count_queries(queries)
    queries.select do |sql|
      sql.match?(/COUNT\(/i) && sql.match?(/FROM "?(?:passports|permission_requests|tool_actions)"?/i)
    end
  end

  def create_permission_request_for(run, status: "pending")
    passport = run.passports.first || create_passport(
      run: run,
      actor_ref: "owner",
      actor_name: "Owner",
      actor_kind: "human",
      provider: "local"
    )
    tool_action = run.tool_actions.create!(
      passport: passport,
      capability: "bash",
      action_kind: "command",
      status: "asking",
      requested_at: Time.current,
      command: "echo #{SecureRandom.hex(4)}"
    )
    attributes = {
      passport: passport,
      tool_action: tool_action,
      status: status
    }
    attributes.merge!(decision: "deny", decided_at: Time.current) if status == "resolved"

    run.permission_requests.create!(attributes)
  end

  def permission_request_sql_queries
    queries = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])

      sql = payload[:sql]
      queries << sql if sql.match?(/(?:FROM|UPDATE|INSERT INTO|DELETE FROM) "?permission_requests"?/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    queries
  end
end
