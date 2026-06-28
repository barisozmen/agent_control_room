require "test_helper"

class RunBroadcastTest < ActiveSupport::TestCase
  test "control room broadcast replaces the mounted run panes" do
    run = demo_run
    passport = run.passports.find_by!(actor_ref: "auth-reviewer")

    streams = capture_turbo_stream_broadcasts(run) do
      run.broadcast_control_room!(selected_passport: passport)
    end

    assert_equal 7, streams.size
    assert_equal %w[session_sidebar run_header passport_tree permission_inbox audit_timeline tool_action_list passport_detail], streams.map { |stream| stream["target"] }
    assert streams.all? { |stream| stream["action"] == "replace" }
  end
end
