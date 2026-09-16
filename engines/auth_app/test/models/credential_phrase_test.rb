require_relative "../test_helper"

class CredentialPhraseTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester-#{SecureRandom.hex(4)}")
    @credential = Auth::Credential::Phrase.create!(user: @user)
  end

  def test_label
    assert_equal "Encryption Phrase", @credential.label
  end

  def test_not_deletable
    assert_not @credential.deletable?
  end

  def test_editable
    assert @credential.editable?
  end

  def test_key_from_secret_uses_pbkdf
    key = @credential.key_from_secret("my secret phrase")
    assert_kind_of RbNaCl::PrivateKey, key
    assert_equal RbNaCl::PrivateKey::BYTES, key.to_bytes.bytesize
  end

  def test_key_from_secret_is_deterministic
    key1 = @credential.key_from_secret("my secret phrase")
    key2 = @credential.key_from_secret("my secret phrase")
    assert_equal key1.to_bytes, key2.to_bytes
  end

  def test_salt_is_alias_for_authenticator
    @credential.update!(authenticator: SecureRandom.hex(32))
    assert_equal @credential.authenticator, @credential.salt
  end

  def test_salt_has_default_value
    assert @credential.salt.present?
    assert @credential.authenticator.present?
  end

  def test_vault_round_trip_with_phrase
    @credential.init_vault("my secret phrase")
    @credential.update_vault({"hello" => "world"})
    assert_equal({"hello" => "world"}, @credential.read_vault("my secret phrase"))
  end

  def test_vault_with_wrong_phrase_raises
    @credential.init_vault("correct phrase")
    @credential.update_vault({"data" => "secret"})
    assert_raises(ArgumentError) { @credential.read_vault("wrong phrase") }
  end
end
