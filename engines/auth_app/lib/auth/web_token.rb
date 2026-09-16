require "jwt"
require "json"

#
# Utility methods for dealing with Javascript Web Tokens (JWT).
#
# The JWT may be in one of three formats:
#
# (1) In the Authorization header
# (2) In params["token"]
# (3) In body["token"] where body is JSON.parse(request.body.read)
#
# The token in params and body are the same, but with the header token the values
# may be under the key "payload".
#
# Example JWT in header:
#
# [
#   {
#     "payload" => {
#       "key" => "hNeZivTCb0xS1qvU2DlBww",
#       "status" => 4,
#       "actions" => [
#         {"type" => 0, "userid" => "uid-1757530251121"}
#       ]
#     },
#     "iat" => 1758228373,
#     "exp" => 1758228673
#   },
#   {
#     "alg" => "HS256",
#     "typ" => "JWT"
#   }
# ]
#
# Example JWT in body or params:
#
# [
#   {
#    "key" => "hNeZivTCb0xS1qvU2DlBww",
#    "status" => 4,
#    "actions" => [
#        {"type" => 0, "userid" => "uid-1757530251121"}
#     ],
#     "iat" => 1758228373,
#     "exp" => 1758228673
#   },
#   {
#     "alg" => "HS256",
#     "typ" => "JWT"
#   }
# ]
#
#

module Auth
  module WebToken
    def self.get(request)
      token_hsh = {}
      token_strings = [
        get_from_header(request),
        get_from_params(request),
        get_from_body(request)
      ]
      token_strings.each do |string|
        token_hsh.merge!(decode(string))
      end
      token_hsh
    end

    #
    # generate the signed JWT from a Hash
    #
    def self.encode(hsh, encrypt: false)
      encrypt_values(hsh) if encrypt
      add_expiry(hsh)
      JWT.encode(hsh, Auth.jwt_secret, 'HS256')
    end

    #
    # decode a JWT token string and return the object it encodes
    #
    # returns nil on decode or signature verification failure
    #
    def self.decode(str)
      return {} unless str.present?

      decoded = JWT.decode(str, Auth.jwt_secret, true, { algorithm: 'HS256' })
      # decoded = Array [ {"data"=>"test", ...}, # payload
      #                   {"alg"=>"HS256", ...} # header   ]
      jwt_data = decoded.first
      payload = jwt_data["payload"] ? jwt_data["payload"] : jwt_data
      decrypt_values(payload)
      payload
    rescue StandardError
      {}
    end

    private

    def self.get_from_header(request)
      request.headers[Auth.jwt_header]&.sub(/^Bearer /, "")
    end

    def self.get_from_params(request)
      request.params[:token]
    end

    def self.get_from_body(request)
      if json?(request)
        body = request.body.read
        if body.present?
          JSON.parse(body)&.dig("token")
        else
          nil
        end
      end
    end

    def self.json?(request)
      request.format.json? ||
        request.content_type == 'application/json' ||
        request.headers['Accept'].to_s.include?('application/json') ||
        request.params[:format] == 'json'
    end

    def self.add_expiry(hsh)
      now = Time.now
      number, unit = Auth.jwt_expiry.split(" ")
      expiry = number.to_i.send(unit)
      hsh["iat"] = now.to_i
      hsh["exp"] = (now + expiry).to_i
      hsh
    end

    def self.encrypt_values(hsh)
      hsh.each do |key, value|
        hsh[key] = {
          #"key" => "app_key",
          "enc" => Auth.encryptor.encrypt(value, key: :app_key)
        }
      end
    end

    def self.decrypt_values(hsh)
      hsh.each do |key, value|
        if value.is_a?(Hash) && value["enc"]
          encryption_key_name = value["key"] || "app_key"
          hsh[key] = Auth.encryptor.decrypt(value["enc"], key: encryption_key_name)
        end
      end
      hsh
    end

  end
end
