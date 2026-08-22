require "test_helper"
require "capybara/cuprite"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
    js_errors: true,
    process_timeout: 20,
    timeout: 15
  }

  def resize_to_mobile
    page.driver.resize(375, 812)
  end

  def resize_to_desktop
    page.driver.resize(1400, 1400)
  end
end
