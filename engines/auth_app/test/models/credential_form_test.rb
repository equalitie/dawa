require_relative "../test_helper"

class CredentialFormTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
  end

  # FIXME: test encryption_is_setup? returns true when credential already has vault_public_key
  def test_encryption_is_setup_when_encrypted
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test encryption_is_setup? returns false for webauthn with prf enabled but no vault
  def test_encryption_is_setup_prf_not_encrypted
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test is_recovery? returns true for Recovery credential
  def test_is_recovery
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test complete? returns true when credential is registered and has encryption
  def test_complete
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test save with valid attributes creates phrase credential when encryption_phrase is set
  def test_save_with_phrase
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that validation requires encryption_phrase to be present
  def test_requires_encryption_phrase
    skip "Not yet implemented"
    assert true
  end
end
