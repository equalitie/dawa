require_relative "../test_helper"

class WebauthnControllerTest < ActionDispatch::IntegrationTest
  def setup
    User.create!(username: "crow")
  end

  # FIXME: test that POST register_initiate returns JSON creation options for the current user
  # Requires a User model that responds to #profiles
  def test_register_initiate
    skip "Not yet implemented — dummy User model lacks #profiles"
    assert true
  end

  # FIXME: test POST register_verify with valid credential creates a webauthn credential
  def test_register_verify
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test POST register_verify with invalid challenge returns error
  def test_register_verify_invalid
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test POST authenticate_initiate returns JSON options for existing credentials
  def test_authenticate_initiate
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test POST authenticate_verify with valid signature authenticates the user
  def test_authenticate_verify
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test POST authenticate_verify with invalid credential returns error
  def test_authenticate_verify_invalid
    skip "Not yet implemented"
    assert true
  end
end
