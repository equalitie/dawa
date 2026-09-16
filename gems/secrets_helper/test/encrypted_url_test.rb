require_relative "test_helper"

class EncryptedUrlTest < Minitest::Test

  def setup
    Secrets::EncryptedUrl.default_key = SecureRandom.random_bytes(32)
  end

  def test_with_key
    secret = "This is very secret"
    keys = {}
    20.times do
      id = rand(10000000)
      key = SecureRandom.random_bytes(32)
      keys[id] = key
    end
    keys.each do |key_id, key|
      encoded = Secrets::EncryptedUrl.encrypt_with_key(secret, id: key_id, key: key)
      assert encoded, "url value must exist (was #{encoded.inspect})"
      assert Base64.urlsafe_decode64(encoded), "should be base64"
      decoded = Secrets::EncryptedUrl.decrypt_with_key(encoded) { |id| keys[id] }
      assert_equal secret, decoded
    end
  end

end
