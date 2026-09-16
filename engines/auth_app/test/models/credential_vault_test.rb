require_relative "../test_helper"

class CredentialVaultTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "user")
    @credential = Auth::Credential.create!(user: @user)
    @secret = SecureRandom.random_bytes(32)
  end

  def test_create_vault
    vault_content = {"mysecret" => "sssssh", "binary" => ["aabbcc"].pack("H*")}

    assert_nil @credential.vault_public_key
    @credential.init_vault(@secret)
    assert @credential.vault_public_key, "reading vault should create public key"

    @credential.update_vault(vault_content)
    assert_equal vault_content, @credential.read_vault(@secret)
    @credential.reload
    assert_equal vault_content, @credential.read_vault(@secret)
  end

  def test_update_vaults
    assert @credential.init_vault(@secret)
    secret2 = SecureRandom.hex(32)
    credential2 = @user.credentials.create!
    assert credential2.init_vault(secret2)

    vault_content = {"beautiful" => "platypus"}
    @user.credentials.update_vaults(vault_content)

    @credential.reload
    credential2.reload
    assert_equal vault_content, credential2.read_vault(secret2)
    assert_equal @credential.read_vault(@secret), credential2.read_vault(secret2)
  end

end
