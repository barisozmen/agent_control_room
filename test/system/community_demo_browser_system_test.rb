require "application_system_test_case"

class CommunityDemoBrowserSystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1000] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--force-prefers-reduced-motion")
  end

  test "presenter resolves demo permission asks through Turbo in a browser" do
    visit root_path

    within("[data-testid='empty-start-panel']") do
      click_button "OpenCode demo"
    end

    assert_selector "turbo-frame#passport_tree", text: "opencode/main-agent"
    assert_selector "turbo-frame#permission_inbox", text: "Ask 1 of 3"
    assert_match %r{/runs/\d+\?panel=audit\z}, find_link("Receipts")[:href]

    stable_url = current_url

    decide_current_ask "Allow once"
    assert_selector "turbo-frame#permission_inbox", text: "Ask 1 of 2"
    assert_equal stable_url, current_url

    decide_current_ask "Add to passport"
    assert_selector "turbo-frame#permission_inbox", text: "Ask 1 of 1"
    assert_equal stable_url, current_url

    decide_current_ask "Deny"
    within("turbo-frame#permission_inbox") do
      assert_text "No pending asks"
      assert_text "All permission asks are resolved."
      assert_text(/last decision/i)
      assert_text "Denied"
      assert_text(/run status/i)
      assert_text "completed"
    end
    assert_selector "turbo-frame#run_header", text: "completed"
    assert_equal stable_url, current_url

    within("turbo-frame#permission_inbox") do
      click_link "Open receipts"
    end

    assert_selector "turbo-frame#audit_timeline", text: "session.finished"
    assert_selector "turbo-frame#audit_timeline", text: "permission.decided"
    assert_selector "turbo-frame#audit_timeline", text: "deny"
  end

  private

    def decide_current_ask(label)
      within("turbo-frame#permission_inbox") do
        click_button label
      end
    end
end
