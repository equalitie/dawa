require_relative "../test_helper"

class CredentialDemoTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
    @credential = Auth::Credential::Demo.create!(user: @user)
  end

  # FIXME: test demo credential generates authenticator and authenticator_id on create
  def test_defaults
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that demo credential is not deletable
  def test_not_deletable
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that demo credential is not editable
  def test_not_editable
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test key_from_secret uses the stored authenticator and authenticator_id instead of the passed secret
  def test_key_from_secret_ignores_secret
    skip "Not yet implemented"
    assert true
  end
end
