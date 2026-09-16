require "rbnacl"
require "base64"

#
# NOTE: for SimpleBox, the key is RbNaCl::SecretBox.key_bytes (which is 32 bytes)
# So, our configured secret should be exactly 64 hex digits
# This key has 256 bits entropy
#

module Secrets
  module EncryptedUrl

    mattr_accessor :default_key

    #
    # encrypt a str using key, returns url safe.
    #
    # @param str [String] value to encrypt
    # @param key [32 bytes binary string]
    #
    def self.encrypt(str, key: default_key)
      assert_key!(key)
      begin
        box = RbNaCl::SimpleBox.from_secret_key(key)
        Base64.urlsafe_encode64(box.encrypt(str.to_s), padding: false)
      rescue
        nil
      end
    end

    #
    # decrypt a base64 encoded string
    #
    # @param str [String] value to encrypt
    # @param key [32 bytes binary string]
    #
    def self.decrypt(str, key: default_key)
      assert_key!(key)
      begin
        box = RbNaCl::SimpleBox.from_secret_key(key)
        box.decrypt(Base64.urlsafe_decode64(str))
      rescue
        nil
      end
    end

    def self.assert_key!(key)
      if key.nil? || key == ""
        raise ArgumentError, "ERROR: Secrets::EncryptedUrl -- either key argument default_key must be specified"
      elsif key.length < 32
        raise ArgumentError, "ERROR: Secrets::EncryptedUrl -- key must be at least 32 bytes"
      end
    end

    #
    # double wrap encryption.
    #
    # outer layer:
    #   encrypted with default (app wide) key
    #   contains an id number and inner layer
    #
    # inner layer:
    #   encrypted with a key that results from passing the id from the outer layer to a block
    #   contains the actual payload
    #
    def self.encrypt_with_key(str, id:, key:)
      box = RbNaCl::SimpleBox.from_secret_key(key)
      encrypt(IntegerEncoder.encode(id, box.encrypt(str.to_s)))
    end

    def self.decrypt_with_key(str, &block)
      id, payload = IntegerEncoder.decode(decrypt(str.to_s))
      key = yield id
      if key
        box = RbNaCl::SimpleBox.from_secret_key(key)
        box.decrypt(payload)
      end
    rescue
      return nil
    end

    # def self.binary_secret(secret_name)
    #   if secret_name.is_a?(Symbol)
    #     error = nil
    #     value = get_configuration_value(secret_name)
    #     if value.nil?
    #       error = "ERROR: the secret '#{secret_name}' is not defined in environment or credentials.yml.enc"
    #     elsif value !~ /\A[a-fA-F0-9]{64,}\z/
    #       error = "ERROR: the secret '#{secret_name}' MUST be at least 64 characters hex"
    #     end
    #     if error
    #       Rails.logger.error(error) if defined?(Rails)
    #       raise ArgumentError, error
    #     end
    #     [value[0..63]].pack('H*')
    #   else
    #     secret_name # the argument is already the key
    #   end
    # end

    # private

    # def self.get_configuration_value(name)
    #   name = name.to_s
    #   ENV[name.upcase] || rails_credentials(name) || conf(name)
    # end

    # def self.rails_credentials(name)
    #   if defined?(Rails)
    #     if Rails.application.respond_to?(name)
    #       Rails.application.send(name)
    #     else
    #       Rails.application.credentials.send(name)
    #     end
    #   end
    # end

    # def self.conf_credentials(name)
    #   if defined?(Conf)
    #     Conf.data[name]
    #   end
    # end

  end
end
