require_relative "../test_helper"

class SessionAuthenticationTest < ActionDispatch::IntegrationTest
  def setup
    User.create!(username: "tester")
  end

  # FIXME: test that set_current_user! resets the session and sets user_id
  def test_set_current_user
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that reset_and_preserve_session preserves configured keys
  def test_reset_and_preserve_session_keys
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that require_authentication raises UnauthenticatedRequest when no user in session
  def test_require_authentication
    skip "Not yet implemented"
    assert true
  end
end
