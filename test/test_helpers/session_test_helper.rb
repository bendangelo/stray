module SessionTestHelper
  def sign_in_as(user)
    Current.session = user.sessions.create!

    if respond_to?(:page) && page.is_a?(Capybara::Session)
      cookie = ActionDispatch::TestRequest.create.cookie_jar.tap do |jar|
        jar.signed[:session_id] = Current.session.id
      end[:session_id]

      visit "/"
      page.driver.browser.manage.add_cookie(
        name: "session_id",
        value: cookie,
        path: "/"
      )
      visit "/"
    else
      ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
        cookie_jar.signed[:session_id] = Current.session.id
        cookies["session_id"] = cookie_jar[:session_id]
      end
    end
  end

  def sign_out
    Current.session&.destroy!

    if respond_to?(:page) && page.is_a?(Capybara::Session)
      page.driver.browser.manage.delete_cookie("session_id")
    else
      cookies.delete("session_id")
    end
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end

ActiveSupport.on_load(:action_dispatch_system_test_case) do
  include SessionTestHelper
end
