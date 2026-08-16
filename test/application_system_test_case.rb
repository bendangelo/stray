require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  def resize_to_mobile
    page.driver.browser.manage.window.resize_to(375, 812)
  end

  def resize_to_desktop
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end
end
