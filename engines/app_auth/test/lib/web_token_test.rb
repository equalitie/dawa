require_relative "../test_helper"

class WebTokenTest < ActiveSupport::TestCase
  def setup
    Raft::Encryption.setup_test_keys
  end

  def test_encode_decode
    hash = {
      "hello" => "world"
    }
    encoded = Auth::WebToken.encode(hash)
    assert hash["exp"]
    assert encoded.is_a?(String)
    assert_equal hash, Auth::WebToken.decode(encoded)
  end

  def test_encryption
    hash = {
      "secret" => "value"
    }
    encoded = Auth::WebToken.encode(hash, encrypt: true)
    assert_equal "value", Raft::Encryption.encryptor.decrypt(hash.dig("secret", "enc"), key: "app_key")
    assert_equal "value", Auth::WebToken.decode(encoded).dig("secret")
  end
end
