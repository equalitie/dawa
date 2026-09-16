#
# This class will encode and decode a 64-bit unsigned integer
# into a compact URL-safe string. The string will be between
# 3 and 15 characters (2 for the checksum, and 1..13 for the
# number itself).
#
# Important considerations:
#
# * If no secret is provided, the encoded string is easily
#   reversed and it is easy to create arbitrary encodings.
#
# * If a secret_name is provided, the encoded strings
#   are harder to reverse or create arbitrary encodings.
#   However, frequency analysis on a bunch of encoded strings,
#   or knowing the input and output of any encoding,
#   allows you to reverse or create arbitrary encodings.
#
# * Because of this, don't use TinyUrl for any record IDs that
#   might otherwise be visible to the user, such as in a URL path
#   or error message.
#
# * When you change the value of the environment variable
#   specified by secret_name, it will invalidate all the
#   previously generated TinyURL encodings.
#
# * There is a 1:4096 chance that if you change the secret
#   an old TinyURL encoded value will be decoded incorrectly.
#   (because we only use 12 bits for the checksum)
#

require 'base64'
require 'digest'

module Secrets
  module TinyUrl
    REG_EXP = /\A[a-zA-Z0-9_-]{1,13}\z/

    #
    # returns true if the string is one that could have been
    # created with self.encode(number)
    #
    def self.match?(str)
      (str =~ REG_EXP) == 0
    rescue ArgumentError
      return false
    end

    #
    # encodes integer, returns a string
    #
    def self.encode(number, secret_name = nil)
      if number.nil?
        return ''
      elsif number >= 18446744073709551616
        raise ArgumentError, 'number is greater than 64 bits'
      end
      if number < 0
        raise ArgumentError, 'number is negative'
      end
      if secret_name
        # prefix is generated before xor. this leaks some
        # information about the number, but makes it harder
        # to construct valid tinyurls
        prefix = guard_prefix(number)
        number = xor_secret(secret_name, number)
      else
        prefix = ""
      end
      binary = [number].pack('Q<*') # 64-bit unsigned little-endian
      encoding = Base64.urlsafe_encode64(binary, padding: false)
      return prefix + compact(encoding)
    end

    #
    # decodes str, returns an integer
    #
    def self.decode(str, secret_name = nil)
      return nil unless str.is_a?(String)

      if secret_name
        prefix = str[0..1]
        str    = str[2..]
      end

      binary = Base64.urlsafe_decode64(inflate(str))
      number = binary.unpack('Q<*').first

      if secret_name
        number = xor_secret(secret_name, number)
        if prefix != guard_prefix(number)
          return nil
        end
      end

      return number
    rescue ArgumentError
      # the str was not base64 encoded
      return nil
    end

    #
    # Normal base64 encoding gives you 8 bits of storage if using
    # just two characters, because of the way base64 aligns the 6-bit
    # and 8-bit boundaries in it's encoding.
    #
    # This approach here gives us a full 12 bits of storage in
    # two characters, but is only useful for integers less than 4096.
    #

    def self.compact_encode(number)
      raise ArgumentError, 'number must be less than 4096' unless number < 4096
      first_digit  = [[(number & 0b111111000000) >> 4].pack('C')].pack('m0')[0]
      second_digit = [[(number & 0b000000111111) << 2].pack('C')].pack('m0')[0]
      encoding = first_digit + second_digit
      return encoding.gsub('/','_').gsub('+','-')
    end

    def self.compact_decode(str)
      first_digit = str[0]
      second_digit = str[1]
      first_bits  = (("#{first_digit}A".unpack('m').first.unpack('C').first & 0b11111100) >> 2)
      second_bits = (("#{second_digit}A".unpack('m').first.unpack('C').first & 0b11111100) >> 2)
      number = (first_bits << 6) | second_bits
      return number
    end

    private

    # pads a string with "A" on the right if less than 6 chars
    def self.inflate(str)
      str.ljust(11, "A")
    end

    # removes trailing "A"
    def self.compact(str)
      str.sub(/A+$/,'')
    end

    #
    # this method uses a secret stored in an environment
    # variable or configuration, then does an xor on the
    # number using the digest of that secret.
    #
    # It is important that we create a digest of the secret,
    # since frequency analysis can trivially reveal the
    # xor value
    #
    def self.xor_secret(secret_name, number)
      secret_value = get_configuration_value(secret_name)
      raise ArgumentError unless secret_value
      hex_secret_str = Digest::MD5.hexdigest(secret_value)
      hex_number_str = number.to_s(16)
      # cut secret number to match digits in hex of input number:
      hex_secret_str = hex_secret_str.slice(0, hex_number_str.length)
      return hex_number_str.to_i(16) ^ hex_secret_str.to_i(16)
    end

    def self.get_configuration_value(name)
      name = name.to_s
      ENV[name.upcase] ||
      ENV[name] ||
      defined?(Rails) && defined?(Rails.application) && Rails.application.credentials.send(name) ||
      defined?(Conf) && Conf.data[name]
    end

    def self.guard_prefix(number)
      compact_encode((number + 2000) % 4096)
    end

    def self.guard_prefix_match?(number, prefix)
      prefix == guard_prefix(number)
    end

  end
end
