require "test_helper"

class PassportTest < ActiveSupport::TestCase
  test "child passport cannot exceed parent authority" do
    run = create_run
    parent = create_passport(run: run, actor_ref: "parent", actor_name: "parent", actor_kind: "human", provider: "local", rules: { edit: "ask" })

    child = run.passports.build(
      parent: parent,
      actor_ref: "child",
      actor_name: "child",
      actor_kind: "agent",
      provider: "opencode",
      status: "active",
      read_rule: "allow",
      edit_rule: "allow",
      bash_rule: "allow",
      web_rule: "allow",
      delegate_rule: "allow"
    )

    assert_not child.valid?
    assert_includes child.errors[:edit_rule], "cannot exceed parent passport"
  end

  test "lineage labels include every parent" do
    run = demo_run
    passport = run.passports.find_by!(actor_ref: "auth-reviewer")

    assert_equal "Baris / opencode/main-agent / security-auditor / auth-reviewer", passport.lineage_label
  end

  test "capability rows load and group grants with one query" do
    run = create_run
    passport = create_passport(run: run, actor_ref: "owner", actor_name: "Owner", actor_kind: "human", provider: "local")
    passport.grants.create!(capability: "bash", pattern: "tmp/z", effect: "allow", scope: "passport")
    passport.grants.create!(capability: "bash", pattern: "tmp/a", effect: "allow", scope: "passport")
    passport.grants.create!(capability: "read", pattern: "app/models/*", effect: "allow", scope: "passport")

    passport = Passport.find(passport.id)
    rows = nil
    queries = capture_sql do
      rows = passport.capability_rows
    end

    assert_equal 1, grant_queries(queries).size, queries.join("\n")
    assert_equal [ "app/models/*" ], grants_for(rows, "read").map(&:pattern)
    assert_equal [ "tmp/a", "tmp/z" ], grants_for(rows, "bash").map(&:pattern)
    assert_empty grants_for(rows, "edit")
  end

  test "passport detail partial reuses one ordered grant collection" do
    run = create_run
    passport = create_passport(run: run, actor_ref: "owner", actor_name: "Owner", actor_kind: "human", provider: "local")
    passport.grants.create!(capability: "bash", pattern: "bin/rails *", effect: "allow", scope: "passport")
    passport.grants.create!(capability: "read", pattern: "app/views/*", effect: "allow", scope: "passport")

    passport = Passport.find(passport.id)
    html = nil
    queries = capture_sql do
      html = ApplicationController.renderer.render(partial: "runs/passport_detail", locals: { run: run, passport: passport })
    end

    assert_equal 1, grant_queries(queries).size, queries.join("\n")
    assert_includes html, "bin/rails *"
    assert_includes html, "app/views/*"
    assert_includes html, "1 grant"
  end

  private

  def grants_for(rows, capability)
    rows.find { |row| row[:capability] == capability }.fetch(:grants)
  end

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

  def grant_queries(queries)
    queries.grep(/FROM "?grants"?/i)
  end
end
