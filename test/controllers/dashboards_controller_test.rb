require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "show enqueues local runtime sync without calling the syncer inline" do
    with_syncer_replaced_by(-> { raise "syncer should run from the job, not the request" }) do
      assert_enqueued_with(job: ObservedRuntimeSessions::LocalProcessSyncJob) do
        get root_path
      end
    end

    assert_response :success
  end

  test "shows the start panel when no run exists" do
    get root_path

    assert_response :success
    assert_select "meta[name='robots'][content='noindex, nofollow']", count: 1
    assert_select "h1", text: "Agent Identity Control Room"
    assert_select "[data-testid='empty-start-panel']"
    assert_select "h2", text: "Runtime observer is waiting"
    assert_select "button", text: "OpenCode demo"
    assert_select "button", text: "Claude Code demo"
    assert_select "button", text: "Codex demo"
    assert_select "turbo-frame#session_sidebar"
    assert_select ".ap-workspace[data-controller~='sidebar-resize'][data-sidebar-resize-storage-key-value='agent-control-room:session-sidebar-width']"
    assert_select ".ap-sidebar-resizer[role='separator']", 1
    assert_select ".ap-sidebar-resizer[role='separator'][aria-label='Resize sessions sidebar'][data-sidebar-resize-target='handle']"
  end

  test "shows the current run control room" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)

    get root_path

    assert_response :success
    assert_select "turbo-frame#run_header"
    assert_select "turbo-frame#session_sidebar"
    assert_select ".ap-workspace[data-controller~='sidebar-resize']"
    assert_select ".ap-sidebar-resizer[role='separator'][aria-orientation='vertical']", 2
    assert_select ".ap-sidebar-resizer[role='separator'][aria-label='Resize sessions sidebar'][data-sidebar-resize-panel-name='session']"
    assert_select ".ap-sidebar-resizer[role='separator'][aria-label='Resize runtime lineage'][data-sidebar-resize-panel-name='lineage']"
    assert_select ".ap-workspace-lineage[data-sidebar-resize-panel-name='lineage']"
    assert_select "turbo-frame#passport_tree"
    assert_select "turbo-frame#permission_inbox"
    assert_select "span", text: "Status: running"
    assert_select "span", text: "2 passports"
    assert_select "span", text: "0 actions"
    assert_select "span", text: "opencode/main-agent"
    assert_select "h2", text: "No pending asks"
    assert_select "[data-testid='permission-inbox-idle']", text: /Waiting for the first permission ask/
    assert_select "a[href='#{run_path(run, panel: "tools")}']", text: "Actions"
    assert_select "a[href='#{run_path(run, panel: "audit")}']", text: "Receipts"
  end

  test "groups observed sessions by project in the left sidebar" do
    first = Run.create!(
      runtime_name: "codex",
      runtime_session_id: "session-first",
      title: "Codex: shared-project",
      project_path: "/tmp/shared-project",
      mode: "observed",
      status: "running",
      started_at: 5.minutes.ago,
      last_seen_at: 5.minutes.ago
    )
    second = Run.create!(
      runtime_name: "opencode",
      runtime_session_id: "session-second",
      title: "Review permissions",
      project_path: "/tmp/shared-project",
      mode: "observed",
      status: "running",
      started_at: Time.current,
      last_seen_at: Time.current
    )
    third = Run.create!(
      runtime_name: "opencode",
      runtime_session_id: "session-third",
      title: "Deploy",
      project_path: "/tmp/other-project",
      mode: "observed",
      status: "running",
      started_at: 2.minutes.ago,
      last_seen_at: 2.minutes.ago
    )
    killed = Run.create!(
      runtime_name: "codex",
      runtime_session_id: "session-killed",
      title: "Killed investigation",
      project_path: "/tmp/shared-project",
      mode: "observed",
      status: "interrupted",
      started_at: 1.minute.ago,
      last_seen_at: 1.minute.ago,
      finished_at: 30.seconds.ago
    )

    get run_path(second)

    assert_response :success
    assert_select "turbo-frame#session_sidebar[data-controller~='session-filter'][data-session-filter-storage-key-value='agent-control-room:session-runtime-filter']" do
      assert_select "button[data-session-filter-target='button'][data-session-filter-runtime-value='all'][aria-pressed='true']", text: "All"
      assert_select "button[data-session-filter-target='button'][data-session-filter-runtime-value='codex']", text: "Codex"
      assert_select "button[data-session-filter-target='button'][data-session-filter-runtime-value='opencode']", text: "Opencode"
      assert_select ".ap-session-project", 2
      assert_select ".ap-session-project", text: /shared-project/ do
        assert_select "details[open][data-controller~='collapsible-project'][data-action='toggle->collapsible-project#save']"
        assert_select "details[data-collapsible-project-key-value=?]", "/tmp/shared-project"
        assert_select "summary"
        assert_select "h3", text: "shared-project"
        assert_select "p", text: "/tmp/shared-project"
        assert_select "li[data-session-filter-target='item'][data-runtime-name='codex'] a[href='#{run_path(first)}']", text: /Codex/
        assert_select "a[href='#{run_path(first)}']", text: /Codex: shared-project/, count: 0
        assert_select "li[data-session-filter-target='item'][data-runtime-name='opencode'] a[href='#{run_path(second)}']", text: /Review permissions/
        assert_select ".ap-session-row-selected", text: /Review permissions/
        assert_select ".ap-session-visible-list a[href='#{run_path(killed)}']", count: 0
        assert_select "details.ap-session-killed-details:not([open])[data-session-filter-target~='group'][data-controller~='collapsible-project'][data-action='toggle->collapsible-project#save']" do
          assert_select "[data-collapsible-project-key-value=?]", "/tmp/shared-project:killed"
          assert_select "summary", text: /Killed/
          assert_select "summary", text: /1/
          assert_select ".ap-session-killed-list a[href='#{run_path(killed)}']", text: /Killed investigation/
        end
      end
      assert_select ".ap-session-project", text: /other-project/ do
        assert_select "details[data-collapsible-project-key-value=?]", "/tmp/other-project"
        assert_select "a[href='#{run_path(third)}']", text: /Deploy/
      end
    end

    get run_path(killed)

    assert_response :success
    assert_select "turbo-frame#session_sidebar" do
      assert_select "details.ap-session-killed-details[open]" do
        assert_select ".ap-session-row-selected[href='#{run_path(killed)}']", text: /Killed investigation/
      end
    end
  end

  private

  def with_syncer_replaced_by(replacement)
    original = ObservedRuntimeSessions::LocalProcessSyncer.method(:sync_if_stale!)
    ObservedRuntimeSessions::LocalProcessSyncer.define_singleton_method(:sync_if_stale!, replacement)
    yield
  ensure
    ObservedRuntimeSessions::LocalProcessSyncer.define_singleton_method(:sync_if_stale!, original)
  end
end
