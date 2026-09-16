require_relative "../test_helper"

class CredentialDemoTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
  end

  def test_defaults_generate_authenticator_and_id
    cred = Auth::Credential::Demo.create!(user: @user)
    assert cred.authenticator.present?
    assert cred.authenticator_id.present?
    assert_not_equal cred.authenticator, cred.authenticator_id
  end

  def test_not_deletable
    cred = Auth::Credential::Demo.create!(user: @user)
    assert_not cred.deletable?
  end

  def test_not_editable
    cred = Auth::Credential::Demo.create!(user: @user)
    assert_not cred.editable?
  end

  def test_label
    cred = Auth::Credential::Demo.create!(user: @user)
    assert_equal "Demo Credential", cred.label
  end

  def test_comment
    cred = Auth::Credential::Demo.create!(user: @user)
    assert_equal "Automatic Encryption", cred.comment
  end

  def test_key_from_secret_uses_stored_authenticator_instead_of_passed_secret
    cred = Auth::Credential::Demo.create!(user: @user)
    key1 = cred.key_from_secret("any_secret")
    key2 = cred.key_from_secret("different_secret")
    # Both should produce the same key since Demo ignores the passed secret
    assert_equal key1, key2
  end

  def test_key_from_secret_returns_rbnacl_sized_key
    cred = Auth::Credential::Demo.create!(user: @user)
    key = cred.key_from_secret("anything")
    assert_equal RbNaCl::PrivateKey::BYTES, key.bytesize
  end
end
