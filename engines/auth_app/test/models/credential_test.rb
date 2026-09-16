require_relative "../test_helper"

class CredentialTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester-#{SecureRandom.hex(4)}")
  end

  def test_scopes
    Auth::Credential.where(user_id: @user.id).delete_all

    Auth::Credential.create!(user: @user, type: "Auth::Credential::Webauthn", is_active: true)
    Auth::Credential.create!(user: @user, type: "Auth::Credential::Recovery", is_active: false)
    Auth::Credential.create!(user: @user, type: "Auth::Credential::Phrase", is_active: false)
    Auth::Credential.create!(user: @user, type: "Auth::Credential::Demo", is_active: false, vault_public_key: SecureRandom.random_bytes(32))

    assert_equal 1, Auth::Credential.where(user_id: @user.id).active.count
    assert_equal 3, Auth::Credential.where(user_id: @user.id).inactive.count
    assert_equal 1, Auth::Credential.where(user_id: @user.id).webauthn.count
    assert_equal 1, Auth::Credential.where(user_id: @user.id).recovery.count
    assert_equal 1, Auth::Credential.where(user_id: @user.id).phrase.count
    assert_equal 3, Auth::Credential.where(user_id: @user.id).visible.count
    assert_equal 3, Auth::Credential.where(user_id: @user.id).without_encryption.count
  end

  def test_registered_false_when_authenticator_nil
    cred = Auth::Credential.create!(user: @user)
    assert_not cred.registered?
  end

  def test_registered_true_when_authenticator_present
    cred = Auth::Credential.create!(user: @user, authenticator: SecureRandom.hex(16))
    assert cred.registered?
  end

  def test_encryption_false_when_vault_public_key_nil
    cred = Auth::Credential.create!(user: @user)
    assert_not cred.encryption?
  end

  def test_encryption_true_when_vault_public_key_present
    cred = Auth::Credential.create!(user: @user, vault_public_key: SecureRandom.random_bytes(32))
    assert cred.encryption?
  end

  def test_supports_prf_returns_false_by_default
    cred = Auth::Credential.create!(user: @user)
    assert_not cred.supports_prf?
  end

  def test_deletable_returns_true_by_default
    cred = Auth::Credential.create!(user: @user)
    assert cred.deletable?
  end

  def test_editable_returns_false_by_default
    cred = Auth::Credential.create!(user: @user)
    assert_not cred.editable?
  end

  def test_label_returns_nil_by_default
    cred = Auth::Credential.create!(user: @user)
    assert_nil cred.label
  end

  def test_comment_returns_nil_by_default
    cred = Auth::Credential.create!(user: @user)
    assert_nil cred.comment
  end

  def test_find_by_webauthn_id
    cred = Auth::Credential.create!(user: @user, authenticator_id: "my-webauthn-id")
    found = Auth::Credential.find_by_webauthn_id("my-webauthn-id")
    assert_equal cred, found
  end

  def test_model_name
    assert_equal "Credential", Auth::Credential.model_name.name
  end

  def test_init_vault_stores_public_key
    cred = Auth::Credential.create!(user: @user)
    secret = SecureRandom.random_bytes(32)
    cred.init_vault(secret)
    assert cred.vault_public_key.present?
  end

  def test_init_vault_with_wrong_secret_raises
    cred = Auth::Credential.create!(user: @user)
    secret = SecureRandom.random_bytes(32)
    cred.init_vault(secret)
    assert_raises(ArgumentError) { cred.init_vault(SecureRandom.random_bytes(32)) }
  end

  def test_reset_vault_changes_public_key
    cred = Auth::Credential.create!(user: @user)
    secret = SecureRandom.random_bytes(32)
    cred.init_vault(secret)
    original_key = cred.vault_public_key
    cred.reset_vault(SecureRandom.random_bytes(32))
    assert_not_equal original_key, cred.vault_public_key
  end

  def test_vault_private_key_raises_on_mismatch
    cred = Auth::Credential.create!(user: @user)
    cred.init_vault(SecureRandom.random_bytes(32))
    assert_raises(ArgumentError) { cred.vault_private_key(SecureRandom.random_bytes(32)) }
  end
end
