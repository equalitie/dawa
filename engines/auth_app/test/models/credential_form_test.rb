require_relative "../test_helper"

class CredentialFormTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
    @credential = Auth::Credential::Webauthn.create!(user: @user, is_active: true)
  end

  def test_encryption_is_setup_when_encrypted
    @credential.update!(vault_public_key: SecureRandom.random_bytes(32))
    form = Auth::CredentialForm.new(@credential)
    assert form.encryption_is_setup?
  end

  def test_encryption_is_setup_false_for_webauthn_with_prf_no_vault
    @credential.update!(data: { prf_enabled: true })
    form = Auth::CredentialForm.new(@credential)
    assert_not form.encryption_is_setup?
  end

  def test_is_recovery
    recovery = Auth::Credential::Recovery.create!(user: @user)
    form = Auth::CredentialForm.new(recovery)
    assert form.is_recovery?
  end

  def test_is_not_recovery
    form = Auth::CredentialForm.new(@credential)
    assert_not form.is_recovery?
  end

  def test_phrase_credential_returns_credential_for_phrase_type
    phrase = Auth::Credential::Phrase.create!(user: @user)
    form = Auth::CredentialForm.new(phrase)
    assert_equal phrase, form.phrase_credential
  end

  def test_phrase_credential_returns_nil_for_prf_supported
    @credential.update!(data: { prf_enabled: true })
    form = Auth::CredentialForm.new(@credential)
    assert_nil form.phrase_credential
  end

  def test_validation_requires_encryption_phrase
    form = Auth::CredentialForm.new(@credential)
    form.encryption_phrase = ""
    assert_not form.valid?
    assert form.errors[:encryption_phrase].present?
  end

  def test_complete_when_registered_and_encrypted
    @credential.update!(authenticator: SecureRandom.hex(16), vault_public_key: SecureRandom.random_bytes(32))
    form = Auth::CredentialForm.new(@credential)
    assert form.complete?
  end

  def test_not_complete_when_not_registered
    form = Auth::CredentialForm.new(@credential)
    assert_not form.complete?
  end

  def test_delegates_to_credential
    form = Auth::CredentialForm.new(@credential)
    assert_equal @credential.to_param, form.to_param
  end

  def test_delegates_model_name
    form = Auth::CredentialForm.new(@credential)
    assert_equal "Credential", form.model_name.name
  end
end
