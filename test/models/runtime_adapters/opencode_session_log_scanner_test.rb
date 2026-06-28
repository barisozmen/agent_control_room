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
