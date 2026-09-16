# require_relative "../test_helper"

class WebTokenTest < ActiveSupport::TestCase

  # FIXME: test that encode creates a signed JWT string with expiry
  def test_encode
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that decode returns the original hash from a valid token
  def test_decode
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that decode returns empty hash for a nil/empty string
  def test_decode_empty
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that decode returns empty hash for a tampered token
  def test_decode_invalid
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that encode with encrypt: true encrypts values
  def test_encode_with_encryption
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that get extracts token from Authorization header, params, or body
  def test_get_token
    skip "Not yet implemented"
    assert true
  end

  #   def setup
#     Raft::Encryption.setup_test_keys
#   end

#   def test_encode_decode
#     hash = {
#       "hello" => "world"
#     }
#     encoded = Auth::WebToken.encode(hash)
#     assert hash["exp"]
#     assert encoded.is_a?(String)
#     assert_equal hash, Auth::WebToken.decode(encoded)
#   end

#   def test_encryption
#     hash = {
#       "secret" => "value"
#     }
#     encoded = Auth::WebToken.encode(hash, encrypt: true)
#     assert_equal "value", Raft::Encryption.encryptor.decrypt(hash.dig("secret", "enc"), key: "app_key")
#     assert_equal "value", Auth::WebToken.decode(encoded).dig("secret")
#   end

end
