require_relative "../test_helper"

class CredentialRecoveryTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
    @credential = Auth::Credential::Recovery.create!(user: @user)
  end

  # FIXME: test that generate creates a 16-character recovery code split every 4 chars
  def test_generate
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that find_by_code finds the credential by a normalized code
  def test_find_by_code
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that find_by_code returns nil for an unknown code
  def test_find_by_code_unknown
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that key_from_secret downcases and strips hyphens before deriving
  def test_key_from_secret_normalizes
    skip "Not yet implemented"
    assert true
  end
end
