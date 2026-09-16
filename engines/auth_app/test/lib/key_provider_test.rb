require_relative "../test_helper"

class KeyProviderTest < ActiveSupport::TestCase
  def setup
    @provider = Auth::KeyProvider.new
  end

  # FIXME: test that random_key returns a binary string of default length (64 bytes)
  def test_random_key
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that key derives an HKDF key from secret and salt
  def test_key_derivation
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that pb_key derives an Argon2 password-based key
  def test_pb_key_derivation
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that private_key returns an RbNaCl::PrivateKey
  def test_private_key
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that to_binary converts a hex string to binary
  def test_to_binary_from_hex
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that to_binary raises ArgumentError for empty string
  def test_to_binary_empty_raises
    skip "Not yet implemented"
    assert true
  end
end
