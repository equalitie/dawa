require_relative "../test_helper"

class CredentialPhraseTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
    @credential = Auth::Credential::Phrase.create!(user: @user)
  end

  # FIXME: test that label returns "Encryption Phrase"
  def test_label
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that phrase credential is not deletable
  def test_not_deletable
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that phrase credential is editable
  def test_editable
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that key_from_secret uses Argon2 password-based key derivation
  def test_key_from_secret_uses_pbkdf
    skip "Not yet implemented"
    assert true
  end
end
