require "test_helper"
require "fileutils"

class RuntimeAdapters::OpencodeSessionLogScannerTest < ActiveSupport::TestCase
  setup do
    @opencode_home = Pathname.new(Dir.mktmpdir("opencode-home"))
  end

  teardown do
    FileUtils.remove_entry(@opencode_home)
  end

  test "marks the newest opencode session for an active project as running" do
    write_json("storage/project/project-1.json", {
      id: "project-1",
      worktree: Rails.root.to_s
    })
    write_json("storage/session/project-1/ses_old.json", {
      id: "ses_old",
      projectID: "project-1",
      directory: Rails.root.to_s,
      title: "Old OpenCode session",
      time: {
        created: 1_782_586_000_000,
        updated: 1_782_586_100_000
      }
    })
    write_json("storage/session/project-1/ses_new.json", {
      id: "ses_new",
      projectID: "project-1",
      title: "New OpenCode session",
      time: {
        created: 1_782_587_000_000,
        updated: 1_782_587_300_000
      }
    })

    sessions = RuntimeAdapters::OpencodeSessionLogScanner.new(
      opencode_home: @opencode_home,
      limit: 1,
      active_project_paths: [ Rails.root.to_s ]
    ).sessions
    event = sessions.sole.to_runtime_event

    assert_equal "opencode", event.fetch(:runtime_name)
    assert_equal "session.started", event.fetch(:type)
    assert_equal "ses_new", event.fetch(:session_id)
    assert_equal "New OpenCode session", event.fetch(:title)
    assert_equal Rails.root.to_s, event.fetch(:project_path)
    assert_equal Time.zone.at(1_782_587_000).iso8601, event.fetch(:started_at)
    assert_equal Time.zone.at(1_782_587_300).iso8601, event.fetch(:last_seen_at)
    assert_equal Time.zone.at(1_782_587_000).iso8601, event.fetch(:occurred_at)
    assert_equal "running", event.fetch(:status)
  end

  test "marks opencode storage sessions as completed when no process is active for the project" do
    write_json("storage/project/project-1.json", {
      id: "project-1",
      worktree: Rails.root.to_s
    })
    write_json("storage/session/project-1/ses_done.json", {
      id: "ses_done",
      projectID: "project-1",
      title: "Finished OpenCode session",
      time: {
        created: 1_782_587_000_000,
        updated: 1_782_587_300_000
      }
    })

    event = RuntimeAdapters::OpencodeSessionLogScanner.new(
      opencode_home: @opencode_home,
      active_project_paths: []
    ).sessions.sole.to_runtime_event

    assert_equal "session.finished", event.fetch(:type)
    assert_equal "completed", event.fetch(:status)
    assert_equal Time.zone.at(1_782_587_000).iso8601, event.fetch(:started_at)
    assert_equal Time.zone.at(1_782_587_300).iso8601, event.fetch(:occurred_at)
  end

  test "turns opencode child sessions into delegated actors on the root session" do
    write_json("storage/project/project-1.json", {
      id: "project-1",
      worktree: Rails.root.to_s
    })
    write_json("storage/session/project-1/ses_root.json", {
      id: "ses_root",
      projectID: "project-1",
      directory: Rails.root.to_s,
      title: "Root OpenCode session",
      time: {
        created: 1_782_587_000_000,
        updated: 1_782_587_300_000
      }
    })
    write_json("storage/session/project-1/ses_child.json", {
      id: "ses_child",
      projectID: "project-1",
      parentID: "ses_root",
      directory: Rails.root.to_s,
      title: "Explore sidebar session rendering (@explore subagent)",
      time: {
        created: 1_782_587_100_000,
        updated: 1_782_587_200_000
      }
    })
    write_json("storage/session/project-1/ses_nested.json", {
      id: "ses_nested",
      projectID: "project-1",
      parentID: "ses_child",
      directory: Rails.root.to_s,
      title: "Review nested behavior (@review subagent)",
      time: {
        created: 1_782_587_150_000,
        updated: 1_782_587_180_000
      }
    })

    events = RuntimeAdapters::OpencodeSessionLogScanner.new(
      opencode_home: @opencode_home,
      limit: 1,
      active_project_paths: [ Rails.root.to_s ]
    ).sessions.map(&:to_runtime_event)

    assert_equal [ "session.started", "actor.delegated", "actor.delegated" ], events.map { |event| event.fetch(:type) }
    assert_equal [ "ses_root", "ses_root", "ses_root" ], events.map { |event| event.fetch(:session_id) }

    child_event = events.second
    assert_equal "opencode-session-ses_child", child_event.fetch(:actor_ref)
    assert_equal "main-agent", child_event.fetch(:parent_actor_ref)
    assert_equal "opencode/explore", child_event.fetch(:actor_name)
    assert_equal "Explore sidebar session rendering (@explore subagent)", child_event.fetch(:task)

    nested_event = events.third
    assert_equal "opencode-session-ses_nested", nested_event.fetch(:actor_ref)
    assert_equal "opencode-session-ses_child", nested_event.fetch(:parent_actor_ref)
    assert_equal "opencode/review", nested_event.fetch(:actor_name)
  end

  test "keeps a root session inside the limit when a child session is recently active" do
    write_json("storage/project/project-1.json", {
      id: "project-1",
      worktree: Rails.root.to_s
    })
    write_json("storage/session/project-1/ses_parent.json", {
      id: "ses_parent",
      projectID: "project-1",
      directory: Rails.root.to_s,
      title: "Older root with recent child",
      time: {
        created: 1_782_586_000_000,
        updated: 1_782_586_100_000
      }
    })
    write_json("storage/session/project-1/ses_child.json", {
      id: "ses_child",
      projectID: "project-1",
      parentID: "ses_parent",
      directory: Rails.root.to_s,
      title: "Recent child (@explore subagent)",
      time: {
        created: 1_782_588_000_000,
        updated: 1_782_588_100_000
      }
    })
    write_json("storage/session/project-1/ses_other_root.json", {
      id: "ses_other_root",
      projectID: "project-1",
      directory: Rails.root.to_s,
      title: "Newer standalone root",
      time: {
        created: 1_782_587_000_000,
        updated: 1_782_587_100_000
      }
    })

    events = RuntimeAdapters::OpencodeSessionLogScanner.new(
      opencode_home: @opencode_home,
      limit: 1,
      active_project_paths: []
    ).sessions.map(&:to_runtime_event)

    assert_equal [ "ses_parent", "ses_parent" ], events.map { |event| event.fetch(:session_id) }
    assert_equal [ "session.finished", "actor.delegated" ], events.map { |event| event.fetch(:type) }
    assert_equal "opencode-session-ses_child", events.second.fetch(:actor_ref)
  end

  test "skips malformed session metadata" do
    write_file("storage/session/project-1/broken.json", "{")

    assert_equal [], RuntimeAdapters::OpencodeSessionLogScanner.new(opencode_home: @opencode_home).sessions
  end

  private

  def write_json(relative_path, payload)
    write_file(relative_path, JSON.generate(payload))
  end

  def write_file(relative_path, content)
    path = @opencode_home.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, content)
  end
end
