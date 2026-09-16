require_relative "../test_helper"

class CredentialTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
  end

  # FIXME: test scopes — active, inactive, webauthn, recovery, phrase, visible, without_encryption
  def test_scopes
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that registered? is false when authenticator is nil
  def test_registered
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that encryption? is false when vault_public_key is nil
  def test_encryption_check
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that supports_prf? returns false (default)
  def test_supports_prf
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that deletable? returns true (default)
  def test_deletable
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that editable? returns false (default)
  def test_editable
    skip "Not yet implemented"
    assert true
  end
end
