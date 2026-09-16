require_relative "../test_helper"

class UserSessionTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
  end

  # FIXME: test that user has_many sessions association
  def test_has_many_sessions
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that user sessions are destroyed when user is deactivated
  def test_destroy_session_on_deactivate
    skip "Not yet implemented"
    assert true
  end
end
