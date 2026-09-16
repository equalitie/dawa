ENV["RAILS_ENV"] = "test"

##
## Standard Rails Stuff
##

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
require "rails/test_help"

# Load fixtures from the engine
# if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
#   ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
#   ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
#   ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
#   ActiveSupport::TestCase.fixtures :all
# end


##
## Test Helpers
##

module AuthenticationHelper
  # All-purpose login helper that works in different test contexts
  def login_as(user=User.first)
    if defined?(@request)
      # Controller tests
      @request.session[:user_id] = user.id
    elsif defined?(session)
      # Integration tests
      session[:user_id] = user.id
    elsif defined?(page)
      # System tests
      page.driver.browser.set_cookie("user_id=#{user.id}")
    end
    user
  end

  def logout
    if defined?(@request)
      @request.session[:user_id] = nil
    elsif defined?(session)
      session[:user_id] = nil
    elsif defined?(page)
      page.driver.browser.clear_cookies
    end
  end
end

class ActiveSupport::TestCase
  include AuthenticationHelper
end

class ActionController::TestCase
  include AuthenticationHelper
end

class ActionDispatch::IntegrationTest
  include AuthenticationHelper

  def login_as(user=User.first)
    post test_session_path, params: { username: user.username }
    follow_redirect!
  end
end

#class ActionDispatch::SystemTestCase
#  include AuthenticationHelper
#end
