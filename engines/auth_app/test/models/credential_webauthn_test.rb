require_relative "../test_helper"

class CredentialWebauthnTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
  end

  def test_label_returns_passkey_when_aaguid_nil
    cred = Auth::Credential::Webauthn.create!(user: @user)
    assert_equal "Passkey", cred.label
  end

  def test_label_returns_aaguid_name_when_present
    cred = Auth::Credential::Webauthn.create!(user: @user, data: { aaguid: "2fc0579f-8113-47ea-b116-bb5a8db9202a" })
    label = cred.label
    assert label.is_a?(String)
    assert label.length > 0
  end

  def test_comment_encrypted_when_encryption_is_setup
    cred = Auth::Credential::Webauthn.create!(user: @user, vault_public_key: SecureRandom.random_bytes(32))
    assert_equal "Automatic Encryption", cred.comment
  end

  def test_comment_phrase_required_when_not_encrypted
    cred = Auth::Credential::Webauthn.create!(user: @user)
    assert_equal "Phrase Required", cred.comment
  end

  def test_supports_prf_returns_prf_enabled
    cred = Auth::Credential::Webauthn.create!(user: @user, data: { prf_enabled: true })
    assert cred.supports_prf?
  end

  def test_supports_prf_returns_false_when_disabled
    cred = Auth::Credential::Webauthn.create!(user: @user, data: { prf_enabled: false })
    assert_not cred.supports_prf?
  end

  def test_editable_true_when_not_encrypted
    cred = Auth::Credential::Webauthn.create!(user: @user)
    assert cred.editable?
  end

  def test_editable_false_when_encrypted
    cred = Auth::Credential::Webauthn.create!(user: @user, vault_public_key: SecureRandom.random_bytes(32))
    assert_not cred.editable?
  end

  def test_public_key_alias
    pk = SecureRandom.hex(32)
    cred = Auth::Credential::Webauthn.create!(user: @user, authenticator: pk)
    assert_equal pk, cred.public_key
  end

  def test_webauthn_id_alias
    cred = Auth::Credential::Webauthn.create!(user: @user, authenticator_id: "my-id")
    assert_equal "my-id", cred.webauthn_id
  end
end
