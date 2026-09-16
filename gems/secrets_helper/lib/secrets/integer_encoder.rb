#
# Takes an integer and binary data, and concats them together,
# reversibly.
#
# @param integer [Integer] Unsigned integer to encode
# @param data [String] Binary data blob to encode
# @return [String] URL-safe base64 encoded string

module Secrets
  class IntegerEncoder
    def self.encode(integer, data)
      raise ArgumentError, "Integer must be non-negative" if integer < 0
      raise ArgumentError, "Data must be a string" unless data.is_a?(String)

      # Convert integer to binary (big-endian, variable length)
      integer_bytes = integer_to_bytes(integer)

      # Combine integer length, integer bytes, and data
      # Format: [1 byte length] [integer bytes] [data bytes]
      integer_bytes.bytesize.chr + integer_bytes + data
    end

    # Decodes an encoded string back to integer and binary data
    # @param bin [String] binary string generated via encode()
    # @return [Array(Integer, String)] Decoded integer and binary data
    def self.decode(bin)
      raise ArgumentError, "Encoded string cannot be nil" if bin.nil?

      # Extract integer length (first byte)
      integer_length = bin.bytes[0]

      # Validate we have enough data
      if bin.bytesize < 1 + integer_length
        raise ArgumentError, "Invalid encoded string: insufficient data"
      end

      # Extract integer bytes
      integer_bytes = bin.byteslice(1, integer_length)

      # Extract remaining data
      data = bin.byteslice(1 + integer_length..-1) || ""

      # Convert bytes back to integer
      integer = bytes_to_integer(integer_bytes)

      [integer, data]
    rescue ArgumentError => e
      # Re-raise our own ArgumentErrors
      raise e
    rescue => e
      raise ArgumentError, "Invalid base64 encoded string: #{e.message}"
    end

    private

    # Convert integer to variable-length byte string
    # @param integer [Integer] Unsigned integer
    # @return [String] Byte representation
    def self.integer_to_bytes(integer)
      return "\x00" if integer == 0

      bytes = []
      while integer > 0
        bytes.unshift(integer & 0xFF)
        integer >>= 8
      end
      bytes.pack('C*')
    end

    # Convert byte string back to integer
    # @param bytes [String] Byte representation
    # @return [Integer] Unsigned integer
    def self.bytes_to_integer(bytes)
      return 0 if bytes.nil? || bytes.empty?

      integer = 0
      bytes.each_byte do |byte|
        integer = (integer << 8) | byte
      end
      integer
    end
  end
end
