require "application_system_test_case"

class SidebarResizeSystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1280, 900] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--force-prefers-reduced-motion")
  end

  setup do
    page.driver.browser.manage.window.resize_to(1280, 900)
  end

  test "developer can drag the sessions sidebar edge wider" do
    run = demo_run

    visit run_path(run)

    assert_selector ".ap-workspace[data-sidebar-resize-ready='true']"
    assert_selector ".ap-sidebar-resizer[role='separator']"

    initial_width = sidebar_width

    page.execute_script(<<~JS)
      const handle = document.querySelector(".ap-sidebar-resizer")
      const rect = handle.getBoundingClientRect()
      const startX = rect.left + rect.width / 2
      const endX = startX + 96

      handle.dispatchEvent(new PointerEvent("pointerdown", {
        bubbles: true,
        button: 0,
        clientX: startX,
        pointerId: 1
      }))

      window.dispatchEvent(new PointerEvent("pointermove", {
        bubbles: true,
        clientX: endX,
        pointerId: 1
      }))

      window.dispatchEvent(new PointerEvent("pointerup", {
        bubbles: true,
        clientX: endX,
        pointerId: 1
      }))
    JS

    resized_width = sidebar_width
    stored_width = page.evaluate_script("Number(localStorage.getItem('agent-control-room:session-sidebar-width'))")

    assert_operator resized_width, :>, initial_width + 70
    assert_equal resized_width.round, stored_width
  end

  private

  def sidebar_width
    page.evaluate_script("document.querySelector('[data-sidebar-resize-target=\"sidebar\"]').getBoundingClientRect().width")
  end
end
