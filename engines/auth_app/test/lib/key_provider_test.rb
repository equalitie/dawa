require_relative "../test_helper"

class KeyProviderTest < ActiveSupport::TestCase
  def setup
    @provider = Auth::KeyProvider.new
  end

  def test_random_key_returns_binary_string_of_default_length
    key = @provider.random_key
    assert_equal Encoding::BINARY, key.encoding
    assert_equal 64, key.bytesize
  end

  def test_key_derives_hkdf_key_from_secret_and_salt
    key = @provider.key(secret: "my_secret", salt: "my_salt")
    assert_equal Encoding::BINARY, key.encoding
    assert_equal 64, key.bytesize
  end

  def test_key_is_deterministic
    key1 = @provider.key(secret: "same", salt: "same")
    key2 = @provider.key(secret: "same", salt: "same")
    assert_equal key1, key2
  end

  def test_key_differs_with_different_salt
    key1 = @provider.key(secret: "same", salt: "salt_a")
    key2 = @provider.key(secret: "same", salt: "salt_b")
    assert_not_equal key1, key2
  end

  def test_key_accepts_custom_bytes
    key = @provider.key(secret: "s", salt: "s", bytes: 32)
    assert_equal 32, key.bytesize
  end

  def test_pb_key_derives_argon2_key
    # Use low opslimit/memlimit for tests
    original_ops = Auth.argon2_opslimit
    original_mem = Auth.argon2_memlimit
    Auth.argon2_opslimit = 3
    Auth.argon2_memlimit = 2**13

    begin
      key = @provider.pb_key(secret: "user_password", salt: SecureRandom.hex(32))
      assert_equal Encoding::BINARY, key.encoding
      assert_equal 64, key.bytesize
    ensure
      Auth.argon2_opslimit = original_ops
      Auth.argon2_memlimit = original_mem
    end
  end

  def test_pb_key_is_deterministic
    original_ops = Auth.argon2_opslimit
    original_mem = Auth.argon2_memlimit
    Auth.argon2_opslimit = 3
    Auth.argon2_memlimit = 2**13

    begin
      salt = SecureRandom.hex(32)
      key1 = @provider.pb_key(secret: "mypassword", salt: salt)
      key2 = @provider.pb_key(secret: "mypassword", salt: salt)
      assert_equal key1, key2
    ensure
      Auth.argon2_opslimit = original_ops
      Auth.argon2_memlimit = original_mem
    end
  end

  def test_private_key_returns_rbnacl_private_key
    hex_secret = SecureRandom.hex(32)
    private_key = @provider.private_key(hex_secret, salt: "test_salt")
    assert_kind_of RbNaCl::PrivateKey, private_key
  end

  def test_private_key_with_binary_input
    binary_secret = SecureRandom.random_bytes(32)
    private_key = @provider.private_key(binary_secret)
    assert_kind_of RbNaCl::PrivateKey, private_key
  end

  def test_private_key_with_matching_key_pair
    key = @provider.private_key("secret", salt: "salt")
    pub = key.public_key

    # Private key derived from same inputs should produce same public key
    key2 = @provider.private_key("secret", salt: "salt")
    assert_equal pub.to_bytes, key2.public_key.to_bytes
  end

  def test_to_binary_converts_hex_string
    hex = "deadbeef"
    result = @provider.to_binary(hex)
    assert_equal Encoding::BINARY, result.encoding
    assert_equal ["deadbeef"].pack("H*"), result
    assert_equal 4, result.bytesize
  end

  def test_to_binary_passes_through_binary
    binary = SecureRandom.random_bytes(16)
    result = @provider.to_binary(binary)
    assert_equal binary, result
  end

  def test_to_binary_raises_on_empty_string
    assert_raises(ArgumentError) { @provider.to_binary("") }
  end

  def test_to_binary_raises_on_nil
    assert_raises(ArgumentError) { @provider.to_binary(nil) }
  end

  def test_to_binary_validates_minimum_bytes
    assert_raises(ArgumentError) { @provider.to_binary("aabb", bytes: 4) }
  end

  def test_to_binary_truncates_to_requested_bytes
    hex = "aabbccdd11223344"
    result = @provider.to_binary(hex, bytes: 2)
    assert_equal 2, result.bytesize
  end

  def test_pb_key_salt_bytes_returns_argon2_salt_size
    assert_equal RbNaCl::PasswordHash::Argon2::SALTBYTES, @provider.pb_key_salt_bytes
  end
end
