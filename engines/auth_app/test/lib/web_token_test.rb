require_relative "../test_helper"

class WebTokenTest < ActiveSupport::TestCase
  def setup
    Auth.jwt_secret = SecureRandom.hex(64)
  end

  def test_encode_creates_signed_jwt_string
    hash = { "user_id" => 42, "role" => "admin" }
    encoded = Auth::WebToken.encode(hash)

    assert encoded.is_a?(String)
    # JWT has three parts separated by dots
    assert_equal 3, encoded.split(".").length
  end

  def test_encode_adds_expiry
    hash = { "data" => "test" }
    travel_to Time.zone.now do
      Auth::WebToken.encode(hash)
      assert hash["iat"], "should have issued-at time"
      assert hash["exp"], "should have expiration"
      assert_equal hash["iat"] + 3600, hash["exp"] # default 1 hour
    end
  end

  def test_decode_returns_original_hash
    original = { "hello" => "world", "number" => 42 }
    encoded = Auth::WebToken.encode(original.dup)
    decoded = Auth::WebToken.decode(encoded)

    assert_equal "world", decoded["hello"]
    assert_equal 42, decoded["number"]
  end

  def test_decode_returns_empty_hash_for_nil
    assert_equal({}, Auth::WebToken.decode(nil))
  end

  def test_decode_returns_empty_hash_for_empty_string
    assert_equal({}, Auth::WebToken.decode(""))
  end

  def test_decode_returns_empty_hash_for_tampered_token
    encoded = Auth::WebToken.encode({ "data" => "test" })
    tampered = encoded.sub(/[a-z]/, "X")
    assert_equal({}, Auth::WebToken.decode(tampered))
  end

  def test_decode_returns_empty_hash_for_garbage
    assert_equal({}, Auth::WebToken.decode("not.a.token.at.all"))
  end

  def test_decode_handles_payload_wrapping
    # Some tokens have the data nested under a "payload" key (from header tokens)
    # The decode method handles both formats
    token_string = JWT.encode(
      { "payload" => { "nested" => "value" } },
      Auth.jwt_secret, 'HS256'
    )
    decoded = Auth::WebToken.decode(token_string)
    assert_equal "value", decoded["nested"]
  end

  def test_encode_with_encryption_encrypts_values
    skip "Requires Auth.encryptor which is not configured in test helper"
    assert true
  end

  def test_get_token_from_header
    request = stub_headers_request("HTTP_AUTHORIZATION" => "Bearer my.jwt.token")
    Auth.stub(:jwt_header, "HTTP_AUTHORIZATION") do
      result = Auth::WebToken.get(request)
      # get merges decoded token data
      assert result.is_a?(Hash)
    end
  end

  def test_get_token_from_params
    request = stub_params_request(token: "my.jwt.token")
    result = Auth::WebToken.get(request)
    assert result.is_a?(Hash)
  end

  def test_encryption
    skip "fixme"
    hash = {
      "secret" => "value"
    }
    # encoded = Auth::WebToken.encode(hash, encrypt: true)
    #assert_equal "value", Raft::Encryption.encryptor.decrypt(hash.dig("secret", "enc"), key: "app_key")
    #assert_equal "value", Auth::WebToken.decode(encoded).dig("secret")
  end

  private

  def stub_headers_request(headers)
    request = Minitest::Mock.new
    def request.params; {}; end
    def request.body; StringIO.new; end
    def request.format;
      @format ||= begin
        f = Minitest::Mock.new
        f.expect(:json?, false)
        def f.json?; false; end
        f
      end
    end
    def request.content_type; nil; end
    def request.headers(key = nil)
      if key
        { "HTTP_AUTHORIZATION" => "Bearer my.jwt.token" }[key]
      else
        {}
      end
    end
    request
  end

  def stub_params_request(params_hash)
    request = Minitest::Mock.new
    def request.headers; {}; end
    def request.body; StringIO.new; end
    def request.format; Minitest::Mock.new.expect(:json?, false); end
    def request.content_type; nil; end
    def request.params
      { token: "my.jwt.token" }
    end
    request
  end
end
