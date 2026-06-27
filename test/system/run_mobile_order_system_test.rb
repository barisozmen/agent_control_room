require "application_system_test_case"

class RunMobileOrderSystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [390, 900] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--force-prefers-reduced-motion")
  end

  test "narrow run workspace shows lineage before current ask before session history" do
    run = demo_run

    visit run_path(run)

    assert_selector ".ap-workspace-lineage turbo-frame#passport_tree", text: "opencode/main-agent"
    assert_selector ".ap-workspace-current-ask turbo-frame#permission_inbox", text: "Ask 1 of 3"
    assert_selector ".ap-workspace-sessions turbo-frame#session_sidebar", text: run.title

    positions = page.evaluate_script(<<~JS)
      Object.fromEntries(
        [
          ["lineage", ".ap-workspace-lineage"],
          ["currentAsk", ".ap-workspace-current-ask"],
          ["sessions", ".ap-workspace-sessions"]
        ].map(([name, selector]) => [name, document.querySelector(selector).getBoundingClientRect().top])
      )
    JS

    assert_operator positions.fetch("lineage"), :<, positions.fetch("currentAsk")
    assert_operator positions.fetch("currentAsk"), :<, positions.fetch("sessions")
  end
end
