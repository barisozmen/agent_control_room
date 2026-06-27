require "application_system_test_case"

class DrawerAccessibilitySystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [390, 844] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--force-prefers-reduced-motion")
  end

  test "drawer behaves as a modal surface for keyboard users" do
    run = demo_run
    passport = run.passports.find_by!(actor_ref: "auth-reviewer")

    visit run_path(run, passport_id: passport.id, panel: "passport")

    assert_selector ".ap-drawer[role='dialog'][aria-modal='true'][aria-labelledby='passport-drawer-title']"
    assert_selector "#passport-drawer-title", text: "auth-reviewer"
    assert evaluate_script("document.querySelector('[data-drawer-target=\"background\"]').inert")
    assert_selector ".ap-drawer a.ap-quiet-link:focus", text: "Passport"

    20.times { send_keys(:tab) }

    assert evaluate_script("document.querySelector('.ap-drawer').contains(document.activeElement)")

    send_keys(:escape)

    assert_no_selector ".ap-drawer"
    assert_current_path run_path(run, passport_id: passport.id), ignore_query: false
  end
end
